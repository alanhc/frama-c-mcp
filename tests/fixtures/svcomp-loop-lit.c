/*
 * The loop of SV-COMP's c/loop-lit/afnp2014.i (Apache-2.0;
 * https://gitlab.com/sosy-lab/benchmarking/sv-benchmarks), kept statement for
 * statement.
 *
 * Upstream states its safety property as a call to __VERIFIER_assert and draws
 * the loop condition from __VERIFIER_nondet_int. Here the property is an ACSL
 * assert and the nondeterministic input is a declaration with no body and an
 * explicit assigns, which is the shape an MCP client produces after translating
 * a reachability property to ACSL. The invariants are not true by construction:
 * x accumulates y, so y <= x needs 1 <= x, and the overflow guards on x + y
 * need the x <= 1 + y * 1000 bound, so some goals reach Alt-Ergo rather than
 * closing in Qed.
 */

/*@ assigns \nothing; */
extern int nondet_int(void);

int main(void)
{
    int x = 1;
    int y = 0;

    /*@
      loop invariant 1 <= x && y <= x;
      loop invariant 0 <= y <= 1000;
      loop invariant x <= 1 + y * 1000;
      loop assigns x, y;
      loop variant 1000 - y;
    */
    while (y < 1000 && nondet_int()) {
        x = x + y;
        y = y + 1;
    }

    /*@ assert x >= y; */
    return 0;
}
