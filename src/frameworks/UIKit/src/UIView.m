#import <UIKit/UIView.h>
#import <Foundation/NSException.h>

@implementation UIView {
    CGRect _bounds;
    CGPoint _center;
    CGAffineTransform _transform;
    NSInteger _tag;
    BOOL _hidden;
    CGFloat _alpha;
    BOOL _opaque;
    BOOL _clipsToBounds;
    UIColor *_backgroundColor;
    __unsafe_unretained UIView *_superview;
    NSMutableArray *_subviews;
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
        // Documented defaults: tag 0, not hidden, opaque YES, clipsToBounds NO,
        // backgroundColor nil. alpha 1.0 is the "totally opaque" end of the documented range;
        // the pages read do not state the default (rung 6).
        _alpha = 1.0;
        _opaque = YES;
        _subviews = [[NSMutableArray alloc] init];
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

- (NSInteger)tag { return _tag; }
- (void)setTag:(NSInteger)tag { _tag = tag; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)hidden { _hidden = hidden; }
// rung 6: stored as given; the pages describe the range 0.0 to 1.0 but not what happens outside it.
- (CGFloat)alpha { return _alpha; }
- (void)setAlpha:(CGFloat)alpha { _alpha = alpha; }
- (BOOL)isOpaque { return _opaque; }
- (void)setOpaque:(BOOL)opaque { _opaque = opaque; }
- (BOOL)clipsToBounds { return _clipsToBounds; }
- (void)setClipsToBounds:(BOOL)clipsToBounds { _clipsToBounds = clipsToBounds; }
- (UIColor *)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(UIColor *)backgroundColor { _backgroundColor = [backgroundColor copy]; }

- (UIWindow *)window { return nil; }

- (void)dealloc
{
    for (UIView *subview in _subviews) {
        subview->_superview = nil;
    }
}

- (UIView *)superview { return _superview; }
- (NSArray *)subviews { return [_subviews copy]; }

// Documented: addSubview: sets the next responder of the view to the receiver.
- (UIResponder *)nextResponder { return _superview; }

- (BOOL)isDescendantOfView:(UIView *)view
{
    for (UIView *v = self; v; v = v->_superview) {
        if (v == view) return YES;
    }
    return NO;
}

// Checks shared by every insertion. Raising is rung 6: the pages read do not say what
// UIKit does for nil, self or an ancestor.
- (void)_validateNewSubview:(UIView *)view
{
    if (!view) {
        [NSException raise:NSInvalidArgumentException format:@"cannot add a nil subview"];
    }
    if ([self isDescendantOfView:view]) {
        [NSException raise:NSInvalidArgumentException format:@"a view cannot be a subview of itself or of its own subview"];
    }
}

// `index` addresses the subviews with `view` itself left out. Documented: a view has one
// superview and an existing one is removed.
// rung 6: moving a view from another superview sends one willRemoveSubview: to the old parent
// and one willMoveToSuperview:/didMoveToSuperview pair naming the new one (no nil step);
// repositioning a view within its current superview sends no hook, since no superview changes.
- (void)_placeValidatedSubview:(UIView *)view atIndex:(NSUInteger)index
{
    __strong UIView *keepAlive = view;
    UIView *old = view->_superview;
    if (old == self) {
        [_subviews removeObjectIdenticalTo:keepAlive];
        [_subviews insertObject:keepAlive atIndex:index];
        return;
    }
    [old willRemoveSubview:keepAlive];
    [keepAlive willMoveToSuperview:self];
    if (old) [old->_subviews removeObjectIdenticalTo:keepAlive];
    [_subviews insertObject:keepAlive atIndex:index];
    keepAlive->_superview = self;
    [keepAlive didMoveToSuperview];
    [self didAddSubview:keepAlive];
}

- (NSUInteger)_subviewCountExcluding:(UIView *)view
{
    return _subviews.count - (view->_superview == self ? 1 : 0);
}

- (void)addSubview:(UIView *)view
{
    [self _validateNewSubview:view];
    [self _placeValidatedSubview:view atIndex:[self _subviewCountExcluding:view]];
}

// Documented: the index cannot be greater than the number of subviews. rung 6: for a view that
// is already a subview the index counts the other subviews, and the count itself means the end.
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index
{
    [self _validateNewSubview:view];
    if (index < 0 || index > (NSInteger)_subviews.count) {
        [NSException raise:NSRangeException format:@"subview index %ld out of range 0...%lu", (long)index, (unsigned long)_subviews.count];
    }
    NSUInteger target = MIN((NSUInteger)index, [self _subviewCountExcluding:view]);
    [self _placeValidatedSubview:view atIndex:target];
}

- (void)_insertSubview:(UIView *)view relativeTo:(UIView *)sibling offset:(NSInteger)offset
{
    [self _validateNewSubview:view];
    if (view == sibling || ![_subviews containsObject:sibling]) {
        [NSException raise:NSInvalidArgumentException format:@"the sibling must be another subview of the receiver"];
    }
    NSUInteger siblingIndex = [_subviews indexOfObjectIdenticalTo:sibling];
    if (view->_superview == self && [_subviews indexOfObjectIdenticalTo:view] < siblingIndex) {
        siblingIndex--;
    }
    [self _placeValidatedSubview:view atIndex:siblingIndex + offset];
}

- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)siblingSubview
{
    [self _insertSubview:view relativeTo:siblingSubview offset:1];
}

