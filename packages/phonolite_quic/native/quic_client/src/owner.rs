//! Cancellation lives independently of decoder/source pointers. Numeric owner
//! IDs are never reused, so a late parent message cannot address a new source.
use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

const LEASE_TIMEOUT: Duration = Duration::from_secs(10);

pub(crate) struct OwnerLease {
    pub cancelled: Arc<AtomicBool>,
    heartbeat: Mutex<Instant>,
    operation_epoch: AtomicU64,
    active_epoch: AtomicU64,
}

impl OwnerLease {
    pub fn new() -> Self {
        Self {
            cancelled: Arc::new(AtomicBool::new(false)),
            heartbeat: Mutex::new(Instant::now()),
            operation_epoch: AtomicU64::new(0),
            active_epoch: AtomicU64::new(0),
        }
    }

    pub fn touch(&self) -> bool {
        if !self.alive(true) {
            return false;
        }
        if let Ok(mut heartbeat) = self.heartbeat.lock() {
            *heartbeat = Instant::now();
        }
        !self.cancelled.load(Ordering::Acquire)
    }

    pub fn alive(&self, enforce_lease: bool) -> bool {
        if enforce_lease
            && self
                .heartbeat
                .lock()
                .map_or(true, |last| last.elapsed() >= LEASE_TIMEOUT)
        {
            self.cancelled.store(true, Ordering::Release);
        }
        !self.cancelled.load(Ordering::Acquire)
    }

    pub fn operation_is_current(&self) -> bool {
        self.operation_epoch.load(Ordering::Acquire) == self.active_epoch.load(Ordering::Acquire)
    }
}

fn registry() -> &'static Mutex<HashMap<u64, Arc<OwnerLease>>> {
    static OWNERS: OnceLock<Mutex<HashMap<u64, Arc<OwnerLease>>>> = OnceLock::new();
    OWNERS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) fn get(id: u64) -> Option<Arc<OwnerLease>> {
    registry().lock().ok()?.get(&id).cloned()
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_create() -> u64 {
    static NEXT_ID: AtomicU64 = AtomicU64::new(1);
    let Ok(id) = NEXT_ID.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |id| {
        (id <= isize::MAX as u64).then(|| id + 1)
    }) else { return 0 };
    let Ok(mut owners) = registry().lock() else {
        return 0;
    };
    owners.insert(id, Arc::new(OwnerLease::new()));
    id
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_heartbeat(id: u64) {
    if let Some(owner) = get(id) {
        owner.touch();
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_cancel(id: u64) {
    if let Some(owner) = get(id) {
        owner.cancelled.store(true, Ordering::Release);
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_alive(id: u64) -> i32 {
    i32::from(get(id).is_some_and(|owner| owner.alive(true)))
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_interrupt(id: u64) -> u64 {
    get(id).map_or(u64::MAX, |owner| {
        owner.operation_epoch.fetch_add(1, Ordering::AcqRel) + 1
    })
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_begin_operation(id: u64, epoch: u64) -> i32 {
    let Some(owner) = get(id) else { return 0 };
    if !owner.alive(true) || owner.operation_epoch.load(Ordering::Acquire) != epoch {
        return 0;
    }
    owner.active_epoch.store(epoch, Ordering::Release);
    i32::from(owner.operation_is_current())
}

/// Pointer-shaped ID for NativeFinalizer; never dereferenced.
#[no_mangle]
pub extern "C" fn phonolite_quic_owner_release(id: *mut c_void) {
    let owner = registry()
        .lock()
        .ok()
        .and_then(|mut owners| owners.remove(&(id as usize as u64)));
    if let Some(owner) = owner {
        owner.cancelled.store(true, Ordering::Release);
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_release_finalizer(id: *mut c_void) {
    phonolite_quic_owner_release(id);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn releasing_an_owner_cancels_borrowers_without_reusing_or_dereferencing_its_id() {
        let id = phonolite_quic_owner_create();
        assert!(id <= isize::MAX as u64);
        let borrower = get(id).unwrap();
        let finalizer: extern "C" fn(*mut c_void) = phonolite_quic_owner_release_finalizer;
        finalizer(id as usize as *mut c_void);
        assert!(!borrower.alive(true));
        assert!(get(id).is_none());
        phonolite_quic_owner_release(id as usize as *mut c_void);
        let next = phonolite_quic_owner_create();
        assert_ne!(id, next);
        phonolite_quic_owner_cancel(id);
        assert!(get(next).unwrap().alive(true));
        phonolite_quic_owner_release(next as usize as *mut c_void);
    }

    #[test]
    fn expired_or_cancelled_leases_cannot_be_revived_by_late_heartbeats() {
        let owner = OwnerLease::new();
        *owner.heartbeat.lock().unwrap() = Instant::now() - LEASE_TIMEOUT;
        assert!(!owner.alive(true));
        assert!(!owner.touch());
        assert!(!owner.alive(true));
    }

    #[test]
    fn a_late_old_operation_cannot_clear_a_newer_seek_interruption() {
        let id = phonolite_quic_owner_create();
        let owner = get(id).unwrap();
        assert_eq!(phonolite_quic_owner_begin_operation(id, 0), 1);
        assert_eq!(phonolite_quic_owner_interrupt(id), 1);
        assert!(!owner.operation_is_current());
        assert_eq!(phonolite_quic_owner_begin_operation(id, 0), 0);
        assert!(!owner.operation_is_current());
        assert_eq!(phonolite_quic_owner_begin_operation(id, 1), 1);
        assert!(owner.operation_is_current());
        phonolite_quic_owner_release(id as usize as *mut c_void);
    }
}
