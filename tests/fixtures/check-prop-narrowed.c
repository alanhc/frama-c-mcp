/*
 * A property that proves beside one that does not, so a check narrowed with
 * prop can be compared against the same check without it.
 *
 * "easy" holds outright. "hard" is not provable: a and b arrive from a volatile
 * read, so EVA cannot fold them and WP cannot discharge the sum either, which
 * makes the unnarrowed check incomplete. Under prop: "easy" WP generates no
 * goal for "hard" at all, so nothing reports it and the run used to come back
 * proved with zero goals. main is here so that EVA has an entry point and
 * EVA_NOT_RUN does not mask the verdict under test.
 */

volatile int nd;

/*@ assigns \nothing;
    ensures easy: \result >= 0;
 */
int g(int a, int b)
{
    //@ assert hard: a + b > 0;
    return 1;
}

int main(void)
{
    return g(nd, nd);
}