- (void)insertSubview:(UIView *)view belowSubview:(UIView *)siblingSubview
{
    [self _insertSubview:view relativeTo:siblingSubview offset:0];
}

// rung 6: callback order is willRemoveSubview:, willMoveToSuperview:nil, removal,
// didMoveToSuperview; the pages only say each is called.
- (void)removeFromSuperview
{
    UIView *parent = _superview;
    if (!parent) return;
    __strong UIView *keepAlive = self;
    [parent willRemoveSubview:keepAlive];
    [keepAlive willMoveToSuperview:nil];
    [parent->_subviews removeObjectIdenticalTo:keepAlive];
    keepAlive->_superview = nil;
    [keepAlive didMoveToSuperview];
}

// rung 6: a view that is not a subview of the receiver is ignored.
- (void)bringSubviewToFront:(UIView *)view
{
    if (view.superview != self) return;
    __strong UIView *keepAlive = view;
    [_subviews removeObjectIdenticalTo:keepAlive];
    [_subviews addObject:keepAlive];
}

- (void)sendSubviewToBack:(UIView *)view
{
    if (view.superview != self) return;
    __strong UIView *keepAlive = view;
    [_subviews removeObjectIdenticalTo:keepAlive];
    [_subviews insertObject:keepAlive atIndex:0];
}

// rung 6: both indices must be below the subview count.
- (void)exchangeSubviewAtIndex:(NSInteger)index1 withSubviewAtIndex:(NSInteger)index2
{
    NSInteger count = (NSInteger)_subviews.count;
    if (index1 < 0 || index1 >= count || index2 < 0 || index2 >= count) {
        [NSException raise:NSRangeException format:@"subview indices %ld and %ld out of range 0..<%ld", (long)index1, (long)index2, (long)count];
    }
    [_subviews exchangeObjectAtIndex:(NSUInteger)index1 withObjectAtIndex:(NSUInteger)index2];
}

// Documented: searches the receiver and all its subviews. rung 6: receiver first, then
// depth-first in subview order, so the first match in that order wins.
- (UIView *)viewWithTag:(NSInteger)tag
{
    if (_tag == tag) return self;
    for (UIView *subview in _subviews) {
        UIView *found = [subview viewWithTag:tag];
        if (found) return found;
    }
    return nil;
}

// Documented: the default implementations do nothing.
- (void)willMoveToSuperview:(UIView *)newSuperview {}
- (void)didMoveToSuperview {}
- (void)didAddSubview:(UIView *)subview {}
- (void)willRemoveSubview:(UIView *)subview {}

@end
