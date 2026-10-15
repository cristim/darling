#include "guest_api.h"

/* Vendored Libc/unistd.h and xnu/sys/wait.h; pid_t is signed int32. */
extern int fork(void);
extern int waitpid(int, int*, int);
extern void _exit(int) __attribute__((noreturn));

static int take(const char** text, const char* expected)
{
	while ( *expected ) {
		if ( **text != *expected++ )
			return 1;
		++*text;
	}
	return 0;
}

static int phase(const char* path, const char* symbol, unsigned count, const char* label)
{
	char error[1024];
	for ( unsigned i = 0; i < count; ++i ) {
		if ( missing(path, symbol, error) )
			return 1;
		const char* cursor = error;
		if ( take(&cursor, "dlopen(") || take(&cursor, path) || take(&cursor, ", 6): ") ||
			 take(&cursor, symbol) || take(&cursor, "  Referenced from: ") || take(&cursor, path) ||
			 take(&cursor, "\n  Expected in: flat namespace\n") || *cursor )
			return 1;
	}
	return emit(1, label) || emit(1, error) || emit(1, "\n");
}

int main(int argc, char** argv)
{
	if ( argc != 4 || (argv[3][0] != 's' && argv[3][0] != 'c') || argv[3][1] )
		return 2;
	int counter = argv[3][0] == 'c';
	if ( phase(argv[1], "Symbol not found: _mst_thread_a\n", counter ? 4095 : 1, "prefork: ") )
		return 10;
	int child = fork();
	if ( child < 0 )
		return 11;
	if ( child == 0 )
		_exit(phase(argv[2], "Symbol not found: _mst_thread_b\n", counter ? 2 : 1, "child: ") ? 12 : 0);
	int status;
	if ( waitpid(child, &status, 0) != child || status != 0 )
		return 13;
	if ( phase(argv[1], "Symbol not found: _mst_thread_a\n", counter ? 2 : 1, "parent: ") )
		return 14;
	return 0;
}
