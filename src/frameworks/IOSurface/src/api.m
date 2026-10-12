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
#import <Foundation/NSLock.h>
#import <Foundation/NSValue.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

/* darling-lol M58b: IOSurfaceCreateMachPort / IOSurfaceLookupFromMachPort are
 * implemented on Darling's fileport machinery plus host shared-memory files;
 * the send/receive helpers live in IOSurfaceObjC.m (they need the internal
 * ImplData). The M57 fake-token registry is gone: fake names made Chromium's
 * mach_port_mod_refs (ui/gfx/mac/io_surface.cc IOSurfaceMachPortTraits) fail
 * with invalid_name on every surface handoff. */
extern mach_port_t _IOSurfaceObjCShmFileportForSurface(IOSurfaceRef buffer);
extern IOSurfaceRef _IOSurfaceInitFromSharedMemfd(int fd);
extern int fileport_makefd(mach_port_t port);

/* Keep the M57 token registry as the in-process fast path; the fileport is
 * used when the surface has a shared backing. */
static NSMutableDictionary<NSNumber*, NSValue*>* gMachPortRegistry = nil;
static NSRecursiveLock* gMachPortRegistryLock = nil;
static pthread_once_t registryOnce = PTHREAD_ONCE_INIT;

/* darling-lol M58c: materialize the rendered GL texture into the IOSurface
 * backing before the surface leaves this process.
 *
 * On macOS, CGLTexImageIOSurface2D makes the IOSurface the texture's storage,
 * so GL rendering lands in IOSurface memory implicitly. Darling's CGL is
 * backed by Mesa/EGL, where CGLTexImageIOSurface2D can only COPY the IOSurface
 * into a private GL texture once at bind time. Chromium's compositor then
 * renders every frame into that texture, and the IOSurface backing (the host
 * shared-memory file shared with the next process) never receives the pixels —
 * every published frame was metadata-correct but all-zero.
 *
 * The fix: at every cross-process handoff point (IOSurfaceCreateMachPort is
 * called by the sender — GPU process for the display surface, renderer process
 * for its GMB content surfaces), copy the bound GL texture back into the
 * IOSurface memory via OpenGL.framework's CGLReadbackIOSurface. The binding
 * table it consults is per-process, so this is a harmless no-op in processes
 * that never GL-bound the surface (browser, software path).
 *
 * OpenGL.framework is resolved with a private dlopen: IOSurface cannot link
 * OpenGL (OpenGL links IOSurface — a cycle), and per the M57bo lesson adding
 * CGL symbols to IOSurface's dependency symbol scope would leak them to every
 * dependent. In GL processes the framework is already loaded (ANGLE depends on
 * it), so dlopen merely bumps the refcount. */
typedef unsigned int _DarlingCGLError;
typedef _DarlingCGLError (*_DarlingReadbackFn)(IOSurfaceRef);

static _DarlingReadbackFn _DarlingResolveReadback(void)
{
	static _DarlingReadbackFn fn;
	static int resolved;
	static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

	pthread_mutex_lock(&lock);
	if (!resolved)
	{
		resolved = 1;
		void* h = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL",
			RTLD_NOW | RTLD_LOCAL);
		if (h)
			fn = (_DarlingReadbackFn) dlsym(h, "CGLReadbackIOSurface");
	}
	pthread_mutex_unlock(&lock);
	return fn;
}

static void _DarlingWriteBackGLTexture(IOSurfaceRef buffer)
{
	_DarlingReadbackFn fn = _DarlingResolveReadback();
	if (!fn)
		return;
	_DarlingCGLError err = fn(buffer);
	if (err != 0 && getenv("M58_WB_TRACE") != NULL)
		fprintf(stderr, "M58WB pid=%d sid=%u readback=0x%x\n",
			(int) getpid(), (unsigned) IOSurfaceGetID(buffer), (unsigned) err);
}

static void initializeSurfaceRegistry(void)
{
    gMachPortRegistry = [[NSMutableDictionary alloc] init];
    gMachPortRegistryLock = [[NSRecursiveLock alloc] init];
}
static void ensureMachPortRegistry(void) { pthread_once(&registryOnce, initializeSurfaceRegistry); }
void _IOSurfaceRegistryLock(void) { ensureMachPortRegistry(); [gMachPortRegistryLock lock]; }
void _IOSurfaceRegistryUnlock(void) { [gMachPortRegistryLock unlock]; }
void _IOSurfaceRegistryForget(IOSurfaceRef buffer)
{
    typedef void (*ForgetFn)(IOSurfaceRef);
    ForgetFn forget = (ForgetFn)dlsym(RTLD_DEFAULT, "CGLForgetIOSurface");
    if (forget) forget(buffer);
    NSNumber *key = [NSNumber numberWithUnsignedInt: IOSurfaceGetID(buffer)];
    NSValue *value = [gMachPortRegistry objectForKey:key];
    if ([value pointerValue] == buffer) [gMachPortRegistry removeObjectForKey:key];
}
IOSurfaceRef _IOSurfaceLookupByID(IOSurfaceID sid)
{
    _IOSurfaceRegistryLock();
    NSValue *value = [gMachPortRegistry objectForKey:[NSNumber numberWithUnsignedInt:sid]];
    IOSurface *surface = (IOSurface*)[value pointerValue];
    [surface retain];
    _IOSurfaceRegistryUnlock();
    return (IOSurfaceRef)surface;
}

