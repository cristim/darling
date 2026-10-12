/*
 This file is part of Darling.

 Copyright (C) 2020 Lubos Dolezel

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

#import <IOSurface/IOSurface.h>
#import <IOSurface/IOSurfaceObjC.h>
#import <IOSurface/IOSurfacePriv.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOCFSerialize.h>
#include <stdatomic.h>
#include <stdlib.h>

/* darling-lol M58b: the guest libc's POSIX shm/mmap API (implemented by
 * elfcalls against the host, so the allocation is really /dev/shm memory
 * that another Darling process can map). */
#include <sys/mman.h>
#include <sys/fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include <mach/mach.h>
#include <sys/fileport.h>
#include <sys/file.h>

static io_service_t g_surfaceService;

typedef struct
{
	struct _IOSurfaceObjectRetval* surface;
	_Atomic int32_t localUseCount;
	/* darling-lol M58b: when the fallback allocation is backed by a host
	 * shared-memory file (see IOSurfacePriv.h), these hold the mapping so
	 * dealloc can unmap/close instead of free()ing platform-managed memory.
	 * shm_fd < 0 means a plain calloc'd private allocation. */
	int shm_fd;
	uint64_t shm_size;
	mach_port_t shm_port;
	NSMutableDictionary* attachments;
} ImplData;

/* Surface IDs cross process boundaries and must not restart at one per process. */
extern long __lolsys_syscall(long,long,long,long,long,long,int);
static IOSurfaceID allocateSurfaceID(void)
{
    char name[80];
    snprintf(name, sizeof(name), "/dev/shm/darling-iosurface-counter-%u", (unsigned)getuid());
    /* The counter is host shared memory, never a guest fileport. Native
     * syscalls preserve the same cross-process flock without routing every
     * video-frame allocation through Darling's descriptor/event machinery. */
    int fd = (int)__lolsys_syscall((long)name,66|02000000 /* Linux O_CLOEXEC */,0600,0,0,0,2);
    if (fd < 0) return 0;
    long locked;
    do { locked=__lolsys_syscall(fd,LOCK_EX,0,0,0,0,73); } while(locked==-4);
    if (locked != 0) { __lolsys_syscall(fd,0,0,0,0,0,3); return 0; }
    IOSurfaceID value = 0;
    long count;
    do { count=__lolsys_syscall(fd,(long)&value,sizeof(value),0,0,0,17); } while(count==-4);
    if ((count != 0 && count != sizeof(value)) || value == UINT32_MAX) {
        __lolsys_syscall(fd,0,0,0,0,0,3); return 0;
    }
    ++value;
    long written;
    do { written=__lolsys_syscall(fd,(long)&value,sizeof(value),0,0,0,18); } while(written==-4);
    if (written != sizeof(value)) value = 0;
    __lolsys_syscall(fd,0,0,0,0,0,3);
    return value;
}

@implementation IOSurface

+ (void)initialize
{
	if (self == [IOSurface self])
	{
		/* darling-lol M58e: do not touch IOKit here at all.
		 *
		 * This class initializer used to look the IOSurfaceRoot IOKit
		 * service up on the first IOSurface use of every Darling
		 * process. There is no way it can SUCCEED under Darling (no
		 * IOSurfaceRoot IOKit server exists — user-space fallbacks
		 * below already key everything off g_surfaceService == 0), but
		 * when the runtime's class-initialization machinery is unlucky
		 * (/helper processes racing CoreFoundation's first CF calls),
		 * the CF objects involved in the call chain can be reported
		 * with garbage isa pointers and the plain CFRelease of the
		 * matching dictionary SEGVs (measured: intermittent SIGSEGV at
		 * window startup in both browser and GPU processes, with LOLSIG
		 * chains ending in libsystem_malloc's free path and in
		 * objc_msgSend on a dead receiver — both reproducible ~1:3 runs
		 * before this change; everything symbolized through the M58e
		 * SIGFRAME walk). */
		g_surfaceService = 0;
		NSLog(@"IOSurface: user-space route (no IOKit IOSurfaceRoot).\n");
	}
}

