#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)
#define NEAR(a, b) (fabs((double)(a) - (double)(b)) < 1e-9)
#define RECT_IS(r, x, y, w, h) (NEAR((r).origin.x, x) && NEAR((r).origin.y, y) && NEAR((r).size.width, w) && NEAR((r).size.height, h))

int main(int argc, char **argv)
{
    @autoreleasepool {
        CHECK(argc == 2);
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!library) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
        Class viewClass = NSClassFromString(@"UIView");
        CHECK(viewClass != Nil && [viewClass isSubclassOfClass:NSClassFromString(@"UIResponder")]);
        // Selector spellings are the ones on the DocC pages (Objective-C variant).
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"initWithFrame:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"frame")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"setFrame:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"bounds")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"setCenter:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"setTransform:")]);

        // Documented: bounds origin is (0,0) and its size equals the frame size; center is the
        // center of the frame rectangle; the transform defaults to the identity.
        UIView *view = [[viewClass alloc] initWithFrame:CGRectMake(10, 20, 100, 50)];
        CHECK(RECT_IS(view.frame, 10, 20, 100, 50));
        CHECK(RECT_IS(view.bounds, 0, 0, 100, 50));
        CHECK(NEAR(view.center.x, 60) && NEAR(view.center.y, 45));
        CHECK(CGAffineTransformIsIdentity(view.transform));

        // Documented: setting center moves the frame origin and leaves the size alone.
        view.center = CGPointMake(0, 0);
        CHECK(RECT_IS(view.frame, -50, -25, 100, 50));
        CHECK(RECT_IS(view.bounds, 0, 0, 100, 50));

        // Documented: setting frame changes center and the size of bounds.
        view.frame = CGRectMake(5, 6, 20, 30);
        CHECK(NEAR(view.center.x, 15) && NEAR(view.center.y, 21));
        CHECK(RECT_IS(view.bounds, 0, 0, 20, 30));

        // Documented: changing the bounds size grows the view about its center and the frame
        // size follows.
        view.bounds = CGRectMake(0, 0, 40, 60);
        CHECK(NEAR(view.center.x, 15) && NEAR(view.center.y, 21));
        CHECK(RECT_IS(view.frame, -5, -9, 40, 60));

        // Documented: a transform scales or rotates the frame within the superview and does not
        // touch center or bounds. The frame values below are rung 6 (the pages call frame
        // undefined for a non-identity transform).
        view.transform = CGAffineTransformMakeScale(2, 0.5);
        CHECK(NEAR(view.center.x, 15) && NEAR(view.center.y, 21));
        CHECK(RECT_IS(view.bounds, 0, 0, 40, 60));
        CHECK(RECT_IS(view.frame, -25, 6, 80, 30));
        view.transform = CGAffineTransformMakeRotation(M_PI_2);
        CHECK(NEAR(view.frame.size.width, 60) && NEAR(view.frame.size.height, 40));
        CHECK(NEAR(view.frame.origin.x, 15 - 30) && NEAR(view.frame.origin.y, 21 - 20));
        view.transform = CGAffineTransformIdentity;
        CHECK(RECT_IS(view.frame, -5, -9, 40, 60));

        // rung 6: plain init is an empty frame.
        UIView *plain = [[viewClass alloc] init];
        CHECK(RECT_IS(plain.frame, 0, 0, 0, 0));
        CHECK(CGAffineTransformIsIdentity(plain.transform));
        puts("PASS UIKit UIView geometry");
    }
    return 0;
}
