/*
	APFS.private

	Apple's private framework over the APFS volume operations Disk Utility and Boot
	Camp Assistant drive.

	Prototypes were read off the call sites in the apps, not guessed: this framework
	has no SDK headers on this system, and a wrong argument count would be undefined
	behaviour rather than a link error. There are no APFS volumes here, so the
	operations report that there was nothing to act on.
*/

#ifndef APFS_H
#define APFS_H

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

int APFSCancelContainerResize(CFTypeRef container);
CFStringRef APFSVolumeRole(CFStringRef volume);

#ifdef __cplusplus
}
#endif

#endif
