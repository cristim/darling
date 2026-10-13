/* dlopen(argv[1]) argv[2] times; each attempt fails on the bundle's missing
 * import, so each one reaches dyld's missing-symbol path. */
extern void* dlopen(const char*, int);
extern long write(int, const void*, unsigned long);

int main(int argc, char** argv)
{
	if ( argc < 3 )
		return 2;
	long n = 0;
	for ( const char* p = argv[2]; *p >= '0' && *p <= '9'; ++p )
		n = n * 10 + (*p - '0');
	long loaded = 0;
	for ( long i = 0; i < n; ++i ) {
		if ( dlopen(argv[1], 2 /* RTLD_NOW */) != 0 )
			++loaded;
	}
	write(1, loaded ? "loaded\n" : "all-failed\n", loaded ? 7 : 11);
	return 0;
}
