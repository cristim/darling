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

#include <Foundation/Foundation.h>

@interface AVAudioPlayer : NSObject

- (instancetype)initWithData:(NSData *)data error:(NSError **)outError;
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError;

@property (nonatomic, readonly, copy) NSData *data;
@property (nonatomic, readonly, copy) NSURL *url;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) id delegate;
@property (nonatomic, assign) NSInteger numberOfLoops;

- (BOOL)prepareToPlay;
- (BOOL)play;
- (void)pause;
- (void)stop;

@end
