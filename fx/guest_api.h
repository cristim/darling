#ifndef MST_GUEST_API_H
#define MST_GUEST_API_H

/* Interface-only declarations: vendored libpthread/pthread.h, dyld/dlfcn.h,
 * Libc/unistd.h and xnu/sys/_types.h. No opaque object layout is allocated. */
typedef struct _opaque_pthread_t* pthread_t;
typedef struct _opaque_pthread_attr_t pthread_attr_t;
extern int pthread_create(pthread_t*, const pthread_attr_t*, void* (*)(void*), void*);
extern int pthread_join(pthread_t, void**);
extern int usleep(unsigned int);
extern void* dlopen(const char*, int);
extern void* dlsym(void*, const char*);
extern char* dlerror(void);
extern int dlclose(void*);
extern long write(int, const void*, unsigned long);
#define RTLD_NOW 2
#define RTLD_LOCAL 4

static int emit(int fd, const char* text)
{
	unsigned long length = 0;
	while ( text[length] )
		++length;
	while ( length ) {
		long result = write(fd, text, length);
		if ( result <= 0 )
			return 1;
		text += result;
		length -= result;
	}
	return 0;
}

static int contains(const char* text, const char* needle)
{
	for ( ; *text; ++text ) {
		unsigned long i = 0;
		while ( needle[i] && text[i] == needle[i] )
			++i;
		if ( !needle[i] )
			return 1;
	}
	return 0;
}

static int missing(const char* path, const char* expected, char error[1024])
{
	dlerror();
	void* handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
	if ( handle )
		return dlclose(handle) == 0 ? 1 : 2;
	const char* message = dlerror();
	if ( !message || !contains(message, expected) )
		return 3;
	unsigned long i = 0;
	for ( ; message[i] && i < 1023; ++i )
		error[i] = message[i];
	error[i] = 0;
	return message[i] ? 4 : 0;
}

#endif
