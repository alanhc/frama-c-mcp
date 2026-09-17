/*
 * Callees whose assigns live only in their behaviors.
 *
 * acsl-skills lists "No default assigns clause, using unguarded behavior
 * assigns" and "... using complete behaviors assigns" among the WP messages
 * that make a proof untrustworthy. Measured on Frama-C 33.0 through check:
 * "set_complete" prints the second message, "set_unguarded" prints nothing at
 * all, and check reports ASSUMED_CALLEE_CONTRACT for both callees, from the
 * call shape rather than from the text. So no message gate is added for them;
 * this fixture pins that the existing code keeps covering both.
 */

int g;
int h;

/*@ behavior pos:
      assumes x > 0;
      assigns g;
      ensures g == x;
    behavior neg:
      assumes x <= 0;
      assigns h;
      ensures h == x;
*/
void set_unguarded(int x)
{
    if (x > 0)
        g = x;
    else
        h = x;
}

/*@ behavior pos:
      assumes x > 0;
      assigns g;
      ensures g == x;
    behavior neg:
      assumes x <= 0;
      assigns h;
      ensures h == x;
    complete behaviors;
    disjoint behaviors;
*/
void set_complete(int x)
{
    if (x > 0)
        g = x;
    else
        h = x;
}

/*@ assigns g, h;
    ensures g == \old(g);
 */
void caller(void)
{
    set_unguarded(-1);
    set_complete(-1);
}
