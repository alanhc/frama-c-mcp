# WP cache provenance: what `from_cache` can honestly claim

Status: **implemented**, 2026-09-16, as option C. Decision 1 was reopened when a
fourth review found the chosen signal wrong for tactic-proved goals (2.7) and an
existing WP request the options had missed (2.6), and closed again on the
measurement recorded there. No code has changed.

## 1. Problem

Every goal the server returns carries `from_cache`, documented in README
("Proof evidence"), docs/writing-acsl.md and CLAUDE.md as "a verdict replayed
from an earlier run rather than one this run computed". The receipt, the
coverage evidence and the replay triage all consume it.

It does not mean that. Measured 2026-09-14 on Frama-C 33.0 with
`tests/fixtures/svcomp-loop-lit.c`: `check` run from an empty working
directory (`check` with its defaults: `Typed+nocast`, Alt-Ergo, no RTE
guards, cache mode `Update`) reports `from_cache: true` on both Alt-Ergo
goals, while that directory's `.frama-c/wp/cache` afterwards holds exactly two
entries, both written by that same run, and `check` issues one `run_wp`. The
number of entries depends on the options: plain `frama-c -wp -wp-rte
-wp-cache update` on the same fixture writes five, because the RTE guards add
three more goals that reach Alt-Ergo.

## 2. Research

### 2.1 Where the word comes from (verified in source)

All paths under the opam switch's `lib/frama-c-wp/core/`.

- `Stats.ml`, `pp_stats`: when the cache is active and a goal has cacheable
  prover results, it prints `" (Cached)"` if `updating || cachemiss = 0`, and
  `" (Cached n/m)"` otherwise. In updating modes it never consults whether
  anything was read; in `Replay` and `Offline` the `n/m` form does reflect
  misses, which is what option B relies on.
- `Cache.ml`, `is_updating`: true for `Update`, `Rebuild` and `Cleanup`.
- `Cache.ml`: in `Rebuild` the lookup always misses, so nothing is ever
  replayed, yet the summary still says `(Cached)`.
- `VCS.ml` / `Cache.ml`: for a prover result, only a real hit yields
  `cached = true`; a freshly proved result is stored with `cached = false`.
  `Stats.stats` sums these into `cached` and `cacheable` (`Stats.mli`). This
  does not hold for the synthetic result WP stores for a tactic proof (2.7).
- `wpApi.ml`, module `STATS`: the goal list's stats record carries only
  `summary`, `tactics`, `proved` and `total`. `cached` and `cacheable` are
  dropped there. The per-result record, module `Result`, does carry each
  result's `cached` flag, and stock requests return it (2.6, option D). The summary string is rendered **at query time** with
  `Cache.get_mode ()`, so it describes the cache mode set when goals are
  fetched, not the mode under which the verdict was obtained.

So in the default `Update` mode the word is printed for every
prover-discharged goal, hit or miss. The server's reading, "`(Cached)` in the
summary means replayed" (`src/mcp/wpclass.rs`, `summary_says_cached`), is
therefore wrong in exactly the mode almost every call runs in.

### 2.2 Plain Frama-C runs (verified)

Same fixture, `frama-c -wp -wp-model Typed+nocast -wp-prover alt-ergo
-wp-cache <mode>`, no `-wp-rte`, fresh directory. The `cached` column is from
`-wp-report-json`. The summary column is the shape of the goal stats summary
as `pp_stats` renders it, with prover times omitted: over the protocol it
reads, for example, `(Qed 4ms) (Alt-Ergo 17ms) (Cached)`. The report itself
has no summary field.

| Run | WP hit/miss | Summary shape on the Alt-Ergo goals | `cached` in `-wp-report-json` |
|---|---|---|---|
| update, empty cache | `updated:2`, 0 hits | `(Alt-Ergo) (Cached)` | 0 |
| update again | `found:2` | `(Alt-Ergo) (Cached)` | 1 |
| rebuild | `updated:2` | `(Alt-Ergo) (Cached)` | 0 |
| replay | `found:2` | `(Alt-Ergo) (Cached)` | 1 |

The summary is identical across all four; only the `cached` count separates a
replay from a computation.

### 2.3 What is not the cause (verified)

- The server does not prove twice: `start_wp_proofs` sends one `startProofs`
  per marker, and `retry_timed_out_goals` is inert unless `retry_unproved`.
