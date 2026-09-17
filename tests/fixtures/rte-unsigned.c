/*
 * Unsigned wraparound and narrowing, which RTE checks only on request.
 *
 * Frama-C 33 defaults -warn-unsigned-overflow and -warn-unsigned-downcast to
 * off, so -wp-rte alone generates no goal for either function and check used to
 * report both as proved. Unsigned wraparound is defined behaviour in C, which
 * is why the kernel leaves it off, but a load that claims runtime errors were
 * checked has to check it: "sub" wraps whenever b > a, and "narrow" truncates
 * any x above 255.
 */

/*@ assigns \nothing; */
unsigned sub(unsigned a, unsigned b)
{
    return a - b;
}

/*@ assigns \nothing; */
unsigned char narrow(unsigned x)
{
    return x;
}