mach_port_t IOSurfaceCreateMachPort(IOSurfaceRef buffer)
{
	if (buffer == NULL)
		return MACH_PORT_NULL;

	/* darling-lol M58c: Chromium may have rendered this surface through a
	 * GL texture (CGLTexImageIOSurface2D's one-shot upload). Materialize
	 * the rendered texture into the IOSurface backing before the surface
	 * is handed to another process. No-op when this process never GL-bound
	 * the surface. */
	_DarlingWriteBackGLTexture(buffer);

	/* darling-lol M58b/M58cz: hand out a REAL mach send right. With a shared
	 * backing this is a fileport over the backing fd; with no shared backing
	 * _IOSurfaceObjCShmFileportForSurface() now also returns a real right
	 * (over /dev/null), so this never returns a fake token again. */
	mach_port_t port = _IOSurfaceObjCShmFileportForSurface(buffer);
	if (port == MACH_PORT_NULL)
		return MACH_PORT_NULL;

    /* ID lookup is distinct from Mach names. Final release is serialized
     * with ID lookup, and deallocation removes this non-owning entry. */
	ensureMachPortRegistry();

	IOSurfaceID sid = (IOSurfaceID) [(IOSurface*) buffer hash];
	if (sid == 0)
		sid = 1;

	[gMachPortRegistryLock lock];
	[gMachPortRegistry setObject: [NSValue valueWithPointer: buffer]
			      forKey: [NSNumber numberWithUnsignedInt: sid]];
	[gMachPortRegistryLock unlock];

	return port;
}

IOSurfaceID IOSurfaceGetID(IOSurfaceRef buffer)
{
	if (buffer == NULL)
		return 0;
	return (IOSurfaceID) [(IOSurface*) buffer hash];
}

CFTypeID IOSurfaceGetTypeID(void)
{
	return (CFTypeID) [IOSurface self];
}

IOSurfaceRef _Nullable IOSurfaceCreate(CFDictionaryRef properties)
{
	return (IOSurfaceRef) [[IOSurface alloc] initWithProperties: (NSDictionary*) properties];
}

IOSurfaceRef _Nullable IOSurfaceLookupFromMachPort(mach_port_t port)
{
	if (port == MACH_PORT_NULL)
		return NULL;

    /* Mach names are reusable and must never index a weak object cache.
     * Reconstruct from the send right's shared backing, including in-process. */
	/* darling-lol M58b: the port is a fileport holding the surface's
	 * shared backing; fileport_makefd() gives this process its own dup of
	 * that fd, which the helper takes ownership of (mmap + object
	 * construction from the wire header). */
	int fd = fileport_makefd(port);
	if (fd >= 0)
	{
		return _IOSurfaceInitFromSharedMemfd(fd);
	}

	return NULL;
}

xpc_object_t IOSurfaceCreateXPCObject(IOSurfaceRef surface)
{
	return 0;
}

IOSurfaceRef IOSurfaceLookupFromXPCObject(xpc_object_t obj)
{
#if NOTYET
	if (xpc_get_type(obj) == _xpc_type_mach_send)
	{
		mach_port_t port = xpc_mach_send_get_right(obj);
		return IOSurfaceLookupFromMachPort(port);
	}
#endif
	return NULL;
}

kern_return_t IOSurfaceLock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t * _Nullable seed)
{
	return [(IOSurface*)buffer lockWithOptions: options seed: seed];
}

static void _DarlingPublishSoftwarePixels(IOSurfaceRef surface) {
    typedef void (*PublishFn)(IOSurfaceRef);
    static PublishFn publish;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    if (!publish) {
        /* Avoid introducing a framework dependency cycle or loading CA into
         * processes that do not use it. Retry if it was not yet loaded. */
        publish = (PublishFn)dlsym(RTLD_DEFAULT, "DarlingCAPublishIOSurfacePixels");
    }
    PublishFn callback = publish;
    pthread_mutex_unlock(&lock);
    if (callback) callback(surface);
}

/* GPU readback completes a lock without claiming software compositor ownership. */
kern_return_t _IOSurfaceUnlockGPUReadback(IOSurfaceRef buffer)
{
    return [(IOSurface*)buffer unlockWithOptions:0 seed:NULL];
}

kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t * _Nullable seed)
{
    kern_return_t result = [(IOSurface*)buffer unlockWithOptions: options seed: seed];
    /* A software compositor reuses its IOSurface without a CALayer setter.
     * Publish completed writes, excluding the read-only snapshot locks. */
    if (result == KERN_SUCCESS && !(options & kIOSurfaceLockReadOnly))
        _DarlingPublishSoftwarePixels(buffer);
    return result;
}

size_t IOSurfaceGetWidth(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer width];
}

size_t IOSurfaceGetHeight(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer height];
}

void *IOSurfaceGetBaseAddress(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer baseAddress];
}

OSType IOSurfaceGetPixelFormat(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer pixelFormat];
}

void IOSurfaceSetValue(IOSurfaceRef buffer, CFStringRef key, CFTypeRef value)
{
	return [(IOSurface*)buffer setAttachment: (id) value forKey: (NSString*) key];
}


CFTypeRef _Nullable IOSurfaceCopyValue(IOSurfaceRef buffer, CFStringRef key)
{
	return (CFTypeRef) [[(IOSurface*) buffer attachmentForKey: (NSString*) key] retain];
}


void IOSurfaceRemoveValue(IOSurfaceRef buffer, CFStringRef key)
{
	[(IOSurface*)buffer removeAttachmentForKey: (NSString*) key];
}


void IOSurfaceSetValues(IOSurfaceRef buffer, CFDictionaryRef keysAndValues)
{
	[(IOSurface*)buffer setAllAttachments: (NSDictionary*)keysAndValues];
}


CFDictionaryRef _Nullable IOSurfaceCopyAllValues(IOSurfaceRef buffer)
{
	return (CFDictionaryRef) [[(IOSurface*)buffer allAttachments] retain];
}


void IOSurfaceRemoveAllValues(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer removeAllAttachments];
}

size_t IOSurfaceGetBytesPerRow(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer bytesPerRow];
}

void IOSurfaceIncrementUseCount(IOSurfaceRef buffer)
{
	[(IOSurface*)buffer incrementUseCount];
}


void IOSurfaceDecrementUseCount(IOSurfaceRef buffer)
{
	[(IOSurface*)buffer decrementUseCount];
}


int32_t IOSurfaceGetUseCount(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer localUseCount];
}

size_t IOSurfaceGetPlaneCount(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer planeCount];
}

uint32_t IOSurfaceGetSeed(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer seed];
}

size_t IOSurfaceGetWidthOfPlane(IOSurfaceRef buffer, size_t planeIndex)
{
	return [(IOSurface*)buffer widthOfPlaneAtIndex: planeIndex];
}


size_t IOSurfaceGetHeightOfPlane(IOSurfaceRef buffer, size_t planeIndex)
{
	return [(IOSurface*)buffer heightOfPlaneAtIndex: planeIndex];
}


size_t IOSurfaceGetBytesPerElementOfPlane(IOSurfaceRef buffer, size_t planeIndex)
{
	return [(IOSurface*)buffer bytesPerElementOfPlaneAtIndex: planeIndex];
}


size_t IOSurfaceGetBytesPerRowOfPlane(IOSurfaceRef buffer, size_t planeIndex)
{
	return [(IOSurface*)buffer bytesPerRowOfPlaneAtIndex: planeIndex];
}


void *IOSurfaceGetBaseAddressOfPlane(IOSurfaceRef buffer, size_t planeIndex)
{
	return [(IOSurface*)buffer baseAddressOfPlaneAtIndex: planeIndex];
}


size_t IOSurfaceGetElementWidthOfPlane(IOSurfaceRef buffer, size_t planeIndex)
{
	return [(IOSurface*)buffer elementWidthOfPlaneAtIndex: planeIndex];
}


size_t IOSurfaceGetElementHeightOfPlane(IOSurfaceRef buffer, size_t planeIndex)
{
	return [(IOSurface*)buffer elementHeightOfPlaneAtIndex: planeIndex];
}

size_t IOSurfaceGetBytesPerElement(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer bytesPerElementOfPlaneAtIndex: 0];
}


size_t IOSurfaceGetElementWidth(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer widthOfPlaneAtIndex: 0];
}


size_t IOSurfaceGetElementHeight(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer heightOfPlaneAtIndex: 0];
}

Boolean IOSurfaceIsInUse(IOSurfaceRef buffer)
{
	return [(IOSurface*)buffer isInUse];
}

kern_return_t IOSurfaceSetPurgeable(IOSurfaceRef buffer, uint32_t newState, uint32_t * _Nullable oldState)
{
	return [(IOSurface*)buffer setPurgeable:newState oldState:oldState];
}
