/*
 * An unsigned wraparound EVA reaches from main.
 *
 * sub(1u, 2u) wraps. With the unsigned RTE options on, EVA reports
 * unsigned_overflow at "a - b"; with them off it reports nothing. The options
 * are kernel state on a long-lived process, so the test loads this file three
 * times in one session, alternating rte, and expects the alarm to follow each
 * load rather than the first one.
 */

/*@ assigns \nothing; */
unsigned sub(unsigned a, unsigned b)
{
    return a - b;
}

int main(void)
{
    return (int) sub(1u, 2u);
}