- No two goals share a VC in the fixture: 0 hits, 2 misses, 2 entries.

### 2.4 Why the existing tests did not catch it

- `tests/unit/acsl-shapes.rs`, `a_replayed_verdict_is_marked_from_cache`,
  asserts that a `(Cached)` summary means replayed, and uses
  `(Qed 39ms) (Alt-Ergo 41ms)` as its "fresh" example. That summary is only
  produced with the cache off; an `Update` run never prints it. **The test
  encodes the defect.**
- `tests/test-mcp-stdio.rs`, `a_replayed_wp_verdict_is_reported_as_one`,
  checks that `None` yields no `true` and that a later `Update` yields *some*
  `true`. The second half passes whether or not anything was replayed,
  because a fresh `Update` also says `(Cached)`.

### 2.5 Where the cache lives (verified)

WP's cache defaults to `.frama-c/wp/cache` under the working directory.
Measured with `frama-c -wp -wp-cache-print`, each variable set alone:

| Variable | Cache directory |
|---|---|
| none | `.frama-c/wp/cache` |
| `FRAMAC_SESSION=/s` | `/s/wp/cache` |
| `FRAMAC_WP_SESSION=/w` | `/w/cache` |
| `FRAMAC_WP_CACHEDIR=/c` | `/c` |
| `FRAMAC_DEVONLY_OPTIONS_PRE="-wp-cache-dir /d"` (and `_POST`) | `/d` |
| `FRAMAC_CACHE`, `FRAMAC_STATE`, `FRAMAC_CONFIG` | unchanged |

The MCP server's Frama-C inherits the environment, so each of these reaches
`check`. Any test that needs an empty cache must control the working directory
and all five variables. It cannot simply clear every `FRAMAC_` variable:
`FRAMAC_LIB`, `FRAMAC_SHARE` and `FRAMAC_PLUGIN` locate the installation and
the plug-in. scripts/lib/wp-gate.sh does exactly this, unsetting every
`FRAMAC_WP_` variable, `FRAMAC_SESSION` and both `FRAMAC_DEVONLY_OPTIONS_`
variables.

The set was found one variable at a time, which is worth recording. An earlier
measurement concluded `FRAMAC_WP_CACHEDIR` had no effect, having judged it by
the `(Cached)` word this document shows to be meaningless; three later reviews
each found one more route. The table above is the measurement that should have
come first.

### 2.6 Options

| Option | Signal | Default mode (`Update`) | Cost |
|---|---|---|---|
| A. Keep reading the summary | word | wrong (always `true`) | none |
| B. Read the summary, mode-aware | word + mode at query | unknown | server only |
| C. Plug-in exports the verdict's own cache flag per goal | WP's `VCS.result.cached` | exact for prover results, wrong for tactic results (2.7) | plug-in request + server |
| D. Read each result's flag through stock WP requests | WP's `VCS.result.cached`, same data as C | as C | server only, plus a proof tree per goal |

B can say `false` under `None`/`Rebuild` (verified: never replay) and read
`(Cached)` versus `(Cached n/m)` under `Replay`/`Offline`, where the
distinction is printed, but must say "unknown" under `Update`/`Cleanup`. It
leaves the default mode undecided and still depends on the query-time mode.

D was missed by the first three drafts. `wpApi.ml`, module `Result`,
serialises each prover result with its `cached` flag, and
`plugins.wp.tip.getNodeInfos` (`wpTipApi.ml`) returns
`Wpo.get_results` for a proof node's goal; the node for a goal is reached
through `plugins.wp.tip.getProofStatus`, and `plugins.wp.tip.getResult`
returns one prover's result. So the flag C would export is already on the
wire, and the choice between C and D is not about data but about cost and
shape:

- D needs no plug-in change and no 32.1 check. But `getProofStatus` calls
  `ProofEngine.proof ~main`, which builds and keeps a proof tree for each goal
  asked about, and it is one request per goal rather than one per fetch.
  Neither the memory kept nor the latency on a file with hundreds of goals has
  been measured.
- C is one batched request and reads results without building trees, at the
  price of a plug-in request and the 32.1 check.

Both read the same flag, so both inherit the tactic problem in 2.7.

**Recommendation: withdrawn** pending the measurement in section 6. C was
recommended while D was unknown; it is still the only candidate besides D that
answers in `Update`, and both replace a string match on free-form text, the
pattern CLAUDE.md already rejects for abort attribution.

