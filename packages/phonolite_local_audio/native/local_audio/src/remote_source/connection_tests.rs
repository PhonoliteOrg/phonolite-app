use super::*;
use std::collections::VecDeque;
use std::io::Cursor;
use std::sync::Mutex;

const TEST_URL: &str = "https://music.test:8443/api/stream/track/original?variant=source";
const TEST_TOTAL: u64 = CACHE_BYTES as u64 * 3 + 13;

enum Exchange {
    Response(Vec<u8>),
    ReadError(io::ErrorKind),
    WriteError(io::ErrorKind),
    FlushError(io::ErrorKind),
}

#[derive(Clone, Debug)]
struct ConnectCall {
    id: usize,
    host: String,
    port: u16,
    deadline: Instant,
}

#[derive(Clone, Debug)]
struct PrepareCall {
    id: usize,
    deadline: Instant,
}

#[derive(Clone, Debug, Default)]
struct Observations {
    connects: Vec<ConnectCall>,
    prepares: Vec<PrepareCall>,
    requests: Vec<(usize, String)>,
    dropped: Vec<usize>,
}

struct Script {
    connections: VecDeque<VecDeque<Exchange>>,
    observations: Observations,
    fail_prepare: Option<(usize, io::ErrorKind)>,
}

#[derive(Clone)]
struct ScriptedConnector(Arc<Mutex<Script>>);

impl ScriptedConnector {
    fn new(connections: Vec<Vec<Exchange>>) -> Self {
        Self(Arc::new(Mutex::new(Script {
            connections: connections.into_iter().map(VecDeque::from).collect(),
            observations: Observations::default(),
            fail_prepare: None,
        })))
    }

    fn observations(&self) -> Observations {
        self.0.lock().unwrap().observations.clone()
    }

    fn fail_prepare(&self, call: usize, kind: io::ErrorKind) {
        self.0.lock().unwrap().fail_prepare = Some((call, kind));
    }
}

struct ScriptedStream {
    id: usize,
    owner: Arc<Mutex<Script>>,
    exchanges: VecDeque<Exchange>,
    request: Vec<u8>,
    response: Cursor<Vec<u8>>,
    read_error: Option<io::ErrorKind>,
}

impl RangeConnector for ScriptedConnector {
    type Stream = ScriptedStream;

    fn connect(&self, host: &str, port: u16, deadline: Instant) -> io::Result<Self::Stream> {
        let mut script = self.0.lock().unwrap();
        let id = script.observations.connects.len();
        script.observations.connects.push(ConnectCall {
            id,
            host: host.to_owned(),
            port,
            deadline,
        });
        if deadline <= Instant::now() {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "expired connection deadline",
            ));
        }
        let exchanges = script
            .connections
            .pop_front()
            .ok_or_else(|| io::Error::other("unexpected extra connection"))?;
        Ok(ScriptedStream {
            id,
            owner: Arc::clone(&self.0),
            exchanges,
            request: Vec::new(),
            response: Cursor::new(Vec::new()),
            read_error: None,
        })
    }

    fn prepare(&self, stream: &mut Self::Stream, deadline: Instant) -> io::Result<()> {
        let mut script = self.0.lock().unwrap();
        let call = script.observations.prepares.len();
        script.observations.prepares.push(PrepareCall {
            id: stream.id,
            deadline,
        });
        if deadline <= Instant::now() {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "expired request deadline",
            ));
        }
        if let Some((failed_call, kind)) = script.fail_prepare {
            if failed_call == call {
                return Err(io::Error::new(kind, "request security preparation failed"));
            }
        }
        Ok(())
    }
}

impl Read for ScriptedStream {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        if let Some(kind) = self.read_error.take() {
            return Err(io::Error::new(kind, "scripted response read failure"));
        }
        self.response.read(buffer)
    }
}

