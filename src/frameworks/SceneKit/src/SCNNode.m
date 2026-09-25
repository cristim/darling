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

#import <SceneKit/SCNNode.h>

@implementation SCNNode

@synthesize name = _name;

- (instancetype)init
{
    if ((self = [super init])) {
        _childNodes = [[NSMutableArray alloc] init];
        _worldOrientation = (SCNVector4){0, 0, 0, 1};
    }
    return self;
}

- (void)dealloc
{
    [_name release];
    [_childNodes release];
    [super dealloc];
}

- (NSArray *)childNodes
{
    return _childNodes;
}

- (void)addChildNode:(SCNNode *)child
{
    if (child)
        [_childNodes addObject:child];
}

- (SCNNode *)childNodeWithName:(NSString *)name recursively:(BOOL)recursively
{
    for (SCNNode *child in _childNodes) {
        if ([[child name] isEqualToString:name])
            return child;
        if (recursively) {
            SCNNode *match = [child childNodeWithName:name recursively:YES];
            if (match)
                return match;
        }
    }
    return nil;
}

- (SCNVector3)worldPosition
{
    return _worldPosition;
}

- (void)setWorldPosition:(SCNVector3)position
{
    _worldPosition = position;
}

- (SCNVector4)worldOrientation
{
    return _worldOrientation;
}

- (void)setWorldOrientation:(SCNVector4)orientation
{
    _worldOrientation = orientation;
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
