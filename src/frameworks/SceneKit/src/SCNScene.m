/*
 This file is part of Darling.

 Copyright (C) 2023 Darling Team

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

#import <SceneKit/SCNScene.h>

@implementation SCNScene

+ (instancetype)sceneNamed:(NSString *)name
{
    if (![name isKindOfClass:[NSString class]] || [name length] == 0)
        return nil;

    NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:name];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory)
        return nil;

    // SceneKit archives contain an entire scene graph. Until SCNScene and its
    // node types implement keyed decoding, returning an empty scene would make
    // callers believe the file loaded successfully.
    NSLog(@"SCNScene: cannot decode scene archive %@", path);
    return nil;
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
