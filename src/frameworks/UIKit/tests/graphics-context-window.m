#import <UIKit/UIGraphicsContext.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSTimer.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void (*push)(CGContextRef);
static void (*pop)(void);
static CGContextRef (*current)(void);

static void checkFixture(BOOL condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", message);
        exit(1);
    }
}

@interface ContextPaintView : NSView {
    unsigned draws;
    NSGraphicsContext *lastDrawContext;
}
- (void)finish:(NSTimer *)timer;
@end

@implementation ContextPaintView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty
{
    NSGraphicsContext *previous = [NSGraphicsContext currentContext];
    lastDrawContext = previous;
    CGContextRef port = [previous graphicsPort];
    checkFixture(previous != nil && port != NULL, "AppKit draw context absent");
    push(port);
    checkFixture(current() == port, "pushed context differs from AppKit port");
    CGContextSaveGState(current());
    NSRect bounds = [self bounds];
    CGContextSetRGBFillColor(current(), 1, 1, 1, 1);
    CGContextFillRect(current(), CGRectMake(0, 0, bounds.size.width, bounds.size.height));
    CGContextSetRGBFillColor(current(), 1, 0, 0, 1);
    CGContextFillRect(current(), CGRectMake(20, 20, 80, 80));
    CGContextSetRGBFillColor(current(), 0, 1, 0, 1);
    CGContextFillRect(current(), CGRectMake(120, 20, 80, 80));
    CGContextSetRGBFillColor(current(), 0, 0, 1, 1);
    CGContextFillRect(current(), CGRectMake(20, 120, 80, 40));
    CGContextRestoreGState(current());
    pop();
    checkFixture([NSGraphicsContext currentContext] == previous, "AppKit context identity not restored");
    checkFixture(current() == port, "AppKit port not restored");
    printf("PASS draw %u previous context restored; red80x80 green80x80 blue80x40\n", ++draws);
    fflush(stdout);
}
- (void)finish:(NSTimer *)timer
{
    checkFixture(draws > 0, "view never drew");
    NSGraphicsContext *previous = [NSGraphicsContext currentContext];
    CGContextRef port = [lastDrawContext graphicsPort];
    checkFixture(port != NULL, "saved drawing port absent");
    [NSGraphicsContext setCurrentContext:nil];
    push(port);
    checkFixture(current() == port, "nil round-trip push failed");
    pop();
    checkFixture(current() == NULL, "explicit nil baseline not restored");
    [NSGraphicsContext setCurrentContext:previous];
    checkFixture([NSGraphicsContext currentContext] == previous, "timer AppKit context not restored");
    puts("PASS native fixture finished; explicit nil baseline and AppKit context restored");
    fflush(stdout);
    exit(0);
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        checkFixture(argc == 1, "unexpected document arguments");
        const char *path = getenv("UIGRAPHICS_LIBRARY");
        checkFixture(path && *path, "expected UIKit artifact environment path");
        void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!library) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
        push = dlsym(library, "UIGraphicsPushContext");
        pop = dlsym(library, "UIGraphicsPopContext");
        current = dlsym(library, "UIGraphicsGetCurrentContext");
        checkFixture(push && pop && current, "missing graphics context exports");
        checkFixture(current() == NULL, "initial context not nil");
        NSApplication *application = [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 240, 180)
                    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [window setTitle:@"UIGraphics synthetic paint"];
        ContextPaintView *view = [[ContextPaintView alloc] initWithFrame:NSMakeRect(0, 0, 240, 180)];
        [window setContentView:view];
        [window setReleasedWhenClosed:NO];
        [window makeKeyAndOrderFront:nil];
        [NSTimer scheduledTimerWithTimeInterval:45 target:view selector:@selector(finish:) userInfo:nil repeats:NO];
        [application run];
    }
    return 1;
}
