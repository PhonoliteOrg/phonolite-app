use std::collections::{HashSet, VecDeque};
use std::ffi::{CStr, CString};
use std::net::{ToSocketAddrs, UdpSocket};
use std::os::raw::{c_char, c_int, c_longlong};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use bytes::Bytes;
use rand::RngCore;
use serde::{Deserialize, Serialize};
mod security;

const ALPN_QUIC: &[&[u8]] = &[b"phonolite-quic"];
const MAX_UDP_SIZE: usize = 65535;
const MAX_QUIC_DATAGRAM: usize = 1350;
const MAX_DELIVERY_BYTES: usize = 512 * 1024;
const MAX_CONTROL_EVENTS: usize = 32;
const KEEPALIVE_INTERVAL: Duration = Duration::from_secs(10);

#[cfg(test)]
fn test_handle(generation: u64) -> (QuicHandle, mpsc::Receiver<ControlCommand>) {
    let (tx, commands) = mpsc::channel();
    let mut delivery = AudioDelivery::default();
    delivery.begin(generation);
    (
        QuicHandle {
            inner: Arc::new(ClientHandle {
                tx,
                delivery: Arc::new(Mutex::new(delivery)),
                events: Arc::new(Mutex::new(VecDeque::new())),
                generation: AtomicU64::new(generation),
                last_error: Arc::new(Mutex::new(None)),
                last_stats: Arc::new(Mutex::new(None)),
                last_rtt_ms: Arc::new(Mutex::new(None)),
            }),
        },
        commands,
    )
}

#[cfg(test)]
mod transition_tests {
    use super::*;

    #[test]
    fn stale_stream_announcement_cannot_select_audio_from_an_earlier_open() {
        let (handle, _) = test_handle(3);
        let sender = AudioSender {
            delivery: Arc::clone(&handle.inner.delivery),
            events: Arc::clone(&handle.inner.events),
            generation: 3,
        };
        let mut state = ClientState::new();
        state.active_track = Some("same-track".to_owned());
        let error = Arc::new(Mutex::new(None));
        let rtt = Arc::new(Mutex::new(None));
        handle_control_bytes(&mut state,
            b"{\"type\":\"stream\",\"request_id\":1,\"track_id\":\"same-track\",\"stream_id\":3,\"role\":\"active\",\"frame_ms\":20}\n",
            &sender, &error, &rtt);
        assert!(state.active_stream.is_none());
        handle_control_bytes(&mut state,
            b"{\"type\":\"stream\",\"request_id\":3,\"track_id\":\"same-track\",\"stream_id\":11,\"role\":\"active\",\"frame_ms\":20}\n",
            &sender, &error, &rtt);
        assert_eq!(state.active_stream, Some(11));
        sender.send(vec![1, 2]);
        let mut output = [0; 2];
        assert_eq!(handle.inner.delivery.lock().unwrap().read(&mut output), 2);
        assert_eq!(output, [1, 2]);
    }

    #[test]
    fn track_switch_discards_old_audio_and_old_end_of_stream() {
        let (mut handle, _) = test_handle(2);
        let mut sender = AudioSender {
            delivery: Arc::clone(&handle.inner.delivery),
            events: Arc::clone(&handle.inner.events),
            generation: 1,
        };
        sender.send(vec![9, 9]);
        sender.send(Vec::new());
        sender.generation = 2;
        sender.send(vec![1, 2, 3]);
        let mut output = [0u8; 16];
        let read = phonolite_quic_read(&mut handle, output.as_mut_ptr(), output.len());
        assert_eq!(read, 3);
        assert_eq!(&output[..3], &[1, 2, 3]);
        assert_eq!(
            phonolite_quic_read(&mut handle, output.as_mut_ptr(), output.len()),
            -5
        );
    }

    #[test]
    fn delivery_bounds_memory_and_retains_tails_across_short_reads() {
        let mut delivery = AudioDelivery::default();
        delivery.begin(1);
        assert!(delivery.push(1, vec![7; MAX_DELIVERY_BYTES]));
        assert_eq!(delivery.available(1), 0);
        assert!(!delivery.push(1, vec![9]));
        let mut output = [0; 3];
        assert_eq!(delivery.read(&mut output), 3);
        assert_eq!(output, [7; 3]);
        assert_eq!(delivery.bytes, MAX_DELIVERY_BYTES - 3);
        assert!(delivery.push(1, vec![1, 2, 3]));
        let mut rest = vec![0; MAX_DELIVERY_BYTES];
        assert_eq!(delivery.read(&mut rest), MAX_DELIVERY_BYTES as c_int);
        assert_eq!(&rest[MAX_DELIVERY_BYTES - 3..], &[1, 2, 3]);
        assert_eq!(delivery.bytes, 0);
    }

    #[test]
    fn seek_invalidates_old_audio_and_partial_read_before_worker_runs() {
        let (mut handle, commands) = test_handle(1);
        assert!(handle.inner.delivery.lock().unwrap().push(1, vec![1, 2, 3]));
        let mut output = [0; 1];
        assert_eq!(phonolite_quic_read(&mut handle, output.as_mut_ptr(), 1), 1);
        let track = CString::new("track").unwrap();
        assert_eq!(
            phonolite_quic_seek(&mut handle, track.as_ptr(), 9000, 42),
            0
        );
        assert_eq!(phonolite_quic_generation(&mut handle), 2);
        assert_eq!(phonolite_quic_read(&mut handle, output.as_mut_ptr(), 1), -5);
        assert!(!handle.inner.delivery.lock().unwrap().push(1, vec![8]));
        let ControlCommand::Seek {
            generation,
            position_ms,
            seek_id,
            ..
        } = commands.try_recv().unwrap()
        else {
            panic!("seek expected")
        };
        assert_eq!((generation, position_ms, seek_id), (2, 9000, 42));
    }

