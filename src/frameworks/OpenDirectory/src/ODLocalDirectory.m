/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Team

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

#import "ODLocalDirectory.h"

#include <arpa/inet.h>
#include <membership.h>
#include <pthread.h>
#include <pwd.h>
#include <uuid/uuid.h>

NSString *const ODFrameworkErrorDomain = @"com.apple.OpenDirectory";
NSString *const ODLocalNodeName = @"/Local/Default";

// getpwent() iterates process-wide state
static pthread_mutex_t enumerationLock = PTHREAD_MUTEX_INITIALIZER;

NSError *ODLocalError(NSInteger code)
{
    return [NSError errorWithDomain: ODFrameworkErrorDomain code: code userInfo: nil];
}

NSString *ODLocalNodeNameForName(NSString *name)
{
    for (NSString *known in @[ODLocalNodeName, @"/Search", @"/Contacts"]) {
        if ([known isEqualToString: name])
            return known;
    }
    return nil;
}

NSString *ODLocalNodeNameForType(unsigned int type)
{
    switch (type) {
        case 0x2201: // kODNodeTypeAuthentication
        case 0x2205: // kODNodeTypeNetwork
            return @"/Search";
        case 0x2204: // kODNodeTypeContacts
            return @"/Contacts";
        default:
            return ODLocalNodeName;
    }
}

static NSDictionary *attributesForEntry(const struct passwd *entry)
{
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSString *name = [NSString stringWithUTF8String: entry->pw_name];
    uuid_t uuid;

    if (name == nil)
        return nil;

    attributes[@"dsAttrTypeStandard:RecordName"] = @[name];
    attributes[@"dsAttrTypeStandard:RecordType"] = @[@"dsRecTypeStandard:Users"];
    attributes[@"dsAttrTypeStandard:AppleMetaNodeLocation"] = @[ODLocalNodeName];
    attributes[@"dsAttrTypeStandard:UniqueID"] = @[[NSString stringWithFormat: @"%u", (unsigned int)entry->pw_uid]];
    attributes[@"dsAttrTypeStandard:PrimaryGroupID"] = @[[NSString stringWithFormat: @"%u", (unsigned int)entry->pw_gid]];

    if (mbr_uid_to_uuid(entry->pw_uid, uuid) != 0) {
        // No stored UUID: use the membership library's compatibility mapping
        // for such accounts, FFFFEEEE-DDDD-CCCC-BBBB-AAAA followed by the uid.
        static const uuid_t prefix = {0xff, 0xff, 0xee, 0xee, 0xdd, 0xdd, 0xcc, 0xcc, 0xbb, 0xbb, 0xaa, 0xaa};
        uint32_t uid = htonl(entry->pw_uid);

        memcpy(uuid, prefix, sizeof(uuid_t));
        memcpy(&uuid[12], &uid, sizeof(uid));
    }
    uuid_string_t text;
    uuid_unparse_upper(uuid, text);
    attributes[@"dsAttrTypeStandard:GeneratedUID"] = @[[NSString stringWithUTF8String: text]];

    NSString *value;
    if (entry->pw_gecos != NULL && (value = [NSString stringWithUTF8String: entry->pw_gecos]) != nil)
        attributes[@"dsAttrTypeStandard:RealName"] = @[value];
    if (entry->pw_dir != NULL && (value = [NSString stringWithUTF8String: entry->pw_dir]) != nil)
        attributes[@"dsAttrTypeStandard:NFSHomeDirectory"] = @[value];
    if (entry->pw_shell != NULL && (value = [NSString stringWithUTF8String: entry->pw_shell]) != nil)
        attributes[@"dsAttrTypeStandard:UserShell"] = @[value];

    return attributes;
}

NSDictionary *ODLocalUserAttributes(NSString *name)
{
    struct passwd entry, *result = NULL;
    char buffer[4096];

    if (![name isKindOfClass: [NSString class]] || [name UTF8String] == NULL)
        return nil;
    if (getpwnam_r([name UTF8String], &entry, buffer, sizeof(buffer), &result) != 0 || result == NULL)
        return nil;

    return attributesForEntry(result);
}

NSArray *ODLocalAllUserAttributes(void)
{
    NSMutableArray *users = [NSMutableArray array];
    struct passwd *entry;

    pthread_mutex_lock(&enumerationLock);
    setpwent();
    while ((entry = getpwent()) != NULL) {
        NSDictionary *attributes = attributesForEntry(entry);
        if (attributes != nil)
            [users addObject: attributes];
    }
    endpwent();
    pthread_mutex_unlock(&enumerationLock);

    return users;
}

BOOL ODLocalRecordTypesIncludeUsers(id recordTypeOrList)
{
    NSArray *types = [recordTypeOrList isKindOfClass: [NSArray class]] ? recordTypeOrList
                   : recordTypeOrList != nil ? @[recordTypeOrList] : @[];

    for (id type in types) {
        if ([type isKindOfClass: [NSString class]] && [type isEqualToString: @"dsRecTypeStandard:Users"])
            return YES;
    }
    return NO;
}
