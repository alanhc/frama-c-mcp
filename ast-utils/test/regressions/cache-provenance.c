/*
 * A loop whose invariants only a prover discharges, so getGoalCacheStats has a
 * cacheable goal to report on beside the ones Qed closes on its own.
 */

/*@ requires 0 <= n <= 1000;
    assigns \nothing;
    ensures \result >= n;
*/
int accumulate(int n)
{
    int total = 0;
    int i = 0;
    /*@ loop invariant 0 <= i <= n;
        loop invariant total >= i;
        loop assigns i, total;
        loop variant n - i;
    */
    while (i < n) {
        total = total + 1 + (i % 2);
        i = i + 1;
    }
    return total;
}
