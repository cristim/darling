/*
 This file is part of Darling.

 Copyright (C) 2017 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <CoreImage/CIExposureAdjust.h>
#import <CoreImage/CIImage.h>
#import <darling-stub-forwarding.h>

@implementation CIExposureAdjust

// Observed on macOS: after -setDefaults the inputEV of an exposure filter is 0 (black-box observation
// with a small test program, tier 2). The archived filter reference still lists 0.50, so it is not
// used. inputImage has no default and is left unchanged, as -[CIFilter setDefaults] documents.
// https://developer.apple.com/documentation/coreimage/cifilter-swift.class/setdefaults()
- (void) setDefaults {
    [self setValue: [NSNumber numberWithDouble: 0] forKey: kCIInputEVKey];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [super methodSignatureForSelector: aSelector] ?: DarlingStubMethodSignature(aSelector);
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    DarlingStubForwardInvocation(self, anInvocation);
}

+ (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [super methodSignatureForSelector: aSelector] ?: DarlingStubMethodSignature(aSelector);
}

+ (void)forwardInvocation:(NSInvocation *)anInvocation {
    DarlingStubForwardInvocation(self, anInvocation);
}

@end
