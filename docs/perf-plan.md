# Performance plan: from ~1 fps to 10 fps on an RX 9060 XT

Written 2026-11-25 from measured runs on Windows 11, RX 9060 XT 16 GB (RDNA 4), i7-9700K
(8 cores, 8 threads), 32 GB, `diag` profile with `diagnostics`. All numbers are per frame
and come from the frame lines of `victory-run.log` (see "Reading a run" at the end).

## 1. Where a frame goes today

Representative world frame after the remap-lock fix (`4bece45`): **1,232 ms, 0.8 fps,
1,400 draws**.

| What | ms / frame | Source line |
|---|---:|---|
| The card busy | ~160 (13 %) | `the card's clock per frame` |
| The card idle while **our submitting thread works** | 908 | same |
| Submitting thread inside submissions (CPU) | 206 (109 user + 97 kernel) | `thread N submitted` |
| Submitting thread waiting for the submission lock | 176 | same |
| Copying back what shaders wrote | 329 (61 MB) | frame line |
| Snapshots of ranges shaders may write | 373 (377 MB compared back) | `recording per frame` |
| Compares after submissions | 727 MB/frame for 25 MB written back | `compared after submissions` |
| Recording, all recording threads | 885 in 18,212 list calls (49 µs a call) | `recording per frame` |
| of it: notes (DRED markers, diagnostics) | 293 | same |
| Heap pass (buffer views + textures picked by index) | 417 (1.0–3.1 s in streaming) | `heap buffers N passes` |
| Texture refreshes | 61 | `texture refreshes per frame` |
| Process CPU, all threads | 869 user + 375 kernel | `frame account` |
| Process page faults | 79,317 | `copies per frame` |
| Upload buffers made since the start | 25,873 (11.7 GB) | `memory:` |
| Submissions | 30.6 | `copies per frame` |

**The one fact that matters:** the card is idle 83–95 % of every frame, and the process uses
about one core's worth of CPU (1,244 ms of CPU in a 1,232 ms frame on 8 cores). The time
is our own CPU work done one step after another. The title is almost never the one we wait
for ("the rest while the title had not submitted" is small).

10 fps is a 100 ms frame. The card's own work (~50–160 ms) already sits near that, so
10 fps needs **the CPU side to hide behind the card**, not merely shrink. Realistic
targets, by stage, for steady world frames (streaming bursts stay slower):

| After stage | Expected frame | fps |
|---|---:|---:|
| now | ~1,200 ms | 0.8 |
| 0 settings | ~800 ms | 1.2 |
| 1 staging pool | ~650 ms | 1.5 |
| 2 copy-back on the card / lazy | ~350 ms | 3 |
| 3 fewer submissions, overlap | ~200 ms | 5 |
| 4 recording cost | ~150 ms | 6–7 |
| 5 card work (shader opt back, RT off cleanly) | ~100 ms | 10 |

These are estimates from the measured shares. Each stage is judged by the log, not assumed.

## 2. How the history of emulators and PC engines solved the same costs

