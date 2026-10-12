/*
 This file is part of Darling.

 Copyright (C) 2017 Lubos Dolezel

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

#include <stdlib.h>
#include <stdio.h>
#import <IOSurface/IOSurface.h>

#include <CoreFoundation/CoreFoundation.h>

/* darling-lol M57: IOSurfaceLookup has to resolve IDs produced by our
 * user-space IOSurface fallback (IOSurfaceCreateMachPort registers tokens in
 * api.m). Returning 0 here broke IOSurface lookup-by-ID and the
 * initWithSurfaceID: recovery path used during frame handoff. */
IOSurfaceRef _Nullable IOSurfaceLookupFromMachPort(mach_port_t port);

static int verbose = 0;

__attribute__((constructor))
static void initme(void) {
    verbose = getenv("STUB_VERBOSE") != NULL;
}


IOSurfaceRef _Nullable IOSurfaceLookup(IOSurfaceID csid){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    if (csid == 0)
        return 0;
    extern IOSurfaceRef _IOSurfaceLookupByID(IOSurfaceID);
    return _IOSurfaceLookupByID(csid);
}


size_t IOSurfaceGetAllocSize(IOSurfaceRef buffer){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    if (buffer == NULL)
        return 0;
    /* darling-lol: Chromium checks the allocation size when wrapping a
     * surface in a GpuMemoryBuffer; returning 0 made every buffer look
     * invalid. The user-space fallback allocates exactly
     * bytesPerRow * height for plane 0. */
    extern size_t _IOSurfaceObjCGetAllocSize(IOSurfaceRef);
    return _IOSurfaceObjCGetAllocSize(buffer);
}



size_t IOSurfaceGetNumberOfComponentsOfPlane(IOSurfaceRef buffer, size_t planeIndex){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}


IOSurfaceComponentName IOSurfaceGetNameOfComponentOfPlane(IOSurfaceRef buffer, size_t planeIndex, size_t componentIndex){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}


IOSurfaceComponentType IOSurfaceGetTypeOfComponentOfPlane(IOSurfaceRef buffer, size_t planeIndex, size_t componentIndex){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}


IOSurfaceComponentRange IOSurfaceGetRangeOfComponentOfPlane(IOSurfaceRef buffer, size_t planeIndex, size_t componentIndex){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}


size_t IOSurfaceGetBitDepthOfComponentOfPlane(IOSurfaceRef buffer, size_t planeIndex, size_t componentIndex){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}


size_t IOSurfaceGetBitOffsetOfComponentOfPlane(IOSurfaceRef buffer, size_t planeIndex, size_t componentIndex){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}


IOSurfaceSubsampling IOSurfaceGetSubsampling(IOSurfaceRef buffer){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}



size_t IOSurfaceGetPropertyMaximum(CFStringRef property){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}

size_t IOSurfaceGetPropertyAlignment(CFStringRef property){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}



size_t IOSurfaceAlignProperty(CFStringRef property, size_t value){
    /* Our shared backing requires valid non-overlapping plane layouts.
     * Chromium aligns every plane stride, allocation and offset through this
     * API; returning zero makes all chroma planes overlap the luma plane. */
    size_t alignment = 1;
    if(property && CFEqual(property,kIOSurfaceAllocSize)) alignment=4096;
    else if(property && (CFEqual(property,kIOSurfaceBytesPerRow) ||
            CFEqual(property,kIOSurfacePlaneBytesPerRow) ||
            CFEqual(property,kIOSurfacePlaneSize) ||
            CFEqual(property,kIOSurfacePlaneOffset))) alignment=64;
    if(value>SIZE_MAX-(alignment-1))return 0;
    return (value+alignment-1)&~(alignment-1);
}



Boolean IOSurfaceAllowsPixelSizeCasting(IOSurfaceRef buffer){
    if (verbose) printf("STUB: %s called\n", __FUNCTION__);
    return 0;
}

