// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIApplication.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSImage.h>
#import <UIKit/UIScreen.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSThread.h>
#include <stdio.h>
#include <stdlib.h>

static UIApplication *sharedApplication;
static BOOL mainEntered;
// NSNotificationCenter does not retain observers, so the bridge lives for the process.
static id bridge;

__attribute__((noreturn)) static void fail(NSString *cause)
{
    NSArray *lines = [cause componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    fprintf(stderr, "UIApplicationMain: %s\n", [[lines componentsJoinedByString:@" "] UTF8String]);
    exit(1);
}

static void guarded(NSString *phase, void (^body)(void))
{
    @try {
        body();
    } @catch (NSException *e) {
        fail([NSString stringWithFormat:@"exception in %@: %@: %@", phase, [e name], [e reason]]);
    }
}

@interface UIApplication ()
@property(nonatomic, readwrite) UIApplicationState applicationState;
@end

@implementation UIApplication
@synthesize delegate = _delegate;
@synthesize applicationState = _applicationState;

+ (UIApplication *)sharedApplication
{
    return sharedApplication;
}
@end

// Forwards AppKit launch/focus/termination notifications to the UIKit delegate. It is also the
// NSApplication delegate, so AppKit hands it the process arguments it would open as documents.
@interface UIApplicationAppKitBridge : NSObject
@property(nonatomic, retain) id<UIApplicationDelegate> delegateOwner;
@end

@implementation UIApplicationAppKitBridge

// Delegate BOOL results report whether launch options were handled; they are not a startup verdict.
- (void)willFinishLaunching:(NSNotification *)note
{
    id<UIApplicationDelegate> d = sharedApplication.delegate;
    if ([d respondsToSelector:@selector(application:willFinishLaunchingWithOptions:)])
        guarded(@"willFinishLaunching", ^{ [d application:sharedApplication willFinishLaunchingWithOptions:@{}]; });
}

- (void)didFinishLaunching:(NSNotification *)note
{
    id<UIApplicationDelegate> d = sharedApplication.delegate;
    if ([d respondsToSelector:@selector(application:didFinishLaunchingWithOptions:)])
        guarded(@"didFinishLaunching", ^{ [d application:sharedApplication didFinishLaunchingWithOptions:@{}]; });
}

- (void)didBecomeActive:(NSNotification *)note
{
    sharedApplication.applicationState = UIApplicationStateActive;
}

- (void)didResignActive:(NSNotification *)note
{
    sharedApplication.applicationState = UIApplicationStateInactive;
}

- (void)willTerminate:(NSNotification *)note
{
    id<UIApplicationDelegate> delegate = sharedApplication.delegate;
    if ([delegate respondsToSelector:@selector(applicationWillTerminate:)]) {
        [delegate applicationWillTerminate:sharedApplication];
    }
}

// UIKit launch arguments are not documents; without this AppKit opens every non-dash argument,
// including the value of a "-Key value" pair.
- (void)application:(NSApplication *)application openFiles:(NSArray *)files
{
}
@end

int UIApplicationMain(int argc, char **argv, NSString *principalClassName, NSString *delegateClassName)
{
    if (![NSThread isMainThread]) {
        fail(@"must be called on the main thread");
    }
    if (mainEntered) {
        fail(@"already called");
    }
    mainEntered = YES;

    // Cocotron's -[NSApplication init] shows a "splash" image as a window; UIKit has no such path.
    if ([NSImage imageNamed:@"splash"] != nil) {
        fail(@"unsupported splash image");
    }

    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *key in @[ @"NSMainNibFile", @"UIMainStoryboardFile" ]) {
        if (info[key] != nil) {
            fail([NSString stringWithFormat:@"unsupported configured resource %@", key]);
        }
    }
    if (info[@"UIApplicationSceneManifest"] != nil) {
        fprintf(stderr, "UIKit: UIApplicationSceneManifest is not supported; launching without scene sessions\n");
    }

    Class principal = [UIApplication class];
    if (principalClassName != nil) {
        principal = NSClassFromString(principalClassName);
        if (![principal isSubclassOfClass:[UIApplication class]]) {
            fail([NSString stringWithFormat:@"principal class %@ is not a UIApplication class", principalClassName]);
        }
    }

    Class delegateClass = Nil;
    if (delegateClassName != nil) {
        delegateClass = NSClassFromString(delegateClassName);
        if (![delegateClass conformsToProtocol:@protocol(UIApplicationDelegate)]) {
            fail([NSString stringWithFormat:@"delegate class %@ does not conform to UIApplicationDelegate", delegateClassName]);
        }
    }

    @try {
        (void)[UIScreen screens];
    } @catch (NSException *e) {
        fail([NSString stringWithFormat:@"screen query failed: %@: %@", [e name], [e reason]]);
    }
    [NSApplication sharedApplication];

    UIApplicationAppKitBridge *appKitBridge = [[UIApplicationAppKitBridge alloc] init];
    bridge = appKitBridge;
    guarded(@"application or delegate init", ^{
        sharedApplication = [[principal alloc] init];
        if (delegateClass == principal) {
            // The docs let a UIApplication subclass be its own delegate.
            appKitBridge.delegateOwner = sharedApplication;
        } else if (delegateClass != Nil) {
            appKitBridge.delegateOwner = [[delegateClass alloc] init];
        }
    });
    sharedApplication.applicationState = UIApplicationStateInactive;
    sharedApplication.delegate = appKitBridge.delegateOwner;
    [NSApp setDelegate:(id)appKitBridge];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:appKitBridge selector:@selector(willFinishLaunching:) name:NSApplicationWillFinishLaunchingNotification object:NSApp];
    [center addObserver:appKitBridge selector:@selector(didFinishLaunching:) name:NSApplicationDidFinishLaunchingNotification object:NSApp];
    [center addObserver:appKitBridge selector:@selector(didBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
    [center addObserver:appKitBridge selector:@selector(didResignActive:) name:NSApplicationDidResignActiveNotification object:NSApp];
    [center addObserver:appKitBridge selector:@selector(willTerminate:) name:NSApplicationWillTerminateNotification object:NSApp];

    [NSApp run];
    // AppKit returned: the loop was stopped without terminate, which is not UIKit success.
    fail(@"run loop returned");
}