| Our cost | Same problem elsewhere | What fixed it there |
|---|---|---|
| One thread prepares, submits and copies back in series; card idle | Dolphin single core before dual core (2008), PCSX2 before MTGS, early RPCS3 | A producer/consumer split: one thread records, another submits, a frame in flight while the next is built (dual core, MTGS, RPCS3's async). D3D12 engines keep 2–3 frames in flight. |
| Comparing hundreds of MB after each submission to find what shaders wrote | Dolphin EFB copies to RAM, Xenia resolves, RPCS3 "write color buffers", Cemu readbacks | Do not read back unless the CPU reads it: protect the pages, fetch on the first CPU touch (Xenia's memory watches, RPCS3 page faults, Dolphin's "EFB copies to texture only"); where a readback is needed, compare on the GPU and fetch only the dirty tiles, one frame late. |
| A new upload buffer for every texture (11.7 GB, 79k page faults a frame) | Every D3D11-to-12 port; DXVK, VKD3D | Ring/linear upload allocators: a few big persistently mapped buffers, sub-allocated, recycled after the fence (DXVK's staging pool, VKD3D's upload rings, UE/Unity per-frame upload heaps). |
| 30 submissions a frame, each a sync point | Early Vulkan/D3D12 ports | Batch command lists into one `ExecuteCommandLists` per frame; use fences, not waits. |
| 49 µs per recorded command | DXVK's early state tracking, Dolphin's vertex loader before JIT | Cheap recording: no formatting or locks per command, dirty-state caching, work moved to submission or worker threads. |
| CPU detiling and hashing of textures | Xenia, yuzu/Ryujinx swizzle, Dolphin "GPU texture decoding" | Upload the tiled bytes as they are and detile in a compute shader; hash nothing, track writes. |
| Optimisation pass 4 off (`SHADER_OPT=11`) for AMD's compiler | Every emulator's shader-compiler workarounds | Fix the emitted pattern that crashes the driver, then turn the optimiser back on. |

## 3. Stages

Each stage lands behind an environment switch that defaults to the old behaviour, is
measured on a run, and becomes the default only once the log shows the gain and no device
loss. Previous work stays intact: every stage is a separate commit on its own branch, and
the switch turns it off.

### Stage 0: settings, no code

- **`VICTORY_D3D12_DRED` unset for speed runs.** With it on, every recorded command gets a
  formatted text marker, a lock and a timestamp query (`HostList::note`, `host.rs`): 293 ms
  a frame. Keep it for crash hunts only.
- **`VICTORY_WIDE_BACK=1`.** Snapshots and compares of shader-written ranges run on kept
  threads in ~1 MiB pieces instead of range by range on the submitting thread (`shadow.rs`
  `wide_back`). Watch for device loss.
- **`VICTORY_TEXTURE_QUEUE_MS=150`** (was 1000). The heap pass may spend this long per pass
  making and staging textures picked by index, on a thread that records the frame. Textures
  arrive a little later; frames stop taking seconds.

Check: notes 0 ms; snapshots and compares lower; heap pass ≤ ~200 ms.

### Stage 1: staging pool (`VICTORY_STAGING_POOL=1`)

Texture staging buffers (`texture.rs` `staging`, `host.rs` `upload_buffer`) are one
committed upload resource each, made per texture and let go after use. Keep let-go buffers
in a pool by size class; take from it before making one. A staging buffer is let go only
when no list holds it (lists hold their `Arc<Staging>` until reset, after the card ran), so
reuse after `Drop` is safe. Cap the pool (default 1 GiB).

Check: `upload buffers made` grows slowly; page faults and kernel time fall.

### Stage 2: copy-back without CPU compares

Today a submission snapshots each range shaders may write, and after the card compares the
whole range on the CPU to find what changed: 727 MB compared for 25 MB written back. Steps:

1. Measure which ranges are ever read by the CPU after the card writes them.
2. Compare on the card (the card-copy path already compares pieces on the card) and fetch
   only differing pieces.
3. Lazy copy-back: guard the pages; copy back on the CPU's first touch.

Check: `snapshots` and `compared back` near zero; "copying back" falls; nothing renders
differently.

### Stage 3: fewer submissions, prepare ahead

30.6 submissions a frame, the submitting thread waiting 176 ms for the submission lock and
550 ms between submissions. Join submissions that need no CPU round trip between them;
prepare submission N+1 while N runs.

Check: submissions per frame and the lock wait fall; "card idle behind us" falls.

### Stage 4: recording cost

49 µs per list call without notes is still ~30× a native call. Profile `list.rs`/`draw.rs`
per call: descriptor mirroring, state tracking, allocations, locks. Cache what repeats.

### Stage 5: card work

Turn the optimiser back on (fix the pass-4 pattern AMD's compiler crashes on), measure GPU
time per pass (`VICTORY_GPU_TIMING`), and cut the heaviest of our own passes.

### Stage 6: textures on the card

Upload tiled bytes as-is and detile in a compute shader (`victory-formats` layouts). Only
once stages 0–3 are in: textures are no longer the top cost (61 ms).

## Status (2026-11-25, branch `perf/combined`)

Measured: the remap-lock fix (`4bece45`) and stage 0 settings: world frame median
1,867 → 534 ms (0.5 → 1.9 fps), card busy 9 → 39 %, 2.7× the draws.

Built and unit-tested, **not yet measured in a run** (all default off unless noted):

| Switch | Stage | What |
|---|---|---|
| `VICTORY_STAGING_POOL=1` (`_MB`, default 1024) | 1 | texture upload buffers reused |
| `VICTORY_UPLOAD_RING=1` | 1 | host lists' upload buffers through the same pool |
| `VICTORY_LIST_ARENA=1` | 1 | list upload blocks of 64 KiB+ reused |
| `VICTORY_READBACK_POOL=1` | 1 | read-back buffers reused |
| `VICTORY_MAPPED_BATCH=1` | 1 | `mapped_bytes` asks the kernel once per 256 blocks |
| `VICTORY_HEAP_SLOTS_BATCH=1` | 1 | heap pass makes buffer views 64 at a time under one lock |
| `VICTORY_CARD_WRITTEN_MIN_MB=1` (+ `VICTORY_CARD_BUFFERS_MB=1536`) | 2 | buffers shaders write compared on the card from 1 MiB |
| `VICTORY_WIDE_BACK_MERGE=1` | 2 | shader-write merges on the kept threads |
| `VICTORY_CARD_WIDE_HASH=1` | 5 | card compares: 64 threads a piece instead of one |
| `VICTORY_INDIRECT_ONE_WAIT=1` | 5 | one shader-write drain per bounded indirect command, not two |
| `VICTORY_CARD_STAMPS=1` | — | our own card work on the card's clock (log only) |
| always on | 4 | shared locks: view table, made slots, buffer map; one host-copy lookup per state change; no per-draw Vec in `bind`; capture ops free without a capture; cached heap GPU handle; drop reasons counted in atomics; pipelines known by pointer |

New log lines: `heap pass per frame: …`, `copystat: recording by part per frame`, the
pools on `memory let go since the start:`, `our lists for copies in the card's memory on
the card's clock`, and the submission-lock split.

Test launcher: `C:\Users\david\Tools\vamd-perf\run-perf.ps1` (every switch above on). If
a run loses the device or renders wrong, turn the stage 5 and stage 2 switches off first.

## Reading a run

```bash
sed 's/\x1b\[[0-9;]*m//g' ~/victory-run.log > /tmp/run.log
grep -aE "fps, [0-9.]+ ms/frame" /tmp/run.log | tail
grep -a "the card's clock per frame" /tmp/run.log | tail -3
grep -a "copystat: recording per frame\|copystat: copies per frame\|copystat: frame account" /tmp/run.log | tail -3
```

`scripts/perf-budget.sh <log>` prints the medians of the numbers in section 1 over world
frames (1,000 draws or more), for a before/after comparison.