    #[test]
    fn cached_seek_suspends_delivery_until_next_remote_request() {
        let (mut handle, commands) = test_handle(1);
        assert!(handle.inner.delivery.lock().unwrap().push(1, vec![1, 2]));
        assert_eq!(phonolite_quic_suspend_audio(&mut handle), 0);
        assert!(matches!(
            commands.try_recv().unwrap(),
            ControlCommand::SuspendAudio
        ));
        assert_eq!(handle.inner.delivery.lock().unwrap().available(1), 0);
        let track = CString::new("track").unwrap();
        assert_eq!(phonolite_quic_seek(&mut handle, track.as_ptr(), 0, 1), 0);
        assert_eq!(
            handle.inner.delivery.lock().unwrap().available(2),
            MAX_DELIVERY_BYTES
        );
    }

    #[test]
    fn open_uses_requested_position_and_serializes_request_identity() {
        let (mut handle, commands) = test_handle(0);
        let track = CString::new("track").unwrap();
        assert_eq!(
            phonolite_quic_open_track_at(
                &mut handle,
                track.as_ptr(),
                std::ptr::null(),
                std::ptr::null(),
                20,
                std::ptr::null(),
                60000
            ),
            0
        );
        let ControlCommand::Open {
            generation,
            start_ms,
            ..
        } = commands.try_recv().unwrap()
        else {
            panic!("open expected")
        };
        assert_eq!((generation, start_ms), (1, 60000));
        let serialized = serde_json::to_value(ClientMessage::Seek {
            request_id: 2,
            track_id: "track",
            position_ms: 9000,
            seek_id: 42,
        })
        .unwrap();
        assert_eq!(serialized["request_id"], 2);
        assert_eq!(serialized["seek_id"], 42);
    }

    #[test]
    fn stream_ack_remains_visible_with_full_audio_buffer_and_stale_errors_are_ignored() {
        let (mut handle, _) = test_handle(3);
        let sender = AudioSender {
            delivery: Arc::clone(&handle.inner.delivery),
            events: Arc::clone(&handle.inner.events),
            generation: 3,
        };
        sender.send(vec![0; MAX_DELIVERY_BYTES]);
        let mut state = ClientState::new();
        state.active_track = Some("track".into());
        handle_control_bytes(&mut state,
            b"{\"type\":\"stream\",\"request_id\":3,\"track_id\":\"track\",\"stream_id\":11,\"role\":\"active\",\"frame_ms\":20,\"seek_id\":42,\"position_ms\":30000,\"range_end_ms\":60000,\"end_of_track\":false,\"source_version\":\"v1\"}\n{\"type\":\"error\",\"request_id\":2,\"message\":\"obsolete\"}\n",
            &sender, &handle.inner.last_error, &handle.inner.last_rtt_ms);
        let event_ptr = phonolite_quic_poll_event(&mut handle);
        let event: serde_json::Value =
            serde_json::from_str(unsafe { CStr::from_ptr(event_ptr) }.to_str().unwrap()).unwrap();
        phonolite_quic_free_string(event_ptr);
        assert_eq!(event["seek_id"], 42);
        assert_eq!(event["range_end_ms"], 60000);
        assert_eq!(event["source_version"], "v1");
        assert!(handle.inner.last_error.lock().unwrap().is_none());
        assert_eq!(sender.available(), 0);
    }

    #[test]
    fn telemetry_coalescing_preserves_partial_message_and_essential_seek() {
        let mut state = ClientState::new();
        enqueue_control(
            &mut state,
            ClientMessage::Buffer {
                request_id: 1,
                buffer_ms: 100,
                target_ms: None,
            },
        );
        state.control_offset = 1;
        enqueue_control(
            &mut state,
            ClientMessage::Buffer {
                request_id: 1,
                buffer_ms: 200,
                target_ms: None,
            },
        );
        enqueue_control(
            &mut state,
            ClientMessage::Seek {
                request_id: 1,
                track_id: "track",
                position_ms: 500,
                seek_id: 1,
            },
        );
        enqueue_control(
            &mut state,
            ClientMessage::Buffer {
                request_id: 1,
                buffer_ms: 300,
                target_ms: None,
            },
        );
        assert_eq!(state.pending_control.len(), 3);
        assert!(std::str::from_utf8(&state.pending_control[0].1)
            .unwrap()
            .contains("100"));
        assert_eq!(state.pending_control[1].0, ControlKind::Essential);
        assert!(std::str::from_utf8(&state.pending_control[2].1)
            .unwrap()
            .contains("300"));
    }
}

#[repr(C)]
pub struct QuicHandle {
    inner: Arc<ClientHandle>,
}

struct ClientHandle {
    tx: mpsc::Sender<ControlCommand>,
    delivery: Arc<Mutex<AudioDelivery>>,
    events: Arc<Mutex<VecDeque<String>>>,
    generation: AtomicU64,
    last_error: Arc<Mutex<Option<String>>>,
    last_stats: Arc<Mutex<Option<String>>>,
    last_rtt_ms: Arc<Mutex<Option<i64>>>,
}

struct AudioSender {
    delivery: Arc<Mutex<AudioDelivery>>,
    events: Arc<Mutex<VecDeque<String>>>,
    generation: u64,
}
impl AudioSender {
    fn current(&self) -> bool {
        self.delivery
            .lock()
            .is_ok_and(|queue| queue.generation == self.generation && !queue.suspended)
    }

    fn available(&self) -> usize {
        self.delivery
            .lock()
            .map_or(0, |queue| queue.available(self.generation))
    }

    fn send(&self, data: Vec<u8>) {
        if let Ok(mut queue) = self.delivery.lock() {
            if data.is_empty() {
                if queue.generation == self.generation {
                    queue.closed = true;
                }
            } else {
                // Read only the queue's available capacity from QUIC. A false
                // result here means a concurrent seek superseded these bytes.
                queue.push(self.generation, data);
            }
        }
    }