### 2.7 Aggregate counts are not the verdict's provenance (verified)

The first draft proposed `from_cache = cached > 0`. That is not exact.
`Stats.cached` counts every cacheable prover result flagged as a hit
(`Stats.ml`, `add_cached`), while a goal's verdict is one result: the one
`VCS.best` selects from `Wpo.get_results`. A goal run with two provers can
hold a cached timeout from one and a fresh proof from the other, giving
`cached = 1` for a verdict computed in this run.

The flag on the selected result is exact for that result. `Cache.get_result`
marks a hit with `VCS.cached`, which sets `cached = true` only when the stored
result is a verdict (`VCS.is_verdict`), and a hit returns without running the
prover; a miss runs the prover and returns its fresh result unflagged. So:

```
best_result_cached wpo = (snd (VCS.best (Wpo.get_results wpo))).cached
```

This fails for a goal proved by tactics, so it cannot be the rule as
written:

- `ProofEngine.validate` stores the tree's consolidated verdict on the main
  goal as a synthetic result under `Prover.Tactical`, built by `Stats.script`,
  which sets `cached = (stats.cached = stats.cacheable)`
  (`ProofEngine.ml`, `Stats.ml`).
- When every subgoal closes in Qed, both counts are 0, so the synthetic result
  says `cached = true` although nothing was read. `VCS.best` prefers a valid
  result, so it selects that one, and the formula answers `true` for a proof
  computed in this run.
- `Wpo.get_results` returns whatever was last stored; `ProofEngine.results`
  (`ProofEngine.mli`) validates the tree first. Reading the former can return
  a stale `Tactical` result.

What the refinement must define, before either C or D is coded: a value for a
goal whose selected result is `Prover.Tactical`. The safe default is `null`
under decision 3, since the synthetic flag carries no provenance. A precise
answer would need the subgoals' own prover results, which is a further
request per node.

`Cache.promote` (`Cache.ml`) is not a problem: it discards a cached timeout
whose recorded limit is below the new one, so a raised timeout reruns the
prover and the fresh result is unflagged, which is the correct answer.

## 3. Architecture (option C, implemented)

This section records the implemented C design. The measurements in section 6
are historical rationale; they no longer leave the request name or design
choice open.

### 3.1 Core flow

```
run_wp / check
  -> WP proves (server protocol, unchanged)
  -> get_wp_goals / wp_goals_payload fetches goals (unchanged)
  -> NEW: one ast-utils request returns, for those goals,
          {wpo -> best_result_cached, cached, cacheable}
  -> enrich_goal_stable_id sets from_cache to true, false or null from
     best_result_cached, never from the summary
  -> consumers (receipt, coverage, replay triage) unchanged in shape
```

### 3.2 Module: ast-utils request

```
Function/module name: getGoalCacheStats

Function description: Report, per WP goal, whether the result that decides
its verdict was read from the cache, with the aggregate counts beside it as
diagnostics.

Preconditions (Requires):
  - WP is loaded in the Frama-C process.
  - Input is a list of wpo identifiers as the server protocol names them
    (the po_gid field, which wpApi uses as the "wpo" key).

Postconditions (Ensures):
  - For each input id that names a live goal:
      { wpo, best_result_cached, cached, cacheable } where
      best_result_cached = the cached flag of VCS.best over
      ProofEngine.results wpo, except that it is absent (reported as
      unknown) when the selected result is Prover.Tactical (2.7),
      and cached, cacheable come from Wp.ProofEngine.consolidated wpo,
      with 0 <= cached <= cacheable.
  - Ids naming no live goal are returned in a separate "unknown" list,
    never silently dropped and never given invented zeros.

Side effects: validates the proof tree through `ProofEngine.results` before
reading the consolidated statistics; it does not mutate proof results.
```

Reachability checked on 33.0: `ProofEngine.consolidated`, `Wpo.get_results`
and `VCS.best` are in the installed interfaces, and the plug-in already links
`frama-c-wp.core` (ast-utils/src/dune). **Not checked on 32.1**, because only
the 33 switch is installed locally, and CI's plugin-floor lane compiles the
plug-in against 32.1, so a missing symbol there blocks a release. Refinement
must confirm those three names exist on 32.1 or add a version conditional of
the kind ast-utils/src already carries, before any code is written.

