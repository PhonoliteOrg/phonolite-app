use std::cell::Cell;
use std::ffi::c_void;
use std::io::{self, Read, Seek, SeekFrom};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::{Duration, Instant};

use symphonia::core::io::MediaSource;

use crate::set_failure_code;

const CACHE_BYTES: usize = 256 * 1024;
const INITIAL_CACHE_BYTES: usize = 16 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
const OPEN_TIMEOUT: Duration = Duration::from_secs(15);

thread_local! {
    static OPERATION_DEADLINE: Cell<Option<Instant>> = const { Cell::new(None) };
}

/// A complete decoder read/seek shares one budget across all short source fills.
pub(crate) struct OperationGuard(Option<Instant>);

impl OperationGuard {
    pub fn enter() -> Self {
        Self::with_timeout(REQUEST_TIMEOUT)
    }

    pub(crate) fn with_timeout(timeout: Duration) -> Self {
        let deadline = Instant::now() + timeout;
        Self(
            OPERATION_DEADLINE.replace(Some(
                OPERATION_DEADLINE
                    .get()
                    .map_or(deadline, |old| old.min(deadline)),
            )),
        )
    }
}

impl Drop for OperationGuard {
    fn drop(&mut self) {
        OPERATION_DEADLINE.set(self.0);
    }
}

pub(crate) fn check_operation() -> Result<(), String> {
    if OPERATION_DEADLINE
        .get()
        .is_some_and(|deadline| Instant::now() >= deadline)
    {
        set_failure_code(-103);
        Err("Audio decoder operation timed out".into())
    } else {
        Ok(())
    }
}

pub type ReadRange = unsafe extern "C" fn(*mut c_void, u64, *mut u8, usize, u32, *mut u64) -> i64;
pub type ErrorCode = unsafe extern "C" fn(*mut c_void) -> i32;
pub type CopyError = unsafe extern "C" fn(*mut c_void, *mut u8, usize) -> usize;
pub type Close = unsafe extern "C" fn(*mut c_void);

struct SourceOwner {
    handle: *mut c_void,
    close: Option<Close>,
}

impl Drop for SourceOwner {
    fn drop(&mut self) {
        if let Some(close) = self.close {
            if !self.handle.is_null() {
                unsafe { close(self.handle) };
            }
        }
    }
}

/// A seekable source-file window delivered by the existing QUIC library.
/// Native callbacks avoid linking another copy of QUIC/TLS into the decoder.
pub(crate) struct QuicSource {
    owner: SourceOwner,
    read_range: ReadRange,
    error_code: ErrorCode,
    copy_error: CopyError,
    size: Option<u64>,
    position: u64,
    cache_start: u64,
    cache: Vec<u8>,
    opening: Arc<AtomicBool>,
    opened_at: Instant,
}

// MediaSource requires Send + Sync. The decoder owns this handle exclusively;
// all operations that invoke its callbacks require an exclusive source borrow.
unsafe impl Send for QuicSource {}
unsafe impl Sync for QuicSource {}

impl QuicSource {
    /// Consumes a live source handle even when validation or opening fails.
    /// Callbacks must belong to a loaded native library for this source's life.
    pub(crate) unsafe fn open(
        handle: *mut c_void,
        read_range: Option<ReadRange>,
        error_code: Option<ErrorCode>,
        copy_error: Option<CopyError>,
        close: Option<Close>,
        opening: Arc<AtomicBool>,
    ) -> Result<Self, String> {
        let owner = SourceOwner { handle, close };
        let invalid = || {
            set_failure_code(-100);
            "invalid native QUIC source descriptor".to_owned()
        };
        if handle.is_null() || close.is_none() {
            return Err(invalid());
        }
        let mut source = Self {
            owner,
            read_range: read_range.ok_or_else(invalid)?,
            error_code: error_code.ok_or_else(invalid)?,
            copy_error: copy_error.ok_or_else(invalid)?,
            size: None,
            position: 0,
            cache_start: 0,
            cache: Vec::new(),
            opening,
            opened_at: Instant::now(),
        };
        source
            .fetch_window(INITIAL_CACHE_BYTES)
            .map_err(|error| error.to_string())?;
        Ok(source)
    }

    fn fetch_window(&mut self, capacity: usize) -> io::Result<()> {
        let now = Instant::now();
        let deadline = if self.opening.load(Ordering::Acquire) {
            (now + REQUEST_TIMEOUT).min(self.opened_at + OPEN_TIMEOUT)
        } else {
            now + REQUEST_TIMEOUT
        };
        let deadline = OPERATION_DEADLINE
            .get()
            .map_or(deadline, |operation| deadline.min(operation));
        let remaining = deadline.saturating_duration_since(now);
        if remaining.is_zero() {
            set_failure_code(-103);
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "Original QUIC source request timed out",
            ));
        }
        let mut bytes = vec![0; capacity];
        let mut total = 0;
        let count = unsafe {
            (self.read_range)(
                self.owner.handle,
                self.position,
                bytes.as_mut_ptr(),
                bytes.len(),
                remaining.as_millis().max(1) as u32,
                &mut total,
            )
        };
        if count < 0 {
            let code = unsafe { (self.error_code)(self.owner.handle) };
            // The transport's -102 means a transient timeout/disconnect. The
            // decoder reserves -102 for an invalid source, so translate it.
            set_failure_code(match code {
                -100 => -100,
                -101 => -102,
                400..=599 => code,
                _ => -103,
            });
            let mut error = [0; 1024];
            let copied =
                unsafe { (self.copy_error)(self.owner.handle, error.as_mut_ptr(), error.len()) }
                    .min(error.len());
            let message = if copied == 0 {
                "Original QUIC source request failed".to_owned()
            } else {
                String::from_utf8_lossy(&error[..copied]).into_owned()
            };
            return Err(io::Error::other(message));
        }
        let expected = total.saturating_sub(self.position).min(capacity as u64);
        if self.size.is_some_and(|size| size != total)
            || (count == 0 && expected != 0)
            || count as u64 > expected
            || count as usize > bytes.len()
        {
            set_failure_code(-102);
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Original QUIC source returned an inconsistent byte range",
            ));
        }
        bytes.truncate(count as usize);
        self.size = Some(total);
        self.cache_start = self.position;
        self.cache = bytes;
        set_failure_code(0);
        Ok(())
    }
}

impl Read for QuicSource {
    fn read(&mut self, output: &mut [u8]) -> io::Result<usize> {
        if output.is_empty() || self.size.is_some_and(|size| self.position >= size) {
            return Ok(0);
        }
        if self.position < self.cache_start
            || self.position >= self.cache_start + self.cache.len() as u64
        {
            self.fetch_window(output.len().clamp(INITIAL_CACHE_BYTES, CACHE_BYTES))?;
        }
        let offset = (self.position - self.cache_start) as usize;
        let count = output.len().min(self.cache.len() - offset);
        output[..count].copy_from_slice(&self.cache[offset..offset + count]);
        self.position += count as u64;
        Ok(count)
    }
}

impl Seek for QuicSource {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.position = match position {
            SeekFrom::Start(position) => position,
            SeekFrom::Current(offset) => checked_offset(self.position, offset)?,
            SeekFrom::End(offset) => checked_offset(self.size.unwrap_or(0), offset)?,
        };
        Ok(self.position)
    }
}

impl MediaSource for QuicSource {
    fn is_seekable(&self) -> bool {
        true
    }

    fn byte_len(&self) -> Option<u64> {
        self.size
    }
}

fn checked_offset(position: u64, offset: i64) -> io::Result<u64> {
    position
        .checked_add_signed(offset)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "invalid source seek offset"))
}