impl Write for ScriptedStream {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        if let Some(Exchange::WriteError(kind)) = self.exchanges.front() {
            let kind = *kind;
            self.exchanges.pop_front();
            return Err(io::Error::new(kind, "scripted stale request write"));
        }
        self.request.extend_from_slice(buffer);
        Ok(buffer.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        if self.request.is_empty() {
            return Ok(());
        }
        let request = String::from_utf8(std::mem::take(&mut self.request)).unwrap();
        self.owner
            .lock()
            .unwrap()
            .observations
            .requests
            .push((self.id, request));
        match self.exchanges.pop_front() {
            Some(Exchange::Response(bytes)) => {
                self.response = Cursor::new(bytes);
                self.read_error = None;
                Ok(())
            }
            Some(Exchange::ReadError(kind)) => {
                self.response = Cursor::new(Vec::new());
                self.read_error = Some(kind);
                Ok(())
            }
            Some(Exchange::FlushError(kind)) => {
                Err(io::Error::new(kind, "scripted stale request flush"))
            }
            Some(Exchange::WriteError(_)) => unreachable!("write errors are consumed by write"),
            None => Err(io::Error::other("unexpected extra request")),
        }
    }
}

impl Drop for ScriptedStream {
    fn drop(&mut self) {
        self.owner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .observations
            .dropped
            .push(self.id);
    }
}

fn source(connector: ScriptedConnector) -> RemoteSource<ScriptedConnector> {
    set_failure_code(0);
    RemoteSource::new(
        Url::parse(TEST_URL).unwrap(),
        "test-token".to_owned(),
        connector,
        Arc::new(AtomicBool::new(false)),
    )
}

fn window(start: u64) -> Exchange {
    Exchange::Response(range_response(
        start,
        TEST_TOTAL,
        "HTTP/1.1",
        "\"source\"",
        "",
    ))
}

fn range_response(start: u64, total: u64, version: &str, etag: &str, extra: &str) -> Vec<u8> {
    let end = start.saturating_add(CACHE_BYTES as u64 - 1).min(total - 1);
    let length = (end - start + 1) as usize;
    let mut response = format!(
        "{version} 206 Partial Content\r\nContent-Length: {length}\r\nContent-Range: bytes {start}-{end}/{total}\r\nETag: {etag}\r\n{extra}\r\n"
    )
    .into_bytes();
    response.extend((start..=end).map(|offset| (offset % 251) as u8));
    response
}

#[test]
fn sequential_ranges_and_seeks_reuse_one_connection_and_preserve_requests() {
    let connector = ScriptedConnector::new(vec![vec![
        window(0),
        window(CACHE_BYTES as u64),
        window(CACHE_BYTES as u64 * 3),
    ]]);
    let mut audio = source(connector.clone());
    audio.fetch_window().unwrap();
    let mut bytes = [0; 8];
    audio.read_exact(&mut bytes).unwrap();
    assert_eq!(bytes, [0, 1, 2, 3, 4, 5, 6, 7]);
    audio.seek(SeekFrom::Start(CACHE_BYTES as u64)).unwrap();
    audio.read_exact(&mut bytes).unwrap();
    assert_eq!(
        bytes,
        std::array::from_fn(|index| ((CACHE_BYTES + index) % 251) as u8)
    );
    let requests = connector.observations().requests.len();
    audio.seek(SeekFrom::Current(7)).unwrap();
    audio.read_exact(&mut bytes).unwrap();
    assert_eq!(
        bytes,
        std::array::from_fn(|index| ((CACHE_BYTES + 15 + index) % 251) as u8)
    );
    assert_eq!(connector.observations().requests.len(), requests);
    audio.seek(SeekFrom::Start(CACHE_BYTES as u64 * 3)).unwrap();
    audio.read_exact(&mut bytes).unwrap();
    assert_eq!(
        bytes,
        std::array::from_fn(|index| ((CACHE_BYTES * 3 + index) % 251) as u8)
    );
    audio.seek(SeekFrom::End(0)).unwrap();
    assert_eq!(audio.read(&mut bytes).unwrap(), 0);

    let observed = connector.observations();
    assert_eq!(observed.connects.len(), 1);
    assert_eq!(observed.connects[0].id, 0);
    assert_eq!(observed.connects[0].host, "music.test");
    assert_eq!(observed.connects[0].port, 8443);
    assert_eq!(observed.prepares.len(), 3);
    assert_eq!(observed.requests.len(), 3);
    for (index, (id, request)) in observed.requests.iter().enumerate() {
        assert_eq!(*id, 0);
        assert!(request.starts_with("GET /api/stream/track/original?variant=source HTTP/1.1\r\n"));
        assert!(request.contains("Host: music.test:8443\r\n"));
        assert!(request.contains("Authorization: Bearer test-token\r\n"));
        assert!(request.contains("Accept-Encoding: identity\r\n"));
        assert!(!request.to_ascii_lowercase().contains("connection: close"));
        let start = [0, CACHE_BYTES as u64, CACHE_BYTES as u64 * 3][index];
        assert!(request.contains(&format!(
            "Range: bytes={start}-{}\r\n",
            start + CACHE_BYTES as u64 - 1
        )));
        assert_eq!(request.contains("If-Range: \"source\"\r\n"), index != 0);
    }
    assert!(observed.prepares[1].deadline >= observed.prepares[0].deadline);
    assert!(observed.prepares.iter().all(|call| call.id == 0));
    assert!(observed.dropped.is_empty());
    drop(audio);
    assert_eq!(connector.observations().dropped, [0]);
}

