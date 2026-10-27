use std::collections::HashMap;
use std::io::{self, BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::{Duration, Instant};

use symphonia::core::io::MediaSource;
use url::Url;

use crate::{failure_code, pinned_tls::PinnedTls, set_failure_code};

const CACHE_BYTES: usize = 256 * 1024;
const MAX_HEADER_BYTES: usize = 16 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
const OPEN_TIMEOUT: Duration = Duration::from_secs(15);

/// A seekable source with one bounded byte window; seeking never downloads the
/// whole file. Every window is pinned to the same file representation by ETag.
pub struct RemoteSource {
    url: Url,
    token: String,
    tls: PinnedTls,
    size: Option<u64>,
    etag: Option<String>,
    position: u64,
    cache_start: u64,
    cache: Vec<u8>,
    opening: Arc<AtomicBool>,
    opened_at: Instant,
}

impl RemoteSource {
    pub fn open(
        url: &str,
        token: &str,
        server_pin: &str,
        opening: Arc<AtomicBool>,
    ) -> Result<Self, String> {
        let url = validate_request(url, token).inspect_err(|_| set_failure_code(-100))?;
        let mut source = Self {
            url,
            token: token.to_owned(),
            tls: PinnedTls::new(server_pin).inspect_err(|_| set_failure_code(-100))?,
            size: None,
            etag: None,
            position: 0,
            cache_start: 0,
            cache: Vec::new(),
            opening,
            opened_at: Instant::now(),
        };
        source.fetch_window().map_err(|error| {
            mark_transport_failure();
            error.to_string()
        })?;

        Ok(source)
    }

    fn fetch_window(&mut self) -> io::Result<()> {
        let deadline = if self.opening.load(Ordering::Acquire) {
            (Instant::now() + REQUEST_TIMEOUT).min(self.opened_at + OPEN_TIMEOUT)
        } else {
            Instant::now() + REQUEST_TIMEOUT
        };
        let host = self.url.host_str().unwrap().trim_matches(['[', ']']);
        let port = self.url.port_or_known_default().unwrap();
        let authority = if host.contains(':') {
            format!("[{host}]:{port}")
        } else {
            format!("{host}:{port}")
        };
        let mut target = self.url.path().to_owned();
        if let Some(query) = self.url.query() {
            target.push('?');
            target.push_str(query);
        }

        let end = self.position.saturating_add(CACHE_BYTES as u64 - 1);
        let mut connection = self
            .tls
            .connect(host, port, deadline)
            .inspect_err(|error| {
                if error.kind() == io::ErrorKind::InvalidData {
                    set_failure_code(-100);
                }
            })?;
        write!(
            connection,
            "GET {target} HTTP/1.1\r\nHost: {authority}\r\nAuthorization: Bearer {}\r\nRange: bytes={}-{end}\r\nAccept-Encoding: identity\r\nConnection: close\r\n",
            self.token, self.position,
        )?;
        if let Some(etag) = &self.etag {
            write!(connection, "If-Range: {etag}\r\n")?;
        }
        write!(connection, "\r\n")?;
        connection.flush()?;

        let mut connection = BufReader::new(connection);
        let response = read_response_headers(&mut connection)?;
        let window = validate_response(
            &response,
            self.position,
            end,
            self.size,
            self.etag.as_deref(),
        )?;
        let bytes = read_window_bytes(&mut connection, window.length)?;

        self.size = Some(window.total);
        self.etag = Some(window.etag);
        self.cache_start = self.position;
        self.cache = bytes;

        Ok(())
    }
}

impl Read for RemoteSource {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        if buffer.is_empty() || self.size.is_some_and(|size| self.position >= size) {
            return Ok(0);
        }

        let cached_end = self.cache_start + self.cache.len() as u64;
        if self.position < self.cache_start || self.position >= cached_end {
            self.fetch_window()
                .inspect_err(|_| mark_transport_failure())?;
        }

        let offset = (self.position - self.cache_start) as usize;
        let count = buffer.len().min(self.cache.len() - offset);
        buffer[..count].copy_from_slice(&self.cache[offset..offset + count]);
        self.position += count as u64;

        Ok(count)
    }
}

impl Seek for RemoteSource {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.position = match position {
            SeekFrom::Start(position) => position,
            SeekFrom::Current(offset) => checked_offset(self.position, offset)?,
            SeekFrom::End(offset) => checked_offset(self.size.unwrap_or(0), offset)?,
        };

        Ok(self.position)
    }
}

impl MediaSource for RemoteSource {
    fn is_seekable(&self) -> bool {
        true
    }

    fn byte_len(&self) -> Option<u64> {
        self.size
    }
}

fn validate_request(url: &str, token: &str) -> Result<Url, String> {
    let url = Url::parse(url).map_err(|_| "invalid Original audio URL")?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err("Original playback requires a trusted HTTPS URL".into());
    }

    if token.is_empty() || token.bytes().any(|value| value.is_ascii_control()) {
        return Err("Original playback requires valid server authentication".into());
    }

    Ok(url)
}