    fn event(&self, event: serde_json::Value) {
        if !self.current() {
            return;
        }
        if let Ok(mut events) = self.events.lock() {
            if events.len() == MAX_CONTROL_EVENTS {
                events.pop_front();
            }
            events.push_back(event.to_string());
        }
    }
}

#[derive(Default)]
struct AudioDelivery {
    generation: u64,
    chunks: VecDeque<Vec<u8>>,
    front_offset: usize,
    bytes: usize,
    closed: bool,
    suspended: bool,
}

impl AudioDelivery {
    fn begin(&mut self, generation: u64) {
        self.generation = generation;
        self.chunks.clear();
        self.front_offset = 0;
        self.bytes = 0;
        self.closed = false;
        self.suspended = false;
    }

    fn suspend(&mut self) {
        self.chunks.clear();
        self.front_offset = 0;
        self.bytes = 0;
        self.suspended = true;
    }

    fn available(&self, generation: u64) -> usize {
        if self.generation != generation || self.suspended || self.closed {
            0
        } else {
            MAX_DELIVERY_BYTES.saturating_sub(self.bytes)
        }
    }

    fn push(&mut self, generation: u64, data: Vec<u8>) -> bool {
        if data.len() > self.available(generation) {
            return false;
        }
        self.bytes += data.len();
        self.chunks.push_back(data);
        true
    }

    fn read(&mut self, output: &mut [u8]) -> c_int {
        let mut copied = 0;
        while copied < output.len() {
            let Some(front) = self.chunks.front() else {
                break;
            };
            let count = (front.len() - self.front_offset).min(output.len() - copied);
            output[copied..copied + count]
                .copy_from_slice(&front[self.front_offset..self.front_offset + count]);
            self.front_offset += count;
            self.bytes -= count;
            copied += count;
            if self.front_offset == front.len() {
                self.chunks.pop_front();
                self.front_offset = 0;
            }
        }
        if copied > 0 {
            copied as c_int
        } else if self.closed {
            0
        } else {
            -5
        }
    }
}

enum ControlCommand {
    Open {
        generation: u64,
        track_id: String,
        mode: Option<String>,
        quality: Option<String>,
        frame_ms: u32,
        queue: Vec<String>,
        start_ms: u32,
    },
    Playback {
        track_id: String,
        position_ms: u32,
        playing: bool,
    },
    Seek {
        generation: u64,
        track_id: String,
        position_ms: u32,
        seek_id: u32,
    },
    Buffer {
        generation: u64,
        buffer_ms: u32,
        target_ms: Option<u32>,
    },
    Advance,
    SuspendAudio,
    Close,
}

#[derive(Serialize)]
#[serde(tag = "type")]
enum ClientMessage<'a> {
    #[serde(rename = "auth")]
    Auth { token: &'a str },
    #[serde(rename = "open")]
    Open {
        request_id: u64,
        track_id: &'a str,
        mode: Option<&'a str>,
        quality: Option<&'a str>,
        frame_ms: u32,
        queue: Option<&'a [String]>,
        start_ms: u32,
    },
    #[serde(rename = "buffer")]
    Buffer {
        request_id: u64,
        buffer_ms: u32,
        target_ms: Option<u32>,
    },
    #[serde(rename = "playback")]
    Playback {
        track_id: &'a str,
        position_ms: u32,
        playing: bool,
    },
    #[serde(rename = "seek")]
    Seek {
        request_id: u64,
        track_id: &'a str,
        position_ms: u32,
        seek_id: u32,
    },
    #[serde(rename = "advance")]
    Advance,
    #[serde(rename = "ping")]
    Ping { ts: Option<i64> },
}

#[derive(Deserialize)]
#[serde(tag = "type")]
enum ServerMessage {
    #[serde(rename = "auth_ok")]
    AuthOk,
    #[serde(rename = "error")]
    Error {
        message: String,
        request_id: Option<u64>,
        seek_id: Option<u32>,
    },
    #[serde(rename = "stream")]
    Stream {
        request_id: Option<u64>,
        track_id: String,
        stream_id: u64,
        role: String,
        frame_ms: u32,
        seek_id: Option<u32>,
        position_ms: Option<u32>,
        source_version: Option<String>,
        range_end_ms: Option<u32>,
        end_of_track: Option<bool>,
    },
    #[serde(rename = "open_ok")]
    OpenOk { track_id: String },
    #[serde(rename = "pong")]
    Pong { ts: Option<i64> },
}

