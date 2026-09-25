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
#import <SceneKit/SCNNode.h>
#import <SceneKit/SCNLight.h>
#import <CoreFoundation/CFBase.h>

typedef const struct __CFKeyedArchiverUID *CFKeyedArchiverUIDRef;
extern CFTypeID _CFKeyedArchiverUIDGetTypeID(void);
extern uint32_t _CFKeyedArchiverUIDGetValue(CFKeyedArchiverUIDRef uid);

static id SCNArchiveObject(NSArray *objects, id reference)
{
    if (!reference || CFGetTypeID((CFTypeRef)reference) != _CFKeyedArchiverUIDGetTypeID())
        return nil;
    NSUInteger index = _CFKeyedArchiverUIDGetValue((CFKeyedArchiverUIDRef)reference);
    return index < [objects count] ? [objects objectAtIndex:index] : nil;
}

static SCNNode *SCNNodeFromArchive(NSArray *objects, id reference)
{
    NSDictionary *record = SCNArchiveObject(objects, reference);
    if (![record isKindOfClass:[NSDictionary class]])
        return nil;

    NSDictionary *classRecord = SCNArchiveObject(objects, [record objectForKey:@"$class"]);
    if (![[classRecord objectForKey:@"$classname"] isEqualToString:@"SCNNode"])
        return nil;

    SCNNode *node = [[[SCNNode alloc] init] autorelease];
    id name = SCNArchiveObject(objects, [record objectForKey:@"name"]);
    if ([name isKindOfClass:[NSString class]])
        [node setName:name];
    NSDictionary *light = SCNArchiveObject(objects, [record objectForKey:@"light"]);
    NSDictionary *lightClass = SCNArchiveObject(objects, [light objectForKey:@"$class"]);
    if ([[lightClass objectForKey:@"$classname"] isEqualToString:@"SCNLight"])
        [node setLight:[[[SCNLight alloc] init] autorelease]];

    NSData *position = [record objectForKey:@"position"];
    if ([position isKindOfClass:[NSData class]] && [position length] == sizeof(float) * 3) {
        float components[3];
        [position getBytes:components length:sizeof(components)];
        // Preserve the archived local transform until parent transform
        // composition is implemented by the renderer.
        [node setWorldPosition:(SCNVector3){components[0], components[1], components[2]}];
    }
    NSData *orientation = [record objectForKey:@"orientation"];
    if ([orientation isKindOfClass:[NSData class]] && [orientation length] == sizeof(float) * 4) {
        float components[4];
        [orientation getBytes:components length:sizeof(components)];
        [node setWorldOrientation:(SCNVector4){components[0], components[1], components[2], components[3]}];
    }

    NSDictionary *children = SCNArchiveObject(objects, [record objectForKey:@"childNodes"]);
    if ([children isKindOfClass:[NSDictionary class]]) {
        for (id childReference in [children objectForKey:@"NS.objects"]) {
            SCNNode *child = SCNNodeFromArchive(objects, childReference);
            if (child)
                [node addChildNode:child];
        }
    }
    return node;
}

@implementation SCNScene

- (instancetype)init
{
    if ((self = [super init]))
        _rootNode = [[SCNNode alloc] init];
    return self;
}

- (void)dealloc
{
    [_rootNode release];
    [super dealloc];
}

- (SCNNode *)rootNode
{
    return _rootNode;
}

+ (instancetype)sceneNamed:(NSString *)name
{
    if (![name isKindOfClass:[NSString class]] || [name length] == 0)
        return nil;

    NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:name];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory)
        return nil;

    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *archive = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:NULL error:NULL];
    NSArray *objects = [archive objectForKey:@"$objects"];
    NSDictionary *top = [archive objectForKey:@"$top"];
    NSDictionary *sceneRecord = SCNArchiveObject(objects, [top objectForKey:@"root"]);
    NSDictionary *classRecord = SCNArchiveObject(objects, [sceneRecord objectForKey:@"$class"]);
    if (![[classRecord objectForKey:@"$classname"] isEqualToString:@"SCNScene"])
        return nil;

    SCNNode *root = SCNNodeFromArchive(objects, [sceneRecord objectForKey:@"rootNode"]);
    if (!root)
        return nil;

    SCNScene *scene = [[[self alloc] init] autorelease];
    [scene->_rootNode release];
    scene->_rootNode = [root retain];
    return scene;
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
