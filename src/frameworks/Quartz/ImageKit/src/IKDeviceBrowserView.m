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

#import <ImageKit/IKDeviceBrowserView.h>

@implementation IKDeviceBrowserView

- (void) setDefaults {
    _displaysLocalCameras = YES;
    _displaysNetworkCameras = YES;
    _displaysLocalScanners = YES;
    _displaysNetworkScanners = YES;
    _mode = IKDeviceBrowserViewDisplayModeTable;
}

- (instancetype) initWithFrame: (NSRect) frame {
    self = [super initWithFrame: frame];
    if (self != nil)
        [self setDefaults];
    return self;
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];
    if (self != nil)
        [self setDefaults];
    return self;
}

- (id<IKDeviceBrowserViewDelegate>) delegate {
    return _delegate;
}

- (void) setDelegate: (id<IKDeviceBrowserViewDelegate>) delegate {
    _delegate = delegate;
}

- (BOOL) displaysLocalCameras {
    return _displaysLocalCameras;
}

- (void) setDisplaysLocalCameras: (BOOL) displays {
    _displaysLocalCameras = displays;
}

- (BOOL) displaysNetworkCameras {
    return _displaysNetworkCameras;
}

- (void) setDisplaysNetworkCameras: (BOOL) displays {
    _displaysNetworkCameras = displays;
}

- (BOOL) displaysLocalScanners {
    return _displaysLocalScanners;
}

- (void) setDisplaysLocalScanners: (BOOL) displays {
    _displaysLocalScanners = displays;
}

- (BOOL) displaysNetworkScanners {
    return _displaysNetworkScanners;
}

- (void) setDisplaysNetworkScanners: (BOOL) displays {
    _displaysNetworkScanners = displays;
}

- (IKDeviceBrowserViewDisplayMode) mode {
    return _mode;
}

- (void) setMode: (IKDeviceBrowserViewDisplayMode) mode {
    _mode = mode;
}

- (ICDevice *) selectedDevice {
    return nil;
}

@end
