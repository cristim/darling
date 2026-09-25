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

#import <AVFoundation/AVPlayer.h>
#import <AVFoundation/AVPlayerItem.h>

@implementation AVPlayer

- (instancetype)initWithURL:(NSURL *)URL
{
    return [self initWithPlayerItem:[AVPlayerItem playerItemWithURL:URL]];
}

- (instancetype)initWithPlayerItem:(AVPlayerItem *)item
{
    if ((self = [super init]))
        _currentItem = [item retain];
    return self;
}

+ (instancetype)playerWithURL:(NSURL *)URL
{
    return [[[self alloc] initWithURL:URL] autorelease];
}

+ (instancetype)playerWithPlayerItem:(AVPlayerItem *)item
{
    return [[[self alloc] initWithPlayerItem:item] autorelease];
}

- (AVPlayerItem *)currentItem { return _currentItem; }

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item
{
    if (_currentItem != item) {
        [_currentItem release];
        _currentItem = [item retain];
    }
}

// Decoding and playback are not available yet; these methods leave the
// player paused rather than claiming that media is being presented.
- (void)play { }
- (void)pause { }

- (void)dealloc
{
    [_currentItem release];
    [super dealloc];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