#[test]
fn server_close_tokens_and_http10_responses_do_not_keep_a_connection() {
    for (version, headers) in [
        ("HTTP/1.1", "Connection: keep-alive, ClOsE\r\n"),
        ("HTTP/1.0", ""),
        ("HTTP/1.0", "Connection: keep-alive\r\n"),
    ] {
        let connector = ScriptedConnector::new(vec![
            vec![Exchange::Response(range_response(
                0,
                TEST_TOTAL,
                version,
                "\"source\"",
                headers,
            ))],
            vec![window(CACHE_BYTES as u64)],
        ]);
        let mut audio = source(connector.clone());
        audio.fetch_window().unwrap();
        assert_eq!(
            connector.observations().dropped,
            [0],
            "{version}: {headers}"
        );
        audio.seek(SeekFrom::Start(CACHE_BYTES as u64)).unwrap();
        audio.fetch_window().unwrap();
        assert_eq!(connector.observations().connects.len(), 2);
    }
}

#[test]
fn stale_reused_connections_retry_once_with_the_same_absolute_deadline() {
    for stale in [
        Exchange::Response(Vec::new()),
        Exchange::ReadError(io::ErrorKind::ConnectionReset),
        Exchange::ReadError(io::ErrorKind::UnexpectedEof),
        Exchange::WriteError(io::ErrorKind::BrokenPipe),
        Exchange::FlushError(io::ErrorKind::ConnectionReset),
    ] {
        let connector = ScriptedConnector::new(vec![
            vec![window(0), stale],
            vec![window(CACHE_BYTES as u64)],
        ]);
        let mut audio = source(connector.clone());
        audio.fetch_window().unwrap();
        audio.seek(SeekFrom::Start(CACHE_BYTES as u64)).unwrap();
        audio.fetch_window().unwrap();
        let observed = connector.observations();
        assert_eq!(observed.connects.len(), 2);
        assert_eq!(observed.prepares.len(), 3);
        assert_eq!(observed.prepares[1].id, 0);
        assert_eq!(observed.prepares[2].id, 1);
        assert_eq!(observed.connects[1].deadline, observed.prepares[1].deadline);
        assert_eq!(observed.prepares[2].deadline, observed.prepares[1].deadline);
        assert_eq!(audio.cache_start, CACHE_BYTES as u64);
        assert_eq!(observed.dropped, [0]);
        assert_eq!(
            failure_code(),
            0,
            "a recovered stale socket is not a playback failure"
        );
    }
}

