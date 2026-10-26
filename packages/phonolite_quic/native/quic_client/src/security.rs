//! Provisional TLS carries only a public health check or PAKE messages, never a
//! password or bearer token. Only OPAQUE authentication can establish a new pin.
use argon2::{Algorithm, Argon2, Params, Version};
use base64::{engine::general_purpose::STANDARD, Engine};
use opaque_ke::{
    CipherSuite, ClientLogin, ClientLoginFinishParameters, CredentialResponse, Identifiers,
    Ristretto255, TripleDh,
};
use rustls::{
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    pki_types::{CertificateDer, ServerName, UnixTime},
    DigitallySignedStruct, SignatureScheme,
};
use serde::Deserialize;
use sha2::{Digest, Sha256, Sha512};
use std::{
    ffi::{CStr, CString},
    io::{BufReader, Read, Write},
    net::{TcpStream, ToSocketAddrs},
    os::raw::c_char,
    sync::Arc,
    time::{Duration, Instant},
};
use zeroize::Zeroizing;

const PROFILE: &str = "phonolite-opaque-v1";
const SERVER_IDENTITY: &[u8] = b"phonolite-server-v1";
const IDENTITY_CHANGED: &str =
    "Server identity changed. Sign in again to verify the new server key.";
struct Suite;
impl CipherSuite for Suite {
    type OprfCs = Ristretto255;
    type KeyExchange = TripleDh<Ristretto255, Sha512>;
    type Ksf = Argon2<'static>;
}

pub fn spki(cert: &[u8]) -> Result<String, String> {
    let (_, cert) = x509_parser::parse_x509_certificate(cert).map_err(|_| "invalid certificate")?;
    Ok(format!("{:x}", Sha256::digest(cert.public_key().raw)))
}

pub fn valid_certificate(cert: &[u8]) -> bool {
    x509_parser::parse_x509_certificate(cert).is_ok_and(|(_, cert)| cert.validity().is_valid())
}

#[derive(Debug)]
struct ProvisionalVerifier {
    pin: Option<String>,
    algorithms: rustls::crypto::WebPkiSupportedAlgorithms,
}
impl ServerCertVerifier for ProvisionalVerifier {
    fn verify_server_cert(
        &self,
        cert: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        let (_, parsed) = x509_parser::parse_x509_certificate(cert.as_ref())
            .map_err(|_| rustls::Error::General("invalid certificate".into()))?;
        let time = x509_parser::time::ASN1Time::from_timestamp(now.as_secs() as i64)
            .map_err(|_| rustls::Error::General("invalid time".into()))?;
        if !parsed.validity().is_valid_at(time) {
            return Err(rustls::Error::General(
                "server certificate is expired or not yet valid; check the device date and time"
                    .into(),
            ));
        }
        if self
            .pin
            .as_ref()
            .is_some_and(|pin| spki(cert.as_ref()).as_ref() != Ok(pin))
        {
            return Err(rustls::Error::General(
                "server public key does not match the saved key".into(),
            ));
        }
        Ok(ServerCertVerified::assertion())
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
        cert: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(message, cert, signature, &self.algorithms)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LoginRequest {
    host: String,
    port: u16,
    username: String,
    password: String,
    expected_spki: Option<String>,
    expected_opaque: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ProbeRequest {
    host: String,
    port: u16,
    expected_spki: Option<String>,
}

// A single deadline covers TCP, TLS, and the complete health response, including
// servers that send response bytes slowly. Login keeps its existing IO timeout.
struct TimedSocket {
    socket: TcpStream,
    deadline: Option<Instant>,
}

impl TimedSocket {
    fn timeout(&self) -> std::io::Result<Duration> {
        self.deadline
            .map_or(Ok(Duration::from_secs(15)), |deadline| {
                deadline
                    .checked_duration_since(Instant::now())
                    .ok_or_else(|| {
                        std::io::Error::new(std::io::ErrorKind::TimedOut, "Connection timed out")
                    })
            })
    }
}

impl Read for TimedSocket {
    fn read(&mut self, bytes: &mut [u8]) -> std::io::Result<usize> {
        self.socket.set_read_timeout(Some(self.timeout()?))?;
        self.socket.read(bytes)
    }
}

impl Write for TimedSocket {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.socket.set_write_timeout(Some(self.timeout()?))?;
        self.socket.write(bytes)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.socket.flush()
    }
}

fn connect_tls(
    host: &str,
    port: u16,
    pin: Option<String>,
    deadline: Option<Instant>,
) -> Result<rustls::StreamOwned<rustls::ClientConnection, TimedSocket>, String> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let verifier = ProvisionalVerifier {
        pin,
        algorithms: provider.signature_verification_algorithms,
    };
    let mut config = rustls::ClientConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(|_| "TLS unavailable")?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(verifier))
        .with_no_client_auth();
    config.alpn_protocols = vec![b"http/1.1".to_vec()];
    config.enable_early_data = false;
    let name = ServerName::try_from(host.to_owned()).map_err(|_| "Invalid server address")?;
    let addresses = (host, port)
        .to_socket_addrs()
        .map_err(|_| "Unable to resolve server")?;
    let mut socket = None;
    for address in addresses.take(4) {
        let timeout = match deadline {
            Some(deadline) => deadline
                .checked_duration_since(Instant::now())
                .ok_or("Connection timed out; check the server address and port")?,
            None => Duration::from_secs(8),
        };
        if let Ok(stream) = TcpStream::connect_timeout(&address, timeout) {
            socket = Some(stream);
            break;
        }
    }
    let socket = socket.ok_or("Unable to connect to server")?;
    let mut stream = rustls::StreamOwned::new(
        rustls::ClientConnection::new(Arc::new(config), name).map_err(|_| "TLS unavailable")?,
        TimedSocket { socket, deadline },
    );
    while stream.conn.is_handshaking() {
        stream
            .conn
            .complete_io(&mut stream.sock)
            .map_err(|error| format!("TLS handshake failed ({:?}): {error}", error.kind()))?;
    }
    Ok(stream)
}

