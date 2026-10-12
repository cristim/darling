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

#import <OpenDirectory/ODRecord.h>

#import "ODLocalDirectory.h"

@implementation ODRecord
{
    NSDictionary *_attributes;
}

ODRecord *ODLocalRecordCreate(NSDictionary *attributes)
{
    ODRecord *record = [[ODRecord alloc] init];

    if (record != nil)
        record->_attributes = [attributes copy];
    return record;
}

- (void)dealloc
{
    [_attributes release];
    [super dealloc];
}

- (NSString *)recordType
{
    return [_attributes[@"dsAttrTypeStandard:RecordType"] firstObject];
}

- (NSString *)recordName
{
    return [_attributes[@"dsAttrTypeStandard:RecordName"] firstObject];
}

- (NSArray *)valuesForAttribute:(ODAttributeType)attribute error:(NSError **)error
{
    if (error != NULL)
        *error = nil;
    if (attribute == nil)
        return nil;
    return _attributes[attribute] ?: @[];
}

- (NSDictionary *)recordDetailsForAttributes:(NSArray *)attributes error:(NSError **)error
{
    if (error != NULL)
        *error = nil;
    if (attributes == nil || [attributes containsObject: @"dsAttributesAll"]
        || [attributes containsObject: @"dsAttributesStandardAll"])
        return _attributes;

    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    for (id attribute in attributes) {
        NSArray *values = _attributes[attribute];
        if (values != nil)
            details[attribute] = values;
    }
    return details;
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
