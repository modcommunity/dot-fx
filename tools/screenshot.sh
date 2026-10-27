#!/usr/bin/env bash
# Render the decals demo to a PNG under Xvfb.
#
#   heavy -- tools/screenshot.sh <out.png> [mesh|decal]
#
# muzzle [fp] draws the four muzzle flash sizes.
# goo [amount] draws the screen goo overlay over a street (Compatibility renderer).
# mesh uses the Compatibility renderer (quads); decal uses Forward+ on Mesa's software Vulkan.
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed" >&2; exit 3; }
[ $# -ge 1 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
OUT="$(realpath -m "$1")"; MODE="${2:-mesh}"
mkdir -p "$(dirname "$OUT")"
godot --headless --path . --import >/dev/null 2>&1
disp=$((90 + RANDOM % 8)); export DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1
Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
if [ "$MODE" = decal ]; then R=(--rendering-method forward_plus --rendering-driver vulkan); else R=(--rendering-method gl_compatibility --rendering-driver opengl3); fi
if [ "$MODE" = goo ]; then
    R=(--rendering-method gl_compatibility --rendering-driver opengl3)
    timeout 120 godot --path . --resolution 1280x720 "${R[@]}" res://examples/goo_demo.tscn -- --shot "$OUT" --amount="${3:-0.6}"
elif [ "$MODE" = muzzle ]; then
    R=(--rendering-method gl_compatibility --rendering-driver opengl3)
    timeout 120 godot --path . --resolution 1280x720 "${R[@]}" res://examples/muzzle_demo.tscn -- --shot "$OUT" ${3:+--fp}
else
    timeout 120 godot --path . --resolution 1280x720 "${R[@]}" res://examples/decals_demo.tscn -- --shot "$OUT" --mode=$MODE
fi
rc=$?
kill $xpid 2>/dev/null
exit $rc
