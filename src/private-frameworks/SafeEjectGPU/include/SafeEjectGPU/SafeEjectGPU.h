/*
	SafeEjectGPU.private

	Apple's private framework behind the "safe to eject" guard on external GPUs.
	Activity Monitor links it and binds one symbol, the SafeEjectGPU class.

	Over NSObject because AppKit and IOKit are not available here to name a real
	superclass. The class symbol is what the linker needs.
*/

#import <Foundation/Foundation.h>

@interface SafeEjectGPU : NSObject
+ (BOOL)isSafeToEjectGPU:(id)gpu;
+ (NSArray*)ejectableDevices;
@end
