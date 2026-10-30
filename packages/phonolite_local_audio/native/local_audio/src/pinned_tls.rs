use std::io::{self, Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::{mpsc, Arc, OnceLock};
use std::time::{Duration, Instant};

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use sha2::{Digest, Sha256};

pub struct PinnedTls {
    config: Arc<rustls::ClientConfig>,
    verifier: Arc<PinnedVerifier>,
    addresses: OnceLock<Vec<SocketAddr>>,
}

impl PinnedTls {
    pub fn new(pin: &str) -> Result<Self, String> {
        if pin.len() != 64 || !pin.bytes().all(|value| value.is_ascii_hexdigit()) {
            return Err("Original playback requires the authenticated server key".into());
        }

        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let verifier = Arc::new(PinnedVerifier {
            pin: pin.to_ascii_lowercase(),
            algorithms: provider.signature_verification_algorithms,
        });
        let config = rustls::ClientConfig::builder_with_provider(provider)
            .with_protocol_versions(&[&rustls::version::TLS13])
            .map_err(|error| error.to_string())?
            .dangerous()
            .with_custom_certificate_verifier(verifier.clone())
            .with_no_client_auth();

        Ok(Self {
            config: Arc::new(config),
            verifier,
            addresses: OnceLock::new(),
        })
    }

    /// A retained session still proves possession of the pinned key, but its
    /// certificate can expire between range requests. Recheck before auth is sent.
    pub(crate) fn verify_peer(&self, connection: &rustls::ClientConnection) -> io::Result<()> {
        self.verify_peer_at(connection, UnixTime::now())
    }

    /// Inspect only already-decrypted plaintext, without reading from TCP.
    /// A complete non-pipelined response must leave no extra bytes or TLS EOF.
    pub(crate) fn reusable_peer(&self, connection: &mut rustls::ClientConnection) -> bool {
        matches!(
            connection.reader().read(&mut [0u8; 1]),
            Err(error) if error.kind() == io::ErrorKind::WouldBlock
        )
    }

    fn verify_peer_at(
        &self,
        connection: &rustls::ClientConnection,
        now: UnixTime,
    ) -> io::Result<()> {
        if connection.is_handshaking()
            || connection.protocol_version() != Some(rustls::ProtocolVersion::TLSv1_3)
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Original audio requires a completed pinned TLS 1.3 handshake",
            ));
        }
        let certificate = connection
            .peer_certificates()
            .and_then(|certificates| certificates.first())
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    "Original audio connection has no verified server certificate",
                )
            })?;
        self.verifier
            .verify_certificate(certificate, now)
            .map(|_| ())
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
    }

    pub fn connect(
        &self,
        host: &str,
        port: u16,
        deadline: Instant,
    ) -> io::Result<rustls::StreamOwned<rustls::ClientConnection, DeadlineSocket>> {
        let mut last_error = io::Error::new(io::ErrorKind::NotFound, "server address not found");
        let mut connected = None;

        if self.addresses.get().is_none() {
            let addresses = resolve_addresses(host, port, deadline)?;
            let _ = self.addresses.set(addresses);
        }

        for address in self.addresses.get().unwrap() {
            let timeout = remaining(deadline)?;
            match TcpStream::connect_timeout(address, timeout) {
                Ok(socket) => {
                    connected = Some(socket);
                    break;
                }
                Err(error) => last_error = error,
            }
        }

        let socket = connected.ok_or(last_error)?;
        socket.set_nodelay(true)?;
        let server_name = ServerName::try_from(host.to_owned())
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid server name"))?;
        let mut connection = rustls::ClientConnection::new(self.config.clone(), server_name)
            .map_err(io::Error::other)?;
        let mut socket = DeadlineSocket { socket, deadline };

        // Prove possession of the pinned key before sending the bearer token.
        while connection.is_handshaking() {
            connection.complete_io(&mut socket)?;
        }

        Ok(rustls::StreamOwned::new(connection, socket))
    }
}

pub struct DeadlineSocket {
    socket: TcpStream,
    deadline: Instant,
}

impl DeadlineSocket {
    pub(crate) fn set_deadline(&mut self, deadline: Instant) {
        self.deadline = deadline;
    }
}

impl Read for DeadlineSocket {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        self.socket
            .set_read_timeout(Some(remaining(self.deadline)?))?;
        self.socket.read(bytes)
    }
}

impl Write for DeadlineSocket {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.socket
            .set_write_timeout(Some(remaining(self.deadline)?))?;
        self.socket.write(bytes)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.socket.flush()
    }
}

fn remaining(deadline: Instant) -> io::Result<Duration> {
    deadline
        .checked_duration_since(Instant::now())
        .filter(|duration| !duration.is_zero())
        .ok_or_else(|| io::Error::new(io::ErrorKind::TimedOut, "Original audio request timed out"))
}

