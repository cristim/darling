/* A bundle built with -undefined dynamic_lookup that reads a data symbol
 * nobody exports. MST_NAME is the symbol's assembly name, set by build.sh. */
#define STR2(x) #x
#define STR(x) STR2(x)
extern int d_flat __asm__(STR(MST_NAME));

int bundle_read(void)
{
	return d_flat;
}
