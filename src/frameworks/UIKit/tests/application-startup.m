// SPDX-License-Identifier: GPL-3.0-or-later
// Mode comes from UIAPP_FIXTURE_MODE (see application-startup.md). Not yet compiled.
#import <UIKit/UIApplication.h>
#import <AppKit/NSApplication.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *mode;
static int willCount, didCount;

@interface FixtureApplication : UIApplication
@end
@implementation FixtureApplication
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
        UIApplicationMain(0, NULL, nil, nil);
    }
    [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(fire:) userInfo:nil repeats:NO];
    return YES;
}
- (void)fire:(NSTimer *)t
{
    fprintf(stderr, "timer\n");
    if (!strcmp(mode, "run-loop-returns")) {
        [NSApp stop:nil];
        // stop: only clears the flag; the loop re-checks it after the next event.
        [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:YES];
    } else {
        [NSApp terminate:nil];
    }
}
- (void)applicationWillTerminate:(UIApplication *)a
{
    fprintf(stderr, "terminate will=%d did=%d\n", willCount, didCount);
}
@end

static int savedArgc;
static char **savedArgv;
static NSString *savedDelegate;

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
        if (!strcmp(mode, "custom-principal")) principal = @"FixtureApplication";
        if (!strcmp(mode, "nil-delegate")) delegate = nil;
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
