#!/usr/bin/env bash
#
# Run headless probes under a watchdog.
#
#   tests/run.sh                    every probe in tests/
#   tests/run.sh MotionProbe        one probe (with or without the .gd)
#   tests/run.sh -t 600 RigProbe    a longer leash for a slow one
#
# A probe that never reaches quit() — a runtime error in _process aborts the
# frame before the exit, and SceneTree just keeps calling it — otherwise pins a
# core indefinitely and writes an unbounded log. This kills it instead, and
# reports TIMEOUT rather than hanging the caller.
#
# macOS has no timeout(1), so the watchdog is a background sleep and a kill.

set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
LIMIT="${PROBE_TIMEOUT:-300}"     # seconds a single probe may run
LOG_CAP_MB="${PROBE_LOG_CAP_MB:-64}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_LOGS="$HOME/Library/Application Support/Godot/app_userdata/Evolution — Procedural Lizard/logs"

while [ $# -gt 0 ]; do
	case "$1" in
		-t) LIMIT="$2"; shift 2 ;;
		-h|--help) sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) break ;;
	esac
done

if [ ! -x "$GODOT" ]; then
	echo "no Godot at $GODOT (set GODOT=/path/to/Godot)" >&2
	exit 127
fi

# Which probes to run.
targets=()
if [ $# -gt 0 ]; then
	for name in "$@"; do
		name="${name%.gd}"
		name="${name#tests/}"
		if [ ! -f "$ROOT/tests/$name.gd" ]; then
			echo "no probe tests/$name.gd" >&2
			exit 2
		fi
		targets+=("$name")
	done
else
	for f in "$ROOT"/tests/*Probe.gd; do
		targets+=("$(basename "$f" .gd)")
	done
fi

# Run one probe with a hard leash. Echoes its output; returns its status, or
# 124 if the watchdog had to step in.
run_one() {
	local name="$1"
	local out; out="$(mktemp -t "probe-$name")"

	"$GODOT" --headless --path "$ROOT" --script "tests/$name.gd" >"$out" 2>&1 &
	local pid=$!

	# Watchdog: if the probe is still alive at the limit, take it down. TERM
	# first so Godot can flush, then KILL for the wedged case.
	(
		sleep "$LIMIT"
		if kill -0 "$pid" 2>/dev/null; then
			touch "$out.timedout"
			kill -TERM "$pid" 2>/dev/null
			sleep 5
			kill -KILL "$pid" 2>/dev/null
		fi
	) &
	local dog=$!

	wait "$pid" 2>/dev/null
	local status=$?
	kill "$dog" 2>/dev/null
	wait "$dog" 2>/dev/null

	if [ -e "$out.timedout" ]; then
		status=124
		rm -f "$out.timedout"
	fi

	# A wedged probe repeats one error every frame. Show the head, not the MBs.
	head -c $((LOG_CAP_MB * 1024 * 1024)) "$out"
	rm -f "$out"
	return $status
}

failed=()
timedout=()

for name in "${targets[@]}"; do
	echo "=== $name ==="
	run_one "$name"
	status=$?
	case $status in
		0) ;;
		124)
			echo "!! $name TIMED OUT after ${LIMIT}s — killed. It never reached quit()."
			timedout+=("$name")
			;;
		*)
			failed+=("$name")
			;;
	esac
	echo
done

# A run that wedged leaves a huge log behind; don't let it sit there.
if [ -d "$GODOT_LOGS" ]; then
	find "$GODOT_LOGS" -name '*.log' -size +"${LOG_CAP_MB}"M -print -delete \
		| sed 's/^/removed oversized log: /'
fi

echo "--- ${#targets[@]} probe(s): ${#failed[@]} failed, ${#timedout[@]} timed out ---"
[ ${#failed[@]} -gt 0 ] && echo "failed:  ${failed[*]}"
[ ${#timedout[@]} -gt 0 ] && echo "timeout: ${timedout[*]}"
[ ${#failed[@]} -eq 0 ] && [ ${#timedout[@]} -eq 0 ]
