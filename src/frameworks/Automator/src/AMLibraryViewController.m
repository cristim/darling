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

#import <Automator/AMLibraryViewController.h>
#import "AMStubSignature.h"

@implementation AMLibraryViewController

- (void)dealloc
{
    [_actionTable setDataSource: nil];
    [_actions release];
    [_visibleActions release];
    [super dealloc];
}

- (void)_loadInstalledActions
{
    NSMutableArray *actions = [NSMutableArray array];
    NSArray *roots = @[ @"/System/Library/Automator", @"/Library/Automator",
                        [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Automator"] ];
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *root in roots) {
        for (NSString *entry in [files contentsOfDirectoryAtPath: root error: NULL]) {
            if (![[entry pathExtension] isEqualToString: @"action"])
                continue;
            NSString *path = [root stringByAppendingPathComponent: entry];
            NSString *infoPath = [path stringByAppendingPathComponent: @"Contents/Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile: infoPath];
            if (info == nil)
                continue;
            NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
            if (![name isKindOfClass: [NSString class]] || [name length] == 0)
                name = [entry stringByDeletingPathExtension];
            [actions addObject: @{ @"name": name, @"path": path }];
        }
    }
    [actions sortUsingComparator: ^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare: right[@"name"]];
    }];
    [_actions release];
    _actions = [actions copy];
    [_visibleActions release];
    _visibleActions = [_actions retain];
}

- (void)loadView
{
    // The imported Automator application does not include AMLibraryView.nib.
    NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 250, 600)];

    [self _loadInstalledActions];

    _searchField = [[NSSearchField alloc] initWithFrame: NSMakeRect(10, 565, 230, 24)];
    [_searchField setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    [_searchField setTarget: self];
    [_searchField setAction: @selector(_searchChanged:)];
    [view addSubview: _searchField];
    [_searchField release];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(10, 10, 230, 545)];
    [scroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [scroll setHasVerticalScroller: YES];
    _actionTable = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 230, 545)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"Action"];
    [column setWidth: 230];
    [_actionTable addTableColumn: column];
    [column release];
    [_actionTable setHeaderView: nil];
    [_actionTable setDataSource: self];
    [scroll setDocumentView: _actionTable];
    [_actionTable release];
    [view addSubview: scroll];
    [scroll release];

    _emptyLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(16, 525, 220, 24)];
    [_emptyLabel setEditable: NO];
    [_emptyLabel setSelectable: NO];
    [_emptyLabel setBordered: NO];
    [_emptyLabel setDrawsBackground: NO];
    [_emptyLabel setStringValue: @"No Automator actions installed."];
    [_emptyLabel setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    [_emptyLabel setHidden: [_visibleActions count] != 0];
    [view addSubview: _emptyLabel];
    [_emptyLabel release];

    [self setView: view];
    [view release];
}

- (NSSearchField *)_searchField
{
    return _searchField;
}

- (void)_searchChanged:(id)sender
{
    NSString *query = [[sender stringValue] stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *action in _actions) {
        if ([query length] == 0 ||
            [action[@"name"] rangeOfString: query options: NSCaseInsensitiveSearch].location != NSNotFound)
            [matches addObject: action];
    }
    [_visibleActions release];
    _visibleActions = [matches retain];
    [_actionTable reloadData];
    [_emptyLabel setStringValue: [_actions count] == 0 ? @"No Automator actions installed." : @"No matching actions."];
    [_emptyLabel setHidden: [_visibleActions count] != 0];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_visibleActions count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    return row >= 0 && row < [_visibleActions count] ? _visibleActions[row][@"name"] : nil;
}

AM_STUB_FORWARDING

@end
