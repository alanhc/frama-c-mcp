# E-ACSL Output

Install probe, measured on Frama-C 33.0 on 2026-09-16. Frama-C 33 installs the
wrapper as `e-acsl-gcc`; older releases named it `e-acsl-gcc.sh`:

```text
$ command -v e-acsl-gcc || command -v e-acsl-gcc.sh
.../bin/e-acsl-gcc
```

Runtime instrumentation of the buggy example, same date. `-c` compiles the
instrumented binary `a.out.e-acsl`, and the wrapper's own help says it is on by
default, so it is written out here to name the step rather than to enable it:

```text
$ e-acsl-gcc -c abs-buggy.c
$ ./a.out.e-acsl
abs-buggy.c: In function 'abs_int'
abs-buggy.c:7: Error: Postcondition failed:
	The failing predicate is:
	\old(x) < 0 ⇒ \result ≡ -\old(x).
	With values at failure point:
	- \old(x): -2147483648
	- \result: -2147483648
```

The instrumented binary exits non-zero (134, an abort) on the violation.

How to report this:

- A present wrapper is not enough; instrumentation must compile and the instrumented executable must run.
- If instrumentation fails, report runtime checking as unavailable, an environment failure rather than a result.
- When it runs, report the concrete input or path that violated a contract, as above: `x == INT_MIN`.
- E-ACSL explores only the executions you run. It complements WP; it does not replace static proof.
