/*
 * A function with a caller, so that a stale entry point is visible.
 *
 * The kernel's -main is sticky and an unchanged reload does not respawn, so a
 * value written for one call survived into the next. With -main left at "g", WP
 * refuses "g" as a recursive entry point and generates no goal for its
 * postcondition, which cost this file two of its six goals and turned a proved
 * check into an incomplete one. Both calls must agree.
 */

/*@ assigns \nothing;
    ensures \result >= 0;
 */
int g(int n)
{
    return n > 0 ? n : 0;
}

int main(void)
{
    return g(3);
}
