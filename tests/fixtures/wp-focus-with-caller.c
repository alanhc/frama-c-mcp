/*
 * check scoped to a function that has a caller.
 *
 * check --function f sets f as the entry point for EVA. That setting used to
 * stay for WP, which then treated f, called by g, as a recursive entry point,
 * printed "(skipped verification)", generated no goal for the false
 * postcondition, and check answered proved over the exit and termination goals
 * alone. check now restores the entry point before WP, so the postcondition is
 * a goal and fails.
 */

/*@ assigns \nothing;
    ensures \result == 42;
 */
int f(int n)
{
    return n;
}

/*@ assigns \nothing; */
int g(void)
{
    return f(42);
}