fn resolve_addresses(host: &str, port: u16, deadline: Instant) -> io::Result<Vec<SocketAddr>> {
    if let Ok(address) = host.parse::<IpAddr>() {
        return Ok(vec![SocketAddr::new(address, port)]);
    }

    // System DNS has no portable cancellation API. Keep it outside the decoder
    // thread and bound its wait; the resolver owns only a hostname, never auth.
    let host = host.to_owned();
    let (send, receive) = mpsc::sync_channel(1);
    std::thread::Builder::new()
        .name("phonolite-original-dns".into())
        .spawn(move || {
            let result = (host.as_str(), port)
                .to_socket_addrs()
                .map(|addresses| addresses.collect());
            let _ = send.send(result);
        })?;

    receive.recv_timeout(remaining(deadline)?).map_err(|_| {
        io::Error::new(
            io::ErrorKind::TimedOut,
            "Original audio server lookup timed out",
        )
    })?
}

#[derive(Debug)]
struct PinnedVerifier {
    pin: String,
    algorithms: rustls::crypto::WebPkiSupportedAlgorithms,
}

impl PinnedVerifier {
    fn verify_certificate(
        &self,
        certificate: &CertificateDer<'_>,
        now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        let (_, parsed) = x509_parser::parse_x509_certificate(certificate.as_ref())
            .map_err(|_| rustls::Error::General("invalid server certificate".into()))?;
        let time = x509_parser::time::ASN1Time::from_timestamp(now.as_secs() as i64)
            .map_err(|_| rustls::Error::General("invalid device time".into()))?;

        if !parsed.validity().is_valid_at(time) {
            return Err(rustls::Error::General(
                "server certificate is expired or not yet valid".into(),
            ));
        }

        let actual = format!("{:x}", Sha256::digest(parsed.public_key().raw));
        if actual != self.pin {
            return Err(rustls::Error::General(
                "server public key does not match the authenticated server".into(),
            ));
        }

        Ok(ServerCertVerified::assertion())
    }
}

impl ServerCertVerifier for PinnedVerifier {
    fn verify_server_cert(
        &self,
        certificate: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        self.verify_certificate(certificate, now)
    }

