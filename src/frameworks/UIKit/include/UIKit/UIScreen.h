// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <CoreGraphics/CGGeometry.h>

NS_ASSUME_NONNULL_BEGIN
@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
+ (NSArray<UIScreen *> *)screens;
@property(nonatomic, readonly) CGRect bounds;
@property(nonatomic, readonly) CGFloat scale;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END
