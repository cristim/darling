/* Link-time stand-in for libSystem: only the names the fixtures import.
 * At run time the guest binds them to the real /usr/lib/libSystem.B.dylib. */
void sb(void) __asm__("dyld_stub_binder");
void sb(void) {}
long write(int fd, const void* buf, unsigned long n) { return 0; }
void* dlopen(const char* path, int mode) { return 0; }
int fork(void) { return 0; }
int execve(const char* path, char* const argv[], char* const envp[]) { return 0; }
int waitpid(int pid, int* status, int options) { return 0; }
void _exit(int status) {}
