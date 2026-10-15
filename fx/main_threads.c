#include "guest_api.h"

static int gate;
struct Work {
	const char* path;
	const char* expected;
	int ready;
	int result;
	char error[1024];
};

static int wait_flag(int* flag)
{
	for ( unsigned int attempt = 0; attempt < 10000; ++attempt ) {
		if ( __atomic_load_n(flag, __ATOMIC_ACQUIRE) )
			return 0;
		if ( usleep(1000) != 0 )
			return 1;
	}
	return 1;
}

static void* worker(void* argument)
{
	struct Work* work = argument;
	__atomic_store_n(&work->ready, 1, __ATOMIC_RELEASE);
	work->result = wait_flag(&gate) ? 5 : missing(work->path, work->expected, work->error);
	return argument;
}

static int join(pthread_t thread, struct Work* work)
{
	void* result = 0;
	if ( pthread_join(thread, &result) != 0 || result != work || work->result != 0 )
		return 1;
	return 0;
}

static int report(const char* marker, struct Work* work)
{
	return emit(1, marker) || emit(1, work->error) || emit(1, "\n");
}

int main(int argc, char** argv)
{
	if ( argc != 4 || (argv[3][0] != 's' && argv[3][0] != 'c') || argv[3][1] )
		return 2;
	struct Work a, b;
	a.path = argv[1];
	a.expected = "Symbol not found: _mst_thread_a\n";
	a.ready = 0;
	a.result = -1;
	a.error[0] = 0;
	b.path = argv[2];
	b.expected = "Symbol not found: _mst_thread_b\n";
	b.ready = 0;
	b.result = -1;
	b.error[0] = 0;
	pthread_t first, second;
	int sequential = argv[3][0] == 's';
	gate = sequential;
	if ( pthread_create(&first, 0, worker, &a) != 0 )
		return 10;
	if ( sequential ) {
		if ( join(first, &a) || report("thread-a-complete\n", &a) )
			return 11;
		if ( pthread_create(&second, 0, worker, &b) != 0 )
			return 12;
		if ( join(second, &b) || report("thread-b-complete\n", &b) )
			return 13;
		return 0;
	}
	if ( pthread_create(&second, 0, worker, &b) != 0 ) {
		__atomic_store_n(&gate, 1, __ATOMIC_RELEASE);
		return join(first, &a) ? 15 : 14;
	}
	int ready = wait_flag(&a.ready) || wait_flag(&b.ready);
	__atomic_store_n(&gate, 1, __ATOMIC_RELEASE);
	int first_result = join(first, &a);
	int second_result = join(second, &b);
	if ( ready || first_result || second_result )
		return 16;
	if ( report("thread-a-complete\n", &a) || report("thread-b-complete\n", &b) )
		return 17;
	return 0;
}
