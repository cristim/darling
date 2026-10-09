// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#import <UIKit/UIResponder.h>
#import <UIKit/UIApplicationDelegate.h>
#import <Foundation/NSObjCRuntime.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, UIApplicationState) {
    UIApplicationStateActive,
    UIApplicationStateInactive,
    UIApplicationStateBackground,
};

@interface UIApplication : UIResponder
// nil until UIApplicationMain has created the application.
+ (nullable UIApplication *)sharedApplication;
@property(nullable, nonatomic, assign) id<UIApplicationDelegate> delegate;
@property(nonatomic, readonly) UIApplicationState applicationState;
@end

// Darling host failure policy, not UIKit behaviour: a startup failure writes one
// "UIApplicationMain: <cause>" line to stderr and exits with status 1. Success never returns.
FOUNDATION_EXPORT int UIApplicationMain(int argc, char *_Nullable *_Nonnull argv,
                      NSString *_Nullable principalClassName,
                      NSString *_Nullable delegateClassName);
NS_ASSUME_NONNULL_END
