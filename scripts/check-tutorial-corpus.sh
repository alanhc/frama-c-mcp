#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/wp-gate.sh
source "$root/scripts/lib/wp-gate.sh"
frama_c="${FRAMA_C_BIN:-frama-c}"
version="$(wp_gate_frama_c_version "$frama_c" "tutorial corpus")" || exit 1

case "$version" in
    31.0 | 33.0) ;;
    *)
        echo "Unsupported tutorial corpus Frama-C version: $version" >&2
        echo "Supported versions are 31.0 and 33.0." >&2
        exit 1
        ;;
esac

status=0

# The Frama-C version guard above does not pin the prover, and the prover is
# what moves these numbers: CI picks it with `why3 config detect`, and locally
# ~/.why3.conf sits outside ~/.opam and is shared by every switch. So assert the
# version the rows were measured under. An Alt-Ergo change then fails here
# saying so, instead of silently shifting every baseline.
expected_prover="Alt-Ergo 2.6.3"

# Measured 2026-08-10 on both switches with -wp-cache none, and identical on
# both, which is why there is one table rather than one per Frama-C version. The
# prover moves these numbers and `expected_prover` above pins it; the Frama-C
# version does not. If a future version ever does move a row, add a `case
# "$version:$name"` arm above the shared table rather than duplicating all
# eleven again.
expected_baseline()
{
    local name="$1"
    case "$name" in
        swap-frame.c) echo "57 57 5" ;;
        abs-behaviors.c) echo "15 16 5" ;;
        triangle-behaviors.c) echo "43 43 10" ;;
        loops.c) echo "46 46 5" ;;
        bsearch.c) echo "27 27 5" ;;
        ghost-code.c) echo "20 20 5" ;;
        count-logic.c) echo "13 15 5" ;;
        sort-permutation.c) echo "33 33 5" ;;
        verker-string.c) echo "31 42 5" ;;
        linked-n.c) echo "14 20 5" ;;
        modular-group) echo "28 28 5" ;;
        *)
            echo "Missing tutorial corpus baseline for fixture $name" >&2
            exit 1
            ;;
    esac
}

check_wp()
{
    local name="$1"
    shift
    local expected_proved expected_total timeout
    read -r expected_proved expected_total timeout < <(expected_baseline "$name")

    # A 0 / 0 row is a table error, so it fails before any WP run is spent.
    if [[ "$expected_proved" -eq "$expected_total" && "$expected_total" -eq 0 ]]; then
        echo "FAIL $name: zero-goal fully-proved result is not a valid shape gate" >&2
        status=1
        return
    fi

    local out

    # WP caches prover verdicts across runs, so without -wp-cache none a rerun
    # replays the previous run's numbers and the gate checks nothing.
    if ! out="$("$frama_c" -wp -wp-rte -wp-prover alt-ergo -wp-cache none -wp-timeout "$timeout" "$@" 2>&1)"; then
        echo "FAIL $name: Frama-C command failed" >&2
        echo "$out" >&2
        status=1
        return
    fi

    # WP lists a prover only for the goals it actually ran, so a fixture Qed
    # discharged on its own prints no such row and cannot be required to name
    # one; the run-wide check below catches a run where no fixture named any.
    if ! wp_gate_check_prover "$name" "$out" "$expected_prover"; then
        echo "Re-measure every row before changing expected_prover." >&2
        status=1
        return
    fi

    if ! wp_gate_expect_counts "$name" "$out" "$expected_proved / $expected_total"; then
        status=1
        return
    fi

    echo "ok $name: $expected_proved / $expected_total"
}

fixture="$root/tests/fixtures/tutorial"

check_wp "swap-frame.c" "$fixture/swap-frame.c"
check_wp "abs-behaviors.c" "$fixture/abs-behaviors.c"
check_wp "triangle-behaviors.c" "$fixture/triangle-behaviors.c"
check_wp "loops.c" "$fixture/loops.c"
check_wp "bsearch.c" "$fixture/bsearch.c"
check_wp "ghost-code.c" "$fixture/ghost-code.c"
check_wp "count-logic.c" "$fixture/count-logic.c"
check_wp "sort-permutation.c" "$fixture/sort-permutation.c"
check_wp "verker-string.c" "$fixture/verker-string.c"
check_wp "linked-n.c" "$fixture/linked-n.c"
check_wp "modular-group" \
    "$fixture/mod-max-abs.c" \
    "$fixture/mod-abs.c" \
    "$fixture/mod-max.c"

echo "skip eva-rotate.c: EVA fixture, not a WP baseline"

wp_gate_require_prover_seen "tutorial corpus" "$expected_prover" || status=1

exit "$status"
