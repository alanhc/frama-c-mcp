#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/wp-gate.sh
source "$root/scripts/lib/wp-gate.sh"
frama_c="${FRAMA_C_BIN:-frama-c}"
version="$(wp_gate_frama_c_version "$frama_c" "abs-int fixtures")" || exit 1

case "$version" in
    31.0 | 33.0) ;;
    *)
        echo "Unsupported Frama-C version: $version" >&2
        echo "Supported versions are 31.0 and 33.0." >&2
        exit 1
        ;;
esac

status=0

# No prover pin, unlike the other Frama-C gates, and not by omission. WP prints
# a prover's version only in the summary row of a prover that discharged a goal.
# abs-int-fixed.c closes every goal in Qed, and abs-int-buggy.c's one Alt-Ergo
# goal times out, which WP reports as "(Alt-Ergo)" with no version. A pin here
# would have nothing to compare and fail every run.

check_wp()
{
    local name="$1"
    local file="$2"
    local expected_proved="$3"
    local expected_total="$4"
    local require_goal="$5"

    # -wp-cache none, as the other Frama-C gates pass. Without it WP runs in
    # update mode, and the buggy fixture's 9 / 10 rests on an Alt-Ergo timeout
    # the cache would replay rather than measure.
    local out
    if ! out="$("$frama_c" -wp -wp-rte -wp-prover alt-ergo -wp-cache none -wp-timeout 5 "$file" 2>&1)"; then
        echo "FAIL $name: Frama-C command failed" >&2
        echo "$out" >&2
        status=1
        return
    fi

    if ! wp_gate_expect_counts "$name" "$out" "$expected_proved / $expected_total"; then
        status=1
        return
    fi

    if [[ "$require_goal" == yes ]] \
        && ! printf '%s\n' "$out" | grep -q 'typed_abs_int_assert_rte_signed_overflow'; then
        echo "FAIL $name: missing signed-overflow goal" >&2
        echo "$out" >&2
        status=1
        return
    fi

    if [[ "$require_goal" == no ]] \
        && printf '%s\n' "$out" | grep -q 'typed_abs_int_assert_rte_signed_overflow'; then
        echo "FAIL $name: fixed fixture still reports signed-overflow goal" >&2
        echo "$out" >&2
        status=1
        return
    fi

    echo "ok $name: $expected_proved / $expected_total"
}

check_wp "abs-int-buggy.c" "$root/tests/fixtures/abs-int-buggy.c" 9 10 yes
check_wp "abs-int-fixed.c" "$root/tests/fixtures/abs-int-fixed.c" 14 14 no

# The WP half above proves the fixtures still differ. This half proves `check`
# says so, which is a separate claim: the buggy fixture returned `incomplete`
# for a whole release while its overflow alarm was missing from `incomplete[]`
# and the verdict came entirely from dead-code demotion. Assert the reason, not
# the verdict.
check_mcp()
{
    local name="$1"
    local file="$2"
    local expectation="$3"
    wp_gate_mcp_ready "$name" || return 0

    local out
    if ! out="$(wp_gate_mcp_check "$frama_c" "$file")"; then
        echo "FAIL $name (MCP): check failed" >&2
        echo "$out" >&2
        status=1
        return
    fi

    if ! printf '%s' "$out" | EXPECT="$expectation" python3 -c '
import json, os, sys

payload = json.load(sys.stdin)
verdict = payload.get("verdict")
incomplete = payload.get("incomplete") or []
codes = [item.get("code") for item in incomplete]

if os.environ["EXPECT"] == "buggy":
    if verdict != "incomplete":
        sys.exit(f"verdict is {verdict}, expected incomplete")
    if not any(
        item.get("code") == "ALARM_NOT_VALID"
        and "signed_overflow" in (item.get("descr") or "")
        for item in incomplete
    ):
        sys.exit(f"no ALARM_NOT_VALID naming signed_overflow; got {codes}")
else:
    if verdict != "proved":
        sys.exit(f"verdict is {verdict}, expected proved; incomplete {codes}")
    if incomplete:
        sys.exit(f"expected an empty incomplete[], got {codes}")
'; then
        echo "FAIL $name (MCP)" >&2
        status=1
        return
    fi

    echo "ok $name (MCP)"
}

check_mcp "abs-int-buggy.c" "$root/tests/fixtures/abs-int-buggy.c" buggy
check_mcp "abs-int-fixed.c" "$root/tests/fixtures/abs-int-fixed.c" fixed

exit "$status"