struct ClientState {
    control_stream_id: u64,
    pending_control: VecDeque<(ControlKind, Bytes)>,
    control_offset: usize,
    control_buf: Vec<u8>,
    active_track: Option<String>,
    active_stream: Option<u64>,
    retired_streams: HashSet<u64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ControlKind {
    Essential,
    Buffer,
    Playback,
    Ping,
}

impl ClientState {
    fn new() -> Self {
        Self {
            control_stream_id: 0,
            pending_control: VecDeque::new(),
            control_offset: 0,
            control_buf: Vec::new(),
            active_track: None,
            active_stream: None,
            retired_streams: HashSet::new(),
        }
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_connect(
    host: *const c_char,
    port: u16,
    token: *const c_char,
    expected_pin: *const c_char,
) -> *mut QuicHandle {
    let host = unsafe { cstr_to_string(host) };
    let token = unsafe { cstr_to_string(token) };
    let expected_pin = unsafe { cstr_to_string(expected_pin) };
    if host.is_empty() || token.is_empty() || expected_pin.len() != 64 {
        return std::ptr::null_mut();
    }
    let addr = if host.contains(':') { format!("[{}]:{}", host, port) } else { format!("{}:{}", host, port) };

    let (tx_cmd, rx_cmd) = mpsc::channel::<ControlCommand>();
    let delivery = Arc::new(Mutex::new(AudioDelivery::default()));
    let events = Arc::new(Mutex::new(VecDeque::new()));
    let tx_bytes = AudioSender {
        delivery: Arc::clone(&delivery),
        events: Arc::clone(&events),
        generation: 0,
    };
    let last_error = Arc::new(Mutex::new(None));
    let last_stats = Arc::new(Mutex::new(None));
    let last_rtt_ms = Arc::new(Mutex::new(None));
    let handle = Arc::new(ClientHandle {
        tx: tx_cmd.clone(),
        delivery,
        events,
        generation: AtomicU64::new(0),
        last_error: Arc::clone(&last_error),
        last_stats: Arc::clone(&last_stats),
        last_rtt_ms: Arc::clone(&last_rtt_ms),
    });

    let thread_handle = handle.clone();
    thread::spawn(move || {
        if let Err(err) = run_client(
            addr,
            token,
            expected_pin,
            rx_cmd,
            tx_bytes,
            last_error,
            last_stats,
            last_rtt_ms,
        ) {
            if let Ok(mut guard) = thread_handle.last_error.lock() {
                *guard = Some(err.clone());
            }
            if let Ok(mut delivery) = thread_handle.delivery.lock() {
                delivery.closed = true;
            }
            if let Ok(mut events) = thread_handle.events.lock() {
                if events.len() == MAX_CONTROL_EVENTS {
                    events.pop_front();
                }
                events
                    .push_back(serde_json::json!({ "type": "error", "message": err }).to_string());
            }
        }
    });

    let boxed = Box::new(QuicHandle { inner: handle });
    Box::into_raw(boxed)
}

#[no_mangle]
pub extern "C" fn phonolite_quic_open_track(
    handle: *mut QuicHandle,
    track_id: *const c_char,
    mode: *const c_char,
    quality: *const c_char,
    frame_ms: u32,
    queue_json: *const c_char,
) -> c_int {
    phonolite_quic_open_track_at(handle, track_id, mode, quality, frame_ms, queue_json, 0)
}

#[no_mangle]
pub extern "C" fn phonolite_quic_open_track_at(
    handle: *mut QuicHandle,
    track_id: *const c_char,
    mode: *const c_char,
    quality: *const c_char,
    frame_ms: u32,
    queue_json: *const c_char,
    start_ms: u32,
) -> c_int {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    let track_id = unsafe { cstr_to_string(track_id) };
    if track_id.is_empty() {
        return -2;
    }
    let mode = unsafe { cstr_to_optional_string(mode) };
    let quality = unsafe { cstr_to_optional_string(quality) };
    let queue = unsafe { cstr_to_optional_string(queue_json) }
        .and_then(|raw| serde_json::from_str::<Vec<String>>(&raw).ok())
        .unwrap_or_default();

    let generation = handle.inner.generation.fetch_add(1, Ordering::SeqCst) + 1;
    if let Ok(mut delivery) = handle.inner.delivery.lock() {
        delivery.begin(generation);
    }
    if let Ok(mut events) = handle.inner.events.lock() {
        events.clear();
    }
    if let Ok(mut error) = handle.inner.last_error.lock() {
        *error = None;
    }
    if handle
        .inner
        .tx
        .send(ControlCommand::Open {
            generation,
            track_id,
            mode,
            quality,
            frame_ms,
            queue,
            start_ms,
        })
        .is_err()
    {
        return -3;
    }
    0
}

#[no_mangle]
pub extern "C" fn phonolite_quic_send_buffer(
    handle: *mut QuicHandle,
    buffer_ms: u32,
    target_ms: u32,
) -> c_int {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    let target = if target_ms == 0 {
        None
    } else {
        Some(target_ms)
    };
    if handle
        .inner
        .tx
        .send(ControlCommand::Buffer {
            generation: handle.inner.generation.load(Ordering::SeqCst),
            buffer_ms,
            target_ms: target,
        })
        .is_err()
    {
        return -2;
    }
    0
}

#[no_mangle]
pub extern "C" fn phonolite_quic_send_playback(
    handle: *mut QuicHandle,
    track_id: *const c_char,
    position_ms: u32,
    playing: c_int,
) -> c_int {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    let track_id = unsafe { cstr_to_string(track_id) };
    if track_id.is_empty() {
        return -2;
    }
    let playing = playing != 0;
    if handle
        .inner
        .tx
        .send(ControlCommand::Playback {
            track_id,
            position_ms,
            playing,
        })
        .is_err()
    {
        return -3;
    }
    0
}

#[no_mangle]
pub extern "C" fn phonolite_quic_seek(
    handle: *mut QuicHandle,
    track_id: *const c_char,
    position_ms: u32,
    seek_id: u32,
) -> c_int {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    let track_id = unsafe { cstr_to_string(track_id) };
    if track_id.is_empty() {
        return -2;
    }
    let generation = handle.inner.generation.fetch_add(1, Ordering::SeqCst) + 1;
    if let Ok(mut delivery) = handle.inner.delivery.lock() {
        delivery.begin(generation);
    }
    if let Ok(mut events) = handle.inner.events.lock() {
        events.clear();
    }
    if let Ok(mut error) = handle.inner.last_error.lock() {
        *error = None;
    }
    if handle
        .inner
        .tx
        .send(ControlCommand::Seek {
            generation,
            track_id,
            position_ms,
            seek_id,
        })
        .is_err()
    {
        return -3;
    }
    0
}

#[no_mangle]
pub extern "C" fn phonolite_quic_suspend_audio(handle: *mut QuicHandle) -> c_int {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    if let Ok(mut delivery) = handle.inner.delivery.lock() {
        delivery.suspend();
    }
    if handle.inner.tx.send(ControlCommand::SuspendAudio).is_err() {
        return -2;
    }
    0
}

#[no_mangle]
pub extern "C" fn phonolite_quic_generation(handle: *mut QuicHandle) -> u64 {
    unsafe { handle.as_ref() }.map_or(0, |handle| handle.inner.generation.load(Ordering::SeqCst))
}

#[no_mangle]
pub extern "C" fn phonolite_quic_advance(handle: *mut QuicHandle) -> c_int {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    if handle.inner.tx.send(ControlCommand::Advance).is_err() {
        return -2;
    }
    0
}

#[no_mangle]
pub extern "C" fn phonolite_quic_read(
    handle: *mut QuicHandle,
    buffer: *mut u8,
    buffer_len: usize,
) -> c_int {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    if buffer.is_null() || buffer_len == 0 {
        return -2;
    }
    let mut delivery = match handle.inner.delivery.lock() {
        Ok(value) => value,
        Err(_) => return -3,
    };
    let output = unsafe { std::slice::from_raw_parts_mut(buffer, buffer_len) };
    delivery.read(output)
}

#[no_mangle]
pub extern "C" fn phonolite_quic_poll_event(handle: *mut QuicHandle) -> *mut c_char {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return std::ptr::null_mut();
    };
    let event = handle
        .inner
        .events
        .lock()
        .ok()
        .and_then(|mut events| events.pop_front());
    event
        .and_then(|event| CString::new(event).ok())
        .map_or(std::ptr::null_mut(), CString::into_raw)
}

#[no_mangle]
pub extern "C" fn phonolite_quic_last_error(handle: *mut QuicHandle) -> *mut c_char {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return std::ptr::null_mut();
    };
    let msg = match handle.inner.last_error.lock() {
        Ok(value) => value.clone().unwrap_or_default(),
        Err(_) => String::new(),
    };
    let cstring = CString::new(msg).unwrap_or_else(|_| CString::new("").unwrap());
    cstring.into_raw()
}

#[no_mangle]
pub extern "C" fn phonolite_quic_poll_stats(handle: *mut QuicHandle) -> *mut c_char {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return std::ptr::null_mut();
    };
    let msg = match handle.inner.last_stats.lock() {
        Ok(mut value) => value.take().unwrap_or_default(),
        Err(_) => String::new(),
    };
    if msg.is_empty() {
        return std::ptr::null_mut();
    }
    let cstring = CString::new(msg).unwrap_or_else(|_| CString::new("").unwrap());
    cstring.into_raw()
}