fn checked_offset(position: u64, offset: i64) -> io::Result<u64> {
    position
        .checked_add_signed(offset)
        .ok_or_else(|| invalid_response("invalid audio seek offset"))
}

struct ResponseHeaders {
    status: u16,
    fields: HashMap<String, String>,
}

struct ResponseWindow {
    length: usize,
    total: u64,
    etag: String,
}

fn read_window_bytes(reader: &mut impl Read, length: usize) -> io::Result<Vec<u8>> {
    let mut bytes = vec![0; length];
    reader.read_exact(&mut bytes).map_err(|error| {
        if error.kind() == io::ErrorKind::UnexpectedEof {
            io::Error::new(
                io::ErrorKind::ConnectionReset,
                "Original audio range ended before its declared length",
            )
        } else {
            error
        }
    })?;

    Ok(bytes)
}

fn read_response_headers(reader: &mut impl BufRead) -> io::Result<ResponseHeaders> {
    let mut bytes = Vec::new();
    let mut fields = HashMap::new();
    let mut consumed = 0;
    read_header_line(reader, &mut bytes, &mut consumed)?;
    let status = std::str::from_utf8(&bytes)
        .ok()
        .and_then(|line| {
            let mut parts = line.split_whitespace();
            match parts.next()? {
                "HTTP/1.0" | "HTTP/1.1" => parts.next()?.parse().ok(),
                _ => None,
            }
        })
        .ok_or_else(|| invalid_response("invalid Original audio response"))?;

    loop {
        read_header_line(reader, &mut bytes, &mut consumed)?;
        if bytes == b"\r\n" {
            break;
        }

        let line = std::str::from_utf8(&bytes)
            .map_err(|_| invalid_response("invalid audio response header"))?;
        let (name, value) = line
            .trim_end_matches("\r\n")
            .split_once(':')
            .ok_or_else(|| invalid_response("invalid audio response header"))?;
        if name.is_empty()
            || name
                .bytes()
                .any(|byte| !byte.is_ascii_alphanumeric() && byte != b'-')
        {
            return Err(invalid_response("invalid audio response header name"));
        }

        let value = value.trim();
        if value.bytes().any(|byte| byte.is_ascii_control()) {
            return Err(invalid_response("invalid audio response header value"));
        }

        if fields
            .insert(name.to_ascii_lowercase(), value.to_owned())
            .is_some()
        {
            return Err(invalid_response("duplicate audio response header"));
        }
    }

    Ok(ResponseHeaders { status, fields })
}

fn read_header_line(
    reader: &mut impl BufRead,
    bytes: &mut Vec<u8>,
    consumed: &mut usize,
) -> io::Result<()> {
    bytes.clear();
    let remaining = MAX_HEADER_BYTES.saturating_sub(*consumed);
    let read = reader.take(remaining as u64).read_until(b'\n', bytes)?;
    *consumed += read;

    if *consumed >= MAX_HEADER_BYTES {
        return Err(invalid_response(
            "audio response headers are incomplete or too large",
        ));
    }

    if read == 0 || !bytes.ends_with(b"\r\n") {
        return Err(io::Error::new(
            io::ErrorKind::ConnectionReset,
            "Original audio connection closed before its response headers",
        ));
    }

    Ok(())
}

fn validate_response(
    response: &ResponseHeaders,
    requested_start: u64,
    requested_end: u64,
    known_total: Option<u64>,
    known_etag: Option<&str>,
) -> io::Result<ResponseWindow> {
    if response.status != 206 {
        let error = invalid_response(&format!(
            "Original audio range request failed (HTTP {})",
            response.status
        ));
        set_failure_code(if response.status >= 400 {
            response.status as i32
        } else {
            -102
        });

        return Err(error);
    }

    if response.fields.contains_key("transfer-encoding")
        || response
            .fields
            .get("content-encoding")
            .is_some_and(|value| value != "identity")
    {
        return Err(invalid_response(
            "encoded audio range responses are unsupported",
        ));
    }

    let content_range = response
        .fields
        .get("content-range")
        .and_then(|value| value.strip_prefix("bytes "))
        .ok_or_else(|| invalid_response("missing audio content range"))?;
    let (range, total) = content_range
        .split_once('/')
        .ok_or_else(|| invalid_response("invalid audio content range"))?;
    let (start, end) = range
        .split_once('-')
        .ok_or_else(|| invalid_response("invalid audio content range"))?;
    let parse = |value: &str| {
        value
            .parse::<u64>()
            .map_err(|_| invalid_response("invalid audio content range"))
    };
    let start = parse(start)?;
    let end = parse(end)?;
    let total = parse(total)?;
    let declared_length = response
        .fields
        .get("content-length")
        .ok_or_else(|| invalid_response("missing audio content length"))?
        .parse::<usize>()
        .map_err(|_| invalid_response("invalid audio content length"))?;

    if total == 0
        || start != requested_start
        || end < start
        || end != requested_end.min(total - 1)
        || end >= total
        || declared_length > CACHE_BYTES
        || end - start + 1 != declared_length as u64
        || known_total.is_some_and(|known| known != total)
    {
        return Err(invalid_response(
            "Original audio range does not match the requested file",
        ));
    }

    let etag = response
        .fields
        .get("etag")
        .filter(|value| value.starts_with('"') && value.ends_with('"') && value.len() >= 2)
        .ok_or_else(|| invalid_response("Original audio requires a stable file identity"))?;
    if known_etag.is_some_and(|known| known != etag) {
        return Err(invalid_response(
            "Original audio file changed during playback",
        ));
    }

    Ok(ResponseWindow {
        length: declared_length,
        total,
        etag: etag.to_owned(),
    })
}

