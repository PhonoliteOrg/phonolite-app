//! Bounded, version-pinned source bytes over the authenticated QUIC connection.
//! The decoder receives native function pointers, never callbacks into Dart.
use std::ffi::c_void;
use std::io;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use serde::Deserialize;

use super::{connect_client, cstr_to_string, ClientHandle, ControlCommand};
use std::os::raw::c_char;

const MAX_SOURCE_BYTES: usize = 256 * 1024;
const INVALID_SOURCE: i32 = -101;
const TRANSPORT_FAILURE: i32 = -102;
const SECURITY_FAILURE: i32 = -100;

type SourceConnection = (Arc<ClientHandle>, Option<thread::JoinHandle<()>>);
type SourceConnector = Box<dyn FnMut() -> Result<SourceConnection, String> + Send>;

pub struct SourceHandle {
    inner: Arc<ClientHandle>,
    worker: Option<thread::JoinHandle<()>>,
    connect: Option<SourceConnector>,
    track_id: String,
    version: Option<String>,
    total_length: Option<u64>,
    stream: Option<SourceStream>,
    error: String,
    error_code: i32,
}

#[derive(Deserialize)]
struct Announcement {
    offset: u64,
    length: u64,
    total_length: u64,
    source_version: String,
}

struct SourceStream {
    generation: u64,
    offset: u64,
    next_position: u64,
    announced: bool,
    finished: bool,
}

impl SourceHandle {
    fn read_range(
        &mut self,
        offset: u64,
        capacity: usize,
        timeout: Duration,
    ) -> Result<Vec<u8>, String> {
        let deadline = Instant::now() + timeout;
        let mut resumed = false;
        self.error_code = TRANSPORT_FAILURE;
        loop {
            if !self.inner.owner.operation_is_current() {
                return Err("QUIC source operation interrupted".into());
            }
            if self
                .inner
                .cancelled
                .load(std::sync::atomic::Ordering::Acquire)
            {
                return Err("QUIC source owner is closed".into());
            }

            let result = (|| {
                if self
                    .stream
                    .as_ref()
                    .is_none_or(|stream| stream.next_position != offset)
                {
                    self.open_stream(offset)?;
                }
                self.read_stream(
                    offset,
                    capacity,
                    deadline.saturating_duration_since(Instant::now()),
                )
            })();
            let Err(error) = result else { return result };
            self.stream = None;
            if let Ok(mut delivery) = self.inner.delivery.lock() {
                delivery.suspend();
            }
            let _ = self.inner.tx.send(ControlCommand::SuspendAudio);

            // Resume the same pinned representation before exposing an I/O
            // error to the parser. Restarting playback would discard decoded
            // PCM even when its buffer could cover a brief reconnect.
            if resumed
                || self.version.is_none()
                || self.connect.is_none()
                || self.error_code != TRANSPORT_FAILURE
                || security_failure(&error)
                || Instant::now() >= deadline
                || self
                    .inner
                    .cancelled
                    .load(std::sync::atomic::Ordering::Acquire)
                || !self.inner.owner.operation_is_current()
            {
                return Err(error);
            }
            self.reconnect()?;
            resumed = true;
        }
    }

    fn reconnect(&mut self) -> Result<(), String> {
        let _ = self.inner.tx.send(ControlCommand::Close);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        let (inner, worker) = self.connect.as_mut().unwrap()()?;
        self.inner = inner;
        self.worker = worker;
        Ok(())
    }

    fn open_stream(&mut self, offset: u64) -> Result<(), String> {
        let generation = self
            .inner
            .generation
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
            + 1;
        self.inner
            .delivery
            .lock()
            .map_err(poisoned)?
            .begin(generation);
        self.inner.events.lock().map_err(poisoned)?.clear();
        *self.inner.last_error.lock().map_err(poisoned)? = None;
        self.inner
            .tx
            .send(ControlCommand::SourceOpen {
                generation,
                track_id: self.track_id.clone(),
                offset,
                source_version: self.version.clone(),
            })
            .map_err(|_| "QUIC source connection is closed".to_string())?;

        self.stream = Some(SourceStream {
            generation,
            offset,
            next_position: offset,
            announced: false,
            finished: false,
        });
        Ok(())
    }