### 3.3 Module: server

```
Function/module name: from_cache derivation (src/mcp/wpclass.rs)

Function description: Decide whether a goal's verdict was replayed.

Preconditions (Requires):
  - The goal record has passed through enrich_goal_stable_id.

Postconditions (Ensures):
  - from_cache = true   iff best_result_cached is true for that goal.
  - from_cache = false  iff best_result_cached is false.
  - from_cache = null   when it could not be obtained (plug-in too old,
    request failed, goal in the unknown list). Present on every goal, never
    absent.
  - goal_is_from_cache becomes three-valued (true, false, unknown), and the
    summary string is no longer read in any mode.

Invariants:
  - An unknown answer is never counted as fresh, as replayed, or as evidence
    in replay triage.

Side effects: one plug-in request per goal fetch (see the interface below).
```

```
Interface: server -> ast-utils (getGoalCacheStats)

Input data: list of wpo ids from the goals just fetched.
Output data: [{wpo, best_result_cached, cached, cacheable}], unknown: [wpo].

The agreement stipulates:
  - Caller sends only ids it received from the goal fetch.
  - Callee returns every id in exactly one of the two lists, and counts
    satisfying 0 <= cached <= cacheable.
  - Caller issues one request per goal fetch, not one per goal.
```

### 3.4 Key decisions

- **`null` for unknown, not absent.** The first draft proposed omitting the
  field. Today the two are equally unsafe: `goal_is_from_cache` falls back to
  reading the summary for a missing field and for `null` alike (`wpclass.rs`),
  and `coverage.rs` counts anything but `true` as fresh. `null` is the better
  choice only together with the 3.3 change, which stops that fallback. `null` keeps the field
  stable in every goal and in the receipt, and says "unknown" in the one
  place a reader looks. Every consumer is changed to handle three states.
- **Keep `from_cache` as the field name; its type widens to a nullable
  boolean.** The receipt schema in docs/architecture.md gains the `null`
  value, and the receipt's hash changes for runs whose value changes, which is
  the point.
- **Fix the documentation first** (workflow §6.3): README "Proof evidence",
  docs/writing-acsl.md, CLAUDE.md's WP-cache constraint and the doc comment on
  `goal_is_from_cache` all state the wrong meaning today.

## 4. Tests

- **Replace** `a_replayed_verdict_is_marked_from_cache`
  (tests/unit/acsl-shapes.rs), because its assertion is the defect (§2.4).
  New cases: `best_result_cached: false` gives `false` even with `cached: 1`
  beside it; `best_result_cached: true` gives `true`; a goal with no answer
  gives `null`; an `Update`-mode `(Cached)` summary never gives `true`.
- **Strengthen** `a_replayed_wp_verdict_is_reported_as_one`
  (tests/test-mcp-stdio.rs) to three states, against a cache directory the
  test owns (the working directory and every variable in section 2.5):
  `None` gives `false` on every goal; a first `Rebuild` gives `false` on
  every goal; a following `Update`, which now replays what `Rebuild` stored,
  gives `true` on the prover-discharged goals. The `Rebuild` step fails today.
- **Pin the tactic case**: a goal proved by a tactic whose subgoals all
  close in Qed gives `from_cache: null`, not `true` (2.7).
- **Unit-test the unknown state**: a goal whose request failed carries
  `from_cache: null`, and coverage and replay triage count it in neither the
  fresh nor the replayed bucket.
- **Add** a `dune runtest` case in ast-utils for the new request, including an
  unknown id, and a 32.1 compile of it through the plugin-floor lane.
- **Consider** asserting `from_cache` in `wp_gate_mcp_check`
  (scripts/lib/wp-gate.sh) once it is trustworthy. Not required; the isolated
  cache there stays correct.

## 5. Consumers whose behaviour changes

Read, not yet traced to every branch; the refinement stage must.

- `src/mcp/wpclass.rs`: `REPLAYED_GOAL_REASON`, `replayed_goal_triage`, the
  replay counts. Today a timeout proved in this run is labelled "not attempted
  on this run".
- `src/mcp/coverage.rs` (replayed evidence; today any non-`true` value counts
  as fresh), `src/mcp/receipt.rs` (`from_cache` in the receipt, which gains a
  `null` value and must be reflected in the receipt schema in
  docs/architecture.md).
