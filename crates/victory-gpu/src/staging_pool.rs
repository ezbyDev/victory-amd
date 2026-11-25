//! Upload buffers of texture staging that no texture and no list holds any
//! more, kept for the next texture that is staged.
//!
//! Nearly every texture upload made an upload buffer of its own: 25,873
//! upload buffers (11.7 GB) were made over a run whose heap pass uploaded
//! 26,094 textures (11.7 GB), each a committed resource made, mapped,
//! faulted in page by page and freed again. A frame of the world took
//! 152,579 page faults and 703 ms of kernel time. A staging buffer is let go
//! only when the last `Arc<Staging>` goes, which is after every list that
//! named it was reset (after the card ran it), so its buffer may be handed
//! to the next texture as it is.
//!
//! `VICTORY_STAGING_POOL=1` turns this on (off by default: a buffer per
//! texture, as before). `VICTORY_STAGING_POOL_MB` caps the bytes kept
//! (1024 by default); past it the buffers given back longest ago are freed.
//! Host lists' own upload buffers (`HostList::upload`, scratch too big for
//! a chunk) share the pool with `VICTORY_UPLOAD_RING=1`: they are held until
//! the list is reset after its last submission ran, as staging is.

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, Ordering::Relaxed};
use std::sync::{Mutex, OnceLock};

/// Whether let-go staging buffers are kept for the next texture.
pub(crate) fn on() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("VICTORY_STAGING_POOL").is_some_and(|v| v == "1"))
}

/// The most bytes kept (`VICTORY_STAGING_POOL_MB`, 1024 MiB by default).
fn most() -> u64 {
    static MOST: OnceLock<u64> = OnceLock::new();
    *MOST.get_or_init(|| {
        std::env::var("VICTORY_STAGING_POOL_MB")
            .ok()
            .and_then(|v| v.trim().parse::<u64>().ok())
            .unwrap_or(1024)
            << 20
    })
}

/// The size a staging buffer of `size` bytes is made at, so that buffers
/// of nearby sizes can stand in for each other: under 1 MiB a multiple of
/// 64 KiB (the upload heap's own granule, so nothing is lost), above it the
/// next eighth of a power of two (at most 12.5 % more than asked).
pub(crate) fn class(size: u64) -> u64 {
    const GRANULE: u64 = 64 << 10;
    let size = size.max(1);
    if size <= 1 << 20 {
        return size.div_ceil(GRANULE) * GRANULE;
    }
    let step = (1u64 << (63 - size.leading_zeros())) / 8;
    size.div_ceil(step) * step
}

/// Things kept by their capacity, taken best fit and let go oldest first.
pub(crate) struct Pool<T> {
    /// By (capacity, when given back).
    kept: BTreeMap<(u64, u64), T>,
    /// Capacity by when given back, for letting go the oldest.
    ages: BTreeMap<u64, u64>,
    bytes: u64,
    next: u64,
}

impl<T> Pool<T> {
    pub(crate) const fn new() -> Self {
        Pool {
            kept: BTreeMap::new(),
            ages: BTreeMap::new(),
            bytes: 0,
            next: 0,
        }
    }

    /// The smallest thing kept that holds `size` bytes and is at most half
    /// as big again as `size`'s class (a bigger one would hold memory the
    /// texture does not use for as long as it lives), and its capacity.
    pub(crate) fn take(&mut self, size: u64) -> Option<(T, u64)> {
        let want = class(size);
        let key = *self
            .kept
            .range((want, 0)..=(want + want / 2, u64::MAX))
            .next()?
            .0;
        let thing = self.kept.remove(&key)?;
        self.ages.remove(&key.1);
        self.bytes -= key.0;
        Some((thing, key.0))
    }

    /// Keeps `thing` (`capacity` bytes); returns what goes to stay within
    /// `most` bytes: the oldest kept first, `thing` itself if it alone is
    /// more than `most`.
    pub(crate) fn give(&mut self, thing: T, capacity: u64, most: u64) -> Vec<T> {
        if capacity > most {
            return vec![thing];
        }
        let at = self.next;
        self.next += 1;
        self.kept.insert((capacity, at), thing);
        self.ages.insert(at, capacity);
        self.bytes += capacity;
        let mut gone = Vec::new();
        while self.bytes > most {
            let Some((at, capacity)) = self.ages.pop_first() else {
                break;
            };
            if let Some(old) = self.kept.remove(&(capacity, at)) {
                gone.push(old);
            }
            self.bytes -= capacity;
        }
        gone
    }

    #[cfg_attr(not(any(test, feature = "diagnostics")), allow(dead_code))]
    pub(crate) fn len(&self) -> usize {
        self.kept.len()
    }