#[test]
fn a_failed_fresh_connection_is_not_retried_and_reconnect_does_not_loop() {
    let connector =
        ScriptedConnector::new(vec![vec![Exchange::Response(Vec::new())], vec![window(0)]]);
    let mut audio = source(connector.clone());
    assert!(audio.read(&mut [0]).is_err());
    assert_eq!(failure_code(), -200);
    assert_eq!(connector.observations().connects.len(), 1);
    assert_eq!(connector.observations().dropped, [0]);
    assert!(audio.cache.is_empty());
    assert!(audio.size.is_none());
    assert!(audio.etag.is_none());

    let connector = ScriptedConnector::new(vec![
        vec![window(0), Exchange::Response(Vec::new())],
        vec![Exchange::Response(Vec::new())],
        vec![window(CACHE_BYTES as u64)],
    ]);
    let mut audio = source(connector.clone());
    audio.fetch_window().unwrap();
    audio.seek(SeekFrom::Start(CACHE_BYTES as u64)).unwrap();
    assert!(audio.read(&mut [0]).is_err());
    assert_eq!(failure_code(), -200);
    assert_eq!(connector.observations().connects.len(), 2);
    assert_eq!(connector.observations().dropped, [0, 1]);
}

#[test]
fn partial_invalid_or_truncated_responses_never_reconnect_or_change_cached_identity() {
    let start = CACHE_BYTES as u64;
    let mut short_body = range_response(start, TEST_TOTAL, "HTTP/1.1", "\"source\"", "");
    short_body.pop();
    for (name, failure) in [
        (
            "partial status",
            Exchange::Response(b"HTTP/1.1 206".to_vec()),
        ),
        (
            "partial header",
            Exchange::Response(b"HTTP/1.1 206 Partial Content\r\nContent-Len".to_vec()),
        ),
        (
            "invalid status",
            Exchange::Response(b"INVALID\r\n\r\n".to_vec()),
        ),
        (
            "redirect",
            Exchange::Response(b"HTTP/1.1 302 Found\r\n\r\n".to_vec()),
        ),
        (
            "ignored range",
            Exchange::Response(b"HTTP/1.1 200 OK\r\n\r\n".to_vec()),
        ),
        (
            "authentication",
            Exchange::Response(b"HTTP/1.1 401 Unauthorized\r\n\r\n".to_vec()),
        ),
        (
            "changed ETag",
            Exchange::Response(range_response(
                start,
                TEST_TOTAL,
                "HTTP/1.1",
                "\"changed\"",
                "",
            )),
        ),
        (
            "changed size",
            Exchange::Response(range_response(
                start,
                TEST_TOTAL + 1,
                "HTTP/1.1",
                "\"source\"",
                "",
            )),
        ),
        (
            "wrong range",
            Exchange::Response(range_response(
                start + 1,
                TEST_TOTAL,
                "HTTP/1.1",
                "\"source\"",
                "",
            )),
        ),
        (
            "duplicate length",
            Exchange::Response(range_response(
                start,
                TEST_TOTAL,
                "HTTP/1.1",
                "\"source\"",
                "Content-Length: 1\r\n",
            )),
        ),
        (
            "chunked",
            Exchange::Response(range_response(
                start,
                TEST_TOTAL,
                "HTTP/1.1",
                "\"source\"",
                "Transfer-Encoding: chunked\r\n",
            )),
        ),
        (
            "compressed",
            Exchange::Response(range_response(
                start,
                TEST_TOTAL,
                "HTTP/1.1",
                "\"source\"",
                "Content-Encoding: gzip\r\n",
            )),
        ),
        ("truncated body", Exchange::Response(short_body)),
        ("timeout", Exchange::ReadError(io::ErrorKind::TimedOut)),
        (
            "TLS integrity",
            Exchange::ReadError(io::ErrorKind::InvalidData),
        ),
    ] {
        let connector = ScriptedConnector::new(vec![vec![window(0), failure], vec![window(start)]]);
        let mut audio = source(connector.clone());
        audio.fetch_window().unwrap();
        let original = audio.cache.clone();
        audio.seek(SeekFrom::Start(start)).unwrap();
        assert!(audio.read(&mut [0]).is_err(), "{name}");
        let expected_code = match name {
            "authentication" => 401,
            "partial status" | "partial header" | "truncated body" | "timeout"
            | "TLS integrity" => -200,
            _ => -102,
        };
        assert_eq!(failure_code(), expected_code, "{name}");
        let observed = connector.observations();
        assert_eq!(observed.connects.len(), 1, "{name}");
        assert_eq!(observed.dropped, [0], "{name}");
        assert_eq!(audio.cache, original, "{name}");
        assert_eq!(audio.cache_start, 0, "{name}");
        assert_eq!(audio.size, Some(TEST_TOTAL), "{name}");
        assert_eq!(audio.etag.as_deref(), Some("\"source\""), "{name}");
    }
}

