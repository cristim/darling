// LOCAL OBSERVATION PROBE, never published. Logs what the unmodified app calls into our code.
#pragma once
#include <stdio.h>
#include <stdint.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <malloc/malloc.h>
#include <CoreFoundation/CoreFoundation.h>

static void probe_arg(uint64_t v)
{
	Dl_info info;
	if (v > 0x10000 && dladdr((void *)v, &info) && info.dli_sname)
		fprintf(stderr, " %#llx<%s+%#lx>", (unsigned long long)v, info.dli_sname, (unsigned long)(v - (uint64_t)info.dli_saddr));
	else if (v > 0x10000 && malloc_zone_from_ptr((void *)v))
		fprintf(stderr, " %#llx<heap:%zu>", (unsigned long long)v, malloc_size((void *)v));
	else
		fprintf(stderr, " %#llx", (unsigned long long)v);
}

static void probe_log(const char *name, uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3,
		      uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7)
{
	uint64_t a[8] = {a0, a1, a2, a3, a4, a5, a6, a7};
	fprintf(stderr, "PROBE %s(", name);
	for (int i = 0; i < 8; i++) probe_arg(a[i]);
	fprintf(stderr, " )\n");
	void *bt[6];
	int n = backtrace(bt, 6);
	for (int i = 1; i < n; i++) {
		Dl_info info;
		if (dladdr(bt[i], &info))
			fprintf(stderr, "PROBE    #%d %s+%#lx (%s)\n", i, info.dli_sname ? info.dli_sname : "?",
				(unsigned long)((char *)bt[i] - (char *)(info.dli_sname ? info.dli_saddr : info.dli_fbase)), info.dli_fname);
	}
}

#define PROBE_FN(name) \
	uint64_t name(uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7) \
	{ probe_log(#name, a0, a1, a2, a3, a4, a5, a6, a7); return 0; }

#define PROBE_CFSTR(name) const CFStringRef name = CFSTR("probe:" #name);

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#define PROBE_FORWARDING \
	+ (NSMethodSignature *)methodSignatureForSelector:(SEL)s { \
		NSMethodSignature *m = [super methodSignatureForSelector:s]; \
		if (!m) { fprintf(stderr, "PROBE +[%s %s]\n", class_getName(self), sel_getName(s)); \
			m = [NSMethodSignature signatureWithObjCTypes:"@@:@@@@"]; } \
		return m; } \
	+ (void)forwardInvocation:(NSInvocation *)inv { } \
	- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { \
		NSMethodSignature *m = [super methodSignatureForSelector:s]; \
		if (!m) { fprintf(stderr, "PROBE -[%s %s]\n", class_getName(object_getClass(self)), sel_getName(s)); \
			m = [NSMethodSignature signatureWithObjCTypes:"@@:@@@@"]; } \
		return m; } \
	- (void)forwardInvocation:(NSInvocation *)inv { } \
	+ (instancetype)alloc { fprintf(stderr, "PROBE +[%s alloc]\n", class_getName(self)); return [super alloc]; } \
	- (instancetype)init { fprintf(stderr, "PROBE -[%s init]\n", class_getName(object_getClass(self))); return [super init]; }
#endif
