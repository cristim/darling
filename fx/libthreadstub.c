#include "guest_api.h"

int pthread_create(pthread_t* thread, const pthread_attr_t* attr, void* (*start)(void*), void* arg) { return -1; }
int pthread_join(pthread_t thread, void** result) { return -1; }
int usleep(unsigned int usec) { return -1; }
char* dlerror(void) { return 0; }
void* dlsym(void* handle, const char* name) { return 0; }
int dlclose(void* handle) { return -1; }