- (nullable instancetype)initWithResponse:(const void*)bytes length:(size_t)length
{
	ImplData* idata = (ImplData*) malloc(sizeof(ImplData));
	idata->surface = malloc(length);
	memcpy(idata->surface, bytes, length);

	idata->localUseCount = 0;
	idata->shm_fd = -1;
	idata->shm_size = 0;
	idata->shm_port = MACH_PORT_NULL;
	idata->attachments = [[NSMutableDictionary alloc] init];
	self->_impl = idata;

	return self;
}

- (nullable instancetype)initWithProperties:(NSDictionary <IOSurfacePropertyKey, id> *)properties
{
    /* The fallback service is absent by construction. Avoid serializing and
     * issuing an IOKit request that cannot succeed for every video frame. */
    if (g_surfaceService == 0)
        return [self _initWithUserSpaceProperties: properties];
	CFDataRef data = IOCFSerialize((CFTypeRef) properties, kIOCFSerializeToBinary);
	uint8_t responseBuffer[3500];

	const void* bytes = CFDataGetBytePtr(data);
	size_t length = CFDataGetLength(data);
	size_t responseLength = sizeof(responseBuffer);

	kern_return_t ret = IOConnectCallMethod(g_surfaceService, kIOSurfaceMethodCreate, NULL, 0, bytes, length, NULL, 0, responseBuffer, &responseLength);
	CFRelease(data);

	if (ret != kIOSurfaceSuccess)
	{
		/* darling-lol M57: Darling has no IOSurfaceRoot IOKit service, so the
		 * real create path always fails and Chromium's GPU process can't
		 * allocate any GPU memory buffer (it then exits with "drivers can't
		 * recover"). Fall back to a plain user-space allocation. */
		return [self _initWithUserSpaceProperties: (NSDictionary*) properties];
	}

	return [self initWithResponse: responseBuffer length: responseLength];
}