fn probe(request: ProbeRequest) -> Result<serde_json::Value, String> {
    if request.host.is_empty() || request.host.len() > 253 || request.port == 0 {
        return Err("Invalid server address or port".into());
    }
    let deadline = Instant::now() + Duration::from_secs(8);
    let stream = connect_tls(&request.host, request.port, None, Some(deadline))?;
    let cert = stream
        .conn
        .peer_certificates()
        .and_then(|certs| certs.first())
        .ok_or("Missing server identity")?;
    check_probe_identity(cert.as_ref(), request.expected_spki.as_deref())?;
    let authority = authority(&request.host, request.port);
    check_health(&mut BufReader::new(stream), &authority)?;
    // Reachability never registers or returns a trusted server identity.
    Ok(serde_json::json!({"ok": true}))
}

fn check_probe_identity(cert: &[u8], expected: Option<&str>) -> Result<(), String> {
    if expected.is_some_and(|expected| spki(cert).as_deref() != Ok(expected)) {
        return Err(IDENTITY_CHANGED.into());
    }
    Ok(())
}

fn login_tls_pin(spki: Option<&str>, opaque: Option<&str>) -> Option<String> {
    // A password-authenticated sign-in can renew the TLS pin only while proving
    // the already remembered OPAQUE identity on this connection's TLS exporter.
    // Other callers keep strict TLS pinning.
    if opaque.is_some_and(|opaque| !opaque.is_empty()) {
        None
    } else {
        spki.map(str::to_owned)
    }
}

