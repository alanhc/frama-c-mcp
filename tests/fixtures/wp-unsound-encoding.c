/*
 * Two false properties WP 33.0 proves under the Typed memory model.
 *
 * "write_int" writes the union through its int member and claims the first byte
 * is unchanged, which is false on any real machine; WP proves it and warns
 * "Accessing union fields with Typed model might be unsound." "toggle" changes
 * g while claiming the labelled logic value val, which has no definition, is
 * unchanged; WP interprets val as reading nothing, proves the claim, and warns
 * "No definition for 'val' interpreted as reads nothing".
 */

union U {
    int i;
    unsigned char c[4];
};
union U u;

/*@ assigns u.i;
    ensures u.i == v;
    ensures u.c[0] == \old(u.c[0]);
 */
void write_int(int v)
{
    u.i = v;
}

int g;
/*@ axiomatic A { logic integer val{L}; } */

/*@ assigns g;
    ensures g == 1 - \old(g) || g == 0;
    ensures val == \old(val);
 */
void toggle(void)
{
    g = g ? 0 : 1;
}