- (nullable instancetype)_initWithUserSpaceProperties:(NSDictionary <IOSurfacePropertyKey, id> *)properties
{
	NSNumber* widthNum = properties[(NSString*)kIOSurfaceWidth];
	NSNumber* heightNum = properties[(NSString*)kIOSurfaceHeight];
	NSNumber* bytesPerRowNum = properties[(NSString*)kIOSurfaceBytesPerRow];
	NSNumber* bytesPerElementNum = properties[(NSString*)kIOSurfaceBytesPerElement];
	NSNumber* pixelFormatNum = properties[(NSString*)kIOSurfacePixelFormat];

	uint32_t width = widthNum ? widthNum.unsignedIntValue : 0;
	uint32_t height = heightNum ? heightNum.unsignedIntValue : 0;
	uint32_t bytesPerElement = bytesPerElementNum ? bytesPerElementNum.unsignedIntValue : 4;
	if (bytesPerElement == 0) bytesPerElement = 4;
	uint32_t bytesPerRow = bytesPerRowNum ? bytesPerRowNum.unsignedIntValue : (width * bytesPerElement);
	if (bytesPerRow == 0) bytesPerRow = width * bytesPerElement;
	uint32_t pixelFormat = pixelFormatNum ? pixelFormatNum.unsignedIntValue : 0;
    NSArray *planeInfo = properties[(NSString*)kIOSurfacePlaneInfo];
    unsigned planeCount = planeInfo.count ? (unsigned)planeInfo.count : 1;
    if (planeCount > 4) { [self release]; return nil; }
    struct _IOSurfacePlane planes[4] = {{0}};
    uint64_t allocSize = 0;
    for (unsigned i=0; i<planeCount; ++i) {
        NSDictionary *info = planeInfo.count ? planeInfo[i] : nil;
        uint64_t pw = info ? [info[(NSString*)kIOSurfacePlaneWidth] unsignedLongLongValue] : width;
        uint64_t ph = info ? [info[(NSString*)kIOSurfacePlaneHeight] unsignedLongLongValue] : height;
        uint64_t pe = info ? [info[(NSString*)kIOSurfacePlaneBytesPerElement] unsignedLongLongValue] : bytesPerElement;
        uint64_t pr = info ? [info[(NSString*)kIOSurfacePlaneBytesPerRow] unsignedLongLongValue] : bytesPerRow;
        NSNumber *offset = info[(NSString*)kIOSurfacePlaneOffset];
        uint64_t po = offset ? offset.unsignedLongLongValue : allocSize;
        if (!pe) pe=1;
        if (!pr) pr=pw*pe;
        if (!pw || !ph || pw>UINT32_MAX || ph>UINT32_MAX || pe>16 ||
            pr>UINT32_MAX || pr<pw*pe || ph>SIZE_MAX/pr || po>SIZE_MAX-pr*ph ||
            (i && po<allocSize)) { [self release]; return nil; }
        planes[i]=(struct _IOSurfacePlane){po,(uint32_t)pe,(uint32_t)pw,(uint32_t)ph,(uint32_t)pr};
        allocSize=po+pr*ph;
    }
    NSNumber *requested=properties[(NSString*)kIOSurfaceAllocSize];
    if (requested && requested.unsignedLongLongValue>allocSize) allocSize=requested.unsignedLongLongValue;
    if (allocSize>SIZE_MAX-IOSURFACE_WIRE_DATA_OFFSET) { [self release]; return nil; }

	/* darling-lol M58b: back the surface with a host shared-memory file so
	 * another process can map the same memory through a fileport handed
	 * off by IOSurfaceCreateMachPort(). The file holds a wire header at
	 * offset 0 and plane 0's data at IOSURFACE_WIRE_DATA_OFFSET. */
	uint64_t shmSize = IOSURFACE_WIRE_DATA_OFFSET + allocSize;

	int shm_fd = -1;
	void* address = NULL;
	char shmName[128];
	static _Atomic unsigned shmCounter = 0;

	shmName[0] = '\0';
	{
		_Atomic unsigned counter = ++shmCounter;
		unsigned attempt;
		for (attempt = 0; attempt < 16; ++attempt)
		{
			/* O_EXCL to guarantee a unique /dev/shm object. */
			snprintf(shmName, sizeof(shmName), "/IOSurface-%d-%u-%u",
			    getpid(), (unsigned) counter + attempt, 0u);
			shm_fd = shm_open(shmName, O_RDWR | O_CREAT | O_EXCL, 0600);
			if (shm_fd >= 0)
				break;
			/* EEXIST -> next name; any other error releases the loop
			 * via the post-check below. */
			shm_fd = -1;
		}
	}

	if (shm_fd >= 0)
	{
		if (shm_unlink(shmName) != 0)
		{
			/* Nobody else needs to find this by name; unlink ASAP so
			 * the object dies with the last fd. */
		}

		if (ftruncate(shm_fd, (off_t) shmSize) != 0)
		{
			close(shm_fd);
			shm_fd = -1;
		} else {
			address = mmap(NULL, shmSize, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
		if (address == NULL || address == MAP_FAILED)
			{
				close(shm_fd);
				shm_fd = -1;
				address = NULL;
			}
		}
	}

	if (shm_fd < 0)
	{
		/* No shared memory available: plain private allocation (in-process
		 * only; IOSurfaceCreateMachPort has nothing to hand off). */
		shmSize = allocSize;
		address = calloc(1, (size_t) allocSize);
		if (address == NULL)
		{
			[self release];
			return nil;
		}
	}

	size_t structSize = sizeof(struct _IOSurfaceObjectRetval) + (planeCount-1)*sizeof(struct _IOSurfacePlane);
	struct _IOSurfaceObjectRetval* surface = calloc(1, structSize);
	if (surface == NULL)
	{
		if (shm_fd >= 0)
		{
			munmap(address, shmSize);
			close(shm_fd);
		} else {
			free(address);
		}
		[self release];
		return nil;
	}

    surface->surfaceID = allocateSurfaceID();
    if (!surface->surfaceID) {
        if (shm_fd >= 0) { munmap(address, shmSize); close(shm_fd); }
        else free(address);
        free(surface);
        [self release];
        return nil;
    }
	surface->pixelFormat = pixelFormat;
	surface->address = (uint64_t) address;
    surface->planeCount = planeCount;
    for (unsigned i=0; i<planeCount; ++i) {
        surface->planes[i]=planes[i];
        if (shm_fd>=0) surface->planes[i].memoryOffset+=IOSURFACE_WIRE_DATA_OFFSET;
    }

	if (shm_fd >= 0)
	{
		/* Fill in the wire header so IOSurfaceLookupFromMachPort() in
		 * another process can rebuild this object from the mapping. */
		struct _IOSurfaceWireHeader wire;
		memset(&wire, 0, sizeof(wire));
		wire.magic = IOSURFACE_WIRE_MAGIC;
		wire.version = IOSURFACE_WIRE_VERSION;
		wire.surfaceID = surface->surfaceID;
		wire.pixelFormat = surface->pixelFormat;
		wire.planeCount = surface->planeCount;
		wire.reserved = 0;
		wire.memoryOffset = surface->planes[0].memoryOffset;
		wire.width = surface->planes[0].width;
		wire.height = surface->planes[0].height;
		wire.bytesPerRow = surface->planes[0].bytesPerRow;
		wire.bytesPerElement = surface->planes[0].bytesPerElement;
        memcpy(wire.planes, surface->planes, planeCount*sizeof(struct _IOSurfacePlane));
		(void) pwrite(shm_fd, &wire, sizeof(wire), 0);
	}

	ImplData* idata = (ImplData*) malloc(sizeof(ImplData));
	idata->surface = surface;
	idata->localUseCount = 0;
	idata->shm_fd = shm_fd;
	idata->shm_size = shmSize;
	idata->shm_port = MACH_PORT_NULL;
	idata->attachments = [[NSMutableDictionary alloc] init];
	self->_impl = idata;

	return self;
}

- (nullable instancetype)initWithSurfaceID:(IOSurfaceID)surfaceID
{
	uint8_t responseBuffer[3500];
	size_t responseLength = sizeof(responseBuffer);

	uint64_t scalar = surfaceID;
	kern_return_t ret = g_surfaceService != 0
		? IOConnectCallMethod(g_surfaceService, kIOSurfaceMethodLookupByID, &scalar, 1, NULL, 0, NULL, 0, responseBuffer, &responseLength)
		: KERN_FAILURE;

	if (ret != kIOSurfaceSuccess)
	{
		/* darling-lol: without the IOSurfaceRoot service (Darling) the
		 * lookup always fails, so re-resolve the ID against our own
		 * user-space registry instead of returning nil. */
		IOSurfaceRef surface = IOSurfaceLookup(surfaceID);
		if (surface != NULL)
			return (IOSurface*) surface;

		[self release];
		return nil;
	}

	return [self initWithResponse: responseBuffer length: responseLength];
}

/* darling-lol: IOSurfaceLookupFromMachPort() calls this, but it was never
 * implemented, so every cross-process frame handoff returned a half-built
 * object. Recover a registered surface by token, else treat the token as an
 * IOSurfaceID and try the registry through iosurface_lookup(). */
- (nullable instancetype)initWithMachPort:(mach_port_t)port
{
	if (port == MACH_PORT_NULL)
	{
		[self release];
		return nil;
	}

	IOSurfaceRef known = IOSurfaceLookup((IOSurfaceID) port);
	if (known != NULL)
	{
		[self release];
		return (IOSurface*) known;
	}

	/* Unknown token: build an empty placeholder rather than nil so callers
	 * that only need the object identity keep working. */
	return [self initWithResponse: "\0" length: 1];
}

/* Serialize final release with registry lookup/retain. The recursive lock
 * permits dealloc to remove the entry while super's release is active. */
- (oneway void) release
{
    extern void _IOSurfaceRegistryLock(void), _IOSurfaceRegistryUnlock(void);
    _IOSurfaceRegistryLock();
    [super release];
    _IOSurfaceRegistryUnlock();
}

- (void) dealloc
{
    extern void _IOSurfaceRegistryForget(IOSurfaceRef);
    if (_impl) _IOSurfaceRegistryForget((IOSurfaceRef)self);
	ImplData* data = (ImplData*) _impl;
	if (data != NULL)
	{
		if (data->surface != NULL)
		{
			if (g_surfaceService != 0)
				IOConnectCallMethod(g_surfaceService, kIOSurfaceMethodRelease, NULL, 0, &data->surface->surfaceID, 1, NULL, 0, NULL, 0);

			/* darling-lol M58b: free the surface's memory according to
			 * its backing; shared mappings belong to mmap, not the
			 * general allocator. */
			if (data->shm_fd >= 0)
			{
				if (data->surface->address != 0)
					munmap((void*)(uintptr_t) data->surface->address, data->shm_size);
				close(data->shm_fd);
			} else if (data->surface->address != 0) {
				free((void*)(uintptr_t) data->surface->address);
			}

			/* The fileport right created by IOSurfaceCreateMachPort()
			 * keeps the backing alive for whoever it was handed to;
			 * releasing our send right is enough here. */
			if (data->shm_port != MACH_PORT_NULL)
				mach_port_deallocate(mach_task_self(), data->shm_port);

			free(data->surface);
		}

		[data->attachments release];
		free(data);
	}
	[super dealloc];
}

- (NSUInteger) hash
{
	ImplData* data = (ImplData*) _impl;
	return data->surface->surfaceID;
}

- (BOOL)isEqual:(id)object
{
	if (![object isKindOfClass: [self class]])
		return NO;

	IOSurface* that = (IOSurface*) object;
	return ((ImplData*) self->_impl)->surface->surfaceID == ((ImplData*) that->_impl)->surface->surfaceID;
}

- (CFTypeID) _cfTypeID
{
    return IOSurfaceGetTypeID();
}

- (NSInteger) width
{
	return [self widthOfPlaneAtIndex: 0];
}

- (NSInteger) height
{
	return [self heightOfPlaneAtIndex: 0];
}

- (void *) baseAddress
{
	return [self baseAddressOfPlaneAtIndex: 0];
}

- (NSInteger) bytesPerRow
{
	return [self bytesPerRowOfPlaneAtIndex: 0];
}

- (NSInteger) bytesPerElement
{
	return [self bytesPerElementOfPlaneAtIndex: 0];
}

- (NSInteger) elementWidth
{
	return [self elementWidthOfPlaneAtIndex: 0];
}

- (NSInteger) elementHeight
{
	return [self elementHeightOfPlaneAtIndex: 0];
}

- (OSType) pixelFormat
{
	return ((ImplData*) _impl)->surface->pixelFormat;
}

- (NSUInteger) planeCount
{
	return ((ImplData*) _impl)->surface->planeCount;
}

- (NSInteger)widthOfPlaneAtIndex:(NSUInteger)planeIndex
{
	if (planeIndex >= [self planeCount])
		return 0;

	ImplData* data = (ImplData*) _impl;
	return data->surface->planes[planeIndex].width;
}

- (NSInteger)heightOfPlaneAtIndex:(NSUInteger)planeIndex
{
	if (planeIndex >= [self planeCount])
		return 0;

	ImplData* data = (ImplData*) _impl;
	return data->surface->planes[planeIndex].height;
}

- (NSInteger)bytesPerRowOfPlaneAtIndex:(NSUInteger)planeIndex
{
	if (planeIndex >= [self planeCount])
		return 0;

	ImplData* data = (ImplData*) _impl;
	return data->surface->planes[planeIndex].bytesPerRow;
}

- (NSInteger)bytesPerElementOfPlaneAtIndex:(NSUInteger)planeIndex
{
	if (planeIndex >= [self planeCount])
		return 0;

	ImplData* data = (ImplData*) _impl;
	return data->surface->planes[planeIndex].bytesPerElement;
}

- (NSInteger)elementWidthOfPlaneAtIndex:(NSUInteger)planeIndex
{
	return 1;
}

- (NSInteger)elementHeightOfPlaneAtIndex:(NSUInteger)planeIndex
{
	return 1;
}

- (void *)baseAddressOfPlaneAtIndex:(NSUInteger)planeIndex
{
	if (planeIndex >= [self planeCount])
		return NULL;

	ImplData* data = (ImplData*) _impl;
	return (void*)(data->surface->address + data->surface->planes[planeIndex].memoryOffset);
}

- (void)setAttachment:(id)anObject forKey:(NSString *)key
{
	if (!key)
		return;
	ImplData* data = (ImplData*) _impl;
	if (anObject)
		[data->attachments setObject:anObject forKey:key];
	else
		[data->attachments removeObjectForKey:key];
}

- (id)attachmentForKey:(NSString *)key
{
	ImplData* data = (ImplData*) _impl;
	return [data->attachments objectForKey:key];
}

- (void)removeAttachmentForKey:(NSString *)key
{
	ImplData* data = (ImplData*) _impl;
	[data->attachments removeObjectForKey:key];
}

- (void)setAllAttachments:(NSDictionary<NSString *, id> *)dict
{
	ImplData* data = (ImplData*) _impl;
	[data->attachments removeAllObjects];
	if (dict)
		[data->attachments addEntriesFromDictionary:dict];
}

- (NSDictionary<NSString *, id> *)allAttachments
{
	ImplData* data = (ImplData*) _impl;
	return data->attachments;
}

- (void)removeAllAttachments
{
	ImplData* data = (ImplData*) _impl;
	[data->attachments removeAllObjects];
}

- (void)incrementUseCount
{
	ImplData* data = (ImplData*) _impl;
	if ((data->localUseCount++) == 0)
	{
		if (g_surfaceService == 0)
			return;
		uint64_t scalar = data->surface->surfaceID;
		IOConnectCallMethod(g_surfaceService, kIOSurfaceMethodIncrementUseCount, &scalar, 1, NULL, 0, NULL, 0, NULL, 0);
	}
}

- (void)decrementUseCount
{
	ImplData* data = (ImplData*) _impl;
	if (--data->localUseCount == 0)
	{
		if (g_surfaceService == 0)
			return;
		uint64_t scalar = data->surface->surfaceID;
		IOConnectCallMethod(g_surfaceService, kIOSurfaceMethodDecrementUseCount, &scalar, 1, NULL, 0, NULL, 0, NULL, 0);
	}
}

- (int32_t) localUseCount
{
	ImplData* data = (ImplData*) _impl;
	return data->localUseCount;
}

/* darling-lol M58b: cross-process identity. IOSurfaceCreateMachPort()
 * (in api.m) calls this to wrap this surface's shared backing in a fileport
 * -- a REAL mach task-port send right referencing our /dev/shm file, so
 * callers that do mach_port_mod_refs()/port-transfer checks get a valid
 * name. Cached on the object so repeated creates reuse the same right. */
static mach_port_t copySurfaceSendRight(mach_port_t port)
{
	/* The surface owns the cached reference; every Create caller owns another. */
	if (mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_SEND, 1) != KERN_SUCCESS)
		return MACH_PORT_NULL;
	return port;
}

