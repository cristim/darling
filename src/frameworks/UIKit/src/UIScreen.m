// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIScreen.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSErrors.h>
#import <Foundation/NSException.h>
#import <objc/runtime.h>
#include <math.h>

@interface UIScreen ()
+ (NSArray<UIScreen *> *)screensForNativeScreens:(NSArray *)nativeScreens;
- (instancetype)initWithNativeScreen:(NSScreen *)screen;
@end

@implementation UIScreen {
    NSScreen *_nativeScreen;
}

static NSArray<UIScreen *> *cachedScreens;

+ (NSArray<UIScreen *> *)screens
{
    return [self screensForNativeScreens:[NSScreen screens]];
}

// Separate from +screens so tests can pass stub NSScreen objects.
+ (NSArray<UIScreen *> *)screensForNativeScreens:(NSArray *)nativeScreens
{
    @synchronized(self) {
        if ([nativeScreens count] == 0) {
            [NSException raise:NSWindowServerCommunicationException
                        format:@"UIScreen requires a connected display"];
        }
        NSMutableArray *screens = [NSMutableArray arrayWithCapacity:[nativeScreens count]];
        for (NSScreen *native in nativeScreens) {
            UIScreen *screen = nil;
            for (UIScreen *known in cachedScreens) {
                if (known->_nativeScreen == native) {
                    screen = known;
                    break;
                }
            }
            [screens addObject:screen ?: [[UIScreen alloc] initWithNativeScreen:native]];
        }
        cachedScreens = [screens copy];
        return cachedScreens;
    }
}

+ (UIScreen *)mainScreen
{
    return [[self screens] firstObject];
}

- (instancetype)initWithNativeScreen:(NSScreen *)screen;
@end

@implementation UIScreen {
    NSScreen *_nativeScreen;
}

+ (NSArray<UIScreen *> *)screens
{
    NSArray *nativeScreens = [NSScreen screens];
    if ([nativeScreens count] == 0) {
        [NSException raise:NSWindowServerCommunicationException
                    format:@"UIScreen requires a connected display"];
    }
    NSMutableArray *screens = [NSMutableArray arrayWithCapacity:[nativeScreens count]];
    for (NSScreen *native in nativeScreens) {
        [screens addObject:[[UIScreen alloc] initWithNativeScreen:native]];
    }
    return [screens copy];
}

+ (UIScreen *)mainScreen
{
    return [[self screens] firstObject];
}

- (instancetype)initWithNativeScreen:(NSScreen *)screen
{
    if ((self = [super init])) {
        if (class_getMethodImplementation([screen class], @selector(backingScaleFactor)) ==
            class_getMethodImplementation([NSScreen class], @selector(backingScaleFactor))) {
            [NSException raise:NSInternalInconsistencyException
                        format:@"UIScreen requires a backend-reported backing scale"];
        }
        _nativeScreen = screen;
        (void)[self bounds];
        (void)[self scale];
    }
    return self;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException format:@"Use UIScreen screen queries"];
    return nil;
}

- (CGRect)bounds
{
    NSRect frame = [_nativeScreen frame];
    if (!isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
        !isfinite(frame.size.width) || !isfinite(frame.size.height) ||
        frame.size.width <= 0 || frame.size.height <= 0) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"UIScreen received invalid display geometry"];
    }
    return CGRectMake(0, 0, frame.size.width, frame.size.height);
}

- (CGFloat)scale
{
    CGFloat scale = [_nativeScreen backingScaleFactor];
    if (!isfinite(scale) || scale <= 0) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"UIScreen received invalid display scale"];
    }
    return scale;
}
@end