fn authority(host: &str, port: u16) -> String {
    if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

fn check_health<T: Read + Write>(io: &mut BufReader<T>, authority: &str) -> Result<(), String> {
    let started = Instant::now();
    write!(io.get_mut(), "GET /api/health HTTP/1.1\r\nHost: {authority}\r\nAccept: application/json\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n")
        .map_err(|_| "Server health check disconnected")?;
    io.get_mut()
        .flush()
        .map_err(|_| "Server health check disconnected")?;
    let response = read_json_response(io, started).map_err(|_| {
        "Server did not return a valid Phonolite health response; check the address and port"
    })?;
    if response["status"] != "ok" {
        return Err("Server is not ready; check the address and port".into());
    }
    Ok(())
}

fn login(request: LoginRequest) -> Result<serde_json::Value, String> {
    let password = Zeroizing::new(request.password);
    let username = request.username.trim().to_ascii_lowercase();
    if request.host.is_empty()
        || request.host.len() > 253
        || request.port == 0
        || username.is_empty()
        || username.len() > 128
        || password.is_empty()
        || password.len() > 1024
    {
        return Err("Invalid sign-in details".into());
    }
    let tls_pin = login_tls_pin(
        request.expected_spki.as_deref(),
        request.expected_opaque.as_deref(),
    );
    let stream = connect_tls(&request.host, request.port, tls_pin, None)?;
    let cert = stream
        .conn
        .peer_certificates()
        .and_then(|c| c.first())
        .ok_or("Missing server identity")?;
    let pin = spki(cert.as_ref())?;
    let mut binding = [0u8; 32];
    stream
        .conn
        .export_keying_material(&mut binding, b"EXPORTER-Channel-Binding", Some(&[]))
        .map_err(|_| "Channel binding unavailable")?;
    let context = login_context(&binding, &username);
    let mut rng = rand08::rngs::OsRng;
    let first =
        ClientLogin::<Suite>::start(&mut rng, password.as_bytes()).map_err(|_| "Sign-in failed")?;
    let authority = authority(&request.host, request.port);
    let mut io = BufReader::new(stream);
    let start = post(
        &mut io,
        &authority,
        "/api/auth/opaque/start",
        serde_json::json!({"profile": PROFILE,"username":username,"message": STANDARD.encode(first.message.serialize())}),
    )?;
    if start["profile"] != PROFILE {
        return Err("Unsupported authentication profile".into());
    }
    let message = STANDARD
        .decode(start["message"].as_str().ok_or("Invalid handshake")?)
        .map_err(|_| "Invalid handshake")?;
    let proof = finish_login(
        first.state,
        password.as_bytes(),
        &context,
        &message,
        request.expected_opaque.as_deref(),
    )?;
    let opaque = STANDARD.encode(proof.server_s_pk.serialize());
    let mut result = post(
        &mut io,
        &authority,
        "/api/auth/opaque/finish",
        serde_json::json!({"attempt":start["attempt"],"message":STANDARD.encode(proof.message.serialize())}),
    )?;
    if result["token"].as_str().is_none_or(|s| s.is_empty()) {
        return Err("Invalid sign-in response".into());
    }
    result["spki_sha256"] = pin.into();
    result["opaque_key"] = opaque.into();
    result["ok"] = true.into();
    Ok(result)
}

fn authentication_hash() -> Argon2<'static> {
    Argon2::new(
        Algorithm::Argon2id,
        Version::V0x13,
        Params::new(65536, 3, 1, None).unwrap(),
    )
}

fn login_context(binding: &[u8; 32], username: &str) -> Vec<u8> {
    let mut context = PROFILE.as_bytes().to_vec();
    context.push(0);
    context.extend_from_slice(binding);
    context.extend_from_slice(username.as_bytes());
    context
}

fn finish_login(
    state: ClientLogin<Suite>,
    password: &[u8],
    context: &[u8],
    message: &[u8],
    expected_opaque: Option<&str>,
) -> Result<opaque_ke::ClientLoginFinishResult<Suite>, String> {
    let hash = authentication_hash();
    let proof = state
        .finish(
            &mut rand08::rngs::OsRng,
            password,
            CredentialResponse::<Suite>::deserialize(message).map_err(|_| "Invalid handshake")?,
            ClientLoginFinishParameters::new(
                Some(&context),
                Identifiers {
                    client: None,
                    server: Some(SERVER_IDENTITY),
                },
                Some(&hash),
            ),
        )
        .map_err(|_| "Unable to sign in; check credentials and server identity")?;
    let opaque = STANDARD.encode(proof.server_s_pk.serialize());
    if expected_opaque.is_some_and(|expected| expected != opaque) {
        return Err(
            "Server authentication identity changed; restore the server security backup".into(),
        );
    }
    Ok(proof)
}

