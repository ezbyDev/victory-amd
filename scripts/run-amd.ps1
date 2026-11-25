# Runs a title with the settings that keep victory-amd stable on AMD Radeon (RDNA) cards.
# See README.md, "What this fork adds", for why each setting is there.
#
#   powershell -ExecutionPolicy Bypass -File scripts\run-amd.ps1

# --- Your paths -------------------------------------------------------------------------
$Exe     = "$PSScriptRoot\..\target\diag\victory.exe"   # the build to run
$Title   = "D:\my-title\title.exe"                       # your own title's executable
$Log     = "$env:USERPROFILE\victory-run.log"            # the run's log
# $env:VICTORY_DATA_DIR = "D:\victory\data"              # saves (default %LOCALAPPDATA%\victory\data)
# $env:VICTORY_CACHE_DIR = "D:\victory\cache"            # shader cache (default %LOCALAPPDATA%\victory\cache)

# --- AMD settings -----------------------------------------------------------------------
Remove-Item Env:VICTORY_RELAY -ErrorAction SilentlyContinue   # the relay thread removes the device on AMD
$env:VICTORY_LATE_WAIT          = "3"      # submissions sent ahead of the wait for the card
$env:VICTORY_SHADER_OPT         = "11"     # clean-up pass 4 off: it crashes AMD's shader compiler
$env:VICTORY_SHADER_LOOP_LIMIT  = "1024"   # a translated loop cannot run until Windows resets the GPU
# $env:VICTORY_D3D12_DRED       = "1"      # crash hunts only: names the commands in flight, ~300 ms a frame
$env:VICTORY_TEXTURE_QUEUE_MB   = "1024"   # textures picked by index arrive in seconds
$env:VICTORY_TEXTURE_QUEUE_MS   = "150"    # at most this long a pass making them (1000 made frames take seconds)
$env:VICTORY_PIPELINE_WORKERS   = "6"      # build pipelines fast enough for scenes to appear
$env:VICTORY_PIPELINE_PRIORITY  = "normal"

# --- Speed (docs/perf-plan.md; measured on an RX 9060 XT: 1,867 -> 430 ms a world frame) ---
$env:VICTORY_WIDE_BACK          = "1"      # snapshots and compares of shader writes on several threads
$env:VICTORY_WIDE_BACK_MERGE    = "1"      # and their merges
$env:VICTORY_KEEP_SNAPSHOTS     = "1"      # snapshots retake only the pieces that changed
$env:VICTORY_KEEP_SNAPSHOTS_MB  = "512"
$env:VICTORY_STAGING_POOL       = "1"      # upload buffers reused (page faults 69k -> 10k a frame)
$env:VICTORY_UPLOAD_RING        = "1"
$env:VICTORY_LIST_ARENA         = "1"
$env:VICTORY_READBACK_POOL      = "1"
$env:VICTORY_MAPPED_BATCH       = "1"      # fewer kernel queries in the heap pass
$env:VICTORY_HEAP_SLOTS_BATCH   = "1"
$env:VICTORY_CARD_WRITTEN_MIN_MB = "1"     # buffers shaders write compared on the card from 1 MiB
$env:VICTORY_CARD_BUFFERS_MB    = "1536"
$env:VICTORY_CARD_WIDE_HASH     = "1"      # card compares: 64 threads a piece
# Not VICTORY_INDIRECT_ONE_WAIT: it hung the card on an RX 9060 XT.

# Compute programs that crash AMD's shader compiler on every setting (c1eee35d, f1687692),
# page-fault on AMD (eeed82b8, 02384a60), or never finish compiling (39f0e9ae).
$env:VICTORY_SKIP_PIPELINES = "c1eee35dbc50a9ef,f16876929fa64f9f,eeed82b877b44b5f,02384a60fda6f2d0,39f0e9aeb156a61c"

# Logged to a file through cmd: piping through PowerShell stalls the title.
cmd /c "`"$Exe`" run `"$Title`" --execute > `"$Log`" 2>&1"
Write-Host "Done. Log: $Log"
