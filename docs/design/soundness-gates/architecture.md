# Soundness gates learned from acsl-skills

Status: **implemented**, 2026-09-17, except section 3.6, which was reverted
after measurement. Source of the ideas: the acsl-skills skillset
(https://github.com/evdenis/acsl-skills, MIT), whose `wp.sh` treats a set of
WP messages as "proved is not evidence" and whose definition of done requires
RTE with the unsigned checks, smoke tests, and no silent-tier message.

## 1. Problem

`check` answers `proved` exactly when `incomplete[]` is empty
(`src/mcp/analysis.rs`, the verdict line after `check_next_call`).
`incomplete[]` is built from goal records, property statuses and a few
message classifiers. Measured on Frama-C 33.0 through the release binary,
2026-09-16, every row below answered `proved` with an empty `incomplete[]`:

| Probe | What WP did | Where the evidence was |
|---|---|---|
| statement contract with a false `requires` | dropped the contract | WARNING "Statement specifications not yet supported (skipped)." in `messages[]` only |
| statement-level `invariant x == n + 7` | dropped the invariant | WARNING "Generalized invariant not yet supported (skipped)." |
| union written through one member, false property about another | proved it | WARNING "Accessing union fields with Typed model might be unsound." |
| undefined logic function with labels, false frame property | proved it | WARNING "No definition for 'val' interpreted as reads nothing" |
| `check --function f` where `f` has a caller, false `ensures` | generated no goal for it | ERROR "Main entry point function 'f' is (potentially) recursive. This case is not supported yet (skipped verification)." |
| dead branch EVA cannot see, false property inside it | proved it | nothing: only WP smoke tests find it |

Two more gaps, measured the same day:

- `rte: true` never checks unsigned wraparound or narrowing. Frama-C 33
  defaults `-warn-unsigned-overflow` and `-warn-unsigned-downcast` to off,
  and nothing in `src/` sets them. `unsigned sub(unsigned a, unsigned b) {
  return a - b; }` gets zero RTE goals, and four with both options on.
- A callee declared with neither code nor specification gets a contract the
  kernel invents (`annot:missing-spec`: "Neither code nor specification for
  function ext, generating default exits, assigns and terminates"). It
  assumes termination and derives `assigns` from pointer parameters only,
  never globals. `ASSUMED_CALLEE_CONTRACT` does not fire, because the invented
  `assigns` is finite.

## 2. Research

### 2.1 What the server can reach (verified)

`frama-c -server-doc` on 33.0 lists setters for everything needed on the
running process. The setters remove no need for the separate command-line
evidence probes: smoke tests and memory-model hypotheses are deliberately
measured in fresh processes:
`kernel.parameters.setWarnUnsignedOverflow`,
`kernel.parameters.setWarnUnsignedDowncast`,
`kernel.parameters.setWpSmokeTests`, `kernel.parameters.setWpSplit`,
`kernel.parameters.setWpSplitConj`.

The messages in section 1 all reach the socket drain `check` already reads
(`messages[]`), with `plugin: "wp"` or `"kernel"`, a `kind`, and the text
quoted above. This matters because not every WP message does: the
memory-model hypotheses are batch-only, which is why
`WP_MEMORY_MODEL_HYPOTHESIS` needs a separate process.

### 2.2 Impact of unsigned checks on this repository (measured)

Goal counts with `-wp-rte` versus `-wp-rte -warn-unsigned-overflow
-warn-unsigned-downcast`, `Typed+nocast`, Alt-Ergo 2.6.3, `-wp-timeout 5`,
`-wp-cache none`, over all 55 fixtures under `tests/fixtures`:

| Fixture | Without | With |
|---|---|---|
| `tutorial/ghost-code.c` | 20 / 20 | 21 / 21 |
| `tutorial/loops.c` | 46 / 46 | 48 / 48 |
| `tutorial/sort-permutation.c` | 33 / 33 | 34 / 34 |
| `tutorial/count-logic.c` | 13 / 15 | 15 / 17 |
| `uninterpreted-operator.c` | 3 / 6 | 4 / 9 |
| `tutorial/eva-rotate.c` | 5 / 6 | 6 / 10 |
| `tutorial/verker-string.c` | 31 / 42 | 33 / 45 |

The other 48 fixtures are unchanged. No fully proved fixture loses its
proof; the new unproved goals are unsigned idioms (`align_up`, `rotateLeft`,
verker's `kmemset` and `kstrlen`), which is the kernel-idiom carve-out
acsl-skills documents in `verifiable-c/references/hostile-c.md`. The shell
gates run plain `frama-c` without these options, so their pinned counts do
not move.

### 2.3 Resetting the entry point after EVA (measured, adopted)

`check --function f` sets `-main f` for EVA, and it used to stay set for WP.
The first measurement, `frama-c -main f -eva m.c -then -main main -wp`, showed
EVA's division alarm surviving the reset and reported `Proved goals: 7 / 7` on a
function whose `ensures \result == 42` is false for `100 / n`. That looked like
a hole and the reset was held back. It was not one: EVA had given that
postcondition a status, and WP emits no goal for a property that already has
one, so the 7 goals simply did not include it, and `check` reports such a
property through its own codes.

Measured through the server on 2026-09-16, with the entry point set back to
`main` in `check_wp_step` before WP, over five scoped checks: a false
postcondition on a function with a caller becomes a failing goal instead of a
skipped function; a scoped function's own `requires` stops being an
obligation; EVA's division alarm survives beside the `ensures` goal; and an
axiom and an unproved lemma in scope are still reported. Adopted, with
`a_scoped_check_proves_a_function_that_has_callers` pinning it.

## 3. Architecture

### 3.1 WP message gates

Five codes, four derived from `messages[]` after the WP step and one from the
run's memory model, added in `check_payload` next to `WP_BACKEND_ANOMALY`:

```
Function/module name: wp_message_gaps (src/mcp/checkgaps.rs)

Function description: Turn WP messages that mean part of the requested work
was skipped, dropped, or encoded unsoundly into incomplete[] entries, and add
the model's own weakenings.

Preconditions (Requires):
  - messages is the drain of the WP step of this check call.
  - model is the run's effective memory model, or None when it is unknown.

Postconditions (Ensures):
  - WP_VERIFICATION_SKIPPED for each message with plugin "wp", kind ERROR,
    whose text contains "skipped verification" (non-natural loop, recursive
    entry point).
  - WP_ANNOTATION_SKIPPED for each message with plugin "wp" whose text
    contains "not yet supported (skipped)" (statement contracts, generalized
    invariants).
  - WP_UNSOUND_ENCODING for each message with plugin "wp" whose text contains
    "might be unsound" or "interpreted as reads nothing".
  - GENERATED_CALLEE_SPEC for each message with plugin "kernel", category
    "annot:missing-spec", whose text contains "Neither code nor specification
    for function". This one is a kernel message, not a WP message: the
    invented contract is what WP then proves against.
  - One entry per code and first message line, carrying the full text and
    every distinct source location it was printed at (WP repeats the union
    warning at each access).
  - WP_WEAKENED_MODEL once, from model alone and not from any message, when
    weakening_model_selectors(model) is non-empty, naming those selectors.
  - No entry for any other message.

Side effects: none.
```

The strings are matched as WP 33.0 prints them, quoted in section 1. A
future WP that rewords one would stop matching and fail open; the fixture
tests in section 5 are what notice.

### 3.2 Unsigned RTE checks

- Unsigned checks are part of what `rte: true` means, with no separate switch.
  Every load sets `kernel.parameters.setWarnUnsignedOverflow` and
  `setWarnUnsignedDowncast` to `rte && !unsigned_rte_skipped` before any analysis, and
  every command-line path that passes `-wp-rte` for a load that asked for
  unsigned checks passes both options beside it (`UNSIGNED_RTE_OPTIONS`, via
  `unsigned_rte_args`). The sandbox spawn, which uses kernel `-rte`, carries
  them too.
- They are set at load rather than where WP generates guards, because they
  also decide which alarms EVA emits, and `check` runs EVA before WP: set
  where guards are generated, a second `check` in one session would report
  unsigned alarms the first did not (reasoned from the call order, not
  measured).
- **The predicate is both halves, and the load's `rte` rather than the
  caller's.** `unsigned_rte_args` read `unsigned_rte_skipped` alone until it
  was measured on 2026-09-16, which is not the same question: `run_wp`
  generates WP's guards in place even for a load that declined `rte`, so every
  command-line site sits inside its own `if rte` while the two kernel switches
  were decided at load time and are off. An `rte: false` load therefore handed
  the memory-model probe `-warn-unsigned-overflow -warn-unsigned-downcast`,
  giving that separate Frama-C run obligations the session it was probing did
  not have. It now asks `rte && !unsigned_rte_skipped`, the same predicate
  `reload_project` sets the switches by, which corrects all six call sites at
  once. Pinned by
  `run_wp_in_place_rte_follows_the_loads_unsigned_setting`, which asserts the
  probe's own command line as well as the run's.
- `frama_c_options` in the payload and the receipt records them, so two
  receipts differing only here are distinguishable.
- **Revised from the first draft**, which proposed an `rte_unsigned` parameter
  and an `RTE_REDUCED` code. The load options are destructured exhaustively
  across profiles, receipts and conclusion comparison, and a per-call switch
  would have touched all of them for a mode section 2.2 shows no fully proved
  fixture needs.
- **The opt-out, added after a second review.** `rte_unsigned: false` on
  `reload_project`, `check` or a verify profile sets
  `ProjectLoadOptions::unsigned_rte_skipped`, which every load setter and every
  command-line path built from the load's options reads, and `check` reports
  `RTE_REDUCED`. **The sandbox is the exception**, and it is the deliberate
  one: `sandbox_frama_c_command_line` passes kernel `-rte` with both unsigned
  options spelled in unconditionally, because a sandbox takes default project
  options rather than the main load's, and its memory-model probe is pinned to
  match that command line. So a project that set `rte_unsigned: false` still
  sees unsigned obligations inside a sandbox. Threading the flag through would
  have to move the probe's defaults in the same edit; it is recorded here as a
  known inconsistency rather than silently claimed to work.
  It lives in the
  load options after all, because it decides which obligations exist, and it
  is serialized only when set so that receipts made without it keep their
  digests.

### 3.3 Smoke tests

- `check` gains `smoke: bool`, default false, and `run_wp {smoke: true}` no
  longer requires `provers`. Either one runs a smoke probe beside the
  memory-model probe: a separate Frama-C over the same printed AST, with
  `-wp-smoke-tests -wp-cache none`, the run's model, RTE options and target
  functions, and the run's effective provers, parallelism and timeout, which
  it reports with its elapsed time. Over the printed AST rather than the files on disk, so annotations
  injected this session are part of what is tested; the old `run_wp {smoke,
  provers}` path proves the files on disk and silently leaves them out.
- **Revised from the first draft**, which set `-wp-smoke-tests` on the running
  process. That would race any other run on the main instance for the length
  of the step, and the probe process already exists for the memory model.
- The probe reports `{ran, passed, total, failed: [goal name]}`, parsed from
  WP's `[Failed] (Doomed) <goal>` lines and its `Smoke Tests: passed / total`
  summary (Frama-C 33.0 output, measured 2026-09-16). The line numbers WP
  prints refer to the printed AST, so they are not reported.
- `SMOKE_TEST_FAILED` for a probe that ran with any failed smoke goal:
  something in scope is unreachable or contradictory, so the goals around it
  prove for the wrong reason. `SMOKE_TEST_UNCHECKED` when smoke tests were
  requested and the probe did not run, so a requested check cannot vanish into
  a proved verdict. **And when the probe ran and WP printed no summary line**,
  which is not the same as a clean result: measured on Frama-C 33, a scope with
  no `requires`, no branch, no loop and no call makes WP generate no smoke goal
  and print no `Smoke Tests:` line at all, and so does a scope whose axiomatic
  carries `0 == 1`, which is exactly what smoke tests exist to catch. `passed`
  and `total` are null there rather than zero, and until 2026-09-16 the null
  was read as zero failures and reported nothing, which is why the entry now
  keys on a missing `total` rather than on a failure count.
- The `run_wp {smoke: true, provers}` isolated path keeps its behaviour and
  adds the same parsed `smoke` object to each attempt.
- **The probe is never narrowed by `prop`**, even when the proof run was. Smoke
  goals are synthetic and carry no property name, so every filter form removes
  all of them: measured on Frama-C 33 against a contradictory precondition, no
  filter reports `Smoke Tests: 0 / 1`, while a named property, an `@ensures`
  category and even `@smoke` each print no smoke line at all. Forwarding the
  run's filter therefore did not narrow the probe, it switched it off, and the
  vacuity it exists to find is exactly what makes the narrowed proof
  meaningless: under `prop: "@ensures"` on `smoke-vacuous.c` the run proves
  `impossible`'s postcondition, which holds only because its precondition
  cannot. The `-wp-fct` list is the scoping that survives. Pinned by
  `a_smoke_probe_does_not_forward_the_property_filter`, which replaced a test
  asserting the opposite.

### 3.3a A check narrowed by prop

- `CHECK_NARROWED_BY_PROP` whenever `check` requested WP and ran with `prop`, carrying the
  filter that was used. A narrowed check is not a verdict about the file, and
  no other entry in the list can say so: WP generates goals only for the
  selected properties, so the ones it skipped never become `GOAL_NOT_VALID` the
  way they do in a full run. Nothing downstream sees an absence.
- **Measured, and it was a false `proved`.** On
  `tests/fixtures/check-prop-narrowed.c`, whose `hard` assert will not
  discharge, `check {files}` reports `incomplete` with `GOAL_NOT_VALID` while
  `check {files, prop: "easy"}` reported **`proved` off zero goals**, having
  attempted nothing at all. The same file under `run_wp {prop}` proves the one
  selected goal, so the narrowing itself works; what was missing was the
  payload saying the verdict had been narrowed.
- EVA is what makes the zero visible rather than a smaller number: `check` runs
  EVA first, and a property EVA has already decided gets no goal from WP, so
  the ensures goals present before EVA are gone after it. The property keys are
  renumbered across that run as well (`#p15` became `#p14` on one measurement),
  which is why the selection is resolved after EVA rather than cached across
  it.
- It lives beside `RTE_REDUCED` in `withheld_by_request_gaps`, the two entries
  that answer "what did the caller decline" rather than "what did the analysis
  find". Pinned by `a_check_narrowed_by_prop_is_never_proved`.

### 3.3b Evidence that was not read

Three gates added on 2026-09-17, all answering "the analysis may not have
happened" rather than "the analysis found something". Each was a path where an
absence read as a clean result.

- **`WP_MESSAGES_TRUNCATED`** whenever `drain_messages` reports a short read.
  Four codes above are derived from the message stream and from nothing else,
  so an unread stream and a clean one produce the same empty list and the
  verdict came back `proved`. The drain already returned the flag and
  `check_payload` already put it in the payload; it simply never reached
  `incomplete[]`. Same fail-closed shape as
  `AST_PARSE_DIAGNOSTICS_UNAVAILABLE` uses for the sibling evidence source, and
  one entry covers every present and future message-derived gate.
- **A receipt from a `prop`-narrowed run is refused as conclusion evidence**,
  in `proof_receipt_evidence_error`. `check` reports the narrowing as
  `CHECK_NARROWED_BY_PROP`, but `store_conclusion` has its own gate whose
  completeness tests are `goals.len() == wp_summary.total` and "every goal is
  progress", and a narrowed receipt passes both trivially: `retain_selected_goals`
  drops the unselected goals before the receipt is written and the summary
  counts what is left. Measured: `run_wp {functions:["f"]}` stores, the same
  call with `prop:"two"` is refused. The refusal is on the receipt rather than
  at the caller, for the reason the vacuity paragraph beside it gives, so
  `store_conclusion` and the profile path both inherit it.
- **Smoke tests reach the isolated CLI route.** `check {smoke: true, provers}`
  runs WP through that route, whose two gates read `params.smoke` while `check`
  asks through `smoke_probe`, so no `-wp-smoke-tests` was passed and the call
  reported `SMOKE_TEST_UNCHECKED` with the reason "WP did not complete" --
  false, WP completed and the route ignored the request. `smoke_requested` is
  the predicate for "smoke was asked for at all", on both routes; which route
  runs the probe is decided by `provers` alone, before it is asked. A second
  predicate that folded `provers.is_none()` in answered identically wherever it
  was called, and was removed. The route now publishes
  a consolidated `smoke_probe` in the same shape the socket route does, so
  `smoke_test_gaps` reads one field either way, and `effective_wp_config.smoke`
  reports what actually ran. Measured on `smoke-vacuous.c`: `SMOKE_TEST_FAILED`
  naming the doomed goal, where the same call reported nothing before.

### 3.4 Invented callee contracts

`GENERATED_CALLEE_SPEC` for each kernel message in category
`annot:missing-spec` whose text says "Neither code nor specification" (the
wholly invented contract). The variant "Neither code nor explicit exits and
terminates", where the user wrote `assigns` but not termination, is not
gated: it is ubiquitous for extern prototypes with contracts, and the
`ensures` and `assigns` the caller relies on are the user's own.

### 3.5 Models that leave C semantics

`WP_WEAKENED_MODEL` when the effective memory model contains `+cast`, `+nat`
or `+real`, naming them. `frama-c -wp-h` describes these as unsafe pointer
casts, natural instead of machine integers, and real instead of IEEE
floating-point arithmetic. The server's own Why3-abort routing recommends
`Typed+cast`; the code keeps a proof obtained that way from reading like a
`Typed+nocast` one. First implemented for `+cast` alone as
`WP_UNSAFE_CAST_MODEL`, renamed before it was ever committed.

### 3.6 Split strategy (not implemented, measured)

The first draft proposed `run_wp {split: "none" | "split" | "conj"}` through
`kernel.parameters.setWpSplit` and `setWpSplitConj`. Implemented and measured
on 2026-09-16, it does not do what it would report. On
`ensures \result >= n && \result >= 0`, plain `frama-c -wp -wp-split
-wp-split-conj` yields four `ensures` parts. Over the server, a session whose
first run used `conj` got the four parts, but a session whose first run used
the default kept one `ensures` goal through a later `conj` run, and a default
run after a `conj` run still showed four parts while `split_strategy` said
`none`. WP applies the setting when a function's goals are first generated and
reuses them afterwards. An option whose recorded strategy can disagree with
the goals in front of the reader is worse than no option, so it was reverted.
Doing it properly needs the goals regenerated when the strategy changes, which
is a design question of its own; `split_strategy` stays null.

### 3.7 Self-check toolchain hint

When `frama-c` is missing, `self_check` lists the opam switches whose `bin`
holds a `frama-c` executable (`opam switch list --short`, then `opam var
--switch=S bin`), the resolution order acsl-skills' `env.sh` uses, and names
them in the install hint.

## 4. Key decisions

- **Gate on the message, not on the goal count.** acsl-skills' measurement
  that "a statement contract vanishes and the function reports 4/4 proved"
  holds here too; no goal-level signal exists for a dropped annotation.
- **Unsigned checks on by default.** Section 2.2 shows no fully proved
  fixture regresses, and the reduction is reported rather than silent.
- **Smoke tests opt-in in `check`.** They double WP's work on the scope; a
  definition of done in `docs/agent-playbook.md` asks for one run, which is
  the right cost model.
- **All new codes are blocking**, like every existing code, because each
  names something the verdict would otherwise overstate.

## 5. Tests

- A fixture per message gate (statement contract, generalized invariant,
  union, reads nothing), each with a false property that WP proves, and a
  stdio test that `check` is not `proved` and names the code.
- The `--function f` caller probe: `WP_VERIFICATION_SKIPPED`.
- `rte-unsigned.c`: unsigned overflow and downcast goals with `rte: true`, none
  with `rte: false`, and the options recorded in `frama_c_options`. One server,
  two loads, so a later `rte: false` load is shown to clear what an earlier
  `rte: true` load set, for EVA's alarms as well as WP's goals.
- Smoke fixture with a contradictory `requires`: `check {smoke: true}` raises
  `SMOKE_TEST_FAILED` naming the doomed goal; `check` without it runs no smoke
  probe; a clean function with `smoke: true` raises nothing.
- Invented contract fixture: `GENERATED_CALLEE_SPEC`; a prototype with a
  contract and no `terminates` does not raise it.
- Unit tests for the pure classifiers and for `incomplete_codes_match_their_documentation`
  picking up the new README rows.

## 6. Order

3.1, 3.4 and 3.5 first (classifiers over data `check` already has), then 3.2,
3.3, 3.6, 3.7. Each lands with its tests and README rows before the next.

## 7. Second review: outcomes

A second independent review, on 2026-09-16, raised the items below. Each is
recorded with what was done and the evidence.

- **A2, done.** `GENERATED_CALLEE_SPEC` now requires `plugin: "kernel"` and
  `category: "annot:missing-spec"`, as 3.4 always said; a probe including
  `<stdio.h>` and calling `puts` did not fire before or after.
- **A3, done.** The smoke probe runs with the proof's provers, parallelism and
  timeout, and reports `provers`, `parallel` and `elapsed_ms`. Measured cost on
  `smoke-vacuous.c`: 12.5 s against 9.5 s for the same `check` without smoke.
- **A5, done.** `unsigned_rte_options_follow_each_load_in_one_session` loads
  one fixture three times in one server; EVA's `unsigned_overflow` alarm
  appears, disappears and reappears with `rte`.
- **A1, not implemented.** WP prints "might be unsound" for any union access,
  so a union written and read through one member reports
  `WP_UNSOUND_ENCODING` although nothing crosses members. The server cannot
  tell the two apart from the message, and every way to let such code reach
  `proved` means accepting the code on the caller's word, which is the opposite
  of what `incomplete[]` exists for. The honest shape is an acknowledgement
  recorded beside the verdict, never one that changes it; that needs a design
  of how an acknowledged gap travels into receipts and stored conclusions, and
  it was not rushed.
- **B1, done.** `run_wp {prop}` proves only the selected properties, over
  property markers, and keeps only their goals; see
  `run_wp_prop_narrows_the_proved_goals`.
- **B2, done.** See 2.3.
- **B4, done.** Each Frama-C the server starts gets its own TMPDIR under
  `/tmp/fcmcp-<uid>`, removed with the process; `a_session_leaves_nothing_in_tmpdir`
  failed without it, listing the preprocessed files left behind.
- **B5, done.** See 3.2.
- **B6, not implemented.** 3.6 stands: the strategy would need goals
  regenerated when it changes, and nothing measured makes that worth its cost.
- **C1, done.** `WP_UNSAFE_CAST_MODEL` became `WP_WEAKENED_MODEL`, covering
  `+cast`, `+nat` and `+real`.
- **C2, no new code.** Measured: the unguarded behavior-assigns shape prints no
  message, and both shapes already raise `ASSUMED_CALLEE_CONTRACT`, which
  `behavior_only_assigns_are_an_assumed_callee_contract` pins.
- **C3, reverted after measurement.** `kernel.parameters.setWpCheckMemoryModel`
  on the running process changed the reported configuration and generated no
  call-site obligation, where `frama-c -wp -wp-check-memory-model` on the same
  fixture does (`caller_call_two_wp_typed_nocast_requires`). WP inserts those
  checks from its batch entry point, the same reason the hypotheses themselves
  need a separate process. Doing it would mean a proving probe per check.
- **C4, done in part.** See A3. Whether the probe matched the proof's
  configuration is now true by construction rather than reported.