mach_port_t _IOSurfaceObjCShmFileportForSurface(IOSurfaceRef buffer)
{
 IOSurface* self = (IOSurface*) buffer;
	ImplData* data = (ImplData*) self->_impl;

	if (buffer == NULL)
		return MACH_PORT_NULL;

	data = (ImplData*) self->_impl;
	if (data == NULL)
		return MACH_PORT_NULL;

	/* darling-lol M58cz: reuse any right we already handed out. This also
	 * covers surfaces restored via initWithMachPort: (which have no shm_fd
	 * but may carry a port). */
	if (data->shm_port != MACH_PORT_NULL)
		return copySurfaceSendRight(data->shm_port);

	if (data->shm_fd >= 0)
	{
		mach_port_t port = MACH_PORT_NULL;
		if (fileport_makeport(data->shm_fd, &port) != KERN_SUCCESS || port == MACH_PORT_NULL)
		{
			NSLog(@"_IOSurfaceObjCShmFileportForSurface: fileport_makeport failed (fd=%d)", data->shm_fd);
			return MACH_PORT_NULL;
		}
		data->shm_port = port;
		return copySurfaceSendRight(data->shm_port);
	}

	/* darling-lol M58cz: a surface with NO shared backing must STILL hand
	 * out a REAL mach send right. The old M57 code returned a fake token
	 * ((mach_port_t) sid); Chromium's IOSurfaceMachPortTraits then failed
	 * mach_port_mod_refs() with KERN_INVALID_NAME on every surface handoff,
	 * and the token could not be carried in a mach message at all. Back the
	 * right with /dev/null: the name is valid for mach_port_mod_refs() and
	 * mojo's port transport; a cross-process lookup of a private surface
	 * still resolves to a placeholder, as before. */
	{
		int nullfd = open("/dev/null", 0 /* O_RDONLY */);
		mach_port_t port = MACH_PORT_NULL;
		if (nullfd >= 0 &&
		    fileport_makeport(nullfd, &port) == KERN_SUCCESS &&
		    port != MACH_PORT_NULL)
		{
			/* the fileport kobject owns nullfd now and closes it on death */
			data->shm_port = port;
			return copySurfaceSendRight(data->shm_port);
		}
		if (nullfd >= 0)
			close(nullfd);
	}
	return MACH_PORT_NULL;
}

