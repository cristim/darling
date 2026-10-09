#import <UIKit/UIKit.h>
#import <Foundation/NSException.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

static NSMutableArray *gLog;

static BOOL raises(void (^block)(void), NSString *name)
{
    @try { block(); } @catch (NSException *e) { return [e.name isEqualToString:name]; }
    return NO;
}

// Records every hierarchy callback as "<tag>:<event>[:<other tag>]".
static NSString *tagOf(UIView *v) { return v ? [NSString stringWithFormat:@"%ld", (long)v.tag] : @"nil"; }

static Class makeRecorder(Class base)
{
    Class c = objc_allocateClassPair(base, "RecordingView", 0);
    class_addMethod(c, NSSelectorFromString(@"willMoveToSuperview:"),
        imp_implementationWithBlock(^(UIView *self_, UIView *to) {
            [gLog addObject:[NSString stringWithFormat:@"%@:willMove:%@:was:%@", tagOf(self_), tagOf(to), tagOf(self_.superview)]]; }), "v@:@");
    class_addMethod(c, NSSelectorFromString(@"didMoveToSuperview"),
        imp_implementationWithBlock(^(UIView *self_) {
            [gLog addObject:[NSString stringWithFormat:@"%@:didMove:now:%@", tagOf(self_), tagOf(self_.superview)]]; }), "v@:");
    class_addMethod(c, NSSelectorFromString(@"didAddSubview:"),
        imp_implementationWithBlock(^(UIView *self_, UIView *sub) {
            [gLog addObject:[NSString stringWithFormat:@"%@:didAdd:%@", tagOf(self_), tagOf(sub)]]; }), "v@:@");
    class_addMethod(c, NSSelectorFromString(@"willRemoveSubview:"),
        imp_implementationWithBlock(^(UIView *self_, UIView *sub) {
            [gLog addObject:[NSString stringWithFormat:@"%@:willRemove:%@", tagOf(self_), tagOf(sub)]]; }), "v@:@");
    objc_registerClassPair(c);
    return c;
}

