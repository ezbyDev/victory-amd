# Instructions for agents

- **Rule #1:** nothing from any game in the repo or in posts: no files, dumps, screenshots,
  shader listings, title names. Counts and 16-digit shader hashes only. Run
  `cargo xtask policy` before every commit.
- Build: `cargo build --profile diag -p victory --features diagnostics`. Tests:
  `cargo test --workspace` (GPU tests need a D3D12 card; one `inplace` WARP test is flaky in
  full runs).
- Run with `scripts/run-amd.ps1`. Log with `cmd /c "... > log 2>&1"`, never `| Tee-Object`.
  Set every `VICTORY_*` switch explicitly; a PowerShell window keeps old ones.
- Read results from the log: the `N fps, X ms/frame` lines, `dropped .../frame without a
  host pipeline: <reason>`, `ms waiting for pipelines`. GPU failures and DRED breadcrumbs
  are in `<data dir>\<title>\crashes.log`.
- Change one thing per run and compare against the same cache. Judge rendering on a warm
  (second) run.
- On AMD: never `VICTORY_RELAY`; keep `VICTORY_SHADER_OPT=11`; never skip the meshlet
  culling program `fc5e66f8f873d3bb` (it hides most geometry).
- Prefer an existing upstream pull request over a new fix; name the tool and model in any
  report.
