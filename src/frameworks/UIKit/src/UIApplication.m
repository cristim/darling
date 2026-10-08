// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIApplication.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSImage.h>
#import <UIKit/UIScreen.h>
#import <Foundation/NSBundle.h>
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
    fprintf(stderr, "UIApplicationMain: %s\n", [cause UTF8String]);
    exit(1);
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

// Forwards AppKit launch/focus/termination notifications to the UIKit delegate.
@interface UIApplicationAppKitBridge : NSObject
@property(nonatomic, retain) UIApplication *application;
@property(nonatomic, retain) id<UIApplicationDelegate> delegateOwner;
@end

@implementation UIApplicationAppKitBridge

- (void)willFinishLaunching:(NSNotification *)note
{
    [self invoke:@selector(application:willFinishLaunchingWithOptions:) phase:@"willFinishLaunching"];
}

- (void)didFinishLaunching:(NSNotification *)note
{
    [self invoke:@selector(application:didFinishLaunchingWithOptions:) phase:@"didFinishLaunching"];
}

// The BOOL result only reports whether launch options were handled; it is not a startup verdict.
- (void)invoke:(SEL)selector phase:(NSString *)phase
{
    id<UIApplicationDelegate> delegate = _application.delegate;
    if (![(id)delegate respondsToSelector:selector]) {
        return;
    }
    @try {
        BOOL (*send)(id, SEL, UIApplication *, NSDictionary *) = (void *)[(id)delegate methodForSelector:selector];
        send(delegate, selector, _application, @{});
    } @catch (NSException *e) {
        fail([NSString stringWithFormat:@"exception in %@: %@: %@", phase, [e name], [e reason]]);
    }
}

- (void)didBecomeActive:(NSNotification *)note
{
    _application.applicationState = UIApplicationStateActive;
}

- (void)didResignActive:(NSNotification *)note
{
    _application.applicationState = UIApplicationStateInactive;
}

- (void)willTerminate:(NSNotification *)note
{
    id<UIApplicationDelegate> delegate = _application.delegate;
    if ([(id)delegate respondsToSelector:@selector(applicationWillTerminate:)]) {
        [delegate applicationWillTerminate:_application];
    }
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

    // Cocotron shows a splash window for a "splash" image and opens documents or calls
    // newDocument: during launch; none of that is a UIKit startup path.
    for (int i = 1; i < argc; i++) {
        if (argv[i][0] != '-') {
            fail(@"document arguments are unsupported");
        }
    }
    if ([NSImage imageNamed:@"splash"] != nil) {
        fail(@"unsupported splash image");
    }

    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *key in @[ @"NSMainNibFile", @"UIMainStoryboardFile", @"UIApplicationSceneManifest", @"CFBundleDocumentTypes" ]) {
        if (info[key] != nil) {
            fail([NSString stringWithFormat:@"unsupported configured resource %@", key]);
        }
    }

    Class principal = [UIApplication class];
    if (principalClassName != nil) {
        principal = NSClassFromString(principalClassName);
        if (principal == Nil || ![principal isSubclassOfClass:[UIApplication class]]) {
            fail([NSString stringWithFormat:@"principal class %@ is not a UIApplication class", principalClassName]);
        }
    }

    Class delegateClass = Nil;
    if (delegateClassName != nil) {
        delegateClass = NSClassFromString(delegateClassName);
        if (delegateClass == Nil || ![delegateClass conformsToProtocol:@protocol(UIApplicationDelegate)]) {
            fail([NSString stringWithFormat:@"delegate class %@ does not conform to UIApplicationDelegate", delegateClassName]);
        }
    }

    @try {
        (void)[UIScreen screens];
    } @catch (NSException *e) {
        fail([NSString stringWithFormat:@"no display: %@: %@", [e name], [e reason]]);
    }
    [NSApplication sharedApplication];

    sharedApplication = [[principal alloc] init];
    sharedApplication.applicationState = UIApplicationStateInactive;

    UIApplicationAppKitBridge *appKitBridge = [[UIApplicationAppKitBridge alloc] init];
    bridge = appKitBridge;
    appKitBridge.application = sharedApplication;
    if (delegateClass != Nil) {
        appKitBridge.delegateOwner = [[delegateClass alloc] init];
        sharedApplication.delegate = appKitBridge.delegateOwner;
    }

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
