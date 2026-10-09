#ifndef DARLING_UIKIT_WINDOW_SCENE_H
#define DARLING_UIKIT_WINDOW_SCENE_H

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@class UIWindow;

// Superclass is NSObject until UIScene exists. Instances are meant to be created by the
// system from a UISceneConfiguration, which is not implemented yet.
@interface UIWindowScene : NSObject
@property(nonatomic, readonly) NSArray<UIWindow *> *windows;
@property(nonatomic, readonly, nullable) UIWindow *keyWindow;
@end

NS_ASSUME_NONNULL_END

#endif