#[no_mangle]
pub extern "C" fn phonolite_quic_poll_rtt_ms(handle: *mut QuicHandle) -> c_longlong {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    match handle.inner.last_rtt_ms.lock() {
        Ok(mut value) => value.take().unwrap_or(-1),
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_close(handle: *mut QuicHandle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        let boxed = Box::from_raw(handle);
        let _ = boxed.inner.tx.send(ControlCommand::Close);
    }
}

unsafe fn cstr_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().trim().to_string()
}

unsafe fn cstr_to_optional_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let value = CStr::from_ptr(ptr).to_string_lossy().trim().to_string();
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn run_client(
    addr: String,
    token: String,
    expected_pin: String,
    rx_cmd: mpsc::Receiver<ControlCommand>,
    mut tx_bytes: AudioSender,
    last_error: Arc<Mutex<Option<String>>>,
    last_stats: Arc<Mutex<Option<String>>>,
    last_rtt_ms: Arc<Mutex<Option<i64>>>,
) -> Result<(), String> {
    let addrs = addr
        .to_socket_addrs()
        .map_err(|err| format!("invalid server addr: {}", err))?
        .collect::<Vec<_>>();
    let server_addr = addrs
        .iter()
        .find(|addr| addr.is_ipv4())
        .copied()
        .or_else(|| addrs.first().copied())
        .ok_or_else(|| "invalid server addr: no resolved addresses".to_string())?;
    let socket = UdpSocket::bind(if server_addr.is_ipv4() { "0.0.0.0:0" } else { "[::]:0" }).map_err(|err| format!("{}", err))?;
    socket
        .connect(server_addr)
        .map_err(|err| format!("socket connect: {}", err))?;
    socket
        .set_nonblocking(true)
        .map_err(|err| format!("socket nonblock: {}", err))?;
    let local_addr = socket.local_addr().map_err(|err| format!("{}", err))?;
    if let Ok(mut guard) = last_stats.lock() {
        *guard = Some(format!(
            "QUIC client socket local={} server={}",
            local_addr, server_addr
        ));
    }

    let mut config =
        quiche::Config::new(quiche::PROTOCOL_VERSION).map_err(|e| format!("{:?}", e))?;
    config
        .set_application_protos(ALPN_QUIC)
        .map_err(|err| format!("alpn error: {:?}", err))?;
    // Self-signed identity is authenticated by OPAQUE. Enforce its SPKI below,
    // after TLS proves possession and before writing any application bytes.
    config.verify_peer(false);
    config.set_max_idle_timeout(30_000);
    config.set_max_recv_udp_payload_size(MAX_QUIC_DATAGRAM);
    config.set_max_send_udp_payload_size(MAX_QUIC_DATAGRAM);
    config.set_initial_max_data(2 * MAX_DELIVERY_BYTES as u64);
    config.set_initial_max_stream_data_bidi_local(64 * 1024);
    config.set_initial_max_stream_data_bidi_remote(64 * 1024);
    config.set_initial_max_stream_data_uni(MAX_DELIVERY_BYTES as u64);
    config.set_max_connection_window(2 * MAX_DELIVERY_BYTES as u64);
    config.set_max_stream_window(MAX_DELIVERY_BYTES as u64);
    config.set_initial_max_streams_bidi(16);
    config.set_initial_max_streams_uni(32);
    config.set_disable_active_migration(true);

    let scid = generate_cid();
    let scid_conn_id = quiche::ConnectionId::from_ref(&scid);
    let mut conn = quiche::connect(None, &scid_conn_id, local_addr, server_addr, &mut config)
        .map_err(|err| format!("connect error: {:?}", err))?;

    let mut state = ClientState::new();
    let mut peer_verified = false;
    enqueue_control(&mut state, ClientMessage::Auth { token: &token });

    let mut recv_buf = vec![0u8; MAX_UDP_SIZE];
    let mut send_buf = vec![0u8; MAX_UDP_SIZE];
    let mut stream_buf = vec![0u8; 64 * 1024];
    let mut next_timeout = conn.timeout().map(|t| Instant::now() + t);
    let mut last_stats_log = Instant::now();
    let mut last_ping = Instant::now();
    let mut pending_datagrams = VecDeque::new();

    loop {
        while let Ok(cmd) = rx_cmd.try_recv() {
            match cmd {
                ControlCommand::Open {
                    generation,
                    track_id,
                    mode,
                    quality,
                    frame_ms,
                    queue,
                    start_ms,
                } => {
                    tx_bytes.generation = generation;
                    state.active_track = Some(track_id.clone());
                    retire_active_stream(&mut state, &mut conn);
                    let queue_opt = if queue.is_empty() {
                        None
                    } else {
                        Some(queue.as_slice())
                    };
                    enqueue_control(
                        &mut state,
                        ClientMessage::Open {
                            request_id: generation,
                            track_id: &track_id,
                            mode: mode.as_deref(),
                            quality: quality.as_deref(),
                            frame_ms,
                            queue: queue_opt,
                            start_ms,
                        },
                    );
                }
                ControlCommand::Playback {
                    track_id,
                    position_ms,
                    playing,
                } => {
                    enqueue_control(
                        &mut state,
                        ClientMessage::Playback {
                            track_id: &track_id,
                            position_ms,
                            playing,
                        },
                    );
                }
                ControlCommand::Seek {
                    generation,
                    track_id,
                    position_ms,
                    seek_id,
                } => {
                    tx_bytes.generation = generation;
                    state.active_track = Some(track_id.clone());
                    retire_active_stream(&mut state, &mut conn);
                    enqueue_control(
                        &mut state,
                        ClientMessage::Seek {
                            request_id: generation,
                            track_id: &track_id,
                            position_ms,
                            seek_id,
                        },
                    );
                }
                ControlCommand::Buffer {
                    generation,
                    buffer_ms,
                    target_ms,
                } => {
                    if generation != tx_bytes.generation {
                        continue;
                    }
                    enqueue_control(
                        &mut state,
                        ClientMessage::Buffer {
                            request_id: generation,
                            buffer_ms,
                            target_ms,
                        },
                    );
                }
                ControlCommand::Advance => {
                    enqueue_control(&mut state, ClientMessage::Advance);
                }
                ControlCommand::SuspendAudio => {
                    retire_active_stream(&mut state, &mut conn);
                }
                ControlCommand::Close => {
                    let _ = tx_bytes.send(Vec::new());
                    return Ok(());
                }
            }
        }

        if last_ping.elapsed() >= KEEPALIVE_INTERVAL {
            let ts = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .ok()
                .map(|v| v.as_millis() as i64);
            enqueue_control(&mut state, ClientMessage::Ping { ts });
            last_ping = Instant::now();
        }

        if verify_identity(&conn, &expected_pin, &mut peer_verified)? { flush_control(&mut state, &mut conn); }
        flush_conn(
            &mut conn,
            &socket,
            &mut send_buf,
            &last_error,
            &mut pending_datagrams,
        );

        loop {
            match socket.recv_from(&mut recv_buf) {
                Ok((len, from)) => {
                    receive_datagram(
                        &mut conn,
                        &mut recv_buf[..len],
                        from,
                        local_addr,
                        &last_error,
                    );
                }
                Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => break,
                Err(err) => {
                    set_last_error_if_empty(&last_error, format!("udp recv error: {}", err));
                    return Err(format!("recv error: {}", err));
                }
            }
        }

        if verify_identity(&conn, &expected_pin, &mut peer_verified)? {
        handle_readable(
            &mut state,
            &mut conn,
            &tx_bytes,
            &last_error,
            &last_rtt_ms,
            &mut stream_buf,
        )?;
        flush_control(&mut state, &mut conn);
        }
        flush_conn(
            &mut conn,
            &socket,
            &mut send_buf,
            &last_error,
            &mut pending_datagrams,
        );

        let now = Instant::now();
        if let Some(deadline) = next_timeout {
            if now >= deadline {
                conn.on_timeout();
            }
        }
        next_timeout = conn.timeout().map(|t| Instant::now() + t);

        if conn.is_closed() {
            if let Some(detail) = connection_close_detail(&conn) {
                set_last_error(&last_error, detail);
            } else {
                set_last_error_if_empty(&last_error, "QUIC connection closed".to_string());
            }
            let _ = tx_bytes.send(Vec::new());
            return Ok(());
        }

        maybe_log_stats(&conn, &mut last_stats_log, &last_stats);

        let mut sleep_for = match next_timeout {
            Some(deadline) => deadline
                .saturating_duration_since(Instant::now())
                .min(Duration::from_millis(5)),
            None => Duration::from_millis(5),
        };
        if let Some(packet) = pending_datagrams.front() {
            sleep_for = sleep_for.min(packet.at.saturating_duration_since(Instant::now()));
        }
        thread::sleep(sleep_for);
    }
}

