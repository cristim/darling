#import <UIKit/UIButton.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>

@implementation UIButton {
    UIButtonType _buttonType;
    NSMutableDictionary<NSNumber *, NSString *> *_titles;
    NSMutableDictionary<NSNumber *, UIColor *> *_titleColors;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _titles = [[NSMutableDictionary alloc] init];
        _titleColors = [[NSMutableDictionary alloc] init];
    }
    return self;
}

// Rung 3 (init(type:) page): the custom button frame is (0, 0, 0, 0). Rung 6: the other types
// are created with the same empty frame, and any buttonType value is stored as given.
+ (instancetype)buttonWithType:(UIButtonType)buttonType
{
    UIButton *button = [[self alloc] initWithFrame:CGRectZero];
    button->_buttonType = buttonType;
    return button;
}

- (UIButtonType)buttonType { return _buttonType; }

// Rung 3 (settitle, title(for:), settitlecolor pages): a value is kept per state, and a state
// without its own value uses the one for UIControlStateNormal. Rung 6: states are matched by
// exact value (a combination such as Highlighted|Selected is its own state), nil removes a value,
// and when Normal is unset the result is nil because the pages only say "a system value".
- (void)setTitle:(NSString *)title forState:(UIControlState)state
{
    NSNumber *key = @(state);
    if (title) _titles[key] = [title copy]; else [_titles removeObjectForKey:key];
}

- (NSString *)titleForState:(UIControlState)state
{
    return _titles[@(state)] ?: _titles[@(UIControlStateNormal)];
}

- (void)setTitleColor:(UIColor *)color forState:(UIControlState)state
{
    NSNumber *key = @(state);
    if (color) _titleColors[key] = color; else [_titleColors removeObjectForKey:key];
}

- (UIColor *)titleColorForState:(UIControlState)state
{
    return _titleColors[@(state)] ?: _titleColors[@(UIControlStateNormal)];
}

@end
