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

#import <SceneKit/SCNMaterial.h>
#import <SceneKit/SCNMaterialProperty.h>

@implementation SCNMaterial

@synthesize lightingModelName = _lightingModelName;
@synthesize shaderModifiers = _shaderModifiers;
@synthesize doubleSided = _doubleSided;
@synthesize writesToDepthBuffer = _writesToDepthBuffer;
@synthesize readsFromDepthBuffer = _readsFromDepthBuffer;

- (instancetype)init
{
    if ((self = [super init]))
        _diffuse = [[SCNMaterialProperty alloc] init];
    return self;
}

- (void)dealloc
{
    [_lightingModelName release];
    [_diffuse release];
    [_shaderModifiers release];
    [super dealloc];
}

- (SCNMaterialProperty *)diffuse
{
    return _diffuse;
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
