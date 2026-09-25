/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers

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

#import <AVFAudio/AVAudioPlayer.h>
#include <stdint.h>
#include <string.h>

static uint64_t readBigEndian64(const uint8_t *bytes)
{
    uint64_t value = 0;
    for (int i = 0; i < 8; ++i)
        value = (value << 8) | bytes[i];
    return value;
}

static BOOL isSupportedAudioData(NSData *data)
{
    const uint8_t *bytes = [data bytes];
    NSUInteger length = [data length];
    if (length < 12 || memcmp(bytes, "caff", 4) != 0 || bytes[4] != 0 || bytes[5] != 1)
        return NO;

    BOOL hasDescription = NO;
    BOOL hasAudio = NO;
    NSUInteger offset = 8;
    while (length - offset >= 12) {
        uint64_t chunkLength = readBigEndian64(bytes + offset + 4);
        NSUInteger available = length - offset - 12;
        if (chunkLength > available)
            return NO;
        if (memcmp(bytes + offset, "desc", 4) == 0)
            hasDescription = chunkLength >= 32;
        if (memcmp(bytes + offset, "data", 4) == 0)
            hasAudio = chunkLength > 4;
        offset += 12 + (NSUInteger)chunkLength;
    }
    return offset == length && hasDescription && hasAudio;
}

@interface AVAudioPlayer () {
    NSData *_audioData;
    NSURL *_audioURL;
    float _volume;
    id _delegate;
    NSInteger _numberOfLoops;
}
@end

@implementation AVAudioPlayer

- (instancetype)initWithData:(NSData *)data error:(NSError **)outError
{
    if (!(self = [super init]))
        return nil;

    if (!isSupportedAudioData(data)) {
        if (outError != NULL)
            *outError = [NSError errorWithDomain:@"AVFoundationErrorDomain" code:-11828 userInfo:nil];
        [self release];
        return nil;
    }

    _audioData = [data copy];
    _volume = 1.0f;
    if (outError != NULL)
        *outError = nil;
    return self;
}

- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError
{
    NSData *data = [NSData dataWithContentsOfURL:url];
    self = [self initWithData:data error:outError];
    if (self != nil)
        _audioURL = [url copy];
    return self;
}

- (NSData *)data { return _audioData; }
- (NSURL *)url { return _audioURL; }
- (float)volume { return _volume; }
- (void)setVolume:(float)volume { _volume = volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume); }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (NSInteger)numberOfLoops { return _numberOfLoops; }
- (void)setNumberOfLoops:(NSInteger)numberOfLoops { _numberOfLoops = numberOfLoops; }

- (BOOL)prepareToPlay { return NO; }
- (BOOL)play { return NO; }
- (void)pause { }
- (void)stop { }

- (void)dealloc
{
    [_audioData release];
    [_audioURL release];
    [super dealloc];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