#[test]
fn reused_security_preparation_failure_sends_no_more_credentials_or_reconnect() {
    let connector = ScriptedConnector::new(vec![
        vec![window(0), window(CACHE_BYTES as u64)],
        vec![window(CACHE_BYTES as u64)],
    ]);
    connector.fail_prepare(1, io::ErrorKind::InvalidData);
    let mut audio = source(connector.clone());
    audio.fetch_window().unwrap();
    audio.seek(SeekFrom::Start(CACHE_BYTES as u64)).unwrap();
    assert_eq!(
        audio.fetch_window().unwrap_err().kind(),
        io::ErrorKind::InvalidData
    );
    let observed = connector.observations();
    assert_eq!(observed.connects.len(), 1);
    assert_eq!(observed.requests.len(), 1);
    assert_eq!(observed.dropped, [0]);
    assert_eq!(failure_code(), -100);
}

#[test]
fn opening_ranges_keep_the_original_total_budget_and_normal_reads_reset_their_budget() {
    let connector = ScriptedConnector::new(vec![vec![window(0), window(CACHE_BYTES as u64)]]);
    let mut audio = source(connector.clone());
    audio.opening.store(true, Ordering::Release);
    audio.opened_at = Instant::now() - Duration::from_secs(14);
    audio.fetch_window().unwrap();
    let expected_deadline = audio.opened_at + OPEN_TIMEOUT;
    assert_eq!(
        connector.observations().connects[0].deadline,
        expected_deadline
    );
    assert_eq!(
        connector.observations().prepares[0].deadline,
        expected_deadline
    );

    audio.opened_at = Instant::now() - OPEN_TIMEOUT - Duration::from_secs(1);
    audio.seek(SeekFrom::Start(CACHE_BYTES as u64)).unwrap();
    assert_eq!(
        audio.fetch_window().unwrap_err().kind(),
        io::ErrorKind::TimedOut
    );
    assert_eq!(connector.observations().connects.len(), 1);
    assert_eq!(connector.observations().requests.len(), 1);

    let connector = ScriptedConnector::new(vec![vec![window(0)]]);
    let mut audio = source(connector.clone());
    audio.opened_at = Instant::now() - OPEN_TIMEOUT - Duration::from_secs(1);
    let before = Instant::now();
    audio.fetch_window().unwrap();
    let deadline = connector.observations().connects[0].deadline;
    assert!(deadline >= before + REQUEST_TIMEOUT);
    assert!(deadline <= Instant::now() + REQUEST_TIMEOUT);
}

#[test]
fn unsolicited_buffered_bytes_prevent_reuse_without_discarding_the_valid_window() {
    let mut response = range_response(0, 13, "HTTP/1.1", "\"source\"", "");
    response.extend_from_slice(b"unsolicited response bytes");
    let connector = ScriptedConnector::new(vec![vec![Exchange::Response(response)]]);
    let mut audio = source(connector.clone());
    audio.fetch_window().unwrap();
    assert_eq!(audio.cache, (0..13).collect::<Vec<u8>>());
    assert_eq!(audio.size, Some(13));
    assert_eq!(connector.observations().dropped, [0]);
}
