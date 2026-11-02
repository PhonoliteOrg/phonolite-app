//! Socket and path ownership for optional, bounded client address migration.
use std::io;
use std::net::{SocketAddr, UdpSocket};
use std::time::{Duration, Instant};

pub(crate) const VALIDATION_TIMEOUT: Duration = Duration::from_secs(1);
const OLD_PATH_GRACE: Duration = Duration::from_millis(250);
const CONFIRMATION_STREAM: u64 = 2;

pub(crate) struct RouteSocket {
    pub socket: UdpSocket,
    pub local: SocketAddr,
    retire_at: Option<Instant>,
}

impl RouteSocket {
    pub fn connect(peer: SocketAddr) -> io::Result<Self> {
        let socket = UdpSocket::bind(if peer.is_ipv4() {
            "0.0.0.0:0"
        } else {
            "[::]:0"
        })?;
        socket.connect(peer)?;
        socket.set_nonblocking(true)?;
        let local = socket.local_addr()?;
        if local.ip().is_unspecified() {
            return Err(io::Error::new(
                io::ErrorKind::AddrNotAvailable,
                "route has no concrete local address",
            ));
        }
        Ok(Self {
            socket,
            local,
            retire_at: None,
        })
    }
}

pub(crate) struct RouteSockets {
    pub routes: Vec<RouteSocket>,
    peer: SocketAddr,
}

impl RouteSockets {
    pub fn new(peer: SocketAddr) -> io::Result<Self> {
        Ok(Self {
            routes: vec![RouteSocket::connect(peer)?],
            peer,
        })
    }

    pub fn candidate(&mut self) -> io::Result<SocketAddr> {
        self.retire(Instant::now());
        if self.routes.len() >= 2 {
            return Err(io::Error::new(
                io::ErrorKind::WouldBlock,
                "another path is still owned",
            ));
        }
        let route = RouteSocket::connect(self.peer)?;
        let local = route.local;
        self.routes.push(route);
        Ok(local)
    }

    pub fn send(&self, bytes: &[u8], from: SocketAddr, to: SocketAddr) -> io::Result<usize> {
        if to != self.peer {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "server endpoint migration is not permitted",
            ));
        }
        let route = self
            .routes
            .iter()
            .find(|route| route.local == from)
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::AddrNotAvailable,
                    "packet belongs to a retired local path",
                )
            })?;
        route.socket.send(bytes)
    }

    pub fn activate(&mut self, local: SocketAddr, now: Instant) {
        for route in &mut self.routes {
            route.retire_at = (route.local != local).then_some(now + OLD_PATH_GRACE);
        }
    }

    pub fn retire(&mut self, now: Instant) {
        self.routes
            .retain(|route| route.retire_at.is_none_or(|at| now < at));
    }

    pub fn owns(&self, local: SocketAddr) -> bool {
        self.routes.iter().any(|route| route.local == local)
    }
}

#[derive(Default)]
pub(crate) struct HandshakeConfirmation {
    marker_started: bool,
    pub confirmed: bool,
}

impl HandshakeConfirmation {
    pub fn update(&mut self, conn: &mut quiche::Connection, identity_verified: bool) {
        if self.confirmed || !identity_verified || !conn.is_established() {
            return;
        }
        if !self.marker_started {
            // quiche 0.20 exposes completion, not confirmation. Collection of a
            // locally created uni stream proves its 1-RTT FIN/data were ACKed,
            // the alternate confirmation rule in RFC 9001 section 4.1.2.
            self.marker_started = conn.stream_send(CONFIRMATION_STREAM, &[0], true) == Ok(1);
        } else if matches!(
            conn.stream_capacity(CONFIRMATION_STREAM),
            Err(quiche::Error::InvalidStreamState(_))
        ) {
            self.confirmed = true;
        }
    }
}

pub(crate) fn permitted(
    conn: &quiche::Connection,
    confirmed: bool,
    identity_verified: bool,
) -> bool {
    confirmed
        && identity_verified
        && conn.is_established()
        && !conn.is_closed()
        && !conn.is_draining()
        && conn
            .peer_transport_params()
            .is_some_and(|params| !params.disable_active_migration)
        && conn.available_dcids() > 0
}

pub(crate) fn replenish_cids(conn: &mut quiche::Connection) -> Result<(), quiche::Error> {
    while conn.scids_left() > 0 {
        let cid = super::generate_cid();
        conn.new_scid(
            &quiche::ConnectionId::from_ref(&cid),
            rand::random::<u128>(),
            false,
        )?;
    }
    while conn.retired_scid_next().is_some() {}
    Ok(())
}

pub(crate) fn activate(conn: &mut quiche::Connection, local: SocketAddr, peer: SocketAddr) -> Result<(), quiche::Error> {
    conn.migrate(local, peer)?;
    // A server changes its active client address only after a non-probing
    // packet arrives. Playback may have no application upload pending.
    conn.send_ack_eliciting()
}

pub(crate) struct PendingMigration {
    pub generation: u64,
    pub local: SocketAddr,
    pub peer: SocketAddr,
    pub deadline: Instant,
}

impl PendingMigration {
    pub fn new(generation: u64, local: SocketAddr, peer: SocketAddr, now: Instant) -> Self {
        Self {
            generation,
            local,
            peer,
            deadline: now + VALIDATION_TIMEOUT,
        }
    }

