# What's needed next

In order. Each item says how to check it.

1. **Missing floors and walls, lowest-detail models, clothing meshes missing.** First test:
   `VICTORY_PIPELINE_WAIT_MS=2000` and `VICTORY_PIPELINE_WORKERS=7`, judged on a warm second
   run. If still missing, the log's `dropped ... without a host pipeline` lines name the
   shaders; fix their translation.
2. **Mesh pipelines the library will not load back** ("the library did not load it: the
   parameter is incorrect"): made again every run (0.2–0.4 ms each). The library now saves
   every 60 s and on the ways out of the process, and says when a save failed.
3. **Frame rate: 430 ms a world frame (2.3 fps, best 3.3).** Plan and measurements in
   `docs/perf-plan.md`; settings in `scripts/run-amd.ps1`. Next: descriptor tables per draw
   (186–198 ms a frame across the recording threads, ~70 % of recording), our card
   compares (51 ms of card time a frame), the submitting thread's preparing + copy-back in
   series (165 + 65 ms), then the shader optimiser back on (item 6) for the card's own work.
4. **Purple / over-bright materials and foliage.** Likely ray-traced resolve shaders with
   incomplete input; find the program writing out-of-range values (skip one family at a
   time).
5. **Faceted shading on faces and bodies.** Interpolated values reaching pixel shaders.
6. **The five AMD skips** (`scripts/run-amd.ps1`): fix in the translator so none is needed.
7. **Ray-traced lighting:** see `docs/fork-ray-tracing.md`.
