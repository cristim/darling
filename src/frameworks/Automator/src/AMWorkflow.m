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

#import <Automator/AMWorkflow.h>
#import <Automator/AMWorkflowMetaData.h>
#import "AMStubSignature.h"

@implementation AMWorkflow

@synthesize hasUnsavedChanges = _hasUnsavedChanges;
@synthesize fileURL = _fileURL;

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _metaData = [[AMWorkflowMetaData alloc] init];
        _actions = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_metaData release];
    [_fileURL release];
    [_actions release];
    [super dealloc];
}

- (instancetype)initWithContentsOfURL:(NSURL *)fileURL error:(NSError **)outError
{
    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL: fileURL options: 0 error: outError];
    if (wrapper == nil) {
        [self release];
        return nil;
    }
    self = [self initWithFileWrapper: wrapper error: outError];
    [wrapper release];
    if (self != nil)
        [self setFileURL: fileURL];
    return self;
}

- (instancetype)initWithFileWrapper:(NSFileWrapper *)fileWrapper error:(NSError **)outError
{
    self = [self init];
    if (self == nil)
        return nil;

    NSFileWrapper *document = fileWrapper;
    if ([fileWrapper isDirectory]) {
        document = [fileWrapper fileWrappers][@"Contents"];
        document = [document fileWrappers][@"document.wflow"];
    }
    NSData *data = [document isRegularFile] ? [document regularFileContents] : nil;
    NSDictionary *plist = data != nil ?
        [NSPropertyListSerialization propertyListWithData: data options: 0 format: NULL error: outError] : nil;
    NSArray *actions = [plist isKindOfClass: [NSDictionary class]] ? plist[@"actions"] : nil;
    if (![actions isKindOfClass: [NSArray class]]) {
        if (outError != NULL)
            *outError = AMWorkflowFormatUnsupportedError();
        [self release];
        return nil;
    }
    [_actions addObjectsFromArray: actions];
    _hasUnsavedChanges = NO;
    if (outError != NULL)
        *outError = nil;
    return self;
}

- (BOOL)writeToURL:(NSURL *)fileURL error:(NSError **)outError
{
    NSFileWrapper *wrapper = [self fileWrapperForWritingReturningSavedPropertyList: NULL
        documentType: nil originalContentsFileWrapper: nil error: outError];
    if (wrapper == nil)
        return NO;
    BOOL written = [wrapper writeToURL: fileURL options: 0 originalContentsURL: nil error: outError];
    if (written) {
        [self setFileURL: fileURL];
        _hasUnsavedChanges = NO;
    }
    return written;
}

- (NSFileWrapper *)fileWrapperForWritingReturningSavedPropertyList:(id *)propertyList documentType:(NSString *)documentType originalContentsFileWrapper:(NSFileWrapper *)original error:(NSError **)outError
{
    for (id action in _actions) {
        if (![action isKindOfClass: [NSDictionary class]]) {
            if (outError != NULL)
                *outError = AMWorkflowFormatUnsupportedError();
            return nil;
        }
    }
    NSDictionary *plist = @{ @"AMDocumentVersion": @"2", @"actions": _actions };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList: plist
        format: NSPropertyListXMLFormat_v1_0 options: 0 error: outError];
    if (data == nil)
        return nil;
    if (propertyList != NULL)
        *propertyList = plist;

    NSFileWrapper *document = [[NSFileWrapper alloc] initRegularFileWithContents: data];
    [document setPreferredFilename: @"document.wflow"];
    NSFileWrapper *contents = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:
        @{ @"document.wflow": document }];
    [document release];
    [contents setPreferredFilename: @"Contents"];
    NSFileWrapper *package = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:
        @{ @"Contents": contents }];
    [contents release];
    if (outError != NULL)
        *outError = nil;
    return [package autorelease];
}

- (NSArray *)actions
{
    return [[_actions copy] autorelease];
}

- (void)addAction:(id)action
{
    [self insertAction: action atIndex: [_actions count]];
}

- (void)insertAction:(id)action atIndex:(NSUInteger)index
{
    [_actions insertObject: action atIndex: index];
    _hasUnsavedChanges = YES;
}

- (void)removeAction:(id)action
{
    if ([_actions containsObject: action]) {
        [_actions removeObject: action];
        _hasUnsavedChanges = YES;
    }
}

- (AMWorkflowMetaData *)_workflowMetaData
{
    return _metaData;
}

- (void)_setWorkflowMetaData:(AMWorkflowMetaData *)metaData
{
    [metaData retain];
    [_metaData release];
    _metaData = metaData;
}

// Automator.app reads the personality back through the metadata after setting it on the workflow,
// and restores both at once from a metadata backup, so the metadata owns it.
- (id)_workflowPersonality
{
    return [_metaData personality];
}

- (void)_setWorkflowPersonality:(id)personality
{
    [_metaData setPersonality: personality];
}

AM_STUB_FORWARDING

@end
