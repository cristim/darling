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

#import <Automator/AMTemplateChooserItem.h>
#import <AppKit/NSImage.h>
#import "AMStubSignature.h"
#import <dispatch/dispatch.h>

@implementation AMTemplateChooserItem

+ (NSArray *)templateChooserItems
{
    static AMTemplateChooserItem *workflowItem;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        workflowItem = [[self alloc] init];
    });
    return @[ workflowItem ];
}

- (NSString *)imageTitle
{
    return @"Workflow";
}

- (NSString *)templateDescription
{
    return @"Create a workflow by adding actions.";
}

- (id)imageRepresentation
{
    NSString *iconPath = [[NSBundle mainBundle] pathForResource: @"AppIcon" ofType: @"icns"];
    return [[[NSImage alloc] initWithContentsOfFile: iconPath] autorelease];
}

AM_STUB_FORWARDING

@end
