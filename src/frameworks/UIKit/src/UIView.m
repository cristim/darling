#import <UIKit/UIView.h>

@implementation UIView {
    CGRect _bounds;
    CGPoint _center;
    CGAffineTransform _transform;
}

// rung 6: UIView's plain -init is not on the pages read; it is routed to the documented
// designated initializer with an empty frame so no field is left zeroed by accident.
- (instancetype)init
{
    return [self initWithFrame:CGRectZero];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super init];
    if (self) {
        _bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
        _center = CGPointMake(frame.origin.x + frame.size.width / 2, frame.origin.y + frame.size.height / 2);
        _transform = CGAffineTransformIdentity;
    }
    return self;
}

- (CGRect)bounds { return _bounds; }
- (void)setBounds:(CGRect)bounds { _bounds = bounds; }
- (CGPoint)center { return _center; }
- (void)setCenter:(CGPoint)center { _center = center; }
- (CGAffineTransform)transform { return _transform; }
- (void)setTransform:(CGAffineTransform)transform { _transform = transform; }

// Transforms act about the center (documented: the anchor point defaults to the center of
// the frame rectangle). rung 6: with a non-identity transform the pages call frame undefined;
// the bounding box of the transformed bounds, translation included, is returned.
- (CGRect)frame
{
    CGFloat halfW = _bounds.size.width / 2, halfH = _bounds.size.height / 2;
    CGPoint corners[4] = {{-halfW, -halfH}, {halfW, -halfH}, {halfW, halfH}, {-halfW, halfH}};
    CGFloat minX = 0, minY = 0, maxX = 0, maxY = 0;
    for (int i = 0; i < 4; i++) {
        CGPoint p = CGPointApplyAffineTransform(corners[i], _transform);
        if (i == 0 || p.x < minX) minX = p.x;
        if (i == 0 || p.x > maxX) maxX = p.x;
        if (i == 0 || p.y < minY) minY = p.y;
        if (i == 0 || p.y > maxY) maxY = p.y;
    }
    return CGRectMake(_center.x + minX, _center.y + minY, maxX - minX, maxY - minY);
}

// rung 6: the pages call frame undefined under a non-identity transform and say not to set
// it; the setter then still moves center and resizes bounds exactly as for the identity case.
- (void)setFrame:(CGRect)frame
{
    _center = CGPointMake(frame.origin.x + frame.size.width / 2, frame.origin.y + frame.size.height / 2);
    _bounds.size = frame.size;
}

@end
