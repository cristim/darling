#include "guest_api.h"

int main(int argc, char** argv)
{
	if ( argc != 3 )
		return 2;
	dlerror();
	void* handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	if ( !handle ) {
		const char* error = dlerror();
		if ( error )
			emit(2, error);
		return 10;
	}
	dlerror();
	int (*entry)(void) = (int (*)(void))dlsym(handle, "bundle_entry");
	const char* error = dlerror();
	if ( !entry || error || entry() != 42 ) {
		if ( error )
			emit(2, error);
		return 11;
	}
	if ( emit(1, "self-entry=42\n") )
		return 12;
	char message[1024];
	if ( missing(argv[2], "Symbol not found: _mst_thread_a\n", message) || emit(1, "separate-miss-complete\n") || emit(1, message) || emit(1, "\n") )
		return 13;
	if ( entry() != 42 || dlclose(handle) != 0 || emit(1, "self-retained=42\n") )
		return 14;
	return 0;
}
