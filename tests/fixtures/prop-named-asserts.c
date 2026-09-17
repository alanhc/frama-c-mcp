/*
 * Three named asserts, a named postcondition and an unnamed assigns, so that
 * run_wp {prop} has names, categories and exclusions to select among. Before
 * prop narrowed the main-instance run, every one of these goals was proved and
 * reported whatever prop said.
 */

/*@ requires n >= 0;
    assigns \nothing;
    ensures pos: \result >= 0;
 */
int f(int n)
{
    int x = n;
    //@ assert one: x == n;
    //@ assert two: x >= 0;
    //@ assert three: x + 0 == n;
    return x;
}