fn post<T: Read + Write>(
    io: &mut BufReader<T>,
    authority: &str,
    path: &str,
    body: serde_json::Value,
) -> Result<serde_json::Value, String> {
    let started = Instant::now();
    let body = serde_json::to_vec(&body).map_err(|_| "Invalid handshake")?;
    write!(io.get_mut(), "POST {path} HTTP/1.1\r\nHost: {authority}\r\nUser-Agent: Phonolite/{} ({})\r\nContent-Type: application/json\r\nAccept-Encoding: identity\r\nContent-Length: {}\r\n\r\n", env!("CARGO_PKG_VERSION"), std::env::consts::OS, body.len()).map_err(|_| "Handshake disconnected")?;
    io.get_mut()
        .write_all(&body)
        .map_err(|_| "Handshake disconnected")?;
    io.get_mut().flush().map_err(|_| "Handshake disconnected")?;
    read_json_response(io, started)
}

fn read_json_response<T: Read>(
    io: &mut BufReader<T>,
    started: Instant,
) -> Result<serde_json::Value, String> {
    let mut header = Vec::new();
    // Bound each byte before allocating. No redirects, chunking, or compression.
    while !header.ends_with(b"\r\n\r\n") {
        if header.len() >= 8192 || started.elapsed() > Duration::from_secs(25) {
            return Err("Invalid handshake response".into());
        }
        let mut byte = [0];
        io.read_exact(&mut byte)
            .map_err(|_| "Handshake disconnected")?;
        header.push(byte[0]);
    }
    let header = std::str::from_utf8(&header).map_err(|_| "Invalid handshake response")?;
    let mut lines = header.split("\r\n");
    let status = lines.next().unwrap_or_default();
    if !status.starts_with("HTTP/1.1 200 ") {
        return Err(if status.contains(" 429 ") {
            "Too many sign-in attempts; try again later"
        } else {
            "Unable to sign in; check credentials and server enrollment"
        }
        .into());
    }
    let mut length = None;
    for line in lines {
        if let Some((key, value)) = line.split_once(':') {
            if key.eq_ignore_ascii_case("content-length") {
                if length.is_some() {
                    return Err("Invalid handshake response".into());
                }
                length = value.trim().parse::<usize>().ok();
            }
            if key.eq_ignore_ascii_case("transfer-encoding")
                || (key.eq_ignore_ascii_case("content-encoding") && value.trim() != "identity")
            {
                return Err("Unsupported handshake response".into());
            }
        }
    }
    let length = length
        .filter(|n| *n <= 8192)
        .ok_or("Invalid handshake response")?;
    let mut body = vec![0; length];
    io.read_exact(&mut body)
        .map_err(|_| "Handshake disconnected")?;
    serde_json::from_slice(&body).map_err(|_| "Invalid handshake response".into())
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_security_probe(request: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if request.is_null() {
            return Err("Missing server address and port".into());
        }
        let request = serde_json::from_slice::<ProbeRequest>(CStr::from_ptr(request).to_bytes())
            .map_err(|_| "Invalid server address or port")?;
        probe(request)
    })
    .unwrap_or_else(|_| Err("Server connection check unavailable".into()));
    let response = result.unwrap_or_else(|error: String| {
        if error == IDENTITY_CHANGED {
            serde_json::json!({"ok":false,"error":error,"code":"server_identity_changed"})
        } else {
            serde_json::json!({"ok":false,"error":error})
        }
    });
    CString::new(response.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_security_login(request: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if request.is_null() {
            return Err("Missing sign-in details".into());
        }
        let raw = Zeroizing::new(CStr::from_ptr(request).to_bytes().to_vec());
        let request =
            serde_json::from_slice::<LoginRequest>(&raw).map_err(|_| "Invalid sign-in details")?;
        login(request)
    })
    .unwrap_or_else(|_| Err("Authentication unavailable".into()));
    let response =
        result.unwrap_or_else(|error: String| serde_json::json!({"ok":false,"error":error}));
    CString::new(response.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_security_spki(cert: *const u8, len: usize) -> *mut c_char {
    if cert.is_null() || len == 0 || len > 65536 {
        return std::ptr::null_mut();
    }
    let der = std::slice::from_raw_parts(cert, len);
    if !valid_certificate(der) {
        return std::ptr::null_mut();
    }
    spki(der)
        .ok()
        .and_then(|pin| CString::new(pin).ok())
        .map_or(std::ptr::null_mut(), CString::into_raw)
}

#[cfg(test)]
mod tests {
    use super::*;
    use opaque_ke::{
        ClientRegistration, ClientRegistrationFinishParameters, ServerLogin, ServerLoginParameters,
        ServerRegistration, ServerSetup,
    };

    fn registration(setup: &ServerSetup<Suite>) -> (ServerRegistration<Suite>, String) {
        let mut rng = rand08::rngs::OsRng;
        let start = ClientRegistration::<Suite>::start(&mut rng, b"correct-password").unwrap();
        let response = ServerRegistration::start(setup, start.message, b"user-id").unwrap();
        let hash = authentication_hash();
        let upload = start
            .state
            .finish(
                &mut rng,
                b"correct-password",
                response.message,
                ClientRegistrationFinishParameters::new(
                    Identifiers {
                        client: None,
                        server: Some(SERVER_IDENTITY),
                    },
                    Some(&hash),
                ),
            )
            .unwrap();
        let pin = STANDARD.encode(upload.server_s_pk.serialize());
        (ServerRegistration::finish(upload.message), pin)
    }

    fn authenticate_in_memory(
        setup: &ServerSetup<Suite>,
        file: &ServerRegistration<Suite>,
        password: &[u8],
        client_context: &[u8],
        server_context: &[u8],
        pin: &str,
    ) -> Result<(), String> {
        let mut rng = rand08::rngs::OsRng;
        let start = ClientLogin::<Suite>::start(&mut rng, password).unwrap();
        let parameters = ServerLoginParameters {
            context: Some(server_context),
            identifiers: Identifiers {
                client: None,
                server: Some(SERVER_IDENTITY),
            },
        };
        let response = ServerLogin::start(
            &mut rng,
            setup,
            Some(file.clone()),
            start.message,
            b"user-id",
            parameters.clone(),
        )
        .unwrap();
        let proof = finish_login(
            start.state,
            password,
            client_context,
            &response.message.serialize(),
            Some(pin),
        )?;
        let authenticated = response.state.finish(proof.message, parameters).unwrap();
        assert_eq!(proof.session_key, authenticated.session_key);
        Ok(())
    }

    #[test]
    fn tls_key_rotation_requires_password_known_opaque_key_and_matching_channel() {
        let old = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let new = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let old_pin = spki(old.cert.der()).unwrap();
        let setup = ServerSetup::<Suite>::new(&mut rand08::rngs::OsRng);
        let (file, opaque_pin) = registration(&setup);
        assert!(handshake(Some(old_pin.clone()), &new).is_err());
        assert_eq!(
            check_probe_identity(new.cert.der(), Some(&old_pin)).unwrap_err(),
            IDENTITY_CHANGED
        );
        assert!(check_probe_identity(old.cert.der(), Some(&old_pin)).is_ok());
        assert_eq!(login_tls_pin(Some(&old_pin), None), Some(old_pin.clone()));
        let pin = login_tls_pin(Some(&old_pin), Some(&opaque_pin));
        assert!(pin.is_none());
        let (client_binding, server_binding) = handshake(pin, &new).unwrap();
        let context = login_context(&client_binding, "listener");
        let server_context = login_context(&server_binding, "listener");
        authenticate_in_memory(
            &setup,
            &file,
            b"correct-password",
            &context,
            &server_context,
            &opaque_pin,
        )
        .unwrap();
        assert!(authenticate_in_memory(
            &setup,
            &file,
            b"wrong-password",
            &context,
            &server_context,
            &opaque_pin
        )
        .is_err());
        let (other_channel, _) = handshake(None, &new).unwrap();
        assert!(authenticate_in_memory(
            &setup,
            &file,
            b"correct-password",
            &context,
            &login_context(&other_channel, "listener"),
            &opaque_pin
        )
        .is_err());
        let impostor = ServerSetup::<Suite>::new(&mut rand08::rngs::OsRng);
        let (other_file, _) = registration(&impostor);
        assert!(authenticate_in_memory(
            &impostor,
            &other_file,
            b"correct-password",
            &context,
            &server_context,
            &opaque_pin
        )
        .unwrap_err()
        .contains("authentication identity changed"));
        // The normal API/stream verifier still rejects the old pin afterwards;
        // only the successful login result authorizes saving the replacement.
        assert!(handshake(Some(old_pin), &new).is_err());
    }

    fn handshake(
        pin: Option<String>,
        identity: &rcgen::CertifiedKey,
    ) -> Result<([u8; 32], [u8; 32]), rustls::Error> {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let config = rustls::ClientConfig::builder_with_provider(provider.clone())
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(ProvisionalVerifier {
                pin,
                algorithms: provider.signature_verification_algorithms,
            }))
            .with_no_client_auth();
        let key = rustls::pki_types::PrivatePkcs8KeyDer::from(identity.key_pair.serialize_der());
        let config_server = rustls::ServerConfig::builder_with_provider(provider)
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(vec![identity.cert.der().clone()], key.into())
            .unwrap();
        let mut client = rustls::ClientConnection::new(
            Arc::new(config),
            ServerName::try_from("localhost").unwrap(),
        )
        .unwrap();
        let mut server = rustls::ServerConnection::new(Arc::new(config_server)).unwrap();
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
                let mut c = [0; 32];
                let mut s = [0; 32];
                client.export_keying_material(&mut c, b"EXPORTER-Channel-Binding", Some(&[]))?;
                server.export_keying_material(&mut s, b"EXPORTER-Channel-Binding", Some(&[]))?;
                return Ok((c, s));
            }
        }
        panic!("in-memory TLS handshake did not complete")
    }
    #[test]
    fn tls_proves_key_possession_and_exporter_is_unique_per_connection() {
        let identity = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let pin = spki(identity.cert.der()).unwrap();
        let (client, server) = handshake(None, &identity).unwrap();
        assert_eq!(client, server);
        let (next, _) = handshake(Some(pin), &identity).unwrap();
        assert_ne!(client, next);
        assert!(handshake(Some("00".repeat(32)), &identity).is_err());
    }
    #[test]
    fn certificate_renewal_keeps_pin_but_key_replacement_changes_it() {
        let first = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let renewed = rcgen::CertificateParams::new(vec!["localhost".into()])
            .unwrap()
            .self_signed(&first.key_pair)
            .unwrap();
        assert_eq!(
            spki(first.cert.der()).unwrap(),
            spki(renewed.der()).unwrap()
        );
        let different = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        assert_ne!(
            spki(first.cert.der()).unwrap(),
            spki(different.cert.der()).unwrap()
        );
        assert!(valid_certificate(renewed.der()));
        assert!(!valid_certificate(b"invalid"));
    }
    #[test]
    fn exported_certificate_pin_rejects_expired_or_malformed_certificates() {
        let key = rcgen::KeyPair::generate().unwrap();
        let mut parameters = rcgen::CertificateParams::new(vec!["localhost".into()]).unwrap();
        parameters.not_before = rcgen::date_time_ymd(2010, 1, 1);
        parameters.not_after = rcgen::date_time_ymd(2020, 1, 1);
        let expired = parameters.self_signed(&key).unwrap();
        let valid = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        unsafe {
            assert!(phonolite_security_spki(expired.der().as_ptr(), expired.der().len()).is_null());
            assert!(phonolite_security_spki(b"invalid".as_ptr(), 7).is_null());
            let value = phonolite_security_spki(valid.cert.der().as_ptr(), valid.cert.der().len());
            assert!(!value.is_null());
            assert_eq!(
                CStr::from_ptr(value).to_str().unwrap(),
                spki(valid.cert.der()).unwrap()
            );
            drop(CString::from_raw(value));
        }
    }
    struct MockIo {
        read: std::io::Cursor<Vec<u8>>,
        write: Vec<u8>,
    }
    impl Read for MockIo {
        fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
            self.read.read(buf)
        }
    }
    impl Write for MockIo {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.write.extend_from_slice(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    fn health_io(status: &str, body: &str) -> BufReader<MockIo> {
        BufReader::new(MockIo {
            read: std::io::Cursor::new(
                format!(
                    "HTTP/1.1 {status}\r\nContent-Length: {}\r\n\r\n{body}",
                    body.len()
                )
                .into_bytes(),
            ),
            write: Vec::new(),
        })
    }

    #[test]
    fn connection_check_requests_only_public_health_without_credentials() {
        let mut io = health_io("200 OK", r#"{"status":"ok"}"#);
        check_health(&mut io, "localhost:3000").unwrap();
        assert_eq!(
            String::from_utf8(io.get_ref().write.clone()).unwrap(),
            "GET /api/health HTTP/1.1\r\nHost: localhost:3000\r\nAccept: application/json\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n"
        );
        assert_eq!(authority("::1", 3000), "[::1]:3000");
    }

    #[test]
    fn connection_check_rejects_wrong_services_redirects_and_unhealthy_servers() {
        for (status, body) in [
            ("200 OK", "<html>Other service</html>"),
            ("200 OK", r#"{"status":"unavailable"}"#),
            ("200 OK", r#"{"ok":true}"#),
            ("200 OK", "[]"),
            ("302 Found", r#"{"status":"ok"}"#),
            ("401 Unauthorized", r#"{"status":"ok"}"#),
            ("404 Not Found", r#"{"status":"ok"}"#),
            ("503 Service Unavailable", r#"{"status":"ok"}"#),
        ] {
            assert!(check_health(&mut health_io(status, body), "localhost:3000").is_err());
        }
        for response in [
            "HTTP/1.1 200 OK\r\nContent-Length: 999999\r\n\r\n".to_owned(),
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n".to_owned(),
            "HTTP/1.1 200 OK\r\nContent-Length: 15\r\nContent-Length: 15\r\n\r\n".to_owned(),
            "x".repeat(9000),
        ] {
            let mut io = BufReader::new(MockIo {
                read: std::io::Cursor::new(response.into_bytes()),
                write: Vec::new(),
            });
            assert!(check_health(&mut io, "localhost:3000").is_err());
        }
    }

    #[test]
    fn connection_check_rejects_invalid_details_before_opening_a_socket() {
        for raw in [
            r#"{"host":"","port":3000}"#,
            r#"{"host":"localhost","port":0}"#,
            r#"{"host":"localhost","port":65536}"#,
            r#"{"host":"localhost","port":3000,"password":"secret"}"#,
        ] {
            let request = CString::new(raw).unwrap();
            unsafe {
                let output = phonolite_security_probe(request.as_ptr());
                let response: serde_json::Value =
                    serde_json::from_str(CStr::from_ptr(output).to_str().unwrap()).unwrap();
                drop(CString::from_raw(output));
                assert_eq!(response["ok"], false);
                assert!(response["spki_sha256"].is_null());
                assert!(response["token"].is_null());
            }
        }
    }

    #[test]
    fn handshake_http_identifies_app_and_platform() {
        let mut io = BufReader::new(MockIo {
            read: std::io::Cursor::new(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".to_vec()),
            write: Vec::new(),
        });
        post(
            &mut io,
            "localhost:3000",
            "/api/auth/opaque/finish",
            serde_json::json!({"message":"proof"}),
        )
        .unwrap();
        let request = String::from_utf8(io.get_ref().write.clone()).unwrap();
        assert!(request.contains(&format!(
            "\r\nUser-Agent: Phonolite/{} ({})\r\n",
            env!("CARGO_PKG_VERSION"),
            std::env::consts::OS
        )));
    }

    #[test]
    fn handshake_http_is_bounded_and_never_follows_redirects() {
        for response in [
            "HTTP/1.1 302 Found\r\nLocation: http://attacker\r\nContent-Length: 2\r\n\r\n{}"
                .to_string(),
            "HTTP/1.1 200 OK\r\nContent-Length: 999999\r\n\r\n".into(),
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n".into(),
            "x".repeat(9000),
        ] {
            let mut io = BufReader::new(MockIo {
                read: std::io::Cursor::new(response.into_bytes()),
                write: Vec::new(),
            });
            assert!(post(
                &mut io,
                "localhost:3000",
                "/api/auth/opaque/start",
                serde_json::json!({"message":"proof"})
            )
            .is_err());
        }
    }
}
