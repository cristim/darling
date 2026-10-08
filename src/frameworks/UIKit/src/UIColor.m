/*
 * Copyright (c) 2011, 2012, The Iconfactory. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of The Iconfactory nor the names of its contributors may
 *    be used to endorse or promote products derived from this software without
 *    specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE ICONFACTORY BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <UIKit/UIColor.h>
#import <Foundation/NSException.h>
#include <math.h>

static void UIRequireColorFinite(CGFloat value)
{
    if (!isfinite(value))
        [NSException raise:NSInvalidArgumentException format:@"Color components must be finite"];
}

static CGFloat UIColorAlpha(CGFloat alpha)
{
    UIRequireColorFinite(alpha);
    return fmin(1, fmax(0, alpha));
}

static BOOL UIColorSpaceMatches(CGColorSpaceRef space, CFStringRef first, CFStringRef second)
{
    CFStringRef name = CGColorSpaceCopyName(space);
    BOOL matches = name == NULL || CFEqual(name, first) || CFEqual(name, second);
    if (name != NULL)
        CFRelease(name);
    return matches;
}

@implementation UIColor {
    CGColorRef _CGColor;
}
- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException format:@"Use a color initializer"];
    return nil;
}
- (instancetype)initWithCGColor:(CGColorRef)color
{
    if (color == NULL)
        [NSException raise:NSInvalidArgumentException format:@"UIColor requires a CGColor"];
    if ((self = [super init]))
        _CGColor = CGColorRetain(color);
    return self;
}
- (instancetype)initWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
    UIRequireColorFinite(red);
    UIRequireColorFinite(green);
    UIRequireColorFinite(blue);
    CGFloat components[] = {red, green, blue, UIColorAlpha(alpha)};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
    if (space == NULL)
        [NSException raise:NSInternalInconsistencyException format:@"CoreGraphics extended sRGB is unavailable"];
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);
    self = [self initWithCGColor:color];
    CGColorRelease(color);
    return self;
}
- (instancetype)initWithWhite:(CGFloat)white alpha:(CGFloat)alpha
{
    UIRequireColorFinite(white);
    CGFloat components[] = {white, UIColorAlpha(alpha)};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedGray);
    if (space == NULL)
        [NSException raise:NSInternalInconsistencyException format:@"CoreGraphics extended gray is unavailable"];
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);
    self = [self initWithCGColor:color];
    CGColorRelease(color);
    return self;
}
+ (UIColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
    return [[self alloc] initWithRed:red green:green blue:blue alpha:alpha];
}
+ (UIColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha
{
    return [[self alloc] initWithWhite:white alpha:alpha];
}
+ (UIColor *)colorWithCGColor:(CGColorRef)color
{
    return [[self alloc] initWithCGColor:color];
}
- (void)dealloc { CGColorRelease(_CGColor); }
- (CGColorRef)CGColor { return _CGColor; }
- (UIColor *)colorWithAlphaComponent:(CGFloat)alpha
{
    CGColorRef color = CGColorCreateCopyWithAlpha(_CGColor, UIColorAlpha(alpha));
    UIColor *result = [UIColor colorWithCGColor:color];
    CGColorRelease(color);
    return result;
}
- (BOOL)getRed:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue alpha:(CGFloat *)alpha
{
    CGColorSpaceRef space = CGColorGetColorSpace(_CGColor);
    CGColorRef converted = NULL;
    CGColorRef color = _CGColor;
    if (CGColorSpaceGetModel(space) != kCGColorSpaceModelRGB ||
        !UIColorSpaceMatches(space, kCGColorSpaceSRGB, kCGColorSpaceExtendedSRGB)) {
        CGColorSpaceRef target = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
        if (target == NULL)
            return NO;
        converted = CGColorCreateCopyByMatchingToColorSpace(target, kCGRenderingIntentDefault, _CGColor, NULL);
        CGColorSpaceRelease(target);
        if (converted == NULL)
            return NO;
        color = converted;
    }
    const CGFloat *components = CGColorGetComponents(color);
    if (red != NULL) *red = components[0];
    if (green != NULL) *green = components[1];
    if (blue != NULL) *blue = components[2];
    if (alpha != NULL) *alpha = CGColorGetAlpha(color);
    if (converted != NULL)
        CGColorRelease(converted);
    return YES;
}
- (BOOL)getWhite:(CGFloat *)white alpha:(CGFloat *)alpha
{
    CGColorSpaceRef space = CGColorGetColorSpace(_CGColor);
    if (CGColorSpaceGetModel(space) != kCGColorSpaceModelMonochrome ||
        !UIColorSpaceMatches(space, kCGColorSpaceGenericGray, kCGColorSpaceExtendedGray))
        return NO;
    if (white != NULL) *white = CGColorGetComponents(_CGColor)[0];
    if (alpha != NULL) *alpha = CGColorGetAlpha(_CGColor);
    return YES;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end
