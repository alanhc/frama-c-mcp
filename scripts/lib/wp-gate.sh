# Shared by the Frama-C fixture gates. Sourced, never run.
#
# Mechanics only. Each gate keeps its own version case, prover pin and expected
# counts: tests/unit/repo-guards.rs reads the version case out of every gate to
# compare it with the CI matrix, and a count is a fact about one fixture. What
# moved here is what four copies had let drift apart: one gate read the prover
# version off any line of output and another off WP's summary row, the gates
# worded the same failures four ways, and they disagreed on whether a missing
# release binary fails CI.

wp_gate_binary="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/target/release/frama-c-mcp"
wp_gate_prover_seen=0

# wp_gate_frama_c_version FRAMA_C LABEL
#
# Prints the Frama-C version number. A failing -version prints FAIL with its
# output and returns 1, because under set -e a bare command substitution exits
# with no message at all.
wp_gate_frama_c_version()
{
    local frama_c="$1"
    local label="$2"
    local out
    if ! out="$("$frama_c" -version 2>&1)"; then
        echo "FAIL $label: $frama_c -version failed" >&2
        printf '%s\n' "$out" >&2
        return 1
    fi
    printf '%s\n' "$out" | awk '{print $1; exit}'
}

# wp_gate_expect_counts LABEL OUTPUT EXPECTED
#
# Returns 0 when the last "Proved goals: P / T" line of a WP run reads EXPECTED,
# written "P / T". Otherwise, a missing summary included, prints FAIL with the
# whole output and returns 1.
wp_gate_expect_counts()
{
    local label="$1"
    local out="$2"
    local expected="$3"
    local counts
    counts="$(printf '%s\n' "$out" \
        | sed -nE 's/.*Proved goals:[[:space:]]*([0-9]+)[[:space:]]*\/[[:space:]]*([0-9]+).*/\1 \/ \2/p' \
        | tail -1)"
    [[ "$counts" == "$expected" ]] && return 0
    echo "FAIL $label: expected $expected, got ${counts:-no summary line}" >&2
    printf '%s\n' "$out" >&2
    return 1
}

# wp_gate_check_prover LABEL OUTPUT EXPECTED
#
# Compares the Alt-Ergo version on WP's per-prover summary row with EXPECTED,
# such as "Alt-Ergo 2.6.3".
#
# Returns 0 when they match or when the run printed no such row, and 1, with a
# FAIL, when they differ. A run that names a version sets wp_gate_prover_seen,
# which wp_gate_require_prover_seen reads.
#
# Anchored to that row: a Why3 warning elsewhere in the output can name a
# different version, and that is not the prover whose verdicts the counts
# record. The row is printed only for a prover that discharged a goal, so a run
# Qed closes alone, or whose Alt-Ergo goals all time out, names none.
wp_gate_check_prover()
{
    local label="$1"
    local out="$2"
    local expected="$3"
    local seen
    seen="$(printf '%s\n' "$out" \
        | sed -nE 's/^[[:space:]]*(Alt-Ergo [0-9]+\.[0-9]+\.[0-9]+):.*/\1/p' \
        | tail -1)"
    [[ -z "$seen" ]] && return 0
    wp_gate_prover_seen=1
    [[ "$seen" == "$expected" ]] && return 0
    echo "FAIL $label: prover is $seen, the counts were measured under $expected" >&2
    return 1
}

# wp_gate_require_prover_seen LABEL EXPECTED
#
# A silent pin is not a pin.
#
# Returns 1, with a FAIL, when no run checked by wp_gate_check_prover named a
# version, since then nothing was compared and the counts are unattributed.
wp_gate_require_prover_seen()
{
    [[ "$wp_gate_prover_seen" -eq 1 ]] && return 0
    echo "FAIL $1: no run reported a prover version, so $2 went unverified" >&2
    return 1
}

# wp_gate_mcp_ready LABEL
#
# Returns 0 when the release binary is built. Otherwise prints SKIP and returns
# 1, except under CI, where it prints FAIL and exits the gate: CI builds the
# binary before any fixture gate runs, so its absence there is a broken lane,
# and a skip would be a gate that passes by not running. Call it directly, not
# in a command substitution, or the exit leaves only the subshell.
wp_gate_mcp_ready()
{
    [[ -x "$wp_gate_binary" ]] && return 0
    if [[ -n "${CI:-}" ]]; then
        echo "FAIL $1 (MCP): $wp_gate_binary not built and CI is set" >&2
        exit 1
    fi
    echo "SKIP $1 (MCP): $wp_gate_binary not built" >&2
    return 1
}

# wp_gate_mcp_check FRAMA_C FILE
#
# Runs check on FILE and prints its JSON payload, returning check's status.
#
# Against a WP cache that holds nothing yet. check has no cache option and runs
# WP in update mode, so it would replay whatever the cache already has. Measured
# on 33.0 with -wp-cache-print, four variables move that cache away from
# .frama-c/wp/cache in the working directory: FRAMAC_WP_CACHEDIR names it,
# FRAMAC_WP_SESSION and FRAMAC_SESSION name a session directory holding it, and
# FRAMAC_DEVONLY_OPTIONS_PRE and _POST pass options, -wp-cache-dir among them.
# FRAMAC_CACHE, FRAMAC_STATE and FRAMAC_CONFIG do not. So this unsets every
# FRAMAC_WP_ variable, the session and the injected options, and runs from an
# empty directory made for the call. The rest of FRAMAC_ stays: FRAMAC_LIB,
# FRAMAC_SHARE and FRAMAC_PLUGIN are how an installation finds the plug-in.
#
# The server's own settings go too. FRAMAC_PROVERS, FRAMAC_TIMEOUT and
# FRAMAC_PAR are its defaults for WP, so a caller's FRAMAC_PROVERS=z3 had the
# MCP half proved by Z3 under a gate that had just pinned Alt-Ergo, and one
# naming an uninstalled prover failed as WP_NOT_RUN, which reads as a broken
# fixture. FRAMA_C_MCP_STATE_DIR would put the server's state outside the
# directory made for it.
#
# The traps remove that directory on an interrupt as well as on return, by
# turning a signal into an exit so the EXIT trap is the one place that cleans.
# FRAMA_C is made absolute before the cd, since a relative path names nothing
# from inside the new directory.
#
# stdout only. check prints JSON there, and folding stderr in would turn any
# future log line into a parse failure reported as a fixture regression. Its
# stderr still reaches the gate's log.
wp_gate_mcp_check()
(
    frama_c="$1"
    file="$2"

    if [[ "$frama_c" == */* ]]; then
        frama_c="$(cd "$(dirname "$frama_c")" && pwd)/$(basename "$frama_c")" || exit 1
    fi

    workdir="$(mktemp -d)" || exit 1
    trap 'rm -rf "$workdir"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    local var
    for var in $(compgen -e); do
        if [[ "$var" == FRAMAC_WP_* ]]; then
            unset "$var"
        fi
    done
    unset FRAMAC_SESSION FRAMAC_DEVONLY_OPTIONS_PRE FRAMAC_DEVONLY_OPTIONS_POST
    unset FRAMAC_PROVERS FRAMAC_TIMEOUT FRAMAC_PAR FRAMA_C_MCP_STATE_DIR
    cd "$workdir" || exit 1
    "$wp_gate_binary" --frama-c "$frama_c" check "$file"
)
