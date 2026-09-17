/*
 * A callee with neither code nor specification, next to one with a contract.
 *
 * The kernel invents a contract for "unspecified": terminates, never exits,
 * assigns only through its pointer parameter. It never lists the global
 * "state", so a caller proves that state survives the call, and nothing checks
 * that the guess holds. "specified" has an assigns clause the user wrote and no
 * terminates, which is the common extern shape and must not be reported: the
 * kernel then adds only the termination clauses.
 */

int state;

extern void unspecified(int *p);

/*@ assigns *p; */
extern void specified(int *p);

/*@ requires \valid(p);
    assigns *p, state;
    ensures state == \old(state);
 */
void caller(int *p)
{
    unspecified(p);
    specified(p);
}
