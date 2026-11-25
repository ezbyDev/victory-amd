# victory-amd

An experimental **Xbox Series compatibility layer for Windows**, tuned for **AMD Radeon
(RDNA) graphics cards**. It runs an Xbox Series title's x86-64 code natively inside its own
process, supplies the platform underneath it (loader, runtime services, Direct3D 12.X on top
of the PC's Direct3D 12), and recompiles the console's GPU shaders to DXIL.

victory-amd is a fork of [VIctory](https://github.com/Marvisak/VIctory), by way of
[victory-fork](https://github.com/fxceless/victory-fork). Almost all of the code is theirs
(see [Credits](#credits)); this fork collects the open fixes and settings that make it run
stably on AMD hardware, where the defaults tuned on NVIDIA cards fail.

**This repository contains no game files, no game code and no game assets, and it never
will** (see [docs/asset-policy.md](docs/asset-policy.md)). You need your own, legally
obtained copy of the software you run. This project is not affiliated with, endorsed by or
connected to Microsoft, Xbox, AMD, or any game developer or publisher.

> **Status: experimental, not playable.** It starts, runs menus at full speed and reaches
> 3D scenes, but those run at 1–3 frames per second with visible rendering errors. Treat it
> as a research and testing tool.

## What works

Tested on one machine: Windows 11 Pro, **AMD Radeon RX 9060 XT 16 GB (RDNA 4)**, Adrenalin
driver 32.0.32029.2010, Intel Core i7-9700K, 32 GB RAM, Series X profile.

| Area | State |
|------|-------|
| Boot, first-run screens, menus | works, 30 fps |
| Video playback with sound | works |
| Saves and profile | works (offline user) |
| Loading into a 3D world | works; slow while shader pipelines are first built |
| 3D rendering | characters, clothing, faces, textures, sky and glass render; much is still wrong (see limitations) |
| Input | XInput pads; keyboard as a pad |
| Audio | music, voice and effects play |
| Stability on AMD | no device loss in normal runs with the settings below |

## Current limitations

- **Frame rate:** 1–3 fps in 3D scenes. About 150–230 ms of each frame goes to copying
  GPU results back to the console's memory, and much of the rest to preparing copies.
- **Lighting:** ray-traced lighting (bounce light, reflections, ray-traced shadows) does not
  run yet. Areas not lit directly are dark, and light does not bounce off surfaces.
- **Wrong colours:** some materials, foliage and objects show bright purple or over-bright
  light; hair can look far too bright. Ray-traced resolve shaders run with incomplete input.
- **Missing geometry:** some walls, floors and ceilings are missing, or appear late, until
  their pipelines have been built.
- **Level of detail:** distant characters can stay at low detail and some objects never
  finish loading their textures.
- **Shading:** some faces and bodies look faceted (flat-shaded polygons).
- **First runs are slow:** thousands of shader pipelines are built on first use; built
  pipelines are kept on disk, so later runs start faster. A run that crashes may lose
  pipelines built during it.
- **AMD driver issues:** a few compute shaders crash or never finish in AMD's shader
  compiler and have to be skipped (see the settings below).
- **Memory:** about 17–24 GB of RAM in use during play; a large Windows paging file helps.
- Tested on one GPU, with one title. Other titles and other cards are unknown.

## What this fork adds to victory-fork

Code (each from an open pull request or fork of victory-fork, merged unchanged except where
two of them touched the same lines):

- **Skipped pipelines are not compiled early** — victory-fork
  [#172](https://github.com/fxceless/victory-fork/pull/172) by ericomeehan. Without it,
  skipping a shader that crashes the driver's compiler does not help.
- **Texture queue limits and pipeline skipping in release builds** — victory-fork
  [#106](https://github.com/fxceless/victory-fork/pull/106) by PastiiJay
  (`VICTORY_TEXTURE_QUEUE_MB`, `VICTORY_TEXTURE_QUEUE_MS`).
- **Pipeline worker count and priority** — commit `76bec97` from
  [bathyal-vi](https://github.com/T-Crypt/bathyal-vi) by T-Crypt
  (`VICTORY_PIPELINE_WORKERS`, `VICTORY_PIPELINE_PRIORITY`).

Settings that matter on AMD, found by victory-fork's testers and confirmed here:

| Setting | Why |
|---------|-----|
| `VICTORY_LATE_WAIT=3` | sends submissions ahead without waiting for the card; about 3× the frame rate, stable on AMD |
| no `VICTORY_RELAY` | the relay thread removes the GPU device on AMD within minutes (victory-fork [#60](https://github.com/fxceless/victory-fork/issues/60)) |
| `VICTORY_SHADER_OPT=11` | shader clean-up pass 4 makes AMD's compiler crash (`amdxc64.dll`) on many compute programs (victory-fork [#145](https://github.com/fxceless/victory-fork/issues/145)) |
| `VICTORY_SHADER_LOOP_LIMIT=1024` | without a cap, a translated loop can run long enough for Windows to reset the GPU |
| `VICTORY_PIPELINE_WORKERS=6`, `VICTORY_PIPELINE_PRIORITY=normal` | with the default 4 low-priority workers, pipelines are built at about one a second and most of the scene is dropped for minutes |
| `VICTORY_TEXTURE_QUEUE_MB=1024`, `VICTORY_TEXTURE_QUEUE_MS=1000` | textures picked by index arrive in seconds instead of minutes |
| `VICTORY_SKIP_PIPELINES=...` | five compute programs that crash or hang AMD's driver (listed in `scripts/run-amd.ps1`) |

## Getting started

Requirements: Windows 10/11 x64, a CPU with AVX2, a Direct3D 12 GPU with shader model 6.6
and mesh shaders, Rust (version pinned in `rust-toolchain.toml`), and a large Windows paging
file (32 GB or more recommended).

```powershell
cargo xtask install-hooks                # asset-policy check on every commit
cargo test --workspace                   # needs no game data
cargo build --profile diag -p victory --features diagnostics   # target\diag\victory.exe
```

Run with the AMD settings (edit the paths at the top of the script first):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run-amd.ps1
```

The script writes the log to the file named at its top. Saves, settings and `crashes.log`
live in the data folder (default `%LOCALAPPDATA%\victory\data`), derived data in the cache
folder (default `%LOCALAPPDATA%\victory\cache`). Close the title normally rather than
killing it, so built pipelines are saved.

Tips:
- **Log to a file with `cmd /c "... > log 2>&1"`**, as the script does. Piping the output
  through PowerShell (`| Tee-Object`) slows the title down until it stalls.
- Environment variables stay set in a PowerShell window; set every switch explicitly, or
  use a new window, when comparing settings.
- The first run with new shader settings recompiles everything; judge rendering on the
  second run.

Input: XInput pads. With none connected, the keyboard acts as a pad while the window has
focus:

| Keys | Pad |
|------|-----|
| W A S D / I J K L | left / right stick |
| arrows | D-pad |
| Enter, Backspace, X, Y | A, B, X, Y |
| Q / E, Z / C | shoulders, triggers |
| F / H | stick clicks |
| Esc, Tab | Menu, View |

## Commands

```
victory inspect <exe|dll> [--imports] [--exports]
victory census [paths...] [--missing] [--strict]
victory lib-exports <import.lib> [--list]
victory shader-info [paths...] [--verbose] [--disasm]
victory translate [paths...] [--validate] [--pipelines] [--list] [--jobs N]
victory run <exe> [--execute] [--unimplemented trap|zero] [--strict]
            [--console series-x|series-s] [-- <title arguments>]
victory config
```

## Debugging (diagnostics build)

| Variable | Effect |
|----------|--------|
| `VICTORY_LOG=<target>=debug,...` | debug and trace output |
| `VICTORY_STACKS=20,60` | every thread's stack at those seconds |
| `VICTORY_D3D12_DEBUG=1` | host debug layer |
| `VICTORY_D3D12_DRED=1` | on a GPU failure, the commands in flight and the page fault, in `crashes.log` |
| `VICTORY_GPU_TIMING=1` | each list run and timed on its own (slow) |
| `VICTORY_D3D12_WARP=1` | software adapter (slow, cannot reset the driver) |
| `VICTORY_SKIP_PIPELINES=<hash>,...` | omit draws and dispatches whose pipeline contains a listed 16-digit shader hash, and do not build them |
| `VICTORY_SHADER_LOOP_LIMIT=<n>` | translated loops stop after `n` iterations per lane |

Every build appends crashes and GPU failures to `crashes.log` in the title's data folder.
Upstream's architecture notes are in [docs/architecture.md](docs/architecture.md).

## Planned improvements

1. Frame rate: reduce the per-frame copy-back of GPU results (victory-fork's
   `VICTORY_CARD_BUFFERS*` and `VICTORY_WIDE_BACK` work), measured one switch at a time on AMD.
2. Keep built pipelines when a run ends abnormally, so restarts do not rebuild them.
3. The bright purple artifacts: find which shader writes out-of-range values.
4. Faceted shading: test victory-fork's interpolation and signature fixes (#52, #61, #110,
   #112) on AMD.
5. Fix the AMD compiler and page-fault cases in the translator, so fewer shaders need
   skipping.
6. Ray-traced lighting, following victory-fork's work in
   [docs/fork-ray-tracing.md](docs/fork-ray-tracing.md).

Contributions follow the asset policy: **nothing from any game, in any form** — no files,
no dumps, no screenshots, no shader listings.

## Credits

- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and its contributors: the
  loader, runtime services, Direct3D 12.X back end and shader recompiler — essentially all
  of the code. GPL-3.0-or-later.
- **[victory-fork](https://github.com/fxceless/victory-fork)** by fxceless and its
  contributors: the world-rendering, speed and memory work this fork is based on (commit
  `4e17478` of its `main` plus commits up to `2119b0e`).
- **ericomeehan** (#172), **PastiiJay** (#106) and **T-Crypt** (bathyal-vi): the changes
  listed above.
- The victory-fork testers whose reports found the AMD settings, among them srcamarda
  (#60), hashdev512 (#145), luisaugustz and nullmarsh (#3).
- [XCL](https://github.com/ivall/xcl) by ivall was used by victory-fork as a behavioural
  reference; no XCL code is included.
- Assembled and tested with [Claude Code](https://claude.com/claude-code).

This repository's history starts with a single commit holding the combined code; the
individual history lives in the projects above.

## License

GPL-3.0-or-later, as VIctory. See [LICENSE](LICENSE).