fn enqueue_control(state: &mut ClientState, message: ClientMessage<'_>) {
    let kind = match &message {
        ClientMessage::Buffer { .. } => ControlKind::Buffer,
        ClientMessage::Playback { .. } => ControlKind::Playback,
        ClientMessage::Ping { .. } => ControlKind::Ping,
        _ => ControlKind::Essential,
    };
    if let Ok(json) = serde_json::to_string(&message) {
        if kind != ControlKind::Essential {
            let mut index = 0;
            state.pending_control.retain(|(previous_kind, _)| {
                let retain = (index == 0 && state.control_offset > 0) || *previous_kind != kind;
                index += 1;
                retain
            });
        }
        let mut line = json;
        line.push('\n');
        state.pending_control.push_back((kind, Bytes::from(line)));
    }
}

fn verify_identity(conn: &quiche::Connection, pin: &str, verified: &mut bool) -> Result<bool, String> {
    if *verified { return Ok(true); }
    if !conn.is_established() { return Ok(false); }
    let cert = conn.peer_cert().ok_or("Missing QUIC server identity")?;
    if !security::valid_certificate(cert) || security::spki(cert)? != pin { return Err("QUIC server identity does not match the authenticated server or certificate expired".into()); }
    *verified = true;
    Ok(true)
}

