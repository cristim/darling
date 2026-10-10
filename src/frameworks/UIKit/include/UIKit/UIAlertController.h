#pragma once
#import <UIKit/UIResponder.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

// rung 6, ABI RISK: the pages name these constants but give no numeric values and no other
// vendored source has them. The values below are a guess in declaration order and must be
// confirmed (rung 3/4) before binary clients depend on them.
typedef NS_ENUM(NSInteger, UIAlertActionStyle) {
    UIAlertActionStyleDefault = 0,
    UIAlertActionStyleCancel,
    UIAlertActionStyleDestructive,
};

typedef NS_ENUM(NSInteger, UIAlertControllerStyle) {
    UIAlertControllerStyleActionSheet = 0,
    UIAlertControllerStyleAlert,
};

NS_ASSUME_NONNULL_BEGIN

// Data model only: the action's handler is stored but nothing can select an action because
// there is no presentation.
@interface UIAlertAction : NSObject
+ (instancetype)actionWithTitle:(nullable NSString *)title style:(UIAlertActionStyle)style
                        handler:(void (^_Nullable)(UIAlertAction *action))handler;
// Readonly is not stated on the pages that could be fetched (rung 6).
@property(nonatomic, readonly, nullable) NSString *title;
@property(nonatomic, readonly) UIAlertActionStyle style;
@end

// Rung 6: the documented superclass is UIViewController, which does not exist in this tree
// yet; UIResponder (its superclass) stands in until it does.
@interface UIAlertController : UIResponder
+ (instancetype)alertControllerWithTitle:(nullable NSString *)title message:(nullable NSString *)message
                          preferredStyle:(UIAlertControllerStyle)preferredStyle;
@property(nonatomic, copy, nullable) NSString *title;
@property(nonatomic, copy, nullable) NSString *message;
@property(nonatomic, readonly) UIAlertControllerStyle preferredStyle;
- (void)addAction:(UIAlertAction *)action;
@property(nonatomic, readonly) NSArray<UIAlertAction *> *actions;
@end

NS_ASSUME_NONNULL_END