static NSString *order(UIView *v)
{
    NSMutableArray *tags = [NSMutableArray array];
    for (UIView *s in v.subviews) [tags addObject:tagOf(s)];
    return [tags componentsJoinedByString:@","];
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
        const char *selectors[] = {"superview", "subviews", "addSubview:", "removeFromSuperview",
            "insertSubview:atIndex:", "insertSubview:aboveSubview:", "insertSubview:belowSubview:",
            "bringSubviewToFront:", "sendSubviewToBack:", "exchangeSubviewAtIndex:withSubviewAtIndex:",
            "isDescendantOfView:", "viewWithTag:", "willMoveToSuperview:", "didMoveToSuperview",
            "didAddSubview:", "willRemoveSubview:"};
        for (unsigned i = 0; i < sizeof selectors / sizeof *selectors; i++) {
            if (![viewClass instancesRespondToSelector:sel_registerName(selectors[i])]) {
                fprintf(stderr, "missing selector %s\n", selectors[i]);
                return 1;
            }
        }
        Class recClass = makeRecorder(viewClass);
        gLog = [NSMutableArray array];
        UIView *(^make)(NSInteger) = ^UIView *(NSInteger tag) {
            UIView *v = [[recClass alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
            v.tag = tag;
            return v;
        };

        // Documented: subviews are ordered back (index 0) to front; addSubview: appends and sets
        // the superview and the next responder.
        UIView *root = make(1), *a = make(2), *b = make(3), *c = make(4);
        CHECK(root.superview == nil && root.subviews.count == 0 && [root nextResponder] == nil);
        [root addSubview:a]; [root addSubview:b]; [root addSubview:c];
        CHECK([order(root) isEqualToString:@"2,3,4"]);
        CHECK(a.superview == root && [a nextResponder] == root);
        // subviews is declared copy: an earlier read is not changed by later edits.
        NSArray *snapshot = root.subviews;
        [b removeFromSuperview];
        CHECK(snapshot.count == 3 && root.subviews.count == 2);

        // Documented: removeFromSuperview clears the superview; removing a parentless view is harmless.
        CHECK(b.superview == nil && [order(root) isEqualToString:@"2,4"]);
        [b removeFromSuperview];
        CHECK(b.superview == nil);

        // Documented: moving a view to a new superview removes it from the old one.
        UIView *other = make(5);
        [other addSubview:a];
        CHECK(a.superview == other && [order(root) isEqualToString:@"4"] && [order(other) isEqualToString:@"2"]);

        // insertSubview variants.
        [root insertSubview:b atIndex:0];
        CHECK([order(root) isEqualToString:@"3,4"]);
        UIView *d = make(6), *e = make(7), *f = make(8);
        [root insertSubview:d aboveSubview:b];
        [root insertSubview:e belowSubview:b];
        [root insertSubview:f atIndex:(NSInteger)root.subviews.count];
        CHECK([order(root) isEqualToString:@"7,3,6,4,8"]);

        // bring to front / send to back / exchange.
        [root bringSubviewToFront:e];
        CHECK([order(root) isEqualToString:@"3,6,4,8,7"]);
        [root sendSubviewToBack:f];
        CHECK([order(root) isEqualToString:@"8,3,6,4,7"]);
        [root exchangeSubviewAtIndex:0 withSubviewAtIndex:4];
        CHECK([order(root) isEqualToString:@"7,3,6,4,8"]);
        [root bringSubviewToFront:a];   // not a subview of root: ignored (rung 6)
        CHECK([order(root) isEqualToString:@"7,3,6,4,8"] && a.superview == other);

        // Documented: addSubview: puts the view on top. Re-adding a current subview moves it
        // there (rung 6) and, since the superview does not change, sends no hook.
        [gLog removeAllObjects];
        [root addSubview:e];
        CHECK([order(root) isEqualToString:@"3,6,4,8,7"] && e.superview == root);
        [root addSubview:e];
        CHECK([order(root) isEqualToString:@"3,6,4,8,7"]);
        [root addSubview:b];
        CHECK([order(root) isEqualToString:@"6,4,8,7,3"] && gLog.count == 0);
        [root addSubview:b];                 // already on top: unchanged
        CHECK([order(root) isEqualToString:@"6,4,8,7,3"]);

        // isDescendantOfView: includes the view itself and distant subviews.
        [a addSubview:make(9)];
        UIView *deep = [a viewWithTag:9];
        CHECK(deep != nil && deep.superview == a);
        CHECK([deep isDescendantOfView:other] && [deep isDescendantOfView:a] && [deep isDescendantOfView:deep]);
        CHECK(![other isDescendantOfView:deep] && ![deep isDescendantOfView:root]);

        // viewWithTag: searches the receiver and all subviews; unknown tag gives nil.
        CHECK([other viewWithTag:5] == other && [other viewWithTag:2] == a && [other viewWithTag:9] == deep);
        CHECK([other viewWithTag:1234] == nil);

        // Errors (rung 6 exception types).
        CHECK(raises(^{ [root addSubview:root]; }, NSInvalidArgumentException));
        CHECK(raises(^{ [deep addSubview:other]; }, NSInvalidArgumentException));
        CHECK(raises(^{ [root addSubview:nil]; }, NSInvalidArgumentException));
        CHECK(raises(^{ [root insertSubview:make(20) atIndex:99]; }, NSRangeException));
        CHECK(raises(^{ [root insertSubview:make(21) aboveSubview:other]; }, NSInvalidArgumentException));
        CHECK(raises(^{ [root exchangeSubviewAtIndex:0 withSubviewAtIndex:5]; }, NSRangeException));
        CHECK([order(root) isEqualToString:@"6,4,8,7,3"]);   // failed calls changed nothing
        // x is not its own sibling; the failed call must not detach it.
        CHECK(raises(^{ [root insertSubview:d aboveSubview:d]; }, NSInvalidArgumentException));
        CHECK(d.superview == root && [order(root) isEqualToString:@"6,4,8,7,3"]);
        CHECK(raises(^{ [root insertSubview:d atIndex:6]; }, NSRangeException));

        // Documented: the index may equal the number of subviews. For a current subview that
        // means the end (rung 6 for the counting of the other subviews).
        [root insertSubview:d atIndex:5];
        CHECK([order(root) isEqualToString:@"4,8,7,3,6"]);
        [root insertSubview:d atIndex:0];
        CHECK([order(root) isEqualToString:@"6,4,8,7,3"]);
        [root insertSubview:d aboveSubview:b];
        CHECK([order(root) isEqualToString:@"4,8,7,3,6"]);
        [root insertSubview:d belowSubview:e];
        CHECK([order(root) isEqualToString:@"4,8,6,7,3"]);

        // Callbacks. Documented only: each is called and the defaults do nothing.
        // Order within one operation is rung 6; the assertions below pin what the names imply.
        [gLog removeAllObjects];
        UIView *p = make(30), *q = make(31);
        [p addSubview:q];
        CHECK([gLog containsObject:@"31:willMove:30:was:nil"]);
        CHECK([gLog containsObject:@"31:didMove:now:30"]);
        CHECK([gLog containsObject:@"30:didAdd:31"]);
        [gLog removeAllObjects];
        [q removeFromSuperview];
        CHECK([gLog containsObject:@"30:willRemove:31"]);
        CHECK([gLog containsObject:@"31:willMove:nil:was:30"]);
        CHECK([gLog containsObject:@"31:didMove:now:nil"]);
        CHECK(gLog.count == 3);
        [gLog removeAllObjects];
        [q removeFromSuperview];            // no superview: no callbacks
        CHECK(gLog.count == 0);

        // Moving to another superview: one transition naming the new superview, no nil step
        // (rung 6). willRemoveSubview: goes to the old parent.
        UIView *oldParent = make(50), *newParent = make(51), *mover = make(52);
        [oldParent addSubview:mover];
        [gLog removeAllObjects];
        [newParent addSubview:mover];
        CHECK([gLog isEqualToArray:(@[@"50:willRemove:52", @"52:willMove:51:was:50",
                                     @"52:didMove:now:51", @"51:didAdd:52"])]);
        CHECK(oldParent.subviews.count == 0 && mover.superview == newParent);

        // A view owned only by its parent survives its own removal and its hooks (a crash,
        // not a value, is what this guards; ARC may keep the receiver alive in the caller).
        @autoreleasepool {
            UIView *holder = make(60);
            [holder addSubview:make(61)];
            [[holder.subviews objectAtIndex:0] removeFromSuperview];
            CHECK(holder.subviews.count == 0);
        }

        // A parent going away does not leave dangling superview pointers.
        UIView *orphan = make(40);
        @autoreleasepool {
            UIView *parent = make(41);
            [parent addSubview:orphan];
            CHECK(orphan.superview == parent);
        }
        CHECK(orphan.superview == nil);
        puts("PASS UIKit UIView hierarchy");
    }
    return 0;
}
