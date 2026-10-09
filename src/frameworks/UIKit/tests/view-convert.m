#import <UIKit/UIKit.h>
#import <Foundation/NSException.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)
#define NEAR(a, b) (fabs((double)(a) - (double)(b)) < 1e-9)
#define PT_IS(p, px, py) (NEAR((p).x, px) && NEAR((p).y, py))
#define RECT_IS(r, rx, ry, rw, rh) (NEAR((r).origin.x, rx) && NEAR((r).origin.y, ry) && NEAR((r).size.width, rw) && NEAR((r).size.height, rh))

static BOOL raises(void (^block)(void), NSString *name)
{
    @try { block(); } @catch (NSException *e) { return [e.name isEqualToString:name]; }
    return NO;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        CHECK(argc == 2);
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!library) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
        Class viewClass = NSClassFromString(@"UIView");
        CHECK(viewClass != Nil);
        // DocC Objective-C spellings.
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"convertPoint:toView:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"convertPoint:fromView:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"convertRect:toView:")]);
        CHECK([viewClass instancesRespondToSelector:NSSelectorFromString(@"convertRect:fromView:")]);

        UIView *root = [[viewClass alloc] initWithFrame:CGRectMake(0, 0, 200, 200)];
        UIView *child = [[viewClass alloc] initWithFrame:CGRectMake(10, 20, 100, 50)];
        UIView *grand = [[viewClass alloc] initWithFrame:CGRectMake(5, 5, 10, 10)];
        [root addSubview:child];
        [child addSubview:grand];

        // Identity transforms, zero bounds origins: the child's origin is its frame origin.
        CHECK(PT_IS([child convertPoint:CGPointMake(0, 0) toView:root], 10, 20));
        CHECK(PT_IS([grand convertPoint:CGPointMake(0, 0) toView:root], 15, 25));
        CHECK(PT_IS([root convertPoint:CGPointMake(15, 25) toView:grand], 0, 0));
        CHECK(PT_IS([grand convertPoint:CGPointMake(15, 25) fromView:root], 0, 0));
        CHECK(PT_IS([root convertPoint:CGPointMake(0, 0) fromView:grand], 15, 25));
        // rung 6: nil means the top-most ancestor's coordinate system.
        CHECK(PT_IS([grand convertPoint:CGPointMake(0, 0) toView:nil], 15, 25));
        CHECK(PT_IS([grand convertPoint:CGPointMake(15, 25) fromView:nil], 0, 0));
        CHECK(PT_IS([grand convertPoint:CGPointMake(3, 4) toView:grand], 3, 4));

        // Siblings convert through their common ancestor.
        UIView *s1 = [[viewClass alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
        UIView *s2 = [[viewClass alloc] initWithFrame:CGRectMake(100, 100, 50, 50)];
        [root addSubview:s1];
        [root addSubview:s2];
        CHECK(PT_IS([s1 convertPoint:CGPointMake(10, 10) toView:s2], -90, -90));
        // fromView: takes the point in the OTHER view's space. s1 sits at the root origin and s2 at
        // (100,100), so s1 (10,10) is root (10,10) is s2 (10-100,10-100) = (-90,-90); and s1
        // (-90,-90) is s2 (-190,-190). The reverse pair swaps the roles.
        CHECK(PT_IS([s2 convertPoint:CGPointMake(10, 10) fromView:s1], -90, -90));
        CHECK(PT_IS([s2 convertPoint:CGPointMake(-90, -90) fromView:s1], -190, -190));
        CHECK(PT_IS([s1 convertPoint:CGPointMake(-90, -90) fromView:s2], 10, 10));
        CHECK(PT_IS([grand convertPoint:CGPointMake(0, 0) toView:s2], -85, -75));

        // Rectangles.
        CHECK(RECT_IS([grand convertRect:CGRectMake(0, 0, 10, 10) toView:root], 15, 25, 10, 10));
        CHECK(RECT_IS([root convertRect:CGRectMake(0, 0, 10, 10) fromView:grand], 15, 25, 10, 10));
        CHECK(RECT_IS([grand convertRect:CGRectMake(15, 25, 10, 10) fromView:root], 0, 0, 10, 10));

        // Documented: the transform acts about the centre, so scaling by 2 maps the bounds
        // origin (-50,-25 from the centre) to twice that distance from the centre (60,45).
        child.transform = CGAffineTransformMakeScale(2, 2);
        CHECK(PT_IS([child convertPoint:CGPointMake(0, 0) toView:root], -40, -5));
        CHECK(PT_IS([child convertPoint:CGPointMake(50, 25) toView:root], 60, 45));
        CHECK(PT_IS([root convertPoint:CGPointMake(-40, -5) toView:child], 0, 0));
        child.transform = CGAffineTransformMakeRotation(M_PI_2);
        CHECK(PT_IS([child convertPoint:CGPointMake(60, 25) toView:root], 60, 55));
        CHECK(PT_IS([root convertPoint:CGPointMake(60, 55) toView:child], 60, 25));
        // rung 6: a rectangle becomes the bounding box of its converted corners.
        CHECK(RECT_IS([child convertRect:CGRectMake(0, 0, 100, 50) toView:root], 35, -5, 50, 100));
        child.transform = CGAffineTransformIdentity;

        // rung 6: a non-zero bounds origin shifts which child point sits at the view's centre.
        child.bounds = CGRectMake(30, 40, 100, 50);
        CHECK(PT_IS([child convertPoint:CGPointMake(30, 40) toView:root], 10, 20));
        CHECK(PT_IS([grand convertPoint:CGPointMake(0, 0) toView:root], -15, -15));
        CHECK(PT_IS([root convertPoint:CGPointMake(10, 20) toView:child], 30, 40));
        child.bounds = CGRectMake(0, 0, 100, 50);

        // rung 6 errors: separate hierarchies, and a transform that cannot be inverted.
        UIView *lonely = [[viewClass alloc] initWithFrame:CGRectMake(0, 0, 5, 5)];
        CHECK(raises(^{ [lonely convertPoint:CGPointZero toView:root]; }, NSInvalidArgumentException));
        CHECK(raises(^{ [root convertPoint:CGPointZero fromView:lonely]; }, NSInvalidArgumentException));
        child.transform = CGAffineTransformMakeScale(0, 0);
        CHECK(raises(^{ [root convertPoint:CGPointZero toView:child]; }, NSInvalidArgumentException));
        puts("PASS UIKit UIView coordinate conversion");
    }
    return 0;
}
