// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#import <Foundation/NSObject.h>
#import <Foundation/NSDictionary.h>

@class UIApplication;

NS_ASSUME_NONNULL_BEGIN
@protocol UIApplicationDelegate <NSObject>
@optional
- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(nullable NSDictionary *)launchOptions;
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(nullable NSDictionary *)launchOptions;
- (void)applicationWillTerminate:(UIApplication *)application;
@end
NS_ASSUME_NONNULL_END
