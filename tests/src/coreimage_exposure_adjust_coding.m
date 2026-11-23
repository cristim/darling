// CFLAGS: -framework Foundation -framework CoreImage
// Copyright (C) 2026 Darling developers
//
// A keyed archive that holds a CIExposureAdjust filter decodes. Sources:
// https://developer.apple.com/documentation/coreimage/cifilter-swift.class (CIFilter conforms to
// NSSecureCoding, manages its input parameters when archiving, and -setDefaults leaves parameters
// that have no default unchanged), https://developer.apple.com/documentation/coreimage/ciexposureadjust
// (the parameters are inputImage and inputEV) and the filter reference
// https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html
// (inputEV is an NSNumber). The archive layout and the default of inputEV are not documented; the
// expected values are what an archive written on macOS showed (black-box observation, tier 2): the
// class name CIExposureAdjust, the key CI_inputEV with an NSNumber, no key for an unset parameter,
// and an inputEV of 0 after -setDefaults (the archived filter reference lists 0.50, which current
// macOS does not give). The class is looked up by name because on macOS CIExposureAdjust is a
// protocol in the public headers.
// Prints OK, or the failures with a non-zero exit status.
#import <CoreImage/CoreImage.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, msg); failures++; } } while (0)

static NSData *archive(id object, BOOL secure) {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: object requiringSecureCoding: secure error: &error];
    CHECK(data != nil, "the object archives");
    return data;
}

// A raised exception is a failure, not a crash. The plain decoder is the one a nib uses.
static id unarchive(NSData *data, BOOL secure) {
    id result = nil;
    @try {
        if (secure) {
            NSError *error = nil;
            NSSet *classes = [NSSet setWithObjects: [NSArray class], [CIFilter class], nil];
            result = [NSKeyedUnarchiver unarchivedObjectOfClasses: classes fromData: data error: &error];
        } else {
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
            result = [unarchiver decodeObjectForKey: NSKeyedArchiveRootObjectKey];
            [unarchiver finishDecoding];
            [unarchiver release];
        }
    } @catch (NSException *exception) {
        printf("FAIL line %d: decoding raised %s\n", __LINE__, [[exception name] UTF8String]);
        failures++;
    }
    return result;
}

// An object that archives only an inputEV, under the class name of the filter: a hand-built archive.
@interface HandBuiltFilter : NSObject <NSCoding>
@end

@implementation HandBuiltFilter
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: @1.25 forKey: @"CI_inputEV"];
}
- (instancetype) initWithCoder: (NSCoder *) coder {
    return [super init];
}
@end

// Records which of the candidate keys an archive holds, by decoding the filter as this class.
static NSArray *probeCandidates;
static NSMutableSet *probeSeen;

@interface KeyProbe : NSObject <NSCoding>
@end

@implementation KeyProbe
- (void) encodeWithCoder: (NSCoder *) coder {
}
- (instancetype) initWithCoder: (NSCoder *) coder {
    for (NSString *key in probeCandidates) {
        if ([coder containsValueForKey: key]) {
            [probeSeen addObject: key];
        }
    }
    return [super init];
}
@end

static NSSet *keysHeldBy(NSData *data) {
    probeCandidates = @[@"CI_inputEV", @"CI_inputImage", @"inputEV", @"inputImage"];
    probeSeen = [NSMutableSet set];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
    [unarchiver setClass: [KeyProbe class] forClassName: @"CIExposureAdjust"];
    [unarchiver decodeObjectForKey: NSKeyedArchiveRootObjectKey];
    [unarchiver finishDecoding];
    [unarchiver release];
    return probeSeen;
}

int main(void) {
    @autoreleasepool {
        Class filterClass = NSClassFromString(@"CIExposureAdjust");
        CHECK(filterClass != Nil && [filterClass isSubclassOfClass: [CIFilter class]], "CIExposureAdjust is a CIFilter");
        if (filterClass == Nil) {
            printf("FAILED\n");
            return 1;
        }

        id filter = [[[filterClass alloc] init] autorelease];
        CHECK([[filter inputKeys] containsObject: kCIInputEVKey], "inputEV is an input parameter");
        CHECK([[filter inputKeys] containsObject: kCIInputImageKey], "inputImage is an input parameter");

        for (int secure = 0; secure <= 1; secure++) {
            // a filter with its exposure set, inside an array like the one a nib stores objects in
            [filter setValue: @1.25 forKey: kCIInputEVKey];
            NSArray *decodedArray = unarchive(archive(@[filter], secure), secure);
            CHECK([decodedArray count] == 1, "the array decodes with its element");
            id decoded = [decodedArray firstObject];
            CHECK([decoded isMemberOfClass: filterClass], "the decoded filter has the archived class");
            CHECK([[decoded valueForKey: kCIInputEVKey] isEqual: @1.25], "inputEV is decoded");
            CHECK([[keysHeldBy(archive(filter, secure)) allObjects] isEqual: @[@"CI_inputEV"]],
                  "inputEV is archived under CI_inputEV, and an unset inputImage is absent");
            CHECK([decoded valueForKey: kCIInputImageKey] == nil, "a filter without an image decodes with a nil inputImage");

            // a filter with no parameter set still decodes; the defaults apply after -setDefaults
            id blank = [[[filterClass alloc] init] autorelease];
            decoded = unarchive(archive(blank, secure), secure);
            CHECK([decoded isMemberOfClass: filterClass], "a filter without parameters decodes");
            CHECK([decoded valueForKey: kCIInputEVKey] == nil, "decoding applies no defaults");
            CHECK([keysHeldBy(archive(blank, secure)) count] == 0, "an unset filter archives no parameter keys");
            [decoded setDefaults];
            CHECK([[decoded valueForKey: kCIInputEVKey] doubleValue] == 0 && [decoded valueForKey: kCIInputEVKey] != nil,
                  "-setDefaults gives inputEV the value 0");
            CHECK([decoded valueForKey: kCIInputImageKey] == nil, "-setDefaults has no default for inputImage");
        }

        // an archive that holds only CI_inputEV decodes into the filter class with that value
        NSKeyedArchiver *builder = [[NSKeyedArchiver alloc] initRequiringSecureCoding: NO];
        [builder setClassName: @"CIExposureAdjust" forClass: [HandBuiltFilter class]];
        [builder encodeObject: [[[HandBuiltFilter alloc] init] autorelease] forKey: NSKeyedArchiveRootObjectKey];
        [builder finishEncoding];
        NSData *handBuilt = [[[builder encodedData] copy] autorelease];
        [builder release];
        id fromHandBuilt = unarchive(handBuilt, NO);
        CHECK([fromHandBuilt isMemberOfClass: filterClass], "the hand-built archive decodes to the filter class");
        CHECK([[fromHandBuilt valueForKey: kCIInputEVKey] isEqual: @1.25], "CI_inputEV is read");
        CHECK([fromHandBuilt valueForKey: kCIInputImageKey] == nil, "an absent CI_inputImage leaves inputImage unset");

        // -setDefaults changes inputEV and leaves a parameter without a default alone
        id image = [CIImage emptyImage];
        id other = [[[filterClass alloc] init] autorelease];
        [other setValue: image forKey: kCIInputImageKey];
        [other setValue: @-3 forKey: kCIInputEVKey];
        [other setDefaults];
        CHECK([[other valueForKey: kCIInputEVKey] doubleValue] == 0, "-setDefaults replaces a set inputEV");
        CHECK([other valueForKey: kCIInputImageKey] == image, "-setDefaults leaves inputImage unchanged");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures ? 1 : 0;
}
