#ifndef DARLING_UIKIT_VIEW_H
#define DARLING_UIKIT_VIEW_H

#import <UIKit/UIResponder.h>
#import <UIKit/UIColor.h>
#import <Foundation/NSArray.h>
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGAffineTransform.h>

NS_ASSUME_NONNULL_BEGIN

@class UIWindow;

// Data model only: there is no layer, drawing or window hosting yet.
@interface UIView : UIResponder
- (instancetype)initWithFrame:(CGRect)frame;

// frame is derived from bounds, center and transform, not stored.
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGPoint center;
@property(nonatomic) CGAffineTransform transform;

@property(nonatomic) NSInteger tag;
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic) CGFloat alpha;
@property(nonatomic, getter=isOpaque) BOOL opaque;
@property(nonatomic) BOOL clipsToBounds;
@property(nonatomic, copy, nullable) UIColor *backgroundColor;
@property(nonatomic, readonly, nullable) UIView *superview;
// Index 0 is the back-most view.
@property(nonatomic, copy, readonly) NSArray<__kindof UIView *> *subviews;
- (void)addSubview:(UIView *)view;
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index;
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)siblingSubview;
- (void)insertSubview:(UIView *)view belowSubview:(UIView *)siblingSubview;
- (void)removeFromSuperview;
- (void)bringSubviewToFront:(UIView *)view;
- (void)sendSubviewToBack:(UIView *)view;
- (void)exchangeSubviewAtIndex:(NSInteger)index1 withSubviewAtIndex:(NSInteger)index2;
- (BOOL)isDescendantOfView:(UIView *)view;
- (nullable __kindof UIView *)viewWithTag:(NSInteger)tag;
// A nil view means the coordinate system of the top-most ancestor (there is no UIWindow yet).
- (CGPoint)convertPoint:(CGPoint)point toView:(nullable UIView *)view;
- (CGPoint)convertPoint:(CGPoint)point fromView:(nullable UIView *)view;
- (CGRect)convertRect:(CGRect)rect toView:(nullable UIView *)view;
- (CGRect)convertRect:(CGRect)rect fromView:(nullable UIView *)view;
- (void)willMoveToSuperview:(nullable UIView *)newSuperview;
- (void)didMoveToSuperview;
- (void)didAddSubview:(UIView *)subview;
- (void)willRemoveSubview:(UIView *)subview;

// Always nil until UIWindow exists: no view can be in a window yet.
@property(nonatomic, readonly, nullable) UIWindow *window;
@end

NS_ASSUME_NONNULL_END

#endif