/* darling-lol M58b: IOSurfaceLookupFromMachPort() (in api.m) calls this when
 * the port is a fileport holding a shared IOSurface backing: map the fd and
 * reconstruct the object from the wire header at offset 0. */
/* Keep at most eight live import mappings. File identity plus the complete
 * validated wire layout prevents descriptor/Mach-name reuse from aliasing a
 * different surface. The cache owns no Mach rights; every lookup still
 * validates its caller's right through fileport_makefd before reaching here. */
struct ImportedSurfaceCacheEntry {
    uint64_t device, inode, size, age;
    struct _IOSurfaceWireHeader wire;
    IOSurface *surface;
};
static struct ImportedSurfaceCacheEntry importedSurfaces[8];
static uint64_t importedSurfaceAge;
extern void _IOSurfaceRegistryLock(void), _IOSurfaceRegistryUnlock(void);
static bool importedSurfaceMatches(struct ImportedSurfaceCacheEntry *entry,
    const struct stat *st, const struct _IOSurfaceWireHeader *wire) {
    return entry->surface && entry->device==(uint64_t)st->st_dev &&
        entry->inode==(uint64_t)st->st_ino && entry->size==(uint64_t)st->st_size &&
        !memcmp(&entry->wire,wire,sizeof(*wire));
}
static IOSurface *cachedImportedSurface(const struct stat *st,
    const struct _IOSurfaceWireHeader *wire, IOSurface *candidate) {
    _IOSurfaceRegistryLock();
    for (unsigned i=0;i<8;i++) if(importedSurfaceMatches(&importedSurfaces[i],st,wire)) {
        IOSurface *result=[importedSurfaces[i].surface retain];
        importedSurfaces[i].age=++importedSurfaceAge;
        _IOSurfaceRegistryUnlock();[candidate release];return result;
    }
    if(!candidate){_IOSurfaceRegistryUnlock();return nil;}
    unsigned index=0;
    for(unsigned i=1;i<8;i++) if(importedSurfaces[i].age<importedSurfaces[index].age)index=i;
    IOSurface *old=importedSurfaces[index].surface;
    importedSurfaces[index]=(struct ImportedSurfaceCacheEntry){
        .device=(uint64_t)st->st_dev,.inode=(uint64_t)st->st_ino,
        .size=(uint64_t)st->st_size,.age=++importedSurfaceAge,
        .wire=*wire,.surface=[candidate retain]};
    _IOSurfaceRegistryUnlock();[old release];return candidate;
}

