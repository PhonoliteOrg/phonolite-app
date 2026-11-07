//! Cancellation lives independently of decoder/source pointers. Numeric owner
//! IDs are never reused, so a late parent message cannot address a new source.
use std::collections::HashMap;
use std::ffi::c_void;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

const LEASE_TIMEOUT: Duration = Duration::from_secs(10);
pub(crate) const RECOVERY_TIMEOUT: Duration = Duration::from_secs(30);
const RECOVERY_ATTEMPTS: u32 = 3;

#[derive(Clone)]
pub(crate) struct SourceMetadata {
    pub source_version: String,
    pub total_length: u64,
}

struct RecoveryEpisode {
    deadline: Instant,
    remaining_attempts: u32,
    attempts: u32,
}

pub(crate) struct OwnerLease {
    pub cancelled: Arc<AtomicBool>,
    heartbeat: Mutex<Instant>,
    operation_epoch: AtomicU64,
    active_epoch: AtomicU64,
    route_generation: AtomicU64,
    recovery: Mutex<Option<RecoveryEpisode>>,
    source_metadata: Mutex<Option<SourceMetadata>>,
    playable_ms: AtomicU64,
    rtt_ms: AtomicU64,
    pub received_bytes: AtomicU64,
    migration_enabled: AtomicBool,
}

