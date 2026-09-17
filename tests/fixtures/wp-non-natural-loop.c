/*
 * A loop WP refuses outright.
 *
 * The goto into the middle of the loop makes the control-flow graph
 * irreducible. WP 33.0 prints "Non-natural loop detected in function 'f'. This
 * case is not supported yet (skipped verification)." and generates no goal for
 * the postcondition, which is false, so without a gate on that message check
 * reads the remaining goals as the whole story.
 */

/*@ requires 0 <= n <= 10;
    assigns \nothing;
    ensures \result == 42;
 */
int f(int n)
{
    int i = 0;
    if (n > 5)
        goto inside;
top:
    i = i + 1;
inside:
    if (i < n)
        goto top;
    return i;
}
