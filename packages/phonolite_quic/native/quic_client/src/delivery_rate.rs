use std::time::{Duration, Instant};

/// Audio payload goodput during demanded range delivery, excluding local or
/// reported read-ahead backpressure. Idle time between ranges is not a sample.
#[derive(Default)]
pub(super) struct DeliveryRate {
    range: Option<Range>,
    recent: Option<(u64, Instant)>,
    suspended: bool,
}

struct Range {
    started: Instant,
    bytes: u64,
    paused_at: Option<Instant>,
    paused_for: Duration,
}

impl DeliveryRate {
    pub fn begin(&mut self, now: Instant) {
        self.range = Some(Range {
            started: now,
            bytes: 0,
            paused_at: self.suspended.then_some(now),
            paused_for: Duration::ZERO,
        });
    }

    pub fn suspend(&mut self, suspended: bool, now: Instant) {
        self.suspended = suspended;
        if let Some(range) = self.range.as_mut() {
            if suspended {
                range.paused_at.get_or_insert(now);
            } else if let Some(paused_at) = range.paused_at.take() {
                range.paused_for += now.saturating_duration_since(paused_at);
            }
        }
    }

    pub fn received(&mut self, bytes: usize, now: Instant) {
        if self.suspended {
            return;
        }
        if let Some(range) = self.range.as_mut() {
            range.bytes = range.bytes.saturating_add(bytes as u64);
            if range.bytes >= 4096 {
                // The raw range's EOS can reach the app before QUIC FIN. Keep
                // delivered capacity evidence even if the next range retires it.
                self.recent = Some((range.bitrate(now), now));
            }
        }
    }

    pub fn end_range(&mut self) {
        // FIN and deliberate retirement stop demand timing. Only received
        // payload establishes or refreshes capacity; a delayed FIN cannot.
        self.range = None;
    }

    pub fn estimate(&self, now: Instant) -> Option<u64> {
        if let Some(range) = self.range.as_ref().filter(|_| !self.suspended) {
            if range.elapsed(now) >= Duration::from_secs(1) {
                // Include demanded silence so a stopped transfer cannot keep
                // advertising the previous range's fast rate.
                return Some(range.bitrate(now));
            }
        }
        self.recent
            .filter(|(_, at)| now.saturating_duration_since(*at) < Duration::from_secs(10))
            .map(|(rate, _)| rate)
    }

    pub fn diagnostic(&self, now: Instant) -> String {
        format!(
            "delivery_bps={:?} delivery_sample_age_ms={:?} delivery_suspended={} range_bytes={:?} range_demand_ms={:?}",
            self.estimate(now),
            self.recent.map(|(_, at)| now.saturating_duration_since(at).as_millis()),
            self.suspended,
            self.range.as_ref().map(|range| range.bytes),
            self.range.as_ref().map(|range| range.elapsed(now).as_millis()),
        )
    }
}

impl Range {
    fn elapsed(&self, now: Instant) -> Duration {
        self.paused_at
            .unwrap_or(now)
            .saturating_duration_since(self.started)
            .saturating_sub(self.paused_for)
    }

    fn bitrate(&self, now: Instant) -> u64 {
        // A short cached burst is useful evidence, but cannot imply infinite
        // bandwidth just because header and body arrived in the same poll.
        let elapsed_ms = self.elapsed(now).as_millis().max(100);
        (u128::from(self.bytes) * 8000 / elapsed_ms).min(u128::from(u64::MAX)) as u64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diagnostic_keeps_unknown_stalled_and_suspended_delivery_distinct() {
        let now = Instant::now();
        let mut rate = DeliveryRate::default();
        assert!(rate.diagnostic(now).contains("delivery_bps=None"));
        rate.begin(now);
        let stalled = rate.diagnostic(now + Duration::from_secs(2));
        assert!(stalled.contains("delivery_bps=Some(0)"));
        assert!(stalled.contains("range_demand_ms=Some(2000)"));
        rate.suspend(true, now + Duration::from_secs(2));
        let paused = rate.diagnostic(now + Duration::from_secs(20));
        assert!(paused.contains("delivery_bps=None"));
        assert!(paused.contains("delivery_suspended=true"));
        assert!(paused.contains("range_demand_ms=Some(2000)"));
    }

    #[test]
    fn reports_payload_bits_per_second_and_expires_idle_samples() {
        let now = Instant::now();
        let mut rate = DeliveryRate::default();
        rate.begin(now);
        rate.received(12_000, now + Duration::from_secs(2));
        assert_eq!(rate.estimate(now + Duration::from_secs(2)), Some(48_000));
        rate.end_range();
        assert_eq!(rate.estimate(now + Duration::from_secs(11)), Some(48_000));
        assert_eq!(rate.estimate(now + Duration::from_secs(12)), None);
    }

    #[test]
    fn receiver_backpressure_and_pauses_do_not_measure_as_slow_network() {
        let now = Instant::now();
        let mut rate = DeliveryRate::default();
        rate.begin(now);
        rate.received(12_000, now + Duration::from_secs(1));
        rate.suspend(true, now + Duration::from_secs(1));
        assert_eq!(rate.estimate(now + Duration::from_secs(20)), None);
        rate.suspend(false, now + Duration::from_secs(20));
        rate.received(12_000, now + Duration::from_secs(21));
        rate.end_range();
        assert_eq!(rate.estimate(now + Duration::from_secs(21)), Some(96_000));
    }

    #[test]
    fn new_stalled_range_overrides_old_fast_burst_and_cancel_does_not_publish_it() {
        let now = Instant::now();
        let mut rate = DeliveryRate::default();
        rate.begin(now);
        rate.received(60_000, now + Duration::from_millis(1));
        rate.end_range();
        assert_eq!(
            rate.estimate(now + Duration::from_millis(1)),
            Some(4_800_000)
        );
        rate.begin(now + Duration::from_secs(1));
        assert_eq!(rate.estimate(now + Duration::from_secs(2)), Some(0));
        rate.end_range();
        assert_eq!(rate.estimate(now + Duration::from_secs(2)), Some(4_800_000));
    }

    #[test]
    fn paused_range_and_tiny_tail_cannot_publish_a_new_fast_sample() {
        let now = Instant::now();
        let mut rate = DeliveryRate::default();
        rate.suspend(true, now);
        rate.begin(now);
        rate.received(12_000, now + Duration::from_secs(1));
        rate.end_range();
        rate.suspend(false, now + Duration::from_secs(2));
        assert_eq!(rate.estimate(now + Duration::from_secs(2)), None);
        rate.begin(now + Duration::from_secs(2));
        rate.received(50, now + Duration::from_secs(3));
        rate.end_range();
        assert_eq!(rate.estimate(now + Duration::from_secs(3)), None);
    }

    #[test]
    fn next_range_before_fin_keeps_measured_capacity_without_counting_inter_range_idle() {
        let now = Instant::now();
        let mut rate = DeliveryRate::default();
        rate.begin(now);
        rate.received(12_000, now + Duration::from_secs(1));
        rate.end_range();
        assert_eq!(rate.estimate(now + Duration::from_secs(8)), Some(96_000));
        assert_eq!(rate.estimate(now + Duration::from_secs(11)), None);
    }
}
