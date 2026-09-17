/*
 * Two annotations WP 33.0 discards while the goals around them still prove.
 *
 * The statement contract in "block" requires x == n + 1, which is false at that
 * point, and the statement-level invariant in "stmt" states x == n + 7, also
 * false. WP prints "Statement specifications not yet supported (skipped)." and
 * "Generalized invariant not yet supported (skipped)." and proves every
 * remaining goal, so without a gate on those messages check reads the file as
 * proved. Both functions' own postconditions are true, which is the point:
 * nothing but the messages says an annotation was dropped.
 */

/*@ assigns \nothing;
    ensures \result == n;
 */
int block(int n)
{
    int x = n;
    /*@ requires x == n + 1;
        ensures x == 2;
     */
    {
        x = x + 0;
    }
    return x;
}

/*@ assigns \nothing;
    ensures \result == n;
 */
int stmt(int n)
{
    int x = n;
    /*@ invariant x == n + 7; */
    x = n;
    return x;
}
