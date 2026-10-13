/* Forks a child that execs argv[1] (a fixture that fails at launch), waits
 * for it, then calls a missing function itself: two processes, two misses. */
extern int fork(void);
extern int execve(const char*, char* const[], char* const[]);
extern int waitpid(int, int*, int);
extern void _exit(int);
extern int f_miss(void);

int main(int argc, char** argv, char** envp)
{
	if ( argc < 2 )
		return 2;
	int pid = fork();
	if ( pid == 0 ) {
		char* args[] = { argv[1], 0 };
		execve(argv[1], args, envp);
		_exit(127);
	}
	int status;
	waitpid(pid, &status, 0);
	return f_miss();
}
