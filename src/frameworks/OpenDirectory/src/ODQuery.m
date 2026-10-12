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

#import <OpenDirectory/ODQuery.h>

#import <OpenDirectory/OpenDirectory.h>
#import "ODLocalDirectory.h"

@implementation ODQuery
{
    BOOL _users;
    NSString *_attribute;
    ODMatchType _matchType;
    NSArray *_queryValues;
    NSInteger _maximumResults;
}

+ (ODQuery *)queryWithNode:(ODNode *)node forRecordTypes:(id)recordTypeOrList attribute:(ODAttributeType)attribute
                 matchType:(ODMatchType)matchType queryValues:(id)queryValueOrList
          returnAttributes:(id)returnAttributeOrList maximumResults:(NSInteger)maximumResults error:(NSError **)error
{
    return [[[self alloc] initWithNode: node forRecordTypes: recordTypeOrList attribute: attribute
                             matchType: matchType queryValues: queryValueOrList
                      returnAttributes: returnAttributeOrList maximumResults: maximumResults error: error] autorelease];
}

- (instancetype)initWithNode:(ODNode *)node forRecordTypes:(id)recordTypeOrList attribute:(ODAttributeType)attribute
                   matchType:(ODMatchType)matchType queryValues:(id)queryValueOrList
            returnAttributes:(id)returnAttributeOrList maximumResults:(NSInteger)maximumResults error:(NSError **)error
{
    if (error != NULL)
        *error = nil;
    if (node == nil) {
        if (error != NULL)
            *error = ODLocalError(kODErrorNodeUnknownName);
        [self release];
        return nil;
    }
    if ((self = [super init]) != nil) {
        NSMutableArray *values = [NSMutableArray array];
        NSArray *given = [queryValueOrList isKindOfClass: [NSArray class]] ? queryValueOrList
                       : queryValueOrList != nil ? @[queryValueOrList] : @[];

        for (id value in given) {
            if ([value isKindOfClass: [NSData class]])
                value = [[[NSString alloc] initWithData: value encoding: NSUTF8StringEncoding] autorelease];
            if ([value isKindOfClass: [NSString class]])
                [values addObject: value];
        }

        _users = ODLocalRecordTypesIncludeUsers(recordTypeOrList);
        _attribute = [attribute copy];
        _matchType = matchType;
        _queryValues = [values copy];
        _maximumResults = maximumResults;
    }
    return self;
}

- (void)dealloc
{
    [_attribute release];
    [_queryValues release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    ODQuery *copy = [[ODQuery allocWithZone: zone] init];

    if (copy != nil) {
        copy->_users = _users;
        copy->_attribute = [_attribute copy];
        copy->_matchType = _matchType;
        copy->_queryValues = [_queryValues copy];
        copy->_maximumResults = _maximumResults;
    }
    return copy;
}

- (BOOL)_value:(NSString *)value matches:(NSString *)wanted
{
    NSStringCompareOptions options = (_matchType & 0x0100) ? NSCaseInsensitiveSearch : 0;

    switch (_matchType & ~0x0100) {
        case kODMatchEqualTo:
            return [value compare: wanted options: options] == NSOrderedSame;
        case kODMatchBeginsWith:
            return [value rangeOfString: wanted options: options | NSAnchoredSearch].location != NSNotFound;
        case kODMatchEndsWith:
            return [value rangeOfString: wanted options: options | NSAnchoredSearch | NSBackwardsSearch].location != NSNotFound;
        case kODMatchContains:
            return [value rangeOfString: wanted options: options].location != NSNotFound;
        default:
            return NO;
    }
}

- (BOOL)_matches:(NSDictionary *)user
{
    if (_matchType == kODMatchAny)
        return YES;

    for (NSString *value in user[_attribute]) {
        for (NSString *wanted in _queryValues) {
            if ([self _value: value matches: wanted])
                return YES;
        }
    }
    return NO;
}

- (NSArray *)resultsAllowingPartial:(BOOL)allowPartial error:(NSError **)error
{
    NSMutableArray *results = [NSMutableArray array];
    NSArray *candidates = @[];

    if (error != NULL)
        *error = nil;
    if (!_users || (_attribute == nil && _matchType != kODMatchAny))
        return results;

    if (_matchType == kODMatchEqualTo && [_attribute isEqualToString: kODAttributeTypeRecordName]) {
        NSMutableArray *named = [NSMutableArray array];
        for (NSString *name in _queryValues) {
            NSDictionary *user = ODLocalUserAttributes(name);
            if (user != nil)
                [named addObject: user];
        }
        candidates = named;
    } else {
        candidates = ODLocalAllUserAttributes();
    }

    for (NSDictionary *user in candidates) {
        if (_maximumResults > 0 && [results count] >= (NSUInteger)_maximumResults)
            break;
        if ([self _matches: user])
            [results addObject: [ODLocalRecordCreate(user) autorelease]];
    }
    return results;
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
