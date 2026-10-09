#import <UIKit/UIWindowScene.h>

@implementation UIWindowScene

// UIWindow does not exist yet, so no scene can own a window.
- (NSArray<UIWindow *> *)windows
{
    return @[];
}

- (UIWindow *)keyWindow
{
    return nil;
}

@end
