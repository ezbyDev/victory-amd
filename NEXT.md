# What's needed next

In order. Each item says how to check it.

1. **Missing floors and walls, lowest-detail models, clothing meshes missing.** First test:
   `VICTORY_PIPELINE_WAIT_MS=2000` and `VICTORY_PIPELINE_WORKERS=7`, judged on a warm second
   run. If still missing, the log's `dropped ... without a host pipeline` lines name the
   shaders; fix their translation.
2. **Keep built pipelines after a crash.** The pipeline library is saved periodically and on
   a normal exit; a crashed run loses its work (library stayed ~1 MB). Check: the backlog
   ("being made") at the start of the next run.
3. **Frame rate (1–3 fps).** About 150–230 ms a frame is copy-back. Try
   `VICTORY_CARD_BUFFERS_MIN_MB=1`, `VICTORY_CARD_BUFFERS_MB=1024`, `VICTORY_WIDE_BACK=1`,
   one at a time; watch for device loss on AMD.
4. **Purple / over-bright materials and foliage.** Likely ray-traced resolve shaders with
   incomplete input; find the program writing out-of-range values (skip one family at a
   time).
5. **Faceted shading on faces and bodies.** Interpolated values reaching pixel shaders.
6. **The five AMD skips** (`scripts/run-amd.ps1`): fix in the translator so none is needed.
7. **Ray-traced lighting:** see `docs/fork-ray-tracing.md`.
