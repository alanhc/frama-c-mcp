/*
 * A contract no state satisfies, beside one that is fine.
 *
 * "impossible" requires n > 0 && n < 0, so every goal in it proves, the false
 * ensures \result == 42 included, on a function that returns 0. Only WP's smoke
 * tests see it: the smoke goal for the precondition is proved, which means the
 * precondition is contradictory. "fine" has a satisfiable requires, so its
 * smoke goal stays unproved and must not be reported.
 */

/*@ requires n > 0 && n < 0;
    assigns \nothing;
    ensures \result == 42;
 */
int impossible(int n)
{
    return 0;
}

/*@ requires n >= 0;
    assigns \nothing;
    ensures \result >= 0;
 */
int fine(int n)
{
    return n;
}