fn flush_control(state: &mut ClientState, conn: &mut quiche::Connection) {
    loop {
        let Some((_, front)) = state.pending_control.front() else {
            break;
        };
        let data = &front[state.control_offset..];
        match conn.stream_send(state.control_stream_id, data, false) {
            Ok(sent) => {
                if sent == data.len() {
                    state.pending_control.pop_front();
                    state.control_offset = 0;
                } else {
                    state.control_offset += sent;
                    break;
                }
            }
            Err(quiche::Error::Done) => break,
            Err(_) => break,
        }
    }
}

// Queue outgoing datagrams until QUIC's scheduled send time.
struct PendingDatagram {
    bytes: Vec<u8>,
    at: Instant,
    address: std::net::SocketAddr,
}

fn flush_conn(
    conn: &mut quiche::Connection,
    socket: &UdpSocket,
    out: &mut [u8],
    last_error: &Arc<Mutex<Option<String>>>,
    pending: &mut VecDeque<PendingDatagram>,
) {
    // A bounded queue prevents the transport from allocating unlimited paced data.
    const MAX_PENDING_PACKETS: usize = 4096;
    const MAX_PENDING_BYTES: usize = 4 * 1024 * 1024;
    let mut pending_bytes: usize = pending.iter().map(|packet| packet.bytes.len()).sum();
    while pending.len() < MAX_PENDING_PACKETS && pending_bytes + out.len() <= MAX_PENDING_BYTES {
        match conn.send(out) {
            Ok((len, send_info)) => {
                pending_bytes += len;
                let packet = PendingDatagram {
                    bytes: out[..len].to_vec(),
                    at: send_info.at,
                    address: send_info.to,
                };
                let index = pending.partition_point(|queued| queued.at <= packet.at);
                pending.insert(index, packet);
            }
            Err(quiche::Error::Done) => break,
            Err(err) => {
                set_last_error_if_empty(last_error, format!("QUIC send error: {:?}", err));
                break;
            }
        }
    }
    while pending
        .front()
        .is_some_and(|packet| packet.at <= Instant::now())
    {
        let packet = pending.pop_front().unwrap();
        // The socket is connected; send() avoids EISCONN on some platforms.
        match socket.send(&packet.bytes) {
            Ok(_) => {}
            Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                pending.push_front(packet);
                break;
            }
            Err(err) => {
                set_last_error_if_empty(
                    last_error,
                    format!("udp send error: {} (to {})", err, packet.address),
                );
                break;
            }
        }
    }
}

fn receive_datagram(
    conn: &mut quiche::Connection,
    bytes: &mut [u8],
    from: std::net::SocketAddr,
    local_addr: std::net::SocketAddr,
    last_error: &Arc<Mutex<Option<String>>>,
) {
    let recv_info = quiche::RecvInfo {
        from,
        to: local_addr,
    };
    if let Err(err) = conn.recv(bytes, recv_info) {
        if err != quiche::Error::Done {
            set_last_error_if_empty(last_error, format!("QUIC recv error: {:?}", err));
        }
    }
}

fn handle_readable(
    state: &mut ClientState,
    conn: &mut quiche::Connection,
    tx_bytes: &AudioSender,
    last_error: &Arc<Mutex<Option<String>>>,
    last_rtt_ms: &Arc<Mutex<Option<i64>>>,
    buf: &mut [u8],
) -> Result<(), String> {
    // Control messages must remain observable when the PCM/cache consumer is
    // paused. Unknown audio streams stay in QUIC until their announcement.
    while conn.stream_readable(state.control_stream_id) {
        match conn.stream_recv(state.control_stream_id, buf) {
            Ok((len, fin)) => {
                if len == 0 {
                    // Ignore empty stream frames; raw opus uses explicit EOS framing.
                    // Treating this as data causes premature end-of-stream in the client.
                    if fin {
                        return Err("QUIC control stream closed".to_string());
                    }
                    break;
                }
                handle_control_bytes(state, &buf[..len], tx_bytes, last_error, last_rtt_ms);
            }
            Err(quiche::Error::Done) => break,
            Err(err) => {
                set_last_error_if_empty(last_error, format!("QUIC stream recv error: {:?}", err));
                break;
            }
        }
    }
    state.retired_streams.retain(|stream_id| {
        // Announcements can arrive before the stream's first data packet.
        // Retry shutdown once QUIC knows about that stream.
        conn.stream_shutdown(*stream_id, quiche::Shutdown::Read, 0)
            .is_err()
    });
    if let Some(stream_id) = state.active_stream {
        while conn.stream_readable(stream_id) {
            let capacity = tx_bytes.available().min(buf.len());
            if capacity == 0 {
                break;
            }
            match conn.stream_recv(stream_id, &mut buf[..capacity]) {
                Ok((len, fin)) => {
                    if len > 0 {
                        tx_bytes.send(buf[..len].to_vec());
                    }
                    if fin {
                        state.active_stream = None;
                        break;
                    }
                    if len == 0 {
                        break;
                    }
                }
                Err(quiche::Error::Done) => break,
                Err(err) => {
                    let message = format!("QUIC audio stream receive error: {err:?}");
                    set_last_error_if_empty(last_error, message.clone());
                    tx_bytes.event(serde_json::json!({
                        "type": "error", "message": message, "request_id": tx_bytes.generation,
                    }));
                    tx_bytes.send(Vec::new());
                    break;
                }
            }
        }
    }
    Ok(())
}

