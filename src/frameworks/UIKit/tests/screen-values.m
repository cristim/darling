// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIScreen.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

@interface StubScreen : NSScreen
@property(nonatomic) NSRect stubFrame;
@property(nonatomic) CGFloat stubScale;
@end
@implementation StubScreen
- (NSRect)frame { return _stubFrame; }
- (CGFloat)backingScaleFactor { return _stubScale; }
@end

// Inherits the base backingScaleFactor, which UIScreen must reject.
@interface BaseScaleScreen : NSScreen
@end
@implementation BaseScaleScreen
- (NSRect)frame { return NSMakeRect(0, 0, 100, 100); }
@end

@interface UIScreen (Fixture)
+ (NSArray *)screensForNativeScreens:(NSArray *)nativeScreens;
@end

static BOOL raises(NSString *name, void (^block)(void))
{
    @try { block(); } @catch (NSException *e) { return [[e name] isEqualToString:name]; }
    return NO;
}

static StubScreen *stub(NSRect frame, CGFloat scale)
{
    StubScreen *s = [[StubScreen alloc] init];
    s.stubFrame = frame;
    s.stubScale = scale;
    return s;
}

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

static BOOL parsePositive(const char *name, double *value)
{
    const char *text = getenv(name);
    if (!text || !*text) return NO;
    char *end;
    *value = strtod(text, &end);
    return end != text && *end == '\0' && isfinite(*value) && *value > 0;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        CHECK(argc == 1);
        double width, height, scale;
        CHECK(parsePositive("SCREEN_EXPECT_WIDTH", &width));
        CHECK(parsePositive("SCREEN_EXPECT_HEIGHT", &height));
        CHECK(parsePositive("SCREEN_EXPECT_SCALE", &scale));
        const char *path = getenv("SCREEN_LIBRARY");
        CHECK(path != NULL);
        void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!library) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
        Class screenClass = NSClassFromString(@"UIScreen");
        CHECK(screenClass != Nil);

        NSApplication *app = [NSApplication sharedApplication];
        CHECK([[app windows] count] == 0);
        NSArray *nativeScreens = [NSScreen screens];
        CHECK([nativeScreens count] == 1);
        NSScreen *native = [nativeScreens objectAtIndex:0];
        CHECK([NSStringFromClass([native class]) isEqualToString:@"WaylandScreen"]);
        CHECK(class_getMethodImplementation([native class], @selector(backingScaleFactor)) !=
              class_getMethodImplementation([NSScreen class], @selector(backingScaleFactor)));
        NSRect nativeFrame = [native frame];
        CHECK(nativeFrame.size.width == width && nativeFrame.size.height == height);
        CHECK([native backingScaleFactor] == scale);

        @try {
            NSArray *screens = [screenClass screens];
            CHECK([screens count] == 1);
            UIScreen *main = [screenClass mainScreen];
            CHECK(main != nil);
            UIScreen *first = [screens objectAtIndex:0];
            CGRect bounds = main.bounds;
            CHECK(bounds.origin.x == 0 && bounds.origin.y == 0);
            CHECK(bounds.size.width == width && bounds.size.height == height);
            CHECK(first.bounds.size.width == width && first.bounds.size.height == height);
            CHECK(main.scale == scale && first.scale == scale);
            CHECK([[app windows] count] == 0);

            CHECK([screenClass mainScreen] == main);
            CHECK([[screenClass screens] objectAtIndex:0] == first);

            CHECK(raises(NSWindowServerCommunicationException, ^{ [screenClass screensForNativeScreens:@[]]; }));
            CHECK(raises(NSInternalInconsistencyException, ^{
                [screenClass screensForNativeScreens:@[ [[BaseScaleScreen alloc] init] ]]; }));
            CHECK(raises(NSInternalInconsistencyException, ^{
                [screenClass screensForNativeScreens:@[ stub(NSMakeRect(0, 0, 0, 100), 1) ]]; }));
            CHECK(raises(NSInternalInconsistencyException, ^{
                [screenClass screensForNativeScreens:@[ stub(NSMakeRect(0, 0, 100, 100), 0) ]]; }));
            CHECK(raises(NSInternalInconsistencyException, ^{
                [screenClass screensForNativeScreens:@[ stub(NSMakeRect(0, 0, NAN, 100), 1) ]]; }));
            CHECK(raises(NSInvalidArgumentException, ^{ [[screenClass alloc] init]; }));

            StubScreen *offset = stub(NSMakeRect(40, 30, 200, 100), 2);
            UIScreen *wrapped = [[screenClass screensForNativeScreens:@[ offset ]] firstObject];
            CHECK(wrapped.bounds.origin.x == 0 && wrapped.bounds.origin.y == 0);
            CHECK(wrapped.bounds.size.width == 200 && wrapped.scale == 2);
            printf("PASS before-window UIScreen bounds=0,0,%.0f,%.0f scale=%.0f native=%s nativeScale=%.0f windows=0\n",
                   bounds.size.width, bounds.size.height, main.scale,
                   [NSStringFromClass([native class]) UTF8String], [native backingScaleFactor]);
        } @catch (NSException *exception) {
            fprintf(stderr, "FAIL exception: %s %s\n", [[exception name] UTF8String], [[exception reason] UTF8String]);
            return 1;
        }
        return 0;
    }
}
