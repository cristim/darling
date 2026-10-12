/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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

#import <OpenDirectory/ODNode.h>

#import "ODLocalDirectory.h"

@implementation ODNode
{
    NSString *_nodeName;
}

+ (instancetype)nodeWithSession:(ODSession *)session type:(ODNodeType)type error:(NSError **)error
{
    return [[[self alloc] initWithSession: session type: type error: error] autorelease];
}

+ (instancetype)nodeWithSession:(ODSession *)session name:(NSString *)name error:(NSError **)error
{
    return [[[self alloc] initWithSession: session name: name error: error] autorelease];
}

- (instancetype)initWithSession:(ODSession *)session type:(ODNodeType)type error:(NSError **)error
{
    if (error != NULL)
        *error = nil;
    if ((self = [super init]) != nil)
        _nodeName = [ODLocalNodeNameForType(type) copy];
    return self;
}

- (instancetype)initWithSession:(ODSession *)session name:(NSString *)name error:(NSError **)error
{
    NSString *known = ODLocalNodeNameForName(name);

    if (error != NULL)
        *error = known != nil ? nil : ODLocalError(kODErrorNodeUnknownName);
    if (known == nil) {
        [self release];
        return nil;
    }
    if ((self = [super init]) != nil)
        _nodeName = [known copy];
    return self;
}

- (void)dealloc
{
    [_nodeName release];
    [super dealloc];
}

- (NSString *)nodeName
{
    return _nodeName;
}

- (NSArray *)subnodeNamesAndReturnError:(NSError **)error
{
    if (error != NULL)
        *error = nil;
    return [_nodeName isEqualToString: ODLocalNodeName] ? @[] : @[ODLocalNodeName];
}

- (NSArray *)unreachableSubnodeNamesAndReturnError:(NSError **)error
{
    if (error != NULL)
        *error = nil;
    return nil;
}

- (NSArray *)supportedRecordTypesAndReturnError:(NSError **)error
{
    if (error != NULL)
        *error = nil;
    return @[kODRecordTypeUsers];
}

- (ODRecord *)recordWithRecordType:(ODRecordType)recordType name:(NSString *)name attributes:(id)attributes error:(NSError **)error
{
    if (error != NULL)
        *error = nil;
    if (!ODLocalRecordTypesIncludeUsers(recordType))
        return nil;

    NSDictionary *user = ODLocalUserAttributes(name);
    return user != nil ? [ODLocalRecordCreate(user) autorelease] : nil;
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