    fn read_stream(
        &mut self,
        offset: u64,
        capacity: usize,
        timeout: Duration,
    ) -> Result<Vec<u8>, String> {
        let generation = self.stream.as_ref().unwrap().generation;
        let deadline = Instant::now() + timeout;
        let mut bytes = Vec::with_capacity(capacity);
        let mut buffer = [0; 16 * 1024];
        loop {
            if self
                .inner
                .cancelled
                .load(std::sync::atomic::Ordering::Acquire)
            {
                return Err("QUIC source owner is closed".into());
            }
            if !self.inner.owner.operation_is_current() {
                return Err("QUIC source operation interrupted".into());
            }
            loop {
                let event = self.inner.events.lock().map_err(poisoned)?.pop_front();
                let Some(event) = event else { break };
                let event: serde_json::Value =
                    serde_json::from_str(&event).map_err(|error| error.to_string())?;
                if event["request_id"]
                    .as_u64()
                    .is_some_and(|id| id != generation)
                {
                    continue;
                }
                match event["type"].as_str() {
                    Some("source") => {
                        if self.stream.as_ref().unwrap().announced {
                            return self.invalid("Duplicate QUIC source announcement");
                        }
                        let accepted: Announcement =
                            serde_json::from_value(event).map_err(|error| error.to_string())?;
                        self.validate(&accepted, self.stream.as_ref().unwrap().offset, capacity)?;
                        self.version = Some(accepted.source_version);
                        self.total_length = Some(accepted.total_length);
                        self.stream.as_mut().unwrap().announced = true;
                    }
                    Some("source_fin") => self.stream.as_mut().unwrap().finished = true,
                    Some("error") => {
                        let message = event["message"]
                            .as_str()
                            .unwrap_or("QUIC source transfer failed");
                        if event["origin"].as_str() == Some("server") {
                            self.error_code = if message
                                .starts_with("source range capacity exhausted")
                                || message == "server shutting down"
                            {
                                TRANSPORT_FAILURE
                            } else {
                                INVALID_SOURCE
                            };
                        }
                        return Err(message.to_owned());
                    }
                    _ => {}
                }
            }
            let stream = self.stream.as_ref().unwrap();
            let announced = stream.announced;
            let finished = stream.finished;
            let expected = if announced {
                (capacity as u64).min(self.total_length.unwrap() - offset) as usize
            } else {
                capacity
            };
            let final_read = announced && offset + expected as u64 == self.total_length.unwrap();
            if announced && bytes.len() > expected {
                return self.invalid("QUIC source exceeded the advertised file length");
            }
            let (queued, closed) = {
                let delivery = self.inner.delivery.lock().map_err(poisoned)?;
                (delivery.bytes, delivery.closed)
            };
            if announced {
                let available_end = offset
                    .checked_add(bytes.len() as u64)
                    .and_then(|end| end.checked_add(queued as u64));
                if available_end.is_none() || available_end > self.total_length {
                    return self.invalid("QUIC source exceeded the advertised file length");
                }
                if finished && available_end != self.total_length {
                    return self
                        .invalid("QUIC source FIN did not match the advertised file length");
                }
            }
            // A decoder fill is a read demand, not a network block size. Return
            // available nonfinal bytes as soon as the rolling queue runs dry;
            // a slow but viable link must not fill 256 KiB before decoding.
            let can_return_progress = !bytes.is_empty()
                && offset + (bytes.len() as u64) < self.total_length.unwrap_or(0)
                && (bytes.len() == expected || queued == 0);
            if announced
                && (can_return_progress || (bytes.len() == expected && final_read && finished))
            {
                self.stream.as_mut().unwrap().next_position = offset + bytes.len() as u64;
                return Ok(bytes);
            }
            let count = buffer.len().min(expected - bytes.len());
            let read = if count == 0 {
                -5
            } else {
                self.inner
                    .delivery
                    .lock()
                    .map_err(poisoned)?
                    .read(&mut buffer[..count])
            };
            if read > 0 {
                let read = read as usize;
                bytes.extend_from_slice(&buffer[..read]);
            } else if read == 0 || (closed && !finished) {
                // The FIN event and the closed flag are published separately.
                // Observe queued events before deciding a close was premature.
                if !self.inner.events.lock().map_err(poisoned)?.is_empty() {
                    continue;
                }
                return Err(self
                    .inner
                    .last_error
                    .lock()
                    .map_err(poisoned)?
                    .clone()
                    .unwrap_or_else(|| {
                        "QUIC source range closed before its complete, advertised FIN".into()
                    }));
            }
            if Instant::now() >= deadline {
                let _ = self.inner.tx.send(ControlCommand::SuspendAudio);
                return Err(self.inner.last_error.lock().map_err(poisoned)?.clone()
                    .unwrap_or_else(|| "Original audio over QUIC timed out; the server may not support source streaming".into()));
            }
            if read <= 0 {
                thread::sleep(Duration::from_millis(2));
            }
        }
    }

    fn validate(
        &mut self,
        value: &Announcement,
        offset: u64,
        _capacity: usize,
    ) -> Result<(), String> {
        if value.offset != offset
            || offset > value.total_length
            || value.length != value.total_length.saturating_sub(offset)
            || value.source_version.is_empty()
            || value.source_version.len() > 256
            || self
                .version
                .as_ref()
                .is_some_and(|version| version != &value.source_version)
            || self
                .total_length
                .is_some_and(|total| total != value.total_length)
        {
            return self.invalid("QUIC source representation or range metadata changed");
        }
        Ok(())
    }

    fn invalid<T>(&mut self, message: &str) -> Result<T, String> {
        self.error_code = INVALID_SOURCE;
        Err(message.into())
    }
}