- `src/mcp/analysis.rs`, the comment on the timed-out retry path, cites a goal
  "reading from_cache" as evidence that a retry replays the timeout. That
  evidence is void under §2.1; the claim needs re-measuring, noting that
  `Cache.promote` discards a cached timeout when the new time limit is higher.

## 6. Decisions

Decided 2026-09-15, after an independent review re-checked section 2 against
the WP sources and corrected the first draft where the sections cited say.
Decision 1 reopened 2026-09-16 (see the status line).

1. **Option C, decided on measurement (2026-09-16).** D was measured on
   `tutorial/verker-string.c`, 42 goals, over a Frama-C server started directly
   with `-wp-rte -wp-model Typed+nocast -wp-prover alt-ergo` and cache mode
   `Update`, twice against one `FRAMAC_WP_CACHEDIR`:

   | Run | WP proof | `getProofStatus` + `getNodeInfos` for every goal | RSS before / after | goals with a cached result |
   |---|---|---|---|---|
   | cold cache | 6.8 s | 4.2 s, 100 ms per goal | 163.6 / 163.6 MB | 0 |
   | warm cache | 1.3 s | 4.2 s, 100 ms per goal | 161.9 / 161.9 MB | 18 |

   The flag D reads is exact: no goal cold, the 18 prover-discharged goals warm
   (the other 24 close in Qed and are not cacheable). The proof trees cost no
   measurable memory. The latency is the objection: two round trips per goal
   add 4.2 s to a fetch whose warm proof took 1.3 s, on every goal fetch, and it
   grows with the goal count. C answers the same flag for every goal in one
   request. D remains the fallback if C cannot reach the flag on 32.1. Either
   way a `Prover.Tactical` selected result gives `null` (2.7).
2. Replace `a_replayed_verdict_is_marked_from_cache`, whose assertion is the
   defect (the exception workflow §1.2 allows): 2.4, 4.
3. `null` for unknown, handled as a third state by every consumer: 3.3, 3.4.
4. One batched request per goal fetch: the interface in 3.3. Applies to C;
   D is one request per goal by construction.
5. Frama-C 32.1 is checked before code: 3.2. Applies to C only.
6. The stdio test proves three states against a cache it owns: 4.

Still open, for the refinement stage rather than for confirmation: the
request's final name under C, and whether a tactic-proved goal can be given a
precise answer from its subgoals' results instead of `null` (2.7).

## 7. As implemented

- **Plug-in**: `plugins.ast-utils.getGoalCacheStats` takes `goals`, a list of
  `wpo` identifiers where an empty list means every goal, and answers
  `{goals: [{wpo, best_result_cached, best_prover, cached, cacheable}], unknown: [...]}`.
  `best_result_cached` is the `cached` flag of the result `VCS.best` selects
  over `ProofEngine.results`, and `null` when that result is the synthetic one
  WP stores for a tactic proof. The prover type moved out of `VCS` in Frama-C
  33, so the module carries cppo arms like the two in `ast_utils`; the 32.1 arm
  was written against that switch's own interfaces (`VCS.Tactical`,
  `VCS.name_of_prover`), which is as far as this machine could check, because
  its 32.1 switch holds a Frama-C built with another OCaml and compiles
  nothing.
- **Server**: `fetch_wp_goals` replaces every goal fetch, adding one request
  per fetch and writing `from_cache` on each goal. Every one: the
  `want: ["vc"]` path in `wp_goal_details_payload` still called `reload_fetch`
  directly until 2026-09-16, so goals read one at a time were the single place
  a caller could not tell a replayed verdict from a computed one, while the
  surrounding prose already claimed otherwise. `goal_is_from_cache` returns
  `Option<bool>`; `coverage.rs` counts `null` as neither fresh nor replayed,
  and the receipt carries the three values.
- **Measured through the server**: `Rebuild` reports nothing replayed, a second
  session over the same cache reports the prover-discharged goals replayed, and
  a run with the cache off reports nothing replayed.
- **Tests**: `run-cache-provenance.sh` in the plug-in's `dune runtest` (cold
  then warm over one cache directory), `from_cache_is_three_valued_and_ignores_the_summary`
  replacing the unit test that asserted the old reading, and
  `a_replayed_wp_verdict_is_reported_as_one` rewritten over three sessions,
  since WP does not re-prove a goal that is already valid and so replays
  nothing within one session.
