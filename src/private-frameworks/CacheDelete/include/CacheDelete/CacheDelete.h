/*
	CacheDelete.private

	Apple's private framework over the "delete caches" machinery: how much space a
	directory's caches occupy, and how to purge them. Boot Camp Assistant links it.

	Prototypes were read off the call sites in the app, not guessed. Nothing is
	reclaimable here, so purging is a no-op and the purgeable space is zero.
*/

#ifndef CACHEDELETE_H
#define CACHEDELETE_H

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void CacheDeletePurgeSpaceWithInfo(CFTypeRef directory, CFDictionaryRef info);
unsigned long long CacheDeleteCopyPurgeableSpaceWithInfo(CFTypeRef directory);

#ifdef __cplusplus
}
#endif

#endif
