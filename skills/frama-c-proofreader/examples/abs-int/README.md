# abs-int Example

This pair demonstrates a missing precondition around `INT_MIN`. The two files
are byte-identical to `tests/fixtures/abs-int-buggy.c` and
`tests/fixtures/abs-int-fixed.c`, which `scripts/check-abs-int-fixtures.sh`
measures on every CI run, and a unit test keeps the copies identical.

`abs-buggy.c` allows `x == INT_MIN`, so `return -x` can overflow. With `-wp-rte`, WP leaves the signed-overflow goal unproved (Frama-C 33.0, Alt-Ergo 2.6.3, `-wp-cache none`):

```text
[wp] [Timeout] typed_abs_int_assert_rte_signed_overflow (Qed 0.83ms) (Alt-Ergo)
[wp] Proved goals:    9 / 10
```

`abs-fixed.c` adds `requires x > INT_MIN;` and uses a caller that satisfies it:

```text
[wp] Proved goals:   14 / 14
```

E-ACSL confirms the buggy case at run time: `e-acsl-gcc -c abs-buggy.c`, then
`./a.out.e-acsl` reports `Postcondition failed` with `\old(x): -2147483648`.
See `../../references/e-acsl-output.md`.
