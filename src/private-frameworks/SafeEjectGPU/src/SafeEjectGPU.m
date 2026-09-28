/*
	SafeEjectGPU.private

	Apple's private framework behind the "safe to eject" guard on external GPUs.
	Activity Monitor links it, and binds one symbol: the SafeEjectGPU class.

	The class answers one question, whether a given GPU can be ejected right now
	without losing work, and it is the caller that then does the ejecting. It is
	over NSObject because AppKit and IOKit are not available to name a superclass
	from here; the class symbol is what the linker needs, and the one selector this
	is reached for is implemented.
*/

#import <Foundation/Foundation.h>

@interface SafeEjectGPU : NSObject

/* Whether the GPU can be ejected safely. NO: no GPU here is one this process
   owns the power state of, and a device that is not there cannot be ejected. */
+ (BOOL)isSafeToEjectGPU:(id)gpu;

/* Devices that can be ejected right now. Empty, for the same reason. */
+ (NSArray*)ejectableDevices;

@end

@implementation SafeEjectGPU

+ (BOOL)isSafeToEjectGPU:(id)gpu
{
	(void)gpu;
	return NO;
}

+ (NSArray*)ejectableDevices
{
	return [NSArray array];
}

@end
