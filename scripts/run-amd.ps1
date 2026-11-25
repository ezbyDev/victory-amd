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
$env:VICTORY_D3D12_DRED         = "1"      # a GPU failure names the commands in flight (crashes.log)
$env:VICTORY_TEXTURE_QUEUE_MB   = "1024"   # textures picked by index arrive in seconds
$env:VICTORY_TEXTURE_QUEUE_MS   = "1000"
$env:VICTORY_PIPELINE_WORKERS   = "6"      # build pipelines fast enough for scenes to appear
$env:VICTORY_PIPELINE_PRIORITY  = "normal"

# Compute programs that crash AMD's shader compiler on every setting (c1eee35d, f1687692),
# page-fault on AMD (eeed82b8, 02384a60), or never finish compiling (39f0e9ae).
$env:VICTORY_SKIP_PIPELINES = "c1eee35dbc50a9ef,f16876929fa64f9f,eeed82b877b44b5f,02384a60fda6f2d0,39f0e9aeb156a61c"

# Logged to a file through cmd: piping through PowerShell stalls the title.
cmd /c "`"$Exe`" run `"$Title`" --execute > `"$Log`" 2>&1"
Write-Host "Done. Log: $Log"