fn retire_active_stream(state: &mut ClientState, conn: &mut quiche::Connection) {
    if let Some(stream_id) = state.active_stream.take() {
        if conn
            .stream_shutdown(stream_id, quiche::Shutdown::Read, 0)
            .is_err()
        {
            state.retired_streams.insert(stream_id);
        }
    }
}

fn handle_control_bytes(
    state: &mut ClientState,
    data: &[u8],
    tx: &AudioSender,
    last_error: &Arc<Mutex<Option<String>>>,
    last_rtt_ms: &Arc<Mutex<Option<i64>>>,
) {
    state.control_buf.extend_from_slice(data);
    loop {
        let pos = match state.control_buf.iter().position(|b| *b == b'\n') {
            Some(pos) => pos,
            None => break,
        };
        let line = state.control_buf.drain(..=pos).collect::<Vec<u8>>();
        if line.is_empty() {
            continue;
        }
        let text = match std::str::from_utf8(&line[..line.len().saturating_sub(1)]) {
            Ok(value) => value,
            Err(_) => continue,
        };
        if let Ok(msg) = serde_json::from_str::<ServerMessage>(text) {
            match msg {
                ServerMessage::Stream {
                    request_id,
                    track_id,
                    stream_id,
                    role,
                    frame_ms,
                    seek_id,
                    position_ms,
                    source_version,
                    range_end_ms,
                    end_of_track,
                } => {
                    if request_id != Some(tx.generation)
                        || !tx.current()
                        || role != "active"
                        || state.active_track.as_deref() != Some(track_id.as_str())
                    {
                        state.retired_streams.insert(stream_id);
                        continue;
                    }
                    if let Some(previous) = state.active_stream.replace(stream_id) {
                        if previous != stream_id {
                            state.retired_streams.insert(previous);
                        }
                    }
                    tx.event(serde_json::json!({
                        "type": "stream", "request_id": request_id, "track_id": track_id,
                        "stream_id": stream_id, "role": role, "frame_ms": frame_ms,
                        "seek_id": seek_id, "position_ms": position_ms,
                        "source_version": source_version, "range_end_ms": range_end_ms,
                        "end_of_track": end_of_track,
                    }));
                }
                ServerMessage::Error {
                    message,
                    request_id,
                    seek_id,
                } => {
                    if !tx.current() || request_id.is_some_and(|id| id != tx.generation) {
                        continue;
                    }
                    tx.event(serde_json::json!({
                        "type": "error", "message": message,
                        "request_id": request_id, "seek_id": seek_id,
                    }));
                    set_last_error_if_empty(last_error, message);
                    tx.send(Vec::new());
                }
                ServerMessage::Pong { ts } => {
                    if let Some(sent_ms) = ts {
                        let now_ms = SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .ok()
                            .map(|v| v.as_millis() as i64);
                        if let Some(now_ms) = now_ms {
                            let rtt = (now_ms - sent_ms).max(0);
                            if let Ok(mut guard) = last_rtt_ms.lock() {
                                *guard = Some(rtt);
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    }
}

fn set_last_error_if_empty(target: &Arc<Mutex<Option<String>>>, message: String) {
    if let Ok(mut guard) = target.lock() {
        if guard.is_none() {
            *guard = Some(message);
        }
    }
}

fn set_last_error(target: &Arc<Mutex<Option<String>>>, message: String) {
    if let Ok(mut guard) = target.lock() {
        *guard = Some(message);
    }
}

fn generate_cid() -> Vec<u8> {
    let mut scid = [0u8; 16];
    rand::rng().fill_bytes(&mut scid);
    scid.to_vec()
}

fn connection_close_detail(conn: &quiche::Connection) -> Option<String> {
    let mut parts = Vec::new();
    if conn.is_timed_out() {
        parts.push("timed_out=true".to_string());
    }
    if let Some(err) = conn.peer_error() {
        parts.push(format!(
            "peer_error(code={}, app={}, reason={})",
            err.error_code,
            err.is_app,
            String::from_utf8_lossy(&err.reason)
        ));
    }
    if let Some(err) = conn.local_error() {
        parts.push(format!(
            "local_error(code={}, app={}, reason={})",
            err.error_code,
            err.is_app,
            String::from_utf8_lossy(&err.reason)
        ));
    }
    if parts.is_empty() {
        None
    } else {
        Some(format!("QUIC connection closed: {}", parts.join(", ")))
    }
}

fn maybe_log_stats(
    conn: &quiche::Connection,
    last_log: &mut Instant,
    last_stats: &Arc<Mutex<Option<String>>>,
) {
    let now = Instant::now();
    if now.duration_since(*last_log) < Duration::from_secs(5) {
        return;
    }
    *last_log = now;
    let stats = conn.stats();
    let path = conn.path_stats().next();
    let message = format!(
        "QUIC client stats: sent_pkts={} recv_pkts={} sent_bytes={} recv_bytes={} established={} timed_out={} path={:?}",
        stats.sent,
        stats.recv,
        stats.sent_bytes,
        stats.recv_bytes,
        conn.is_established(),
        conn.is_timed_out(),
        path,
    );
    if let Ok(mut guard) = last_stats.lock() {
        *guard = Some(message);
    }
}