fn invalid_response(message: &str) -> io::Error {
    set_failure_code(-102);
    io::Error::new(io::ErrorKind::InvalidData, message.to_owned())
}

fn mark_transport_failure() {
    if failure_code() == 0 {
        set_failure_code(-200);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn response(headers: &str) -> ResponseHeaders {
        read_response_headers(&mut Cursor::new(headers.as_bytes())).unwrap()
    }

    #[test]
    fn range_contract_accepts_exact_and_final_windows() {
        let headers = response("HTTP/1.1 206 Partial Content\r\nContent-Length: 3\r\nContent-Range: bytes 10-12/13\r\nETag: \"source\"\r\n\r\n");
        let window = validate_response(&headers, 10, 99, Some(13), Some("\"source\"")).unwrap();
        assert_eq!(window.length, 3);
        assert_eq!(window.total, 13);
    }

    #[test]
    fn range_contract_rejects_redirects_ignored_ranges_and_changed_sources() {
        for status in [200, 302, 401, 404, 416, 500] {
            let headers = response(&format!("HTTP/1.1 {status} Response\r\n\r\n"));
            assert!(validate_response(&headers, 0, 9, None, None).is_err());
        }
        let headers = response("HTTP/1.1 206 Partial Content\r\nContent-Length: 10\r\nContent-Range: bytes 0-9/20\r\nETag: \"new\"\r\n\r\n");
        assert!(validate_response(&headers, 0, 9, Some(20), Some("\"old\"")).is_err());
        assert!(validate_response(&headers, 0, 9, Some(21), None).is_err());
        assert!(validate_response(&headers, 1, 10, None, None).is_err());
    }

    #[test]
    fn range_contract_rejects_unbounded_or_inconsistent_payloads() {
        for extra in [
            "Content-Length: 99\r\n",
            "Content-Length: 10\r\nTransfer-Encoding: chunked\r\n",
            "Content-Length: 10\r\nContent-Encoding: gzip\r\n",
        ] {
            let headers = response(&format!("HTTP/1.1 206 Partial Content\r\nContent-Range: bytes 0-9/20\r\nETag: \"source\"\r\n{extra}\r\n"));
            assert!(validate_response(&headers, 0, 9, None, None).is_err());
        }
        for bytes in [
            b"HTTP/1.1 206 Partial Content\r\nContent-Length: 10\r\nContent-Length: 10\r\n\r\n"
                .to_vec(),
            vec![b'x'; MAX_HEADER_BYTES + 1],
            b"HTTP/1.1 206 Partial Content\r\nIncomplete".to_vec(),
        ] {
            assert!(read_response_headers(&mut Cursor::new(bytes)).is_err());
        }
    }

    #[test]
    fn authentication_stays_on_trusted_https_requests() {
        for url in [
            "http://localhost/audio",
            "https://user@localhost/audio",
            "https://localhost/audio#fragment",
        ] {
            assert!(validate_request(url, "token").is_err());
        }
        assert!(validate_request("https://localhost/audio", "token\r\nInjected: header").is_err());
        assert!(validate_request("https://localhost/audio", "").is_err());
        assert!(validate_request("https://localhost:3000/api/stream/id/original", "token").is_ok());
    }

    #[test]
    fn seeking_keeps_offsets_within_the_unsigned_address_space() {
        assert_eq!(checked_offset(10, -3).unwrap(), 7);
        assert!(checked_offset(0, -1).is_err());
        assert!(checked_offset(u64::MAX, 1).is_err());
    }

    #[test]
    fn truncated_range_is_a_transport_failure_instead_of_audio_eof() {
        let error = read_window_bytes(&mut Cursor::new(b"short"), 20).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::ConnectionReset);
        assert_eq!(
            read_window_bytes(&mut Cursor::new(b"exact"), 5).unwrap(),
            b"exact"
        );
    }
}
