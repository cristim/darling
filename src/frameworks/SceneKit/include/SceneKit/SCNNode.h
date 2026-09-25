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

#include <Foundation/Foundation.h>

typedef struct { double x, y, z; } SCNVector3;
typedef struct { double x, y, z, w; } SCNVector4;
@class SCNLight, SCNGeometry;

@interface SCNNode : NSObject
{
    NSString *_name;
    NSMutableArray *_childNodes;
    SCNVector3 _worldPosition;
    SCNVector4 _worldOrientation;
    SCNLight *_light;
    SCNGeometry *_geometry;
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly, retain) NSArray *childNodes;
@property (nonatomic, retain) SCNLight *light;
@property (nonatomic, retain) SCNGeometry *geometry;

- (void)addChildNode:(SCNNode *)child;
- (SCNNode *)childNodeWithName:(NSString *)name recursively:(BOOL)recursively;
- (void)enumerateChildNodesUsingBlock:(void (^)(SCNNode *child, BOOL *stop))block;
- (SCNVector3)worldPosition;
- (void)setWorldPosition:(SCNVector3)position;
- (SCNVector4)worldOrientation;
- (void)setWorldOrientation:(SCNVector4)orientation;

@end
