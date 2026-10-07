/*
	CPAnalytics.private

	The app binds _OBJC_CLASS_$_CPAnalytics, so the class has to exist as a real
	Objective-C class or the bind fails. Photo Booth only ever sends it the two
	event selectors that are also exported from CPAnalytics.c, so a bare
	NSObject subclass is enough; anything more would be behaviour invented for a
	framework whose real semantics are not knowable from here.
*/

#import <Foundation/Foundation.h>

@interface CPAnalytics : NSObject
@end

@implementation CPAnalytics
@end