impl Drop for SourceHandle {
    fn drop(&mut self) {
        self.inner
            .cancelled
            .store(true, std::sync::atomic::Ordering::Release);
        let _ = self.inner.tx.send(ControlCommand::Close);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

fn poisoned<T>(_: std::sync::PoisonError<T>) -> String {
    io::Error::other("QUIC source state unavailable").to_string()
}

fn security_failure(error: &str) -> bool {
    error.contains("identity") || error.contains("SPKI") || error.contains("certificate")
}

#[no_mangle]
pub extern "C" fn phonolite_quic_source_connect(
    host: *const c_char,
    port: u16,
    track_id: *const c_char,
    token: *const c_char,
    server_pin: *const c_char,
) -> *mut c_void {
    source_connect(host, port, track_id, token, server_pin, None)
}

#[no_mangle]
pub extern "C" fn phonolite_quic_source_connect_owned(
    host: *const c_char,
    port: u16,
    track_id: *const c_char,
    token: *const c_char,
    server_pin: *const c_char,
    owner_id: u64,
) -> *mut c_void {
    if owner_id == 0 {
        return source_connect(host, port, track_id, token, server_pin, None);
    }
    let Some(owner) = super::owner::get(owner_id) else {
        return std::ptr::null_mut();
    };
    source_connect(host, port, track_id, token, server_pin, Some(owner))
}

fn source_connect(
    host: *const c_char,
    port: u16,
    track_id: *const c_char,
    token: *const c_char,
    server_pin: *const c_char,
    owner: Option<Arc<super::OwnerLease>>,
) -> *mut c_void {
    let track_id = unsafe { cstr_to_string(track_id) };
    if track_id.is_empty() {
        return std::ptr::null_mut();
    }
    let host = unsafe { cstr_to_string(host) };
    let token = unsafe { cstr_to_string(token) };
    let server_pin = unsafe { cstr_to_string(server_pin) };
    let mut connect: SourceConnector = Box::new(move || {
        connect_client(
            host.clone(),
            port,
            token.clone(),
            server_pin.clone(),
            true,
            owner.clone(),
        )
        .map(|(inner, worker)| (inner, Some(worker)))
    });
    let connected = connect();
    let Ok((inner, worker)) = connected else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(SourceHandle {
        inner,
        worker,
        connect: Some(connect),
        track_id,
        version: None,
        total_length: None,
        stream: None,
        error: String::new(),
        error_code: 0,
    }))
    .cast()
}

/// The caller owns the handle exclusively and supplies at most 256 KiB.
#[no_mangle]
pub extern "C" fn phonolite_quic_source_read_range(
    handle: *mut c_void,
    offset: u64,
    output: *mut u8,
    capacity: usize,
    timeout_ms: u32,
    total_length: *mut u64,
) -> i64 {
    let Some(source) = (unsafe { handle.cast::<SourceHandle>().as_mut() }) else {
        return i64::from(SECURITY_FAILURE);
    };
    if output.is_null()
        || total_length.is_null()
        || !(1..=MAX_SOURCE_BYTES).contains(&capacity)
        || !(1..=60_000).contains(&timeout_ms)
    {
        source.error = "Invalid QUIC source range request".into();
        source.error_code = INVALID_SOURCE;
        return i64::from(source.error_code);
    }
    source.error_code = TRANSPORT_FAILURE;
    match source.read_range(
        offset,
        capacity,
        Duration::from_millis(u64::from(timeout_ms)),
    ) {
        Ok(bytes) => {
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len());
                *total_length = source.total_length.unwrap();
            }
            source.error.clear();
            source.error_code = 0;
            bytes.len() as i64
        }
        Err(error) => {
            if security_failure(&error) {
                source.error_code = SECURITY_FAILURE;
            }
            source.error = error;
            i64::from(source.error_code)
        }
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_source_error_code(handle: *const c_void) -> i32 {
    unsafe { handle.cast::<SourceHandle>().as_ref() }
        .map_or(SECURITY_FAILURE, |source| source.error_code)
}

#[no_mangle]
pub extern "C" fn phonolite_quic_source_error(
    handle: *const c_void,
    output: *mut u8,
    capacity: usize,
) -> usize {
    let Some(source) = (unsafe { handle.cast::<SourceHandle>().as_ref() }) else {
        return 0;
    };
    if output.is_null() || capacity == 0 {
        return 0;
    }
    let length = source.error.len().min(capacity);
    unsafe {
        std::ptr::copy_nonoverlapping(source.error.as_ptr(), output, length);
    }
    length
}

#[no_mangle]
pub extern "C" fn phonolite_quic_source_close(handle: *mut c_void) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<SourceHandle>()));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::{handle_control_bytes, test_handle, AudioSender, ClientState};
    use super::*;

    #[test]
    fn owner_cancellation_interrupts_an_inflight_fill_and_rejects_later_reads() {
        let (mut source, commands) = source();
        let cancelled = Arc::clone(&source.inner.cancelled);
        let cancelling = thread::spawn(move || {
            commands.recv().unwrap();
            thread::sleep(Duration::from_millis(10));
            cancelled.store(true, std::sync::atomic::Ordering::Release);
        });
        let started = Instant::now();
        assert!(source
            .read_range(0, 1024, Duration::from_secs(5))
            .unwrap_err()
            .contains("closed"));
        assert!(started.elapsed() < Duration::from_millis(250));
        assert!(source.read_range(0, 1024, Duration::from_secs(5)).is_err());
        cancelling.join().unwrap();
    }

    #[test]
    fn a_seek_epoch_interrupts_a_fill_without_destroying_the_pinned_source() {
        let (mut source, commands) = source();
        let id = super::super::owner::phonolite_quic_owner_create();
        let owner = super::super::owner::get(id).unwrap();
        let client = Arc::get_mut(&mut source.inner).unwrap();
        client.owner = Arc::clone(&owner);
        client.cancelled = Arc::clone(&owner.cancelled);
        let inner = Arc::clone(&source.inner);
        let interrupting = thread::spawn(move || {
            let ControlCommand::SourceOpen { generation, .. } = commands.recv().unwrap() else {
                panic!("open expected")
            };
            announce(&inner, generation, 0, 8);
            thread::sleep(Duration::from_millis(10));
            super::super::owner::phonolite_quic_owner_interrupt(id);
            commands
        });
        assert!(source
            .read_range(0, 4, Duration::from_secs(5))
            .unwrap_err()
            .contains("interrupted"));
        assert_eq!(source.version.as_deref(), Some("fixed-source-version"));
        let commands = interrupting.join().unwrap();
        while commands.try_recv().is_ok() {}
        assert_eq!(
            super::super::owner::phonolite_quic_owner_begin_operation(id, 1),
            1
        );
        let worker = deliver(
            Arc::clone(&source.inner),
            commands,
            4,
            8,
            vec![5, 6, 7, 8],
            true,
            false,
        );
        assert_eq!(
            source.read_range(4, 4, Duration::from_secs(1)).unwrap(),
            vec![5, 6, 7, 8]
        );
        worker.join().unwrap();
        super::super::owner::phonolite_quic_owner_release(id as usize as *mut c_void);
    }

    fn source() -> (SourceHandle, std::sync::mpsc::Receiver<ControlCommand>) {
        let (handle, commands) = test_handle(0);
        handle.inner.delivery.lock().unwrap().limit = super::super::MAX_SOURCE_DELIVERY_BYTES;
        (
            SourceHandle {
                inner: Arc::clone(&handle.inner),
                worker: None,
                connect: None,
                track_id: "source-track".into(),
                version: None,
                total_length: None,
                stream: None,
                error: String::new(),
                error_code: TRANSPORT_FAILURE,
            },
            commands,
        )
    }

    fn disconnected_source() -> (SourceHandle, std::sync::mpsc::Receiver<ControlCommand>) {
        let (mut source, commands) = source();
        source.version = Some("fixed-source-version".into());
        source.total_length = Some(10);
        source.stream = Some(SourceStream {
            generation: 1,
            offset: 0,
            next_position: 4,
            announced: true,
            finished: false,
        });
        source.inner.delivery.lock().unwrap().begin(1);
        source.inner.delivery.lock().unwrap().closed = true;
        *source.inner.last_error.lock().unwrap() =
            Some("QUIC connection closed: timed_out=true".into());
        (source, commands)
    }

    #[test]
    fn a_dropped_connection_resumes_the_same_version_at_the_unreturned_byte_offset() {
        let (mut source, _old_commands) = disconnected_source();
        let (mut next, commands) = test_handle(0);
        let owner = Arc::clone(&source.inner.owner);
        Arc::get_mut(&mut next.inner).unwrap().owner = Arc::clone(&owner);
        Arc::get_mut(&mut next.inner).unwrap().cancelled = Arc::clone(&owner.cancelled);
        let resumed = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let attempts = Arc::clone(&resumed);
        let inner = Arc::clone(&next.inner);
        source.connect = Some(Box::new(move || {
            attempts.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            Ok((Arc::clone(&next.inner), None))
        }));
        let worker = thread::spawn(move || {
            let ControlCommand::SourceOpen {
                generation,
                offset,
                source_version,
                ..
            } = commands.recv().unwrap()
            else {
                panic!("source resume expected")
            };
            assert_eq!(offset, 4);
            assert_eq!(source_version.as_deref(), Some("fixed-source-version"));
            let tx = announce(&inner, generation, offset, 10);
            tx.send(vec![5, 6, 7, 8, 9, 10]);
            tx.event(serde_json::json!({"type":"source_fin", "request_id":generation}));
            tx.send(Vec::new());
        });
        assert_eq!(
            source.read_range(4, 6, Duration::from_secs(1)).unwrap(),
            vec![5, 6, 7, 8, 9, 10]
        );
        assert!(source
            .read_range(10, 6, Duration::from_secs(1))
            .unwrap()
            .is_empty());
        assert_eq!(resumed.load(std::sync::atomic::Ordering::Relaxed), 1);
        assert!(!owner.cancelled.load(std::sync::atomic::Ordering::Acquire));
        worker.join().unwrap();
    }

    #[test]
    fn a_reconnect_cannot_change_the_accepted_source_representation() {
        let (mut source, _old_commands) = disconnected_source();
        let (next, commands) = test_handle(0);
        let inner = Arc::clone(&next.inner);
        source.connect = Some(Box::new(move || Ok((Arc::clone(&next.inner), None))));
        let worker = thread::spawn(move || {
            let ControlCommand::SourceOpen { generation, .. } = commands.recv().unwrap() else {
                panic!("source resume expected")
            };
            inner.events.lock().unwrap().push_back(
                serde_json::json!({
                    "type":"source", "request_id":generation, "offset":4, "length":6,
                    "total_length":10, "source_version":"different-version",
                })
                .to_string(),
            );
        });
        assert!(source
            .read_range(4, 6, Duration::from_secs(1))
            .unwrap_err()
            .contains("metadata changed"));
        assert_eq!(source.error_code, INVALID_SOURCE);
        worker.join().unwrap();
    }

    #[test]
    fn security_failures_source_rejections_and_owner_cancellation_never_reconnect() {
        for (message, server, cancelled) in [
            ("SPKI identity mismatch", false, false),
            ("source changed during continuous playback", true, false),
            ("cancelled", false, true),
        ] {
            let (mut source, _commands) = disconnected_source();
            source.connect = Some(Box::new(|| panic!("this failure must not reconnect")));
            if cancelled {
                source
                    .inner
                    .cancelled
                    .store(true, std::sync::atomic::Ordering::Release);
            } else {
                source.inner.events.lock().unwrap().push_back(
                    serde_json::json!({
                        "type":"error", "request_id":1, "message":message,
                        "origin":if server { "server" } else { "client" },
                    })
                    .to_string(),
                );
            }
            assert!(source.read_range(4, 6, Duration::from_secs(1)).is_err());
        }
    }

    #[test]
    fn a_failed_resume_does_not_loop_or_extend_the_original_read_budget() {
        let (mut source, _old_commands) = disconnected_source();
        let (next, commands) = test_handle(0);
        let inner = Arc::clone(&next.inner);
        let resumed = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let attempts = Arc::clone(&resumed);
        source.connect = Some(Box::new(move || {
            assert_eq!(
                attempts.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
                0
            );
            Ok((Arc::clone(&next.inner), None))
        }));
        let worker = thread::spawn(move || {
            let ControlCommand::SourceOpen { generation, .. } = commands.recv().unwrap() else {
                panic!("source resume expected")
            };
            let tx = announce(&inner, generation, 4, 10);
            tx.event(serde_json::json!({"type":"error", "message":"connection lost again"}));
        });
        assert!(source
            .read_range(4, 6, Duration::from_secs(1))
            .unwrap_err()
            .contains("lost again"));
        assert_eq!(resumed.load(std::sync::atomic::Ordering::Relaxed), 1);
        worker.join().unwrap();

        let (mut source, _commands) = disconnected_source();
        source.inner.delivery.lock().unwrap().closed = false;
        source.connect = Some(Box::new(|| {
            panic!("an expired operation must not get a new budget")
        }));
        let started = Instant::now();
        assert!(source.read_range(4, 6, Duration::from_millis(30)).is_err());
        assert!(started.elapsed() < Duration::from_millis(250));
    }

    fn deliver(
        inner: Arc<ClientHandle>,
        commands: std::sync::mpsc::Receiver<ControlCommand>,
        offset: u64,
        total: u64,
        bytes: Vec<u8>,
        fin: bool,
        duplicate: bool,
    ) -> thread::JoinHandle<()> {
        thread::spawn(move || {
            let ControlCommand::SourceOpen {
                generation,
                track_id,
                ..
            } = commands.recv().unwrap()
            else {
                panic!("source range expected")
            };
            let tx = AudioSender {
                delivery: Arc::clone(&inner.delivery),
                events: Arc::clone(&inner.events),
                generation,
            };
            let mut state = ClientState::new();
            state.active_track = Some(track_id.clone());
            state.source_stream = true;
            let message = serde_json::json!({
                "type":"source", "request_id":generation, "track_id":track_id,
                "stream_id":3, "offset":offset, "length":total.saturating_sub(offset),
                "total_length":total, "source_version":"fixed-source-version",
            })
            .to_string()
                + "\n";
            handle_control_bytes(
                &mut state,
                message.as_bytes(),
                &tx,
                &inner.last_error,
                &inner.last_rtt_ms,
            );
            if duplicate {
                handle_control_bytes(
                    &mut state,
                    message.as_bytes(),
                    &tx,
                    &inner.last_error,
                    &inner.last_rtt_ms,
                );
            }
            assert_eq!(state.active_stream, Some(3));
            if !bytes.is_empty() {
                tx.send(bytes);
            }
            if fin {
                tx.event(serde_json::json!({ "type":"source_fin", "request_id":generation }));
            }
            tx.send(Vec::new());
        })
    }

    #[test]
    fn source_window_retains_every_byte_and_total_identity() {
        let (mut source, commands) = source();
        let expected: Vec<u8> = (0..MAX_SOURCE_BYTES)
            .map(|value| (value % 256) as u8)
            .collect();
        let worker = deliver(
            Arc::clone(&source.inner),
            commands,
            17,
            17 + expected.len() as u64,
            expected.clone(),
            true,
            false,
        );
        assert_eq!(
            source
                .read_range(17, MAX_SOURCE_BYTES, Duration::from_secs(1))
                .unwrap(),
            expected
        );
        assert_eq!(source.total_length, Some(17 + expected.len() as u64));
        assert_eq!(source.version.as_deref(), Some("fixed-source-version"));
        worker.join().unwrap();
    }

    #[test]
    fn eof_is_an_empty_explicitly_finished_source_range() {
        let (mut source, commands) = source();
        let worker = deliver(
            Arc::clone(&source.inner),
            commands,
            7,
            7,
            vec![],
            true,
            false,
        );
        assert!(source
            .read_range(7, 128, Duration::from_secs(1))
            .unwrap()
            .is_empty());
        worker.join().unwrap();
    }

    #[test]
    fn partial_close_missing_fin_extra_bytes_and_duplicate_announcements_fail() {
        for (bytes, fin, duplicate) in [
            (vec![1, 2], true, false),
            (vec![1, 2, 3], false, false),
            (vec![1, 2, 3, 4], true, false),
            (vec![1, 2, 3], true, true),
        ] {
            let (mut source, commands) = source();
            let worker = deliver(
                Arc::clone(&source.inner),
                commands,
                0,
                3,
                bytes,
                fin,
                duplicate,
            );
            assert!(source.read_range(0, 3, Duration::from_secs(1)).is_err());
            worker.join().unwrap();
        }
    }

    #[test]
    fn source_metadata_is_bound_to_requested_window_and_prior_identity() {
        let (mut source, _) = source();
        let mut announcement = Announcement {
            offset: 8,
            length: 2,
            total_length: 10,
            source_version: "one".into(),
        };
        assert!(source.validate(&announcement, 8, 4).is_ok());
        assert!(source.validate(&announcement, 7, 4).is_err());
        source.version = Some("two".into());
        assert!(source.validate(&announcement, 8, 4).is_err());
        source.version = None;
        source.total_length = Some(11);
        assert!(source.validate(&announcement, 8, 4).is_err());
        source.total_length = None;
        announcement.offset = 11;
        assert!(source.validate(&announcement, 11, 4).is_err());
    }

    #[test]
    fn source_does_not_select_stale_generation_or_opus_streams() {
        let (handle, _) = test_handle(5);
        let tx = AudioSender {
            delivery: Arc::clone(&handle.inner.delivery),
            events: Arc::clone(&handle.inner.events),
            generation: 5,
        };
        let mut state = ClientState::new();
        state.active_track = Some("source-track".into());
        state.source_stream = true;
        for message in [
            r#"{"type":"source","request_id":4,"track_id":"source-track","stream_id":3,"offset":0,"length":1,"total_length":1,"source_version":"v1"}"#,
            r#"{"type":"stream","request_id":5,"track_id":"source-track","stream_id":7,"role":"active","frame_ms":20}"#,
        ] {
            handle_control_bytes(
                &mut state,
                (message.to_owned() + "\n").as_bytes(),
                &tx,
                &handle.inner.last_error,
                &handle.inner.last_rtt_ms,
            );
        }
        assert_eq!(state.active_stream, None);
        assert_eq!(state.retired_streams.len(), 2);
        assert!(handle.inner.events.lock().unwrap().is_empty());
    }

    #[test]
    fn source_drop_joins_its_network_worker_after_cancellation() {
        use std::sync::atomic::{AtomicBool, Ordering};
        let (mut source, _) = source();
        let cancelled = Arc::clone(&source.inner.cancelled);
        let stopped = Arc::new(AtomicBool::new(false));
        let reported = Arc::clone(&stopped);
        source.worker = Some(thread::spawn(move || {
            while !cancelled.load(Ordering::Acquire) {
                thread::yield_now();
            }
            reported.store(true, Ordering::Release);
        }));
        drop(source);
        assert!(stopped.load(Ordering::Acquire));
    }

    #[test]
    fn source_capacity_and_shutdown_errors_remain_recoverable() {
        for (message, expected) in [
            (
                "source range capacity exhausted; retry playback",
                TRANSPORT_FAILURE,
            ),
            ("server shutting down", TRANSPORT_FAILURE),
            ("source changed; reopen original playback", INVALID_SOURCE),
        ] {
            let (mut source, commands) = source();
            let inner = Arc::clone(&source.inner);
            let worker = thread::spawn(move || {
                let ControlCommand::SourceOpen { generation, .. } = commands.recv().unwrap() else {
                    panic!("source range expected")
                };
                let tx = AudioSender {
                    delivery: Arc::clone(&inner.delivery),
                    events: Arc::clone(&inner.events),
                    generation,
                };
                tx.event(serde_json::json!({ "type":"error", "origin":"server", "request_id":generation, "message":message }));
            });
            assert!(source.read_range(0, 4, Duration::from_secs(1)).is_err());
            assert_eq!(source.error_code, expected);
            worker.join().unwrap();
        }
    }

    fn announce(
        inner: &Arc<ClientHandle>,
        generation: u64,
        offset: u64,
        total: u64,
    ) -> AudioSender {
        let tx = AudioSender {
            delivery: Arc::clone(&inner.delivery),
            events: Arc::clone(&inner.events),
            generation,
        };
        let mut state = ClientState::new();
        state.active_track = Some("source-track".into());
        state.source_stream = true;
        let message = serde_json::json!({
            "type":"source", "request_id":generation, "track_id":"source-track", "stream_id":3,
            "offset":offset, "length":total-offset, "total_length":total,
            "source_version":"fixed-source-version",
        })
        .to_string()
            + "\n";
        handle_control_bytes(
            &mut state,
            message.as_bytes(),
            &tx,
            &inner.last_error,
            &inner.last_rtt_ms,
        );
        tx
    }

    #[test]
    fn contiguous_reads_reuse_one_open_and_only_the_final_tail_waits_for_fin() {
        let (mut source, commands) = source();
        let inner = Arc::clone(&source.inner);
        let expected: Vec<u8> = (0..MAX_SOURCE_BYTES * 4 + 13)
            .map(|index| (index % 251) as u8)
            .collect();
        let payload = expected.clone();
        let (finish, finishing) = std::sync::mpsc::channel();
        let worker = thread::spawn(move || {
            let ControlCommand::SourceOpen {
                generation,
                offset: 0,
                source_version: None,
                ..
            } = commands.recv().unwrap()
            else {
                panic!("one initial source open expected")
            };
            let tx = announce(&inner, generation, 0, payload.len() as u64);
            tx.send(payload);
            // There is no FIN while the decoder consumes four complete fills.
            finishing.recv_timeout(Duration::from_secs(2)).unwrap();
            assert!(
                commands.try_recv().is_err(),
                "contiguous fills must not send another source request"
            );
            tx.event(serde_json::json!({"type":"source_fin", "request_id":generation}));
            tx.send(Vec::new());
        });
        let mut actual = Vec::new();
        for offset in (0..MAX_SOURCE_BYTES * 4).step_by(MAX_SOURCE_BYTES) {
            actual.extend(
                source
                    .read_range(offset as u64, MAX_SOURCE_BYTES, Duration::from_secs(1))
                    .unwrap(),
            );
        }
        assert_eq!(actual.len(), MAX_SOURCE_BYTES * 4);
        finish.send(()).unwrap();
        actual.extend(
            source
                .read_range(
                    actual.len() as u64,
                    MAX_SOURCE_BYTES,
                    Duration::from_secs(1),
                )
                .unwrap(),
        );
        assert_eq!(actual, expected);
        assert!(source
            .read_range(
                actual.len() as u64,
                MAX_SOURCE_BYTES,
                Duration::from_secs(1)
            )
            .unwrap()
            .is_empty());
        worker.join().unwrap();
        assert_eq!(
            source
                .inner
                .generation
                .load(std::sync::atomic::Ordering::SeqCst),
            1
        );
    }

    #[test]
    fn random_seek_reopens_once_and_ignores_old_generation_bytes() {
        let (mut source, commands) = source();
        let inner = Arc::clone(&source.inner);
        let expected: Vec<u8> = (0..MAX_SOURCE_BYTES * 2)
            .map(|index| (index % 251) as u8)
            .collect();
        let payload = expected.clone();
        let worker = thread::spawn(move || {
            let mut old: Option<AudioSender> = None;
            for target in [0, 11] {
                let ControlCommand::SourceOpen {
                    generation,
                    offset,
                    source_version,
                    ..
                } = commands.recv().unwrap()
                else {
                    panic!("source open expected")
                };
                assert_eq!(offset, target);
                if target == 11 {
                    assert_eq!(source_version.as_deref(), Some("fixed-source-version"));
                }
                if let Some(stale) = &old {
                    stale.send(vec![255; 400]);
                }
                let tx = announce(&inner, generation, offset, payload.len() as u64);
                tx.send(payload[offset as usize..].to_vec());
                tx.event(serde_json::json!({"type":"source_fin", "request_id":generation}));
                tx.send(Vec::new());
                old = Some(tx);
            }
        });
        assert_eq!(
            source
                .read_range(0, MAX_SOURCE_BYTES, Duration::from_secs(1))
                .unwrap(),
            expected[..MAX_SOURCE_BYTES]
        );
        assert_eq!(
            source
                .read_range(11, MAX_SOURCE_BYTES, Duration::from_secs(1))
                .unwrap(),
            expected[11..11 + MAX_SOURCE_BYTES]
        );
        worker.join().unwrap();
        assert_eq!(
            source
                .inner
                .generation
                .load(std::sync::atomic::Ordering::SeqCst),
            2
        );
    }

    #[test]
    fn full_source_rolling_buffer_stays_bounded_and_control_is_observable() {
        let (source, _) = source();
        source.inner.delivery.lock().unwrap().begin(1);
        let tx = announce(&source.inner, 1, 0, u64::MAX);
        tx.send(vec![7; super::super::MAX_SOURCE_DELIVERY_BYTES]);
        tx.send(vec![9; 1]);
        assert_eq!(tx.available(), 0);
        assert_eq!(
            source.inner.delivery.lock().unwrap().bytes,
            super::super::MAX_SOURCE_DELIVERY_BYTES
        );
        let event = source.inner.events.lock().unwrap().pop_front().unwrap();
        let metadata: serde_json::Value = serde_json::from_str(&event).unwrap();
        assert_eq!(metadata["length"], u64::MAX);
        let mut output = [0; 17];
        assert_eq!(source.inner.delivery.lock().unwrap().read(&mut output), 17);
        assert_eq!(output, [7; 17]);
        assert_eq!(tx.available(), 17);
        let normal = super::super::AudioDelivery::default();
        assert_eq!(normal.available(0), super::super::MAX_DELIVERY_BYTES);
    }

    #[test]
    fn excess_data_is_rejected_before_fin_without_waiting_for_timeout() {
        let (mut source, commands) = source();
        let inner = Arc::clone(&source.inner);
        let worker = thread::spawn(move || {
            let ControlCommand::SourceOpen { generation, .. } = commands.recv().unwrap() else {
                panic!("source open expected")
            };
            let tx = announce(&inner, generation, 0, 3);
            tx.send(vec![1, 2, 3, 4]);
        });
        assert!(source
            .read_range(0, 3, Duration::from_secs(1))
            .unwrap_err()
            .contains("advertised file length"));
        assert_eq!(source.error_code, INVALID_SOURCE);
        worker.join().unwrap();
    }

    #[test]
    fn source_error_after_an_accepted_fill_fails_the_next_fill() {
        let (mut source, commands) = source();
        let inner = Arc::clone(&source.inner);
        let (fail, failing) = std::sync::mpsc::channel();
        let worker = thread::spawn(move || {
            let ControlCommand::SourceOpen { generation, .. } = commands.recv().unwrap() else {
                panic!("source open expected")
            };
            let tx = announce(&inner, generation, 0, (MAX_SOURCE_BYTES * 2) as u64);
            tx.send(vec![7; MAX_SOURCE_BYTES]);
            failing.recv_timeout(Duration::from_secs(2)).unwrap();
            tx.event(
                serde_json::json!({ "type":"error", "origin":"server", "request_id":generation,
                "message":"source changed during continuous playback" }),
            );
            tx.send(Vec::new());
        });
        assert_eq!(
            source
                .read_range(0, MAX_SOURCE_BYTES, Duration::from_secs(1))
                .unwrap(),
            vec![7; MAX_SOURCE_BYTES]
        );
        fail.send(()).unwrap();
        assert!(source
            .read_range(
                MAX_SOURCE_BYTES as u64,
                MAX_SOURCE_BYTES,
                Duration::from_secs(1)
            )
            .unwrap_err()
            .contains("source changed"));
        assert!(source.stream.is_none());
        worker.join().unwrap();
    }

    #[test]
    fn slow_progressing_source_returns_available_bytes_without_waiting_for_a_full_fill() {
        let (mut source, commands) = source();
        let inner = Arc::clone(&source.inner);
        let (stop, stopping) = std::sync::mpsc::channel();
        let worker = thread::spawn(move || {
            let ControlCommand::SourceOpen { generation, .. } = commands.recv().unwrap() else {
                panic!("source open expected")
            };
            let tx = announce(&inner, generation, 0, 1024 * 1024);
            // The link would supply 256 Kibit/s, enough for 128 kbit/s audio,
            // but would need eight seconds for a complete 256 KiB fill.
            loop {
                tx.send(vec![7; 4096]);
                if stopping.recv_timeout(Duration::from_millis(125)).is_ok() {
                    break;
                }
            }
        });
        let started = Instant::now();
        let result = source.read_range(0, MAX_SOURCE_BYTES, Duration::from_secs(1));
        stop.send(()).unwrap();
        worker.join().unwrap();
        assert_eq!(result.unwrap(), vec![7; 4096]);
        assert!(started.elapsed() < Duration::from_millis(500));
        assert_eq!(source.stream.as_ref().unwrap().next_position, 4096);
    }

    #[test]
    fn a_source_with_no_byte_progress_still_times_out_and_cancels_delivery() {
        let (mut source, commands) = source();
        let inner = Arc::clone(&source.inner);
        let worker = thread::spawn(move || {
            let ControlCommand::SourceOpen { generation, .. } = commands.recv().unwrap() else {
                panic!("source open expected")
            };
            announce(&inner, generation, 0, 100);
        });
        let error = source
            .read_range(0, MAX_SOURCE_BYTES, Duration::from_millis(30))
            .unwrap_err();
        worker.join().unwrap();
        assert!(error.contains("timed out"));
        assert!(source.stream.is_none());
        assert!(source.inner.delivery.lock().unwrap().suspended);
    }
}
