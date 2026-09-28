/*
	APFS.private

	Apple's private framework over the APFS volume/container operations that Disk
	Utility and Boot Camp Assistant drive. Two of the local apps link it, binding
	three symbols.

	There are no APFS volumes here, so the operations report the result that means
	"there was nothing to act on" rather than inventing a volume to act on. The
	prototypes are not guessed: there are no SDK headers for this framework, so the
	arity and the return type were read off the call sites in the apps themselves.
	APFSCancelContainerResize is called with one pointer and its result is masked to
	a byte, so it returns an int. APFSVolumeRole is imported but never called, so
	nothing constrains it beyond having to exist.
*/

#include <CoreFoundation/CoreFoundation.h>

/* Cancels a container resize. Called with a single pointer, which the caller may
   pass as NULL, and its result is used as a byte, so it returns a status. */
int APFSCancelContainerResize(CFTypeRef container)
{
	(void)container;
	/* No resize is in progress, so the container is already in the state the caller
	   wanted. Reporting success is the accurate answer, and it is what lets a
	   caller finish a resize flow rather than treat it as failed. */
	return 0;
}

/* The role a volume plays, such as system or data. Imported but never called by
   either app, so the prototype is unconstrained by evidence; this one only has to
   exist. There is no volume to describe, so it reports none. */
CFStringRef APFSVolumeRole(CFStringRef volume)
{
	(void)volume;
	return NULL;
}
