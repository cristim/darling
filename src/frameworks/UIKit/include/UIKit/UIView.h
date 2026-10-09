#ifndef DARLING_UIKIT_VIEW_H
#define DARLING_UIKIT_VIEW_H

#import <UIKit/UIResponder.h>
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGAffineTransform.h>

NS_ASSUME_NONNULL_BEGIN

// Data model only: there is no layer, drawing or window hosting yet.
@interface UIView : UIResponder
- (instancetype)initWithFrame:(CGRect)frame;

// frame is derived from bounds, center and transform, not stored.
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGPoint center;
@property(nonatomic) CGAffineTransform transform;
@end

NS_ASSUME_NONNULL_END

#endif
