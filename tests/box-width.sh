#!/bin/bash
# ---------------------------------------------------------------------------
# box-width.sh - verify that every box line drawn by cccpu.sh is 69 columns.
#
# The drawing code lives inside cccpu.sh, so this test extracts its function
# definitions (everything above the MAIN LOGIC marker) and drives them with a
# fixed set of fake cores. That keeps the result identical on every machine and
# exercises the real drawing helpers instead of a copy of them.
#
# The core grid only renders when stdout is a terminal, so each case runs on a
# pty supplied by `script`. Failing lines are printed with their measured width
# and the script exits non-zero.
# ---------------------------------------------------------------------------
set -u

EXPECTED_WIDTH=69

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TARGET=$SCRIPT_DIR/../cccpu.sh

if [ ! -r "$TARGET" ]; then
    echo "FAIL: cannot read $TARGET" >&2
    exit 1
fi
if ! command -v script >/dev/null 2>&1; then
    echo "FAIL: 'script' (util-linux) is required to give the grid a pty" >&2
    exit 1
fi

WORK=$(mktemp -d) || { echo "FAIL: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

FAILED=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILED=1; }
ok()   { printf 'ok   %s\n' "$*"; }

# --- extract the function definitions from the script under test -----------
awk '/^# --- MAIN LOGIC/{exit} {print}' "$TARGET" > "$WORK/lib.sh"
if ! grep -q '^function draw_rule' "$WORK/lib.sh"; then
    echo "FAIL: could not extract the drawing functions from $TARGET" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$WORK/lib.sh"

if (( TABLE_WIDTH != EXPECTED_WIDTH )); then
    fail "cccpu.sh derives TABLE_WIDTH=$TABLE_WIDTH, expected $EXPECTED_WIDTH"
else
    ok "cccpu.sh derives a table width of $TABLE_WIDTH columns"
fi

# Byte-vs-character counting depends on the locale, so only measure the Unicode
# cases when this shell counts characters rather than bytes.
PROBE='■■'
RUN_UNICODE=0
(( ${#PROBE} == 2 )) && RUN_UNICODE=1

strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g' "$1"; }

measure() {   # $1 = label, $2 = ANSI-free output file
    local label=$1 file=$2 line n=0 bad=0
    while IFS= read -r line; do
        line=${line%$'\r'}
        case $line in
            "+"*|"|"*|"┌"*|"│"*|"├"*|"└"*)
                n=$(( n + 1 ))
                if (( ${#line} != EXPECTED_WIDTH )); then
                    if (( bad == 0 )); then
                        printf '  %s: %d columns, expected %d: %s\n' \
                            "$label" "${#line}" "$EXPECTED_WIDTH" "$line" >&2
                    fi
                    bad=$(( bad + 1 ))
                fi
                ;;
        esac
    done < "$file"

    if (( n == 0 )); then
        fail "$label: no box lines were drawn"
    elif (( bad > 0 )); then
        fail "$label: $bad of $n box lines are not $EXPECTED_WIDTH columns"
    else
        ok "$label ($n box lines, all $EXPECTED_WIDTH columns)"
    fi
}

run_case() {   # $1 = label, $2 = shell code to run on the pty
    local label=$1 snippet=$2 runner=$WORK/runner.sh
    {
        printf 'source %q\n' "$WORK/lib.sh"
        printf 'FAKE_CORES=%q\n' "$FAKE_CORES"
        printf 'ONLINE_LIST=%q\n' "$ONLINE_LIST"
        printf 'ls() { local i; for (( i = 0; i < FAKE_CORES; i++ )); do echo "/sys/devices/system/cpu/cpu$i"; done; }\n'
        printf 'get_enumerated_online_cpus() { echo "$ONLINE_LIST"; }\n'
        printf '%s\n' "$snippet"
    } > "$runner"

    if ! script -q -e -c "bash $(printf '%q' "$runner")" /dev/null > "$WORK/raw.txt" 2>&1; then
        fail "$label: the drawing code exited non-zero"
        return
    fi
    strip_ansi "$WORK/raw.txt" > "$WORK/clean.txt"
    measure "$label" "$WORK/clean.txt"
}

# --- cases -----------------------------------------------------------------
FAKE_CORES=2;   ONLINE_LIST="0 1"
run_case "ascii: 2 cores" 'show_online_cores; show_status_table'

FAKE_CORES=8;   ONLINE_LIST="0 1 2 3"
run_case "ascii: table only" 'show_status_table'

FAKE_CORES=64;  ONLINE_LIST=$(seq -s ' ' 0 23)
run_case "ascii: 64 cores, 24 online" 'show_online_cores; show_status_table'

FAKE_CORES=64;  ONLINE_LIST="0"
run_case "ascii: 64 cores, 1 online" 'show_online_cores'

FAKE_CORES=128; ONLINE_LIST="0"
run_case "ascii: 128 cores (3-digit ids)" 'show_online_cores'

run_case "end-to-end: cccpu.sh -T" "bash $(printf '%q' "$TARGET") -T"

if (( RUN_UNICODE )); then
    FAKE_CORES=64; ONLINE_LIST=$(seq -s ' ' 0 23)
    run_case "unicode: 64 cores" 'set_box_style unicode; show_online_cores; show_status_table'

    FAKE_CORES=2;  ONLINE_LIST="0 1"
    run_case "unicode: 2 cores" 'set_box_style unicode; show_online_cores; show_status_table'
else
    printf 'skip unicode cases: this locale does not count multibyte characters\n'
fi

echo
if (( FAILED )); then
    echo "FAILED: box lines are not all $EXPECTED_WIDTH columns" >&2
    exit 1
fi
echo "PASS: every box line is $EXPECTED_WIDTH columns"