    #[cfg_attr(not(any(test, feature = "diagnostics")), allow(dead_code))]
    pub(crate) fn bytes(&self) -> u64 {
        self.bytes
    }
}

/// A kept upload buffer and where it is mapped.
pub(crate) struct Kept {
    pub(crate) buffer: windows::Win32::Graphics::Direct3D12::ID3D12Resource,
    pub(crate) data: usize,
}

static POOL: Mutex<Pool<Kept>> = Mutex::new(Pool::new());

/// Buffers taken from the pool, and staging buffers it had none for, since
/// the start; buffers freed past the cap.
static COUNTS: [AtomicU64; 3] = [const { AtomicU64::new(0) }; 3];

/// A kept upload buffer for `size` bytes and its capacity, if the pool is
/// on and has one.
pub(crate) fn take(size: u64) -> Option<(Kept, u64)> {
    if !on() {
        return None;
    }
    take_any(size)
}

/// A kept upload buffer for `size` bytes and its capacity, whichever user
/// turned the pool on (list uploads: `crate::host::upload_ring`).
pub(crate) fn take_any(size: u64) -> Option<(Kept, u64)> {
    let taken = POOL.lock().unwrap_or_else(|e| e.into_inner()).take(size);
    COUNTS[usize::from(taken.is_none())].fetch_add(1, Relaxed);
    taken
}

/// A staging buffer of `capacity` bytes that nothing uses any more: kept,
/// or freed past the cap.
pub(crate) fn give(kept: Kept, capacity: u64) {
    let gone = POOL
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .give(kept, capacity, most());
    COUNTS[2].fetch_add(gone.len() as u64, Relaxed);
    // Freed outside the lock.
    drop(gone);
}

/// For the memory line: buffers kept, their bytes, taken, missed, freed past
/// the cap.
#[cfg(feature = "diagnostics")]
pub(crate) fn memory() -> [u64; 5] {
    let (len, bytes) = {
        let pool = POOL.lock().unwrap_or_else(|e| e.into_inner());
        (pool.len() as u64, pool.bytes())
    };
    [len, bytes, COUNTS[0].load(Relaxed), COUNTS[1].load(Relaxed), COUNTS[2].load(Relaxed)]
}

#[cfg(test)]
mod tests {
    use super::{Pool, class};

    const K: u64 = 1 << 10;
    const M: u64 = 1 << 20;

    #[test]
    fn classes_round_to_64_kib_then_eighths() {
        assert_eq!(class(0), 64 * K);
        assert_eq!(class(1), 64 * K);
        assert_eq!(class(64 * K), 64 * K);
        assert_eq!(class(64 * K + 1), 128 * K);
        assert_eq!(class(M), M);
        assert_eq!(class(M + 1), M + 128 * K);
        assert_eq!(class(5 * M), 5 * M);
        assert_eq!(class(5 * M + 1), 5 * M + 512 * K);
        assert_eq!(class(16 * M - 1), 16 * M);
        for size in [3 * K, 700 * K, 3 * M + 7, 100 * M + 3] {
            let c = class(size);
            assert!(c >= size && c <= size + size / 8 + 64 * K, "{size} -> {c}");
            assert_eq!(class(c), c, "a class is its own class");
        }
    }

    #[test]
    fn takes_the_smallest_that_fits_within_half_again() {
        let mut pool = Pool::new();
        for (i, c) in [4 * M, 2 * M, 3 * M, 128 * K].into_iter().enumerate() {
            assert!(pool.give(i, c, u64::MAX).is_empty());
        }
        assert_eq!(pool.take(2 * M + 1), Some((2, 3 * M)), "2 MiB is too small");
        assert_eq!(pool.take(2 * M), Some((1, 2 * M)));
        // 4 MiB is more than 1.5 times 2 MiB's class.
        assert_eq!(pool.take(2 * M), None);
        assert_eq!(pool.take(4 * M), Some((0, 4 * M)));
        assert_eq!(pool.take(100 * K), Some((3, 128 * K)));
        assert_eq!(pool.len(), 0);
        assert_eq!(pool.bytes(), 0);
    }

    #[test]
    fn past_the_cap_the_oldest_go() {
        let mut pool = Pool::new();
        assert!(pool.give('a', 4 * M, 10 * M).is_empty());
        assert!(pool.give('b', 4 * M, 10 * M).is_empty());
        assert_eq!(pool.give('c', 4 * M, 10 * M), vec!['a']);
        assert_eq!(pool.bytes(), 8 * M);
        assert_eq!(pool.give('d', 11 * M, 10 * M), vec!['d'], "bigger than the cap");
        assert_eq!(pool.give('e', 8 * M, 10 * M), vec!['b', 'c']);
        assert_eq!(pool.len(), 1);
        assert_eq!(pool.take(8 * M), Some(('e', 8 * M)));
    }
}