    fn verify_tls12_signature(
        &self,
        _: &[u8],
        _: &CertificateDer<'_>,
        _: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Err(rustls::Error::General("TLS 1.3 is required".into()))
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        certificate: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(message, certificate, signature, &self.algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requires_a_complete_authenticated_pin() {
        for pin in ["", "abc", &"zz".repeat(32)] {
            assert!(PinnedTls::new(pin).is_err());
        }
        assert!(PinnedTls::new(&"00".repeat(32)).is_ok());
    }

    #[test]
    fn pinned_verifier_checks_key_and_certificate_validity() {
        let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let (_, parsed) = x509_parser::parse_x509_certificate(identity.cert.der()).unwrap();
        let provider = rustls::crypto::ring::default_provider();
        let mut verifier = PinnedVerifier {
            pin: format!("{:x}", Sha256::digest(parsed.public_key().raw)),
            algorithms: provider.signature_verification_algorithms,
        };
        let name = ServerName::try_from("localhost").unwrap();

        assert!(verifier
            .verify_server_cert(identity.cert.der(), &[], &name, &[], UnixTime::now())
            .is_ok());
        verifier.pin = "00".repeat(32);
        assert!(verifier
            .verify_server_cert(identity.cert.der(), &[], &name, &[], UnixTime::now())
            .is_err());

        let key = rcgen::KeyPair::generate().unwrap();
        let mut parameters = rcgen::CertificateParams::new(vec!["localhost".into()]).unwrap();
        parameters.not_before = rcgen::date_time_ymd(2010, 1, 1);
        parameters.not_after = rcgen::date_time_ymd(2020, 1, 1);
        let expired = parameters.self_signed(&key).unwrap();
        let (_, parsed) = x509_parser::parse_x509_certificate(expired.der()).unwrap();
        verifier.pin = format!("{:x}", Sha256::digest(parsed.public_key().raw));

        assert!(verifier
            .verify_server_cert(expired.der(), &[], &name, &[], UnixTime::now())
            .is_err());
    }

    #[test]
    fn pinned_tls_verifies_key_possession_in_an_in_memory_handshake() {
        let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let (_, parsed) = x509_parser::parse_x509_certificate(identity.cert.der()).unwrap();
        let pin = format!("{:x}", Sha256::digest(parsed.public_key().raw));
        assert!(handshake(&pin, &identity).is_ok());
        assert!(handshake(&"00".repeat(32), &identity).is_err());
    }

    #[test]
    fn retained_peer_requires_a_completed_tls13_handshake() {
        let tls = PinnedTls::new(&"00".repeat(32)).unwrap();
        let connection = rustls::ClientConnection::new(
            tls.config.clone(),
            ServerName::try_from("localhost").unwrap(),
        )
        .unwrap();
        let error = tls.verify_peer(&connection).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
        assert!(error
            .to_string()
            .contains("completed pinned TLS 1.3 handshake"));
    }

    #[test]
    fn retained_peer_rechecks_pin_and_certificate_validity() {
        let key_pair = rcgen::KeyPair::generate().unwrap();
        let mut parameters = rcgen::CertificateParams::new(vec!["localhost".into()]).unwrap();
        parameters.not_before = rcgen::date_time_ymd(2000, 1, 1);
        parameters.not_after = rcgen::date_time_ymd(2100, 1, 1);
        let identity = rcgen::CertifiedKey {
            cert: parameters.self_signed(&key_pair).unwrap(),
            key_pair,
        };
        let (_, parsed) = x509_parser::parse_x509_certificate(identity.cert.der()).unwrap();
        let pin = format!("{:x}", Sha256::digest(parsed.public_key().raw));
        let tls = PinnedTls::new(&pin).unwrap();
        let connection = handshake(&pin, &identity).unwrap();
        assert!(tls.verify_peer(&connection).is_ok());

        let wrong_pin = PinnedTls::new(&"00".repeat(32)).unwrap();
        let error = wrong_pin.verify_peer(&connection).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
        assert!(error.to_string().contains("public key does not match"));

        let before = UnixTime::since_unix_epoch(Duration::from_secs(
            u64::try_from(parsed.validity().not_before.timestamp() - 1).unwrap(),
        ));
        let after = UnixTime::since_unix_epoch(Duration::from_secs(
            u64::try_from(parsed.validity().not_after.timestamp() + 1).unwrap(),
        ));
        for time in [before, after] {
            let error = tls.verify_peer_at(&connection, time).unwrap_err();
            assert_eq!(error.kind(), io::ErrorKind::InvalidData);
            assert!(error.to_string().contains("expired or not yet valid"));
        }
    }

    #[test]
    fn retained_peer_reuse_requires_an_idle_plaintext_buffer_without_tls_eof() {
        let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let (_, parsed) = x509_parser::parse_x509_certificate(identity.cert.der()).unwrap();
        let pin = format!("{:x}", Sha256::digest(parsed.public_key().raw));
        let tls = PinnedTls::new(&pin).unwrap();
        let (mut client, mut server) = handshake_pair(&pin, &identity).unwrap();
        assert!(tls.reusable_peer(&mut client));
        assert!(tls.reusable_peer(&mut client));

        server.writer().write_all(b"unsolicited plaintext").unwrap();
        let mut bytes = Vec::new();
        server.write_tls(&mut bytes).unwrap();
        client.read_tls(&mut bytes.as_slice()).unwrap();
        client.process_new_packets().unwrap();
        assert!(!tls.reusable_peer(&mut client));

        let (mut client, mut server) = handshake_pair(&pin, &identity).unwrap();
        server.send_close_notify();
        let mut bytes = Vec::new();
        server.write_tls(&mut bytes).unwrap();
        client.read_tls(&mut bytes.as_slice()).unwrap();
        client.process_new_packets().unwrap();
        assert!(!tls.reusable_peer(&mut client));
    }

    fn handshake(
        pin: &str,
        identity: &rcgen::CertifiedKey,
    ) -> Result<rustls::ClientConnection, rustls::Error> {
        handshake_pair(pin, identity).map(|(client, _)| client)
    }

    fn handshake_pair(
        pin: &str,
        identity: &rcgen::CertifiedKey,
    ) -> Result<(rustls::ClientConnection, rustls::ServerConnection), rustls::Error> {
        let client_config = PinnedTls::new(pin).unwrap();
        let mut client = rustls::ClientConnection::new(
            client_config.config,
            ServerName::try_from("localhost").unwrap(),
        )?;
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let server_config = rustls::ServerConfig::builder_with_provider(provider)
            .with_protocol_versions(&[&rustls::version::TLS13])?
            .with_no_client_auth()
            .with_single_cert(
                vec![identity.cert.der().clone()],
                rustls::pki_types::PrivatePkcs8KeyDer::from(identity.key_pair.serialize_der())
                    .into(),
            )?;
        let mut server = rustls::ServerConnection::new(Arc::new(server_config))?;

        for _ in 0..20 {
            let mut bytes = Vec::new();
            client.write_tls(&mut bytes).unwrap();
            server.read_tls(&mut bytes.as_slice()).unwrap();
            server.process_new_packets()?;
            let mut bytes = Vec::new();
            server.write_tls(&mut bytes).unwrap();
            client.read_tls(&mut bytes.as_slice()).unwrap();
            client.process_new_packets()?;

            if !client.is_handshaking() && !server.is_handshaking() {
                return Ok((client, server));
            }
        }

        Err(rustls::Error::General(
            "in-memory TLS handshake did not finish".into(),
        ))
    }
}