    pub fn matches(&self, local: SocketAddr, peer: SocketAddr) -> bool {
        self.local == local && self.peer == peer
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Identity(std::path::PathBuf);

    impl Identity {
        fn pipe(disable_migration: bool) -> (Self, quiche::testing::Pipe) {
            let path =
                std::env::temp_dir().join(format!("phonolite-migration-{}", rand::random::<u64>()));
            std::fs::create_dir(&path).unwrap();
            let pair = rcgen::generate_simple_self_signed(vec!["quic.tech".into()]).unwrap();
            std::fs::write(path.join("cert.pem"), pair.cert.pem()).unwrap();
            std::fs::write(path.join("key.pem"), pair.key_pair.serialize_pem()).unwrap();
            let mut config = quiche::Config::new(quiche::PROTOCOL_VERSION).unwrap();
            config
                .load_cert_chain_from_pem_file(path.join("cert.pem").to_str().unwrap())
                .unwrap();
            config
                .load_priv_key_from_pem_file(path.join("key.pem").to_str().unwrap())
                .unwrap();
            config
                .set_application_protos(super::super::ALPN_QUIC)
                .unwrap();
            config.verify_peer(false);
            config.set_initial_max_data(1024 * 1024);
            config.set_initial_max_stream_data_bidi_local(65536);
            config.set_initial_max_stream_data_bidi_remote(65536);
            config.set_initial_max_stream_data_uni(65536);
            config.set_initial_max_streams_bidi(16);
            config.set_initial_max_streams_uni(16);
            config.set_active_connection_id_limit(4);
            config.set_disable_active_migration(disable_migration);
            config.set_max_ack_delay(0);
            let mut pipe = quiche::testing::Pipe::with_config(&mut config).unwrap();
            pipe.handshake().unwrap();
            (Self(path), pipe)
        }
    }

    impl Drop for Identity {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(self.0.join("cert.pem"));
            let _ = std::fs::remove_file(self.0.join("key.pem"));
            let _ = std::fs::remove_dir(&self.0);
        }
    }

    #[test]
    fn confirmation_requires_identity_and_an_acknowledged_one_rtt_marker() {
        let (_identity, mut pipe) = Identity::pipe(false);
        let mut confirmation = HandshakeConfirmation::default();
        confirmation.update(&mut pipe.client, false);
        assert!(!confirmation.marker_started);
        confirmation.update(&mut pipe.client, true);
        confirmation.update(&mut pipe.client, true);
        assert!(confirmation.marker_started);
        assert!(!confirmation.confirmed);
        let flight = quiche::testing::emit_flight(&mut pipe.client).unwrap();
        quiche::testing::process_flight(&mut pipe.server, flight).unwrap();
        confirmation.update(&mut pipe.client, true);
        assert!(!confirmation.confirmed);
        pipe.advance().unwrap();
        confirmation.update(&mut pipe.client, true);
        assert!(confirmation.confirmed);
    }

    #[test]
    fn peer_permission_confirmation_and_spare_ids_are_all_required() {
        for disabled in [false, true] {
            let (_identity, mut pipe) = Identity::pipe(disabled);
            assert!(!permitted(&pipe.client, true, true));
            replenish_cids(&mut pipe.client).unwrap();
            replenish_cids(&mut pipe.server).unwrap();
            pipe.advance().unwrap();
            assert!(!permitted(&pipe.client, false, true));
            assert!(!permitted(&pipe.client, true, false));
            assert_eq!(permitted(&pipe.client, true, true), !disabled);
        }
    }

    #[test]
    fn validated_local_migration_retains_the_existing_application_stream() {
        let (_identity, mut pipe) = Identity::pipe(false);
        replenish_cids(&mut pipe.client).unwrap();
        replenish_cids(&mut pipe.server).unwrap();
        pipe.client.stream_send(0, b"before", false).unwrap();
        pipe.advance().unwrap();
        let mut bytes = [0; 64];
        assert_eq!(pipe.server.stream_recv(0, &mut bytes).unwrap().0, 6);
        let new_local = "127.0.0.1:9876".parse().unwrap();
        let peer = quiche::testing::Pipe::server_addr();
        pipe.client.probe_path(new_local, peer).unwrap();
        pipe.advance().unwrap();
        assert!(pipe.client.is_path_validated(new_local, peer).unwrap());
        activate(&mut pipe.client, new_local, peer).unwrap();
        pipe.advance().unwrap();
        assert!(pipe.server.path_stats().any(|path| path.active && path.peer_addr == new_local));
        pipe.client.stream_send(0, b"after", false).unwrap();
        pipe.advance().unwrap();
        let (count, finished) = pipe.server.stream_recv(0, &mut bytes).unwrap();
        assert_eq!(&bytes[..count], b"after");
        assert!(!finished);
        assert!(!pipe.client.is_closed());
    }

    #[test]
    fn path_deadline_and_server_identity_never_change_with_later_hints() {
        let local = "192.0.2.1:1000".parse().unwrap();
        let peer = "192.0.2.2:2000".parse().unwrap();
        let started = Instant::now();
        let pending = PendingMigration::new(1, local, peer, started);
        assert_eq!(pending.deadline, started + VALIDATION_TIMEOUT);
        assert!(!pending.matches(local, "192.0.2.3:2000".parse().unwrap()));
        let sockets = RouteSockets {
            routes: Vec::new(),
            peer,
        };
        assert_eq!(
            sockets
                .send(&[], local, "192.0.2.3:2000".parse().unwrap())
                .unwrap_err()
                .kind(),
            io::ErrorKind::InvalidInput
        );
    }
}
