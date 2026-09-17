# WP Output

Install check:

```text
$ frama-c -version
33.0 (Arsenic)
```

Buggy `abs-int` run, measured on Frama-C 33.0 with Alt-Ergo 2.6.3 on 2026-09-16.
`-wp-cache none` makes every verdict computed on this run; without it a verdict
can be replayed from WP's cache and marked `(Cached)`:

```text
$ frama-c -wp -wp-rte -wp-cache none skills/frama-c-proofreader/examples/abs-int/abs-buggy.c
[wp] 8 goals scheduled
[wp] [Timeout] typed_abs_int_assert_rte_signed_overflow (Qed 0.83ms) (Alt-Ergo)
[wp] Proved goals:    9 / 10
  Timeout:         1
```

Fixed `abs-int` run, same toolchain and date:

```text
$ frama-c -wp -wp-rte -wp-cache none skills/frama-c-proofreader/examples/abs-int/abs-fixed.c
[wp] 12 goals scheduled
[wp] Proved goals:   14 / 14
```

How to read this:

- `Proved goals: 9 / 10` means one generated obligation was not proved.
- `typed_abs_int_assert_rte_signed_overflow` is an RTE signed-overflow goal, not a postcondition name.
- `Timeout` means the prover did not establish the goal. Check whether the property is false, underspecified, or just hard.
- Frama-C exits 0 even with goals left unproved, so compare the two halves of `Proved goals` rather than trusting the exit status.
- Measure with `-wp-cache none`. WP's default cache mode replays earlier verdicts, and the `(Cached)` word it prints is not a reliable sign of which verdicts were replayed.
- A fully proved run proves the generated obligations for the ACSL and `-wp-rte` configuration that ran; it does not prove omitted requirements, and it does not rule out a vacuous contract: run smoke tests before calling it verified.
