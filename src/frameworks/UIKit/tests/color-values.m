#import <UIKit/UIColor.h>
#include <dlfcn.h>
#include <stdio.h>
#include <math.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)
#define CLOSE(a, b) (fabs((a) - (b)) < 0.00001)

int main(int argc, char **argv)
{
    @autoreleasepool {
        CHECK(argc == 2);
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!library) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
        Class colorClass = NSClassFromString(@"UIColor");
        CHECK(colorClass != Nil);
        UIColor *rgb = [colorClass colorWithRed:0.25 green:0.5 blue:0.75 alpha:0.4];
        CGFloat r, g, b, a;
        CHECK([rgb getRed:&r green:&g blue:&b alpha:&a]);
        CHECK(CLOSE(r, 0.25) && CLOSE(g, 0.5) && CLOSE(b, 0.75) && CLOSE(a, 0.4));
        CHECK(CGColorSpaceGetModel(CGColorGetColorSpace(rgb.CGColor)) == kCGColorSpaceModelRGB);
        CHECK(CGColorGetNumberOfComponents(rgb.CGColor) == 4);
        CFStringRef name = CGColorSpaceCopyName(CGColorGetColorSpace(rgb.CGColor));
        CHECK(name && CFEqual(name, kCGColorSpaceExtendedSRGB));
        CFRelease(name);
        UIColor *extended = [[colorClass alloc] initWithRed:1.25 green:-0.5 blue:2 alpha:2];
        CHECK([extended getRed:&r green:&g blue:&b alpha:&a]);
        CHECK(CLOSE(r, 1.25) && CLOSE(g, -0.5) && CLOSE(b, 2) && a == 1);
        CHECK([extended getRed:NULL green:NULL blue:NULL alpha:NULL]);
        UIColor *gray = [colorClass colorWithWhite:1.25 alpha:-1];
        CGFloat white;
        CHECK([gray getWhite:&white alpha:&a] && CLOSE(white, 1.25) && a == 0);
        CHECK(CGColorGetNumberOfComponents(gray.CGColor) == 2);
        name = CGColorSpaceCopyName(CGColorGetColorSpace(gray.CGColor));
        CHECK(name && CFEqual(name, kCGColorSpaceExtendedGray));
        CFRelease(name);
        UIColor *replacement = [rgb colorWithAlphaComponent:0.8];
        CHECK(CGColorGetColorSpace(replacement.CGColor) == CGColorGetColorSpace(rgb.CGColor));
        CHECK([replacement getRed:&r green:&g blue:&b alpha:&a]);
        CHECK(CLOSE(r, 0.25) && CLOSE(g, 0.5) && CLOSE(b, 0.75) && CLOSE(a, 0.8));
        CHECK(CLOSE(CGColorGetAlpha(rgb.CGColor), 0.4));
        CHECK(CGColorGetAlpha([rgb colorWithAlphaComponent:2].CGColor) == 1);
        CHECK(CGColorGetAlpha([rgb colorWithAlphaComponent:-1].CGColor) == 0);
        CHECK([gray colorWithAlphaComponent:0.5].CGColor != NULL);
        UIColor *owned;
        @autoreleasepool {
            CGColorRef raw = CGColorCreateGenericRGB(0.1, 0.2, 0.3, 0.6);
            owned = [[colorClass alloc] initWithCGColor:raw];
            CGColorRelease(raw);
        }
        CHECK([owned getRed:&r green:&g blue:&b alpha:&a]);
        CHECK(CLOSE(r, 0.1) && CLOSE(g, 0.2) && CLOSE(b, 0.3) && CLOSE(a, 0.6));
        CGColorRef retained = CGColorRetain(owned.CGColor);
        owned = nil;
        CHECK(CLOSE(CGColorGetAlpha(retained), 0.6));
        CGColorRelease(retained);
        CGColorRef rawGray = CGColorCreateGenericGray(0.35, 0.7);
        UIColor *deviceGray = [colorClass colorWithCGColor:rawGray];
        CGColorRelease(rawGray);
        CHECK([deviceGray getWhite:&white alpha:&a] && CLOSE(white, 0.35) && CLOSE(a, 0.7));
        CHECK([deviceGray getRed:&r green:&g blue:&b alpha:&a]);
        CHECK(CLOSE(r, 0.35) && CLOSE(g, 0.35) && CLOSE(b, 0.35) && CLOSE(a, 0.7));
        UIColor *copy = [rgb copy];
        CHECK(CGColorEqualToColor(copy.CGColor, rgb.CGColor));
        rgb = nil;
        CHECK([copy getRed:&r green:&g blue:&b alpha:&a] && CLOSE(a, 0.4));
        CGColorRef rawCMYK = CGColorCreateGenericCMYK(0.1, 0.2, 0.3, 0.4, 0.5);
        UIColor *cmyk = [colorClass colorWithCGColor:rawCMYK];
        CGColorRelease(rawCMYK);
        r = 11; g = 12; b = 13; a = 14; white = 15;
        CHECK(![cmyk getRed:&r green:&g blue:&b alpha:&a]);
        CHECK(r == 11 && g == 12 && b == 13 && a == 14);
        CHECK(![cmyk getWhite:&white alpha:&a] && white == 15 && a == 14);
        CHECK(![copy getWhite:&white alpha:&a] && white == 15 && a == 14);
        CHECK(![gray getRed:&r green:&g blue:&b alpha:&a] && r == 11 && a == 14);
        puts("PASS UIKit UIColor RGB/gray values, ownership, alpha, copies and unsupported getter outputs");
    }
    return 0;
}
