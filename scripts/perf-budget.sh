#!/usr/bin/env bash
# Medians of the frame budget (docs/perf-plan.md, section 1) over world frames: frame lines
# of at least MIN_DRAWS draws (default 1000), and the other lines logged in the same second.
#
#   scripts/perf-budget.sh ~/victory-run.log [MIN_DRAWS]
set -euo pipefail
log=${1:?usage: perf-budget.sh LOG [MIN_DRAWS]}
min=${2:-1000}
sed 's/\x1b\[[0-9;]*m//g' "$log" | awk -v min="$min" '
function num(s, re,   m) { if (match(s, re)) { m = substr(s, RSTART, RLENGTH); gsub(/[^0-9.]/, "", m); return m + 0 } return "" }
function put(k, key, v) { if (v != "") val[k, key] = v }
{
  key = substr($0, 1, 19)
  if ($0 ~ /fps, [0-9.]+ ms\/frame/) {
    d = num($0, "[0-9.]+ draws/frame")
    if (d >= min) world[key] = 1
    put("frame ms", key, num($0, "[0-9.]+ ms/frame"))
    put("preparing ms", key, num($0, "\\(([0-9.]+) preparing"))
    put("textures ms", key, num($0, "textures [0-9.]+ ms"))
    put("copying back ms", key, num($0, "; [0-9.]+ copying back"))
    put("heap pass ms", key, num($0, "passes [0-9.]+ ms"))
    put("draws", key, d)
  }
  if ($0 ~ /the card.s clock per frame/) {
    put("card busy %", key, num($0, "about [0-9.]+%"))
    put("card idle behind us ms", key, num($0, "[0-9.]+ ms of that while the submitting"))
  }
  if ($0 ~ /copystat: copies per frame/) {
    put("submissions", key, num($0, "[0-9.]+ submissions"))
    put("page faults", key, num($0, "[0-9.]+ page faults"))
  }
  if ($0 ~ /copystat: recording per frame/) {
    put("recording ms (all threads)", key, num($0, "list calls [0-9.]+ ms"))
    put("notes ms", key, num($0, "notes [0-9.]+ ms"))
    put("snapshots ms", key, num($0, "snapshots [0-9.]+ ms"))
    put("compared back MB", key, num($0, "[0-9.]+ MB compared back"))
  }
  if ($0 ~ /copystat: frame account/) {
    put("process user ms", key, num($0, "ran [0-9.]+ ms user"))
    put("process kernel ms", key, num($0, "[0-9.]+ ms kernel"))
  }
  if ($0 ~ /submitted [0-9.]+x\/frame/) {
    put("submission lock wait ms", key, num($0, "[0-9.]+ ms waiting for the submission lock"))
  }
  if ($0 ~ /copystat: memory: /) {
    put("upload buffers made", key, num($0, "made so far: [0-9]+ upload"))
  }
}
END {
  n = split("frame ms|draws|card busy %|card idle behind us ms|preparing ms|textures ms|copying back ms|heap pass ms|recording ms (all threads)|notes ms|snapshots ms|compared back MB|submissions|submission lock wait ms|process user ms|process kernel ms|page faults|upload buffers made", names, "|")
  frames = 0; for (k in world) frames++
  printf "%d world frame lines (draws >= %d)\n", frames, min
  printf "%-28s %10s %10s %10s\n", "", "median", "min", "max"
  for (i = 1; i <= n; i++) {
    c = 0; delete a
    for (k in world) if (((names[i], k) in val)) a[++c] = val[names[i], k]
    if (c == 0) { printf "%-28s %10s\n", names[i], "-"; continue }
    asort(a)
    printf "%-28s %10.1f %10.1f %10.1f\n", names[i], a[int((c + 1) / 2)], a[1], a[c]
  }
}'
