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

#import <AVFoundation/AVPlayerLayer.h>
#import <AVFoundation/AVPlayer.h>

@implementation AVPlayerLayer

+ (instancetype)playerLayerWithPlayer:(AVPlayer *)player
{
    AVPlayerLayer *layer = [[[self alloc] init] autorelease];
    layer.player = player;
    return layer;
}

- (AVPlayer *)player { return _player; }

- (void)setPlayer:(AVPlayer *)player
{
    if (_player != player) {
        [_player release];
        _player = [player retain];
    }
}

- (void)dealloc
{
    [_player release];
    [super dealloc];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
