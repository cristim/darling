#ifndef DARLING_UIKIT_VIEW_H
#define DARLING_UIKIT_VIEW_H

#import <UIKit/UIResponder.h>
#import <UIKit/UIColor.h>
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
// Always nil until UIWindow exists: no view can be in a window yet.
@property(nonatomic, readonly, nullable) UIWindow *window;
@end

NS_ASSUME_NONNULL_END

#endif
