#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

int main(int argc, char **argv)
{
    @autoreleasepool {
        CHECK(argc == 2);
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!library) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
        Class viewClass = NSClassFromString(@"UIView");
        CHECK(viewClass != Nil);
        // Spellings from the DocC Objective-C declarations; the BOOL getters are isHidden and isOpaque.
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"isHidden")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"setHidden:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"isOpaque")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"setOpaque:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"clipsToBounds")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"setBackgroundColor:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"window")]);
        CHECK(![viewClass instancesRespondToSelector:NSSelectorFromString(@"hidden")]);
        CHECK(![viewClass instancesRespondToSelector:NSSelectorFromString(@"opaque")]);

        UIView *view = [[viewClass alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        // Documented defaults.
        CHECK(view.tag == 0);
        CHECK(!view.hidden);
        CHECK(view.opaque);
        CHECK(!view.clipsToBounds);
        CHECK(view.backgroundColor == nil);
        CHECK(view.window == nil);
        CHECK(view.alpha == 1.0);   // rung 6: default not stated on the pages read

        view.tag = 42; CHECK(view.tag == 42);
        view.tag = -7; CHECK(view.tag == -7);
        view.hidden = YES; CHECK(view.hidden && [view isHidden]);
        view.hidden = NO; CHECK(![view isHidden]);
        view.alpha = 0.25; CHECK(view.alpha == 0.25);
        view.opaque = NO; CHECK(![view isOpaque]);
        view.clipsToBounds = YES; CHECK(view.clipsToBounds);

        // backgroundColor is declared copy; the stored colour compares equal in value.
        UIColor *red = [UIColor colorWithRed:1 green:0 blue:0 alpha:1];
        view.backgroundColor = red;
        CGFloat r = -1, g = -1, b = -1, a = -1;
        CHECK(view.backgroundColor != nil);
        CHECK([view.backgroundColor getRed:&r green:&g blue:&b alpha:&a]);
        CHECK(r == 1 && g == 0 && b == 0 && a == 1);
        view.backgroundColor = nil;
        CHECK(view.backgroundColor == nil);

        // None of the state properties touches the geometry.
        CHECK(CGRectEqualToRect(view.frame, CGRectMake(0, 0, 10, 10)));
        puts("PASS UIKit UIView state properties");
    }
    return 0;
}
