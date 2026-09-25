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

#include <AppKit/NSView.h>

@class ICDevice;

typedef NS_ENUM(NSInteger, IKDeviceBrowserViewDisplayMode) {
    IKDeviceBrowserViewDisplayModeTable = 0,
    IKDeviceBrowserViewDisplayModeOutline = 1,
    IKDeviceBrowserViewDisplayModeIcon = 2,
};

@protocol IKDeviceBrowserViewDelegate;

@interface IKDeviceBrowserView : NSView {
    id<IKDeviceBrowserViewDelegate> _delegate;
    BOOL _displaysLocalCameras;
    BOOL _displaysNetworkCameras;
    BOOL _displaysLocalScanners;
    BOOL _displaysNetworkScanners;
    IKDeviceBrowserViewDisplayMode _mode;
}

@property (assign) id<IKDeviceBrowserViewDelegate> delegate;
@property BOOL displaysLocalCameras;
@property BOOL displaysNetworkCameras;
@property BOOL displaysLocalScanners;
@property BOOL displaysNetworkScanners;
@property IKDeviceBrowserViewDisplayMode mode;
@property (readonly) ICDevice *selectedDevice;

@end

@protocol IKDeviceBrowserViewDelegate <NSObject>
@optional
- (void) deviceBrowserView: (IKDeviceBrowserView *)browserView selectionDidChange: (ICDevice *)device;
- (void) deviceBrowserView: (IKDeviceBrowserView *)browserView didEncounterError: (NSError *)error;
@end
