// SPDX-License-Identifier: GPL-3.0-or-later
// Mode comes from UIAPP_FIXTURE_MODE (see application-startup.md).
#import <UIKit/UIKit.h>
#import <AppKit/NSApplication.h>
#import <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *mode;
static int willCount, didCount;
static int savedArgc;
static char **savedArgv;
static NSString *savedDelegate;

// Same shape as an app that names its own UIApplication subclass and a UIResponder-based
// delegate that implements only some optional callbacks.
static int shapeInitCount;

@interface ShapeApplication : UIApplication
@end
@implementation ShapeApplication
- (instancetype)init
{
    if ((self = [super init])) shapeInitCount++;
    return self;
}
@end

@interface ShapeDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation ShapeDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o
{
    fprintf(stderr, "shape did main=%d init=%d class=%s shared=%d delegate-identity=%d delegate-class=%s state=%ld\n",
            [NSThread isMainThread], shapeInitCount, class_getName([a class]),
            a == [ShapeApplication sharedApplication] && a == [UIApplication sharedApplication],
            a.delegate == self, class_getName([(id)a.delegate class]), (long)a.applicationState);
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.2];
    return YES;
}
- (void)applicationWillTerminate:(UIApplication *)a
{
    fprintf(stderr, "shape terminate init=%d\n", shapeInitCount);
}
@end

// A UIApplication subclass named as both principal and delegate class (documented case).
static int selfInitCount;

@interface SelfDelegateApplication : UIApplication <UIApplicationDelegate>
@end
@implementation SelfDelegateApplication
- (instancetype)init
{
    if ((self = [super init])) selfInitCount++;
    return self;
}
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o
{
    fprintf(stderr, "self did init=%d delegate-is-app=%d shared-is-app=%d\n", selfInitCount,
            a.delegate == (id)a, a == [UIApplication sharedApplication]);
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.2];
    return YES;
}
@end

@interface ThrowingApplication : UIApplication
@end
@implementation ThrowingApplication
- (instancetype)init { [NSException raise:@"Fixture" format:@"init"]; return nil; }
@end

@interface NotADelegate : NSObject
@end
@implementation NotADelegate
@end

@interface FixtureDelegate : NSObject <UIApplicationDelegate>
@end
@implementation FixtureDelegate
- (BOOL)application:(UIApplication *)a willFinishLaunchingWithOptions:(NSDictionary *)o
{
    if (!strcmp(mode, "throw-will")) [NSException raise:@"Fixture" format:@"will"];
    // BOOL NO must not abort startup.
    fprintf(stderr, "will %d main=%d shared=%d state=%ld opts=%lu\n", ++willCount, [NSThread isMainThread],
            a == [UIApplication sharedApplication], (long)a.applicationState, (unsigned long)[o count]);
    return NO;
}
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o
{
    if (!strcmp(mode, "throw-did")) [NSException raise:@"Fixture" format:@"did"];
    fprintf(stderr, "did %d after-will=%d delegate-identity=%d class=%s\n", ++didCount, willCount == 1,
            a.delegate == self, class_getName([a class]));
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:NSApplicationDidBecomeActiveNotification object:NSApp];
    fprintf(stderr, "state-active=%d\n", a.applicationState == UIApplicationStateActive);
    [center postNotificationName:NSApplicationDidResignActiveNotification object:NSApp];
    fprintf(stderr, "state-inactive=%d\n", a.applicationState == UIApplicationStateInactive);
    if (!strcmp(mode, "duplicate")) {
        UIApplicationMain(savedArgc, savedArgv, nil, nil);
    }
    [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(fire:) userInfo:nil repeats:NO];
    return YES;
}
- (void)fire:(NSTimer *)t
{
    fprintf(stderr, "timer\n");
    if (!strcmp(mode, "run-loop-returns")) {
        [NSApp stop:nil];
    } else {
        [NSApp terminate:nil];
    }
}
- (void)applicationWillTerminate:(UIApplication *)a
{
    fprintf(stderr, "terminate will=%d did=%d\n", willCount, didCount);
}
@end

@interface Helper : NSObject
@end
@implementation Helper
- (void)offMain { UIApplicationMain(savedArgc, savedArgv, nil, savedDelegate); }
- (void)nilFire:(NSTimer *)t
{
    fprintf(stderr, "nil-delegate shared=%d delegate-nil=%d\n", [UIApplication sharedApplication] != nil,
            [UIApplication sharedApplication].delegate == nil);
    [NSApp terminate:nil];
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        mode = getenv("UIAPP_FIXTURE_MODE") ?: "ok";
        fprintf(stderr, "shared-before-launch-nil=%d\n", [UIApplication sharedApplication] == nil);
        NSString *principal = nil, *delegate = @"FixtureDelegate";
        if (!strcmp(mode, "bad-principal")) principal = @"NSObject";
        if (!strcmp(mode, "bad-delegate")) delegate = @"NotADelegate";
        if (!strcmp(mode, "missing-delegate")) delegate = @"NoSuchClass";
        if (!strcmp(mode, "nil-delegate")) delegate = nil;
        if (!strcmp(mode, "throw-init")) principal = @"ThrowingApplication";
        if (!strcmp(mode, "app-subclass")) {
            principal = @"ShapeApplication";
            delegate = @"ShapeDelegate";
        }
        if (!strcmp(mode, "self-delegate")) {
            principal = @"SelfDelegateApplication";
            delegate = @"SelfDelegateApplication";
        }
        savedArgc = argc;
        savedArgv = argv;
        savedDelegate = delegate;
        Helper *helper = [[Helper alloc] init];
        if (!strcmp(mode, "off-main")) {
            [NSThread detachNewThreadSelector:@selector(offMain) toTarget:helper withObject:nil];
            [NSThread sleepForTimeInterval:5];
            return 0;
        }
        if (!strcmp(mode, "nil-delegate")) {
            [NSTimer scheduledTimerWithTimeInterval:0.2 target:helper selector:@selector(nilFire:) userInfo:nil repeats:NO];
        }
        return UIApplicationMain(argc, argv, principal, delegate);
    }
}
