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

#import <Foundation/Foundation.h>
#import <OpenDirectory/OpenDirectory.h>

// The local node: user records read from the system account database.
// Every value is an array of strings, keyed by attribute type.

extern NSString *const ODLocalNodeName;

NSError *ODLocalError(NSInteger code);
// nil when the name is not one of the nodes a standalone system has
NSString *ODLocalNodeNameForName(NSString *name);
NSString *ODLocalNodeNameForType(unsigned int type);
NSDictionary *ODLocalUserAttributes(NSString *name);
NSArray *ODLocalAllUserAttributes(void);
// a single record type or a list of them
BOOL ODLocalRecordTypesIncludeUsers(id recordTypeOrList);

ODRecord *ODLocalRecordCreate(NSDictionary *attributes);
