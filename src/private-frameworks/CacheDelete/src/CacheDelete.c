/*
	CacheDelete.private

	Apple's private framework over the "delete caches" machinery: how much space a
	directory's caches occupy, and how to purge them. Boot Camp Assistant links it,
	which is the one local app that binds it.

	Prototypes were read off the call sites in the app, not guessed: this framework
	has no SDK headers on this system. PurgeSpaceWithInfo is called with two
	arguments and its result is discarded, so it returns void. CopyPurgeableSpace
	WithInfo is called with one argument and its result is consumed as a quantity,
	so it returns an amount.

	There is no cache to purge here, so purging is a no-op and the purgeable space
	is zero. Zero is the truthful answer: nothing is reclaimable, which is the same
	state a caller has to handle for a directory that happens to be empty.
*/

#include <CoreFoundation/CoreFoundation.h>

/* Purges the caches in a directory. Result is discarded by the caller. */
void CacheDeletePurgeSpaceWithInfo(CFTypeRef directory, CFDictionaryRef info)
{
	(void)directory;
	(void)info;
}

/* How much space the caches in a directory occupy. */
unsigned long long CacheDeleteCopyPurgeableSpaceWithInfo(CFTypeRef directory)
{
	(void)directory;
	return 0;
}