impl OwnerLease {
    pub fn new() -> Self {
        Self {
            cancelled: Arc::new(AtomicBool::new(false)),
            heartbeat: Mutex::new(Instant::now()),
            operation_epoch: AtomicU64::new(0),
            active_epoch: AtomicU64::new(0),
            route_generation: AtomicU64::new(0),
            recovery: Mutex::new(None),
            source_metadata: Mutex::new(None),
            playable_ms: AtomicU64::new(8000),
            rtt_ms: AtomicU64::new(0),
            received_bytes: AtomicU64::new(0),
            migration_enabled: AtomicBool::new(false),
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

    pub fn route_generation(&self) -> u64 {
        self.route_generation.load(Ordering::Acquire)
    }

    pub fn stall_timeout(&self) -> Duration {
        let minimum = if self.playable_ms.load(Ordering::Acquire) <= 4000 { 5000 } else { 8000 };
        Duration::from_millis(self.rtt_ms.load(Ordering::Acquire).saturating_mul(6).clamp(minimum, 12000))
    }

    pub fn observe_transport(&self, rtt_ms: u64, received: u64) {
        self.rtt_ms.store(rtt_ms, Ordering::Release);
        self.received_bytes.fetch_add(received, Ordering::AcqRel);
    }

    pub fn migration_enabled(&self) -> bool {
        self.migration_enabled.load(Ordering::Acquire)
    }

    pub fn note_route(&self, generation: u64) {
        self.route_generation.fetch_max(generation, Ordering::AcqRel);
    }

    pub fn begin_recovery(&self, remaining: Duration, attempts_remaining: u32) {
        let Ok(mut recovery) = self.recovery.lock() else { return };
        let deadline = Instant::now() + remaining.min(RECOVERY_TIMEOUT);
        match recovery.as_mut() {
            Some(active) => {
                active.deadline = active.deadline.min(deadline);
                active.remaining_attempts = active.remaining_attempts.min(attempts_remaining);
            }
            None => *recovery = Some(RecoveryEpisode {
                deadline,
                remaining_attempts: attempts_remaining.min(RECOVERY_ATTEMPTS),
                attempts: RECOVERY_ATTEMPTS.saturating_sub(attempts_remaining.min(RECOVERY_ATTEMPTS)),
            }),
        }
    }

    pub fn reserve_connection(&self) -> Result<(), String> {
        let mut recovery = self.recovery.lock().map_err(|_| "QUIC recovery state unavailable")?;
        if let Some(active) = recovery.as_mut() {
            if Instant::now() >= active.deadline || active.remaining_attempts == 0 {
                return Err("Original connection recovery budget exhausted".into());
            }
            active.remaining_attempts -= 1;
            active.attempts += 1;
        }
        Ok(())
    }

    pub fn recovery_remaining(&self) -> Option<Duration> {
        self.recovery.lock().ok()?.as_ref()
            .map(|active| active.deadline.saturating_duration_since(Instant::now()))
    }

    pub fn recovery_attempts(&self) -> u32 {
        self.recovery.lock().ok().and_then(|active| active.as_ref().map(|active| active.attempts)).unwrap_or(0)
    }

    pub fn source_metadata(&self) -> Option<SourceMetadata> {
        self.source_metadata.lock().ok()?.clone()
    }

    pub fn accept_source(&self, metadata: SourceMetadata) -> Result<(), String> {
        let mut accepted = self.source_metadata.lock().map_err(|_| "QUIC source metadata unavailable")?;
        if accepted.as_ref().is_some_and(|old| old.source_version != metadata.source_version || old.total_length != metadata.total_length) {
            return Err("QUIC source representation or length changed".into());
        }
        *accepted = Some(metadata);
        Ok(())
    }
}

fn registry() -> &'static Mutex<HashMap<u64, Arc<OwnerLease>>> {
    static OWNERS: OnceLock<Mutex<HashMap<u64, Arc<OwnerLease>>>> = OnceLock::new();
    OWNERS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) fn get(id: u64) -> Option<Arc<OwnerLease>> {
    registry().lock().ok()?.get(&id).cloned()
}

fn next_owner_id(next: &AtomicU64) -> Option<u64> {
    let mut id = next.load(Ordering::Relaxed);
    while id <= isize::MAX as u64 {
        match next.compare_exchange_weak(id, id + 1, Ordering::Relaxed, Ordering::Relaxed) {
            Ok(_) => return Some(id),
            Err(current) => id = current,
        }
    }
    None
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_create() -> u64 {
    static NEXT_ID: AtomicU64 = AtomicU64::new(1);
    let Some(id) = next_owner_id(&NEXT_ID) else { return 0 };
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

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_route_changed(id: u64, generation: u64) {
    if let Some(owner) = get(id).filter(|owner| owner.alive(true)) { owner.note_route(generation); }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_playable_ms(id: u64, playable_ms: u64) {
    if let Some(owner) = get(id) { owner.playable_ms.store(playable_ms, Ordering::Release); }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_rtt_ms(id: u64) -> u64 {
    get(id).map_or(0, |owner| owner.rtt_ms.load(Ordering::Acquire))
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_received_bytes(id: u64) -> u64 {
    get(id).map_or(0, |owner| owner.received_bytes.load(Ordering::Acquire))
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_set_migration_enabled(id: u64, enabled: i32) {
    if let Some(owner) = get(id) { owner.migration_enabled.store(enabled != 0, Ordering::Release); }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_recovery_begin(id: u64, remaining_ms: u32, attempts_remaining: u32) {
    if let Some(owner) = get(id).filter(|owner| owner.alive(true)) {
        owner.begin_recovery(Duration::from_millis(remaining_ms as u64), attempts_remaining);
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_recovery_remaining_ms(id: u64) -> u32 {
    get(id).and_then(|owner| owner.recovery_remaining()).map_or(0, |remaining| remaining.as_millis().min(u32::MAX as u128) as u32)
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_recovery_attempts(id: u64) -> u32 {
    get(id).map_or(0, |owner| owner.recovery_attempts())
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_recovery_finish(id: u64) {
    if let Some(owner) = get(id) {
        if let Ok(mut recovery) = owner.recovery.lock() { *recovery = None; }
    }
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_copy_source_metadata(id: u64, output: *mut u8, capacity: usize) -> usize {
    let Some(metadata) = get(id).and_then(|owner| owner.source_metadata()) else { return 0 };
    let encoded = serde_json::json!({"source_version": metadata.source_version, "total_length": metadata.total_length}).to_string();
    if !output.is_null() && capacity >= encoded.len() {
        unsafe { std::ptr::copy_nonoverlapping(encoded.as_ptr(), output, encoded.len()); }
    }
    encoded.len()
}

#[no_mangle]
pub extern "C" fn phonolite_quic_owner_expect_source(id: u64, source_version: *const c_char, total_length: u64) -> i32 {
    let Some(owner) = get(id).filter(|owner| owner.alive(true)) else { return 0 };
    let version = unsafe { super::cstr_to_string(source_version) };
    if version.is_empty() || version.len() > 256 { return 0; }
    i32::from(owner.accept_source(SourceMetadata { source_version: version, total_length }).is_ok())
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
    fn owner_ids_stop_at_the_pointer_limit_without_wrapping() {
        let next = AtomicU64::new(isize::MAX as u64);
        assert_eq!(next_owner_id(&next), Some(isize::MAX as u64));
        assert_eq!(next_owner_id(&next), None);
        assert_eq!(next.load(Ordering::Relaxed), isize::MAX as u64 + 1);
    }

    #[test]
    fn concurrent_owner_ids_are_unique() {
        let next = Arc::new(AtomicU64::new(1));
        let workers: Vec<_> = (0..4).map(|_| {
            let next = Arc::clone(&next);
            std::thread::spawn(move || {
                (0..256).map(|_| next_owner_id(&next).unwrap()).collect::<Vec<_>>()
            })
        }).collect();
        let ids: std::collections::BTreeSet<_> = workers.into_iter()
            .flat_map(|worker| worker.join().unwrap()).collect();
        assert_eq!(ids.len(), 1024);
        assert_eq!(ids.first(), Some(&1));
        assert_eq!(ids.last(), Some(&1024));
    }

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

    #[test]
    fn route_hints_do_not_cancel_an_operation_or_spend_a_paused_recovery_budget() {
        let owner = OwnerLease::new();
        owner.note_route(2);
        owner.note_route(1);
        assert_eq!(owner.route_generation(), 2);
        assert!(owner.operation_is_current());
        assert!(owner.alive(false));
        assert!(owner.recovery_remaining().is_none());
    }

    #[test]
    fn recovery_deadline_and_cumulative_attempts_cannot_be_renewed_by_nested_retries() {
        let owner = OwnerLease::new();
        owner.begin_recovery(Duration::from_secs(4), 3);
        owner.reserve_connection().unwrap();
        let deadline = owner.recovery.lock().unwrap().as_ref().unwrap().deadline;
        owner.begin_recovery(Duration::from_secs(15), 3);
        assert_eq!(owner.recovery.lock().unwrap().as_ref().unwrap().deadline, deadline);
        assert_eq!(owner.recovery_attempts(), 1);
        let replacement = OwnerLease::new();
        replacement.begin_recovery(owner.recovery_remaining().unwrap(), 2);
        replacement.reserve_connection().unwrap();
        replacement.reserve_connection().unwrap();
        assert_eq!(replacement.recovery_attempts(), 3);
        assert!(replacement.reserve_connection().is_err());
        replacement.begin_recovery(Duration::ZERO, 3);
        assert!(replacement.recovery_remaining().unwrap().is_zero());
    }

    #[test]
    fn expected_source_metadata_is_pinned_before_replacement_bytes() {
        let owner = OwnerLease::new();
        owner.accept_source(SourceMetadata { source_version: "version".into(), total_length: 123 }).unwrap();
        assert!(owner.accept_source(SourceMetadata { source_version: "changed".into(), total_length: 123 }).is_err());
        assert!(owner.accept_source(SourceMetadata { source_version: "version".into(), total_length: 124 }).is_err());
        assert_eq!(owner.source_metadata().unwrap().total_length, 123);
    }
    #[test]
    fn stall_detection_allows_loss_recovery_and_accounts_for_path_latency() {
        let owner = OwnerLease::new();
        owner.playable_ms.store(800, Ordering::Release);
        assert_eq!(owner.stall_timeout(), Duration::from_secs(5));
        owner.observe_transport(1500, 123);
        assert_eq!(owner.stall_timeout(), Duration::from_secs(9));
        owner.observe_transport(10000, 321);
        assert_eq!(owner.stall_timeout(), Duration::from_secs(12));
        assert_eq!(owner.received_bytes.load(Ordering::Acquire), 444);
        assert_eq!(owner.recovery_attempts(), 0);
    }

}