IOSurfaceRef _IOSurfaceInitFromSharedMemfd(int fd)
{
	struct stat st;
	if (fd < 0 || fstat(fd, &st) != 0 || st.st_size < (off_t) sizeof(struct _IOSurfaceWireHeader))
	{
		if (fd >= 0)
			close(fd);
		return NULL;
	}

	uint64_t shmSize = (uint64_t) st.st_size;

	struct _IOSurfaceWireHeader wire;
	if (pread(fd, &wire, sizeof(wire), 0) != sizeof(wire) ||
	    wire.magic != IOSURFACE_WIRE_MAGIC ||
	    wire.version != IOSURFACE_WIRE_VERSION ||
	    !wire.planeCount || wire.planeCount > 4 ||
	    wire.memoryOffset != IOSURFACE_WIRE_DATA_OFFSET ||
	    st.st_size < (off_t)(wire.memoryOffset + (uint64_t) wire.bytesPerRow * (uint64_t) wire.height))
	{
		close(fd);
		return NULL;
	}

    for (unsigned i=0; i<wire.planeCount; ++i) {
        struct _IOSurfacePlane p=wire.planes[i];
        uint64_t bytes=(uint64_t)p.bytesPerRow*p.height;
        if (!p.width || !p.height || !p.bytesPerElement || p.bytesPerElement>16 ||
            (uint64_t)p.width*p.bytesPerElement>p.bytesPerRow ||
            p.memoryOffset<IOSURFACE_WIRE_DATA_OFFSET || p.memoryOffset>shmSize || bytes>shmSize-p.memoryOffset) {
            close(fd); return NULL;
        }
    }
    unsigned planeCount=wire.planeCount;
    bool cacheEnabled=getenv("RCLOL_IOSURFACE_IMPORT_CACHE")!=NULL;
    if(cacheEnabled) {
        IOSurface *cached=cachedImportedSurface(&st,&wire,nil);
        if(cached){close(fd);return (IOSurfaceRef)cached;}
    }

	void* address = mmap(NULL, shmSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (address == NULL || address == MAP_FAILED)
	{
		close(fd);
		return NULL;
	}

	size_t structSize = sizeof(struct _IOSurfaceObjectRetval) + (planeCount-1)*sizeof(struct _IOSurfacePlane);
	struct _IOSurfaceObjectRetval* surface = calloc(1, structSize);
	if (surface == NULL)
	{
		munmap(address, shmSize);
		close(fd);
		return NULL;
	}

	surface->surfaceID = wire.surfaceID;
	surface->pixelFormat = wire.pixelFormat;
	surface->address = (uint64_t) address;
    surface->planeCount=planeCount;
    memcpy(surface->planes,wire.planes,planeCount*sizeof(struct _IOSurfacePlane));

	IOSurface* obj = [IOSurface alloc];
	ImplData* idata = (ImplData*) malloc(sizeof(ImplData));
	idata->surface = surface;
	idata->localUseCount = 0;
	idata->shm_fd = fd;
	idata->shm_size = shmSize;
	idata->shm_port = MACH_PORT_NULL;
	idata->attachments = [[NSMutableDictionary alloc] init];
	obj->_impl = idata;

	return (IOSurfaceRef)(cacheEnabled?cachedImportedSurface(&st,&wire,obj):obj);
}
- (kern_return_t)lockWithOptions:(IOSurfaceLockOptions)options seed:(nullable uint32_t *)seed
{
	ImplData* data = (ImplData*) _impl;
	struct _IOSurfaceLockUnlock args = {
		.surfaceID = data->surface->surfaceID,
		.options = options,
	};
	/* darling-lol: user-space fallback surfaces have no IOSurfaceRoot
	 * connection, so calling the (null) service returns an error and the
	 * frame path treats the surface as unusable. There is no real lock to
	 * take for a private allocation, so succeed. */
	if (g_surfaceService == 0)
		return kIOSurfaceSuccess;
	return IOConnectCallMethod(g_surfaceService, kIOSurfaceMethodLock, NULL, 0, &args, sizeof(args), NULL, 0, NULL, 0);
}

- (kern_return_t)unlockWithOptions:(IOSurfaceLockOptions)options seed:(nullable uint32_t *)seed
{
	ImplData* data = (ImplData*) _impl;
	struct _IOSurfaceLockUnlock args = {
		.surfaceID = data->surface->surfaceID,
		.options = options,
	};
	if (g_surfaceService == 0)
		return kIOSurfaceSuccess;
	return IOConnectCallMethod(g_surfaceService, kIOSurfaceMethodUnlock, NULL, 0, &args, sizeof(args), NULL, 0, NULL, 0);
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

size_t _IOSurfaceObjCGetAllocSize(IOSurfaceRef buffer) {
    ImplData *data=(ImplData*)((IOSurface*)buffer)->_impl;
    return data->shm_fd>=0 ? data->shm_size-IOSURFACE_WIRE_DATA_OFFSET : data->shm_size;
}
