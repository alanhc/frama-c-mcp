#!/usr/bin/env bash
# getGoalCacheStats reports which goals WP replayed from its proof cache.
#
# The server protocol cannot answer this: wpApi sends a goal's summary, tactics,
# proved and total, and the "(Cached)" word in that summary is printed for every
# cacheable goal whenever the cache mode is updating, hit or miss. The flag that
# means a replay sits on the prover result, which this request reads.
#
# Two runs over one cache directory: the first fills it, so no goal is replayed,
# and the second replays what the prover discharged.
set -euo pipefail

FC="${FRAMA_C:-$(command -v frama-c || echo ~/.opam/frama/bin/frama-c)}"
if [ ! -x "$FC" ]; then
    echo "SKIP - no frama-c on PATH"
    exit 2
fi

# run() changes directory, so retain a usable executable when FRAMA_C was a
# relative path supplied by a caller.
FC="$(cd "$(dirname "$FC")" && pwd)/$(basename "$FC")"

# The fixture owns its cache. Ambient WP/session/developer settings make a cold
# run non-cold and invalidate the provenance assertion.
unset FRAMAC_WP_CACHE FRAMAC_WP_CACHE_DIR FRAMAC_WP_SESSION \
    FRAMAC_SESSION FRAMAC_DEVONLY_OPTIONS FRAMAC_DEVONLY_OPTIONS_WP

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp "$HERE/cache-provenance.c" "$WORK/"
cat > "$WORK/batch.json" << 'JSON'
[ {"kind":"GET","id":"stats","request":"plugins.ast-utils.getGoalCacheStats","data":{"goals":[]}} ]
JSON

run()
{
    (cd "$WORK" && "$FC" -load-module ast_utils_plugin \
        -wp -wp-model Typed+nocast -wp-prover alt-ergo -wp-timeout 5 \
        -wp-cache update -wp-cache-dir "$WORK/cache" cache-provenance.c \
        -then -server-batch batch.json -server-batch-output-dir . > /dev/null 2>&1)
    cp "$WORK/batch.out.json" "$WORK/$1.json"
}

run cold
run warm

python3 - "$WORK/cold.json" "$WORK/warm.json" << 'PY'
import json, sys

fails = []


def rows(path):
    data = {row.get("id"): row for row in json.load(open(path))}
    stats = (data.get("stats", {}).get("data") or {}).get("result")
    if stats is None:
        fails.append(f"{path}: no result payload")
        return []
    if stats.get("unknown"):
        fails.append(f"{path}: unknown goal ids {stats['unknown']}")
    return stats.get("goals") or []


cold, warm = rows(sys.argv[1]), rows(sys.argv[2])
if not cold:
    fails.append("the cold run reported no goal")
if any(goal.get("best_result_cached") for goal in cold):
    fails.append(f"a goal was replayed on a cold cache: {cold}")
if not any(goal.get("best_result_cached") for goal in warm):
    fails.append(f"no goal was replayed on a warm cache: {warm}")
for goal in cold + warm:
    for field in ("wpo", "best_prover", "cached", "cacheable"):
        if field not in goal:
            fails.append(f"goal is missing {field}: {goal}")

if fails:
    print("FAIL: getGoalCacheStats")
    for fail in fails:
        print("  -", fail)
    raise SystemExit(1)
print("PASS: getGoalCacheStats reports cold and warm cache provenance")
PY
