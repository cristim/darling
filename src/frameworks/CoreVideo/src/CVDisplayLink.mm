#include <CoreVideo/CVDisplayLink.h>
#include <stdint.h>
#include <string.h>
#include <memory>
#include <map>
#include <mutex>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSDictionary.h>
#import <dispatch/dispatch.h>
#include <CoreGraphics/CGWindow.h>
#include <CoreGraphics/CGDirectDisplay.h>

/*
 * M58b FrameSink bridge.
 *
 * Chromium 108's viz source does keep receiving the display ticks, but its
 * CompositorFrameSinkSupport stops forwarding them after the first no-damage
 * response.  Under Darling the support object also crosses a guest-memory
 * boundary before the timing-details map is serialized.  When we deliberately
 * keep the source alive, that stale map can otherwise reach Mojo and crash the
 * GPU process.  Keep this compatibility bridge here, beside the display pump,
 * so it is installed in every Electron process that uses this shim.
 *
 * These are guarded offsets for Electron 22.3.27 / Chromium 108.  Every patch
 * checks the original bytes and fails closed when a different framework is
 * loaded.  The bridge is intentionally limited to the known framework image.
 */
extern "C" {
int mprotect(void *, unsigned long, int);
unsigned _dyld_image_count(void);
const char *_dyld_get_image_name(unsigned);
const char *_dyld_get_image_header(unsigned);
}

static const unsigned long kCFSSShouldSendVA = 0x64fb760UL;
static const unsigned long kDirectClientOnBeginVA = 0x141bdc0UL;
static const unsigned long kBundleClientOnBeginVA = 0x64fdfd0UL;
static const unsigned long kRendererBindToClientVA = 0x5e21c10UL;
static const unsigned long kRendererOnBeginVA = 0x5e23140UL;
static const unsigned long kNullDetailsThunkVA = 0x64cde60UL;
static const unsigned long kTimingCopyCallVA = 0x64cdd96UL;
static const unsigned long kTimingDefaultCtorVA = 0x0eeb080UL;
static const unsigned long kContextCopyCallVA = 0x64cdd76UL;
static const unsigned long kContextDefaultCtorVA = 0x0ef1d20UL;
static const unsigned long kInlineCopyCallVA = 0x64cdd86UL;
static void frameSinkTrace(const char *tag, unsigned long value);

static void (*gNullDetailsThunkOriginal)(void *, void *, void *) = nullptr;

static void zeroInlineDetails(void *destination, const void *source) {
	unsigned char zeros[0xa0] = {};
	int fd = open("/Volumes/SystemRoot/proc/self/mem", O_WRONLY, 0);
	if (fd >= 0) {
		pwrite(fd, zeros, sizeof(zeros), (off_t)(unsigned long)destination);
		close(fd);
	}
}

static bool mappedRange(const void *pointer, size_t size) {
	if (pointer == nullptr || size == 0)
		return false;
	unsigned long start = (unsigned long)pointer & ~0xfffUL;
	unsigned long end = ((unsigned long)pointer + size + 0xfffUL) & ~0xfffUL;
	for (unsigned long page = start; page < end; page += 0x1000) {
		char resident = 0;
		if (mincore((void *)page, 0x1000, &resident) != 0)
			return false;
	}
	return true;
}

static void nullDetailsThunkGuard(void *block, void *arg, void *details) {
	/* This thunk serializes compositor timing metadata. Under Darling its
	 * nested vectors refer to the producer's guest-memory view. Preserve the
	 * completion callback but substitute a coherent empty details payload. */
	if (details == nullptr)
		return;
	gNullDetailsThunkOriginal(block, arg, details);
}

static bool installNullDetailsThunkGuard(unsigned char *base) {
	unsigned char *target = base + kNullDetailsThunkVA;
	static const unsigned char expected[15] = {
		0x55, 0x48, 0x89, 0xe5, 0x48, 0x89, 0xd0, 0x48,
		0x8b, 0x52, 0x28, 0x48, 0x8b, 0x48, 0x30
	};
	if (memcmp(target, expected, sizeof(expected)) != 0)
		return false;
	unsigned char *copyCall = base + kTimingCopyCallVA;
	static const unsigned char expectedCopyCall[5] = {
		0xe8, 0x95, 0xd6, 0xa1, 0xfa
	};
	unsigned char *contextCall = base + kContextCopyCallVA;
	unsigned char *inlineCall = base + kInlineCopyCallVA;
	static const unsigned char expectedContextCall[5] = {
		0xe8, 0x05, 0x40, 0xa2, 0xfa
	};
	static const unsigned char expectedInlineCall[5] = {
		0xe8, 0x55, 0x9c, 0xa1, 0xfa
	};
	if (memcmp(copyCall, expectedCopyCall, sizeof(expectedCopyCall)) != 0)
		return false;
	if (memcmp(contextCall, expectedContextCall,
		sizeof(expectedContextCall)) != 0)
		return false;
	if (memcmp(inlineCall, expectedInlineCall, sizeof(expectedInlineCall)) != 0)
		return false;

	unsigned char *trampoline = (unsigned char *)mmap(nullptr, 4096,
		PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
	if (trampoline == MAP_FAILED)
		return false;
	memcpy(trampoline, expected, sizeof(expected));
	unsigned char *jump = trampoline + sizeof(expected);
	jump[0] = 0x48;
	jump[1] = 0xb8;
	unsigned long resume = (unsigned long)(target + sizeof(expected));
	memcpy(jump + 2, &resume, sizeof(resume));
	jump[10] = 0xff;
	jump[11] = 0xe0;
	gNullDetailsThunkOriginal =
		(void (*)(void *, void *, void *))trampoline;

	unsigned long page = (unsigned long)target & ~0xfffUL;
	if (mprotect((void *)page, 0x1000, PROT_READ | PROT_WRITE | PROT_EXEC) != 0)
		return false;
	int32_t relativeCtor = (int32_t)(kTimingDefaultCtorVA -
		(kTimingCopyCallVA + sizeof(expectedCopyCall)));
	copyCall[0] = 0xe8;
	memcpy(copyCall + 1, &relativeCtor, sizeof(relativeCtor));
	int32_t relativeContextCtor = (int32_t)(kContextDefaultCtorVA -
		(kContextCopyCallVA + sizeof(expectedContextCall)));
	contextCall[0] = 0xe8;
	memcpy(contextCall + 1, &relativeContextCtor,
		sizeof(relativeContextCtor));
	int64_t inlineDistance = (unsigned long)&zeroInlineDetails -
		(unsigned long)(inlineCall + sizeof(expectedInlineCall));
	if (inlineDistance < INT32_MIN || inlineDistance > INT32_MAX)
		return false;
	int32_t relativeInlineHelper = (int32_t)inlineDistance;
	inlineCall[0] = 0xe8;
	memcpy(inlineCall + 1, &relativeInlineHelper,
		sizeof(relativeInlineHelper));
	unsigned char detour[12] = { 0x48, 0xb8 };
	unsigned long guard = (unsigned long)&nullDetailsThunkGuard;
	memcpy(detour + 2, &guard, sizeof(guard));
	detour[10] = 0xff;
	detour[11] = 0xe0;
	memcpy(target, detour, sizeof(detour));
	memset(target + sizeof(detour), 0x90,
		sizeof(expected) - sizeof(detour));
	return true;
}

struct FrameSinkHook {
	unsigned char *target;
	unsigned char saved[12];
	unsigned long replacement;
	volatile int lock;
	bool installed;
};

struct FrameSinkSavedState {
	uint32_t magic;
	unsigned char direct[12];
	unsigned char bundle[12];
};

struct RendererHookSavedState {
	uint32_t magic;
	unsigned char saved[12];
};

struct RendererBeginState {
	uint32_t magic;
	uint32_t running;
	unsigned long sink;
	uint64_t sequence;
};

static const uint32_t kFrameSinkSavedMagic = 0x4d353846u;

static FrameSinkHook gDirectClientHook = {};
static FrameSinkHook gBundleClientHook = {};
static FrameSinkHook gRendererNeedsHook = {};
static unsigned char gEmptyFrameTimingDetails[24] = {};

static const uint32_t kRendererHookMagic = 0x4d353853u;
static const uint32_t kRendererBeginMagic = 0x4d353842u;

static bool frameSinkPrologueIsUsable(const unsigned char *prologue);

static void frameSinkTrace(const char *tag, unsigned long value) {
	char line[96];
	int len = snprintf(line, sizeof(line), "FS pid=%d %s %lx\n", (int)getpid(),
		tag, value);
	int fd = open("/Volumes/SystemRoot/tmp/opencode/framesink-bridge.log",
		O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd >= 0) {
		write(fd, line, (size_t)len);
		close(fd);
	}
}

static const char *rendererHookStatePath(void) {
	static char path[128];
	static bool initialized = false;
	if (!initialized) {
		snprintf(path, sizeof(path), "/dev/shm/darling-renderer-hook-%d.state",
			(int)getpid());
		initialized = true;
	}
	return path;
}

static const char *rendererBeginStatePath(void) {
	static char path[128];
	static bool initialized = false;
	if (!initialized) {
		snprintf(path, sizeof(path), "/dev/shm/darling-renderer-begin-%d.state",
			(int)getpid());
		initialized = true;
	}
	return path;
}

static bool rendererHookStateIsUsable(void) {
	RendererHookSavedState state = {};
	int fd = open(rendererHookStatePath(), O_RDONLY, 0);
	if (fd < 0)
		return false;
	ssize_t got = read(fd, &state, sizeof(state));
	close(fd);
	return got == (ssize_t)sizeof(state) &&
		state.magic == kRendererHookMagic &&
		frameSinkPrologueIsUsable(state.saved);
}

static void rendererWriteState(void *sink, bool running) {
	RendererBeginState state = {};
	int fd = open(rendererBeginStatePath(), O_RDWR | O_CREAT, 0644);
	if (fd < 0)
		return;
	if (flock(fd, LOCK_EX) == 0) {
		lseek(fd, 0, SEEK_SET);
		if (read(fd, &state, sizeof(state)) != (ssize_t)sizeof(state) ||
			state.magic != kRendererBeginMagic)
			memset(&state, 0, sizeof(state));
		state.magic = kRendererBeginMagic;
		state.sink = (unsigned long)sink;
		state.running = running ? 1 : 0;
		lseek(fd, 0, SEEK_SET);
		ftruncate(fd, 0);
		write(fd, &state, sizeof(state));
		flock(fd, LOCK_UN);
	}
	close(fd);
}

static bool rendererReadState(RendererBeginState *state) {
	int fd = open(rendererBeginStatePath(), O_RDONLY, 0);
	if (fd < 0)
		return false;
	ssize_t got = read(fd, state, sizeof(*state));
	close(fd);
	return got == (ssize_t)sizeof(*state) &&
		state->magic == kRendererBeginMagic && state->running != 0 &&
		state->sink != 0;
}

static unsigned char *frameSinkFindFramework(void) {
	for (unsigned i = 0; i < _dyld_image_count(); ++i) {
		const char *name = _dyld_get_image_name(i);
		if (name && strstr(name, "Versions/A/Electron Framework"))
			return (unsigned char *) _dyld_get_image_header(i);
	}
	return nullptr;
}

static const char *frameSinkStatePath(void) {
	static char path[128];
	static bool initialized = false;
	if (!initialized) {
		snprintf(path, sizeof(path), "/dev/shm/darling-framesink-%d.state",
			(int) getpid());
		initialized = true;
	}
	return path;
}

static bool frameSinkReadSaved(FrameSinkSavedState *state) {
	int fd = open(frameSinkStatePath(), 0, 0);
	if (fd < 0)
		return false;
	ssize_t got = read(fd, state, sizeof(*state));
	close(fd);
	return got == (ssize_t) sizeof(*state) &&
		state->magic == kFrameSinkSavedMagic;
}

static bool frameSinkStateIsUsable(void) {
	FrameSinkSavedState state = {};
	if (!frameSinkReadSaved(&state))
		return false;
	/* A record containing only the direct prologue is an old/partial record.
	 * PID reuse makes that case common: the first CoreVideo image wrote its
	 * direct hook, then another image observed the file and skipped the bundle
	 * hook.  Never let a zero bundle prologue be used to restore executable
	 * code. */
	for (unsigned i = 0; i < sizeof(state.direct); ++i)
		if (state.direct[i] == 0)
			return false;
	for (unsigned i = 0; i < sizeof(state.bundle); ++i)
		if (state.bundle[i] == 0)
			return false;
	return true;
}

static bool frameSinkPrologueIsUsable(const unsigned char *prologue) {
	/* Both Chromium methods begin with a frame-pointer prologue; the remaining
	 * bytes are version-specific but must not be all zero. */
	if (prologue[0] != 0x55 || prologue[1] != 0x48 ||
		prologue[2] != 0x89 || prologue[3] != 0xe5)
		return false;
	for (unsigned i = 4; i < 12; ++i)
		if (prologue[i] != 0)
			return true;
	return false;
}

static void frameSinkWriteJump(unsigned char *target, unsigned long replacement) {
	unsigned char jump[12];
	jump[0] = 0x48;
	jump[1] = 0xb8;
	for (unsigned i = 0; i < 8; ++i)
		jump[i + 2] = (replacement >> (i * 8)) & 0xff;
	jump[10] = 0xff;
	jump[11] = 0xe0;
	for (unsigned i = 0; i < sizeof(jump); ++i)
		target[i] = jump[i];
}

static bool frameSinkPatchBytes(unsigned char *at, const unsigned char *want,
	unsigned count, const unsigned char *replacement) {
	for (unsigned i = 0; i < count; ++i)
		if (at[i] != want[i])
			return false;
	unsigned long page = (unsigned long) at & ~0xfffUL;
	if (mprotect((void *) page, 0x1000, 7) != 0)
		return false;
	for (unsigned i = 0; i < count; ++i)
		at[i] = replacement[i];
	return true;
}

static void frameSinkHookPatch(FrameSinkHook *hook, bool enabled) {
	unsigned char jump[12];
	unsigned long page = (unsigned long) hook->target & ~0xfffUL;
	mprotect((void *) page, 0x1000, 7);
	if (!enabled) {
		for (unsigned i = 0; i < sizeof(hook->saved); ++i)
			hook->target[i] = hook->saved[i];
		return;
	}
	jump[0] = 0x48;
	jump[1] = 0xb8;
	for (unsigned i = 0; i < 8; ++i)
		jump[i + 2] = (hook->replacement >> (i * 8)) & 0xff;
	jump[10] = 0xff;
	jump[11] = 0xe0;
	for (unsigned i = 0; i < sizeof(jump); ++i)
		hook->target[i] = jump[i];
}

static bool frameSinkInstallHook(FrameSinkHook *hook, unsigned char *target,
	void *replacement) {
	/* Do not overwrite an already-installed copy of this bridge. */
	if (target[0] == 0x48 && target[1] == 0xb8)
		return false;
	/* All three Chromium functions have the normal x86_64 frame prologue. */
	if (target[0] != 0x55 || target[1] != 0x48 || target[2] != 0x89 ||
		target[3] != 0xe5)
		return false;
	hook->target = target;
	hook->replacement = (unsigned long) replacement;
	for (unsigned i = 0; i < sizeof(hook->saved); ++i)
		hook->saved[i] = target[i];
	frameSinkHookPatch(hook, true);
	hook->installed = true;
	return true;
}

static void frameSinkCallOriginal(unsigned long offset, unsigned long replacement,
	bool bundle, void *self, void *args, void *details) {
	/* Do not dereference FrameSinkHook or any other shim global here.  This
	 * function is entered from Chromium's callback thread, whose guest view is
	 * not the constructor's view under Darling. */
	unsigned char *base = frameSinkFindFramework();
	FrameSinkSavedState saved = {};
	int fd = open(frameSinkStatePath(), O_RDWR, 0);
	if (fd < 0 || !base)
		return;
	if (flock(fd, LOCK_EX) != 0) {
		close(fd);
		return;
	}
	lseek(fd, 0, 0);
	if (read(fd, &saved, sizeof(saved)) != (ssize_t) sizeof(saved) ||
		saved.magic != kFrameSinkSavedMagic ||
		!frameSinkPrologueIsUsable(bundle ? saved.bundle : saved.direct)) {
		frameSinkTrace(bundle ? "bad-bundle-state" : "bad-direct-state",
			(unsigned long)details);
		flock(fd, LOCK_UN);
		close(fd);
		return;
	}
	unsigned char *target = base + offset;
	const unsigned char *prologue = bundle ? saved.bundle : saved.direct;
	unsigned long page = (unsigned long) target & ~0xfffUL;
	if (mprotect((void *) page, 0x1000, 7) != 0) {
		flock(fd, LOCK_UN);
		close(fd);
		return;
	}
	for (unsigned i = 0; i < 12; ++i)
		target[i] = prologue[i];
	((void (*)(void *, void *, void *)) target)(self, args, details);
	frameSinkWriteJump(target, replacement);
	flock(fd, LOCK_UN);
	close(fd);
}

static void frameSinkDirectOnBegin(void *self, void *args, void *details) {
	frameSinkCallOriginal(kDirectClientOnBeginVA,
		(unsigned long) frameSinkDirectOnBegin, false, self, args, details);
}

static void frameSinkBundleOnBegin(void *self, void *args, void *details) {
	frameSinkCallOriginal(kBundleClientOnBeginVA,
		(unsigned long) frameSinkBundleOnBegin, true, self, args, details);
}

static bool frameSinkRendererBindToClient(void *self, void *client) {
	/* BindToClient runs in every renderer even when OnNeedsBeginFrames never
	 * does under Darling.  Capturing here breaks that circular dependency. */
	frameSinkTrace("renderer-bind-entry", (unsigned long)self);
	rendererWriteState(self, true);
	frameSinkTrace("renderer-bind-saved", (unsigned long)client);
	unsigned char *base = frameSinkFindFramework();
	RendererHookSavedState saved = {};
	int fd = open(rendererHookStatePath(), O_RDWR, 0);
	if (fd < 0 || !base)
		return false;
	if (flock(fd, LOCK_EX) != 0) {
		close(fd);
		return false;
	}
	lseek(fd, 0, SEEK_SET);
	if (read(fd, &saved, sizeof(saved)) != (ssize_t)sizeof(saved) ||
		saved.magic != kRendererHookMagic ||
		!frameSinkPrologueIsUsable(saved.saved)) {
		flock(fd, LOCK_UN);
		close(fd);
		return false;
	}
	unsigned char *target = base + kRendererBindToClientVA;
	unsigned long page = (unsigned long)target & ~0xfffUL;
	bool result = false;
	if (mprotect((void *)page, 0x1000, 7) == 0) {
		for (unsigned i = 0; i < sizeof(saved.saved); ++i)
			target[i] = saved.saved[i];
		frameSinkTrace("renderer-bind-call", (unsigned long)target);
		result = ((bool (*)(void *, void *))target)(self, client);
		frameSinkWriteJump(target,
			(unsigned long)frameSinkRendererBindToClient);
	}
	flock(fd, LOCK_UN);
	close(fd);
	frameSinkTrace("renderer-bind", (unsigned long)self);
	return result;
}

static void rendererBeginTimerF(CFRunLoopTimerRef timer, void *info) {
	(void)timer;
	(void)info;
	RendererBeginState state = {};
	if (!rendererReadState(&state))
		return;
	unsigned char *base = frameSinkFindFramework();
	if (!base)
		return;

	struct mach_timebase_info timebase = {};
	mach_timebase_info(&timebase);
	uint64_t denominator = timebase.denom ? timebase.denom : 1;
	uint64_t nowUs = mach_absolute_time() * (uint64_t)timebase.numer /
		denominator / 1000ULL;
	uint64_t sequence = ++state.sequence;

	/* Chromium 108 release BeginFrameArgs: frame/deadline/interval,
	 * BeginFrameId, trace id, type and critical-path flag. */
	unsigned char args[128] = {};
	*(uint64_t *)(args + 0) = nowUs;
	*(uint64_t *)(args + 8) = nowUs + 16666ULL;
	*(uint64_t *)(args + 16) = 16666ULL;
	*(uint64_t *)(args + 24) = 0xffffffffULL;
	*(uint64_t *)(args + 32) = sequence;
	*(int64_t *)(args + 40) = -1;
	*(uint32_t *)(args + 48) = 1;
	args[52] = 1;
	unsigned char details[24] = {};

	/* Save the sequence before entering Chromium; OnBeginFrame can re-enter
	 * the needs callback and rewrite this same host record. */
	int fd = open(rendererBeginStatePath(), O_WRONLY | O_TRUNC, 0644);
	if (fd >= 0) {
		write(fd, &state, sizeof(state));
		close(fd);
	}
	((void (*)(void *, void *, void *))(base + kRendererOnBeginVA))(
		(void *)state.sink, args, details);
	if (sequence <= 8)
		frameSinkTrace("renderer-pump", sequence);
}

static void startRendererBeginTimer(void) {
	CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL,
		CFAbsoluteTimeGetCurrent() + 2.0, 1.0 / 60.0, 0, 0,
		rendererBeginTimerF, NULL);
	if (timer)
		CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopDefaultMode);
}

static void installFrameSinkBridge(void) {
	/* Private Chromium callbacks cannot safely be invoked across Darling's
	 * divergent guest-memory views. Keep all experimental detours disabled. */
	return;

	for (unsigned i = 0; i < _dyld_image_count(); ++i) {
		const char *name = _dyld_get_image_name(i);
		if (!name || !strstr(name, "Versions/A/Electron Framework"))
			continue;
		unsigned char *base = (unsigned char *) _dyld_get_image_header(i);
		bool nullGuardInstalled = installNullDetailsThunkGuard(base);
		frameSinkTrace("null-guard", nullGuardInstalled ? 1UL : 0UL);
		/* All earlier FrameSink experiments remain disabled. */
		return;
		unsigned char *shouldSend = base + kCFSSShouldSendVA;
		unsigned char shouldSendWant[] = {
			0x55, 0x48, 0x89, 0xe5, 0x41, 0x57
		};
		unsigned char shouldSendReplacement[] = {
			0xb8, 0x01, 0x00, 0x00, 0x00, 0xc3
		};
		/* Returning true keeps viz from treating a no-damage reply as a reason
		 * to stop the renderer's begin-frame stream. */
		frameSinkPatchBytes(shouldSend, shouldSendWant, sizeof(shouldSendWant),
			shouldSendReplacement);
		/* Do not detour live Chromium callback entries here. A 12-byte absolute
		 * jump cannot be installed atomically and raced BrowserWindow startup.
		 * The guarded ShouldSend patch above is complete before these callbacks
		 * are active and is the only safe FrameSink compatibility change. */
		bool directInstalled = false;
		bool bundleInstalled = false;
		bool rendererNeedsInstalled = false;
		frameSinkTrace("install", (directInstalled ? 1UL : 0UL) |
			(bundleInstalled ? 2UL : 0UL) |
			(rendererNeedsInstalled ? 4UL : 0UL));
		/* A second CoreVideo image may run this constructor after the first
		 * image has already patched Chromium.  Its local hook structs are empty;
		 * preserve the first image's host-file prologue in that case. */
		if (!frameSinkStateIsUsable() && directInstalled && bundleInstalled) {
			FrameSinkSavedState saved = {};
			saved.magic = kFrameSinkSavedMagic;
			memcpy(saved.direct, gDirectClientHook.saved, sizeof(saved.direct));
			memcpy(saved.bundle, gBundleClientHook.saved, sizeof(saved.bundle));
			int fd = open(frameSinkStatePath(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
			if (fd >= 0) {
				if (flock(fd, LOCK_EX) == 0) {
					write(fd, &saved, sizeof(saved));
					flock(fd, LOCK_UN);
				}
				close(fd);
			}
		}
		if (!rendererHookStateIsUsable() && rendererNeedsInstalled) {
			RendererHookSavedState saved = {};
			saved.magic = kRendererHookMagic;
			memcpy(saved.saved, gRendererNeedsHook.saved, sizeof(saved.saved));
			int fd = open(rendererHookStatePath(),
				O_WRONLY | O_CREAT | O_TRUNC, 0644);
			if (fd >= 0) {
				write(fd, &saved, sizeof(saved));
				close(fd);
			}
		}
		if (rendererNeedsInstalled)
			startRendererBeginTimer();
		return;
	}
}

__attribute__((constructor)) static void installFrameSinkBridgeAtLoad(void) {
	installFrameSinkBridge();
}

static const NSString* kDirectDisplayArray = @"CGDirectDisplay";

/*
 * darling-lol M58b final pump design: host-file-backed display-link state.
 *
 * Diagnosis this session: under Darling, guest helper threads (dispatch
 * sources, detached pthreads, CFRunLoop timers) do not reliably observe
 * writes made elsewhere in the guest — globals, dictionary contents and
 * even objc associated-object storage diverge for the timer's thread, and
 * a detached pthread sleep loop hangs inside its FIRST sleep. The one
 * store proven to round-trip across processes AND across the shim's two
 * loaded instances is the HOST filesystem (/dev/shm via shm_open, used by
 * the M58b IOSurface work, and fileports via the M58 kobject machinery).
 *
 * So the shim keeps NO guest-side state. The display link's state lives in
 * a per-pid host file; Create/Start/SetOutputCallback/Stop are trivial side
 * effects on that file; the runloop timer fires every 1/60 s and reads the
 * file fresh each tick, invoking Chromium's callback with a plausible
 * CVTimeStamp. The timer itself fires (verified: continuous ~60 Hz records).
 */

#include <CoreVideo/CVDisplayLink.h>
#include <memory>
#include <map>
#include <mutex>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <time.h>
#include <stdio.h>
#include <string.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSDictionary.h>
#include <CoreGraphics/CGWindow.h>
#include <CoreGraphics/CGDirectDisplay.h>


/* sturdy host-shared record, written fresh on every mutation. */
struct CVLinkStateRec {
	uint32_t magic;      /* 0xC81DFA10 */
	uint32_t version;
	void* callback;
	void* userInfo;
	uint32_t running;
	uint32_t alive;
	uint32_t ticks;
	uint32_t nullTicks;
	/* darling-lol M58e: number of CVDisplayLinkRef objects alive in this
	 * process. The pump must keep ticking while >= 1 link exists, and MUST
	 * stop invoking the callback after the last link is released — the
	 * callback targets Chromium's DisplayLinkMac, which unregisters its
	 * callback by releasing the link (calling it afterwards would be
	 * use-after-free every tick). */
	uint32_t refs;
	uint64_t reserved;
    CVDisplayLinkRef link;
};
static const uint32_t kStateMagic = 0xC81DFA10u;
static const uint32_t kStateVersion = 1;

static void traceLog(const char* fmt, uint64_t a, uint64_t b) {
    if (!getenv("RCLOL_CV_TRACE")) return;
	char msg[192];
	struct timespec ts;
#ifdef CLOCK_MONOTONIC
	clock_gettime(CLOCK_MONOTONIC, &ts);
#else
	ts.tv_sec = (time_t) mach_absolute_time() / 1000000000ull;
	ts.tv_nsec = 0;
#endif
	snprintf(msg, sizeof(msg), "%lld.%03ld %d %s",
	    (long long) ts.tv_sec, ts.tv_nsec / 1000000,
	    (int) getpid(), /* msg below */ "");
	snprintf(msg + strlen(msg), sizeof(msg) - strlen(msg), fmt, a, b);
	int fd = open("/Volumes/SystemRoot/tmp/opencode/cvpump.log",
	    1 | 0x200 | 8, 0644);
	if (fd >= 0) { write(fd, msg, strlen(msg)); close(fd); }
}

static const char* statePathFor(void) {
	static char path[128];
	static bool init = false;
	if (!init) {
		snprintf(path, sizeof(path), "/dev/shm/darling-cvlink-%d.state",
		    (int) getpid());
		init = true;
	}
	return path;
}

/* These private records live in the host /dev/shm. Bypass recursive guest
 * path expansion on Chromium's small callback stacks, and avoid frame-time RPC. */
extern "C" long __lolsys_syscall(long,long,long,long,long,long,int);
static int clockOpen(void) { return (int)__lolsys_syscall((long)statePathFor(),66,0600,0,0,0,2); }
static void clockClose(int fd) { __lolsys_syscall(fd,0,0,0,0,0,3); }
static long clockRead(int fd,void *p,size_t n,off_t offset) { return __lolsys_syscall(fd,(long)p,n,offset,0,0,17); }
static long clockWrite(int fd,const void *p,size_t n,off_t offset) { return __lolsys_syscall(fd,(long)p,n,offset,0,0,18); }
static int clockFlock(int fd,int op) { return (int)__lolsys_syscall(fd,op,0,0,0,0,73); }
static bool readState(CVLinkStateRec *out) {
    int fd=clockOpen();if(fd<0)return false;
    long got=clockRead(fd,out,sizeof(*out),0);clockClose(fd);
    return got==sizeof(*out) && out->magic==kStateMagic && out->version>=1 && out->alive;
}
static bool writeState(CVLinkStateRec *rec) {
    int fd=clockOpen();if(fd<0)return false;
    long put=clockWrite(fd,rec,sizeof(*rec),0);clockClose(fd);return put==sizeof(*rec);
}
struct CVStateGuard {
    int fd; bool locked;
    CVStateGuard() : fd(clockOpen()), locked(false) {
        if(fd<0)return;
        uint64_t owner=0;clockRead(fd,&owner,sizeof(owner),offsetof(CVLinkStateRec,reserved));
        uint64_t thread=(uintptr_t)pthread_self();
        if(!owner || owner!=thread)locked=clockFlock(fd,LOCK_EX)==0;
    }
    ~CVStateGuard(){if(fd>=0){if(locked)clockFlock(fd,LOCK_UN);clockClose(fd);}}
};
__attribute__((constructor)) static void initializeDisplayClockRecord(void) {
    CVLinkStateRec rec={};rec.magic=kStateMagic;rec.version=kStateVersion;rec.alive=1;writeState(&rec);
}
static void registerDisplayLink(CVDisplayLinkRef link) {
    CVStateGuard guard;CVLinkStateRec rec={};
    if(readState(&rec)){++rec.refs;if(!rec.callback)rec.link=link;writeState(&rec);}
}

static const char* displayLinkTick =
    "displayLinkTick"; /* marker so grep can find the tick body */

static void displayLinkTickFromRec(CVLinkStateRec* rec) {
	CVDisplayLinkOutputCallback callback = (CVDisplayLinkOutputCallback) rec->callback;
	if (traceLog != NULL) {
		/* darling-lol M58d: full continuity logging while the begin-frame
		 * stall is under diagnosis (previously capped at 32 records). */
		traceLog("PUMP cb=%p ticks=%llu\n", (uint64_t) callback, rec->ticks);
	}
	if (callback != NULL && rec->running && rec->refs) {
		rec->ticks++;
		struct mach_timebase_info timebase;
		mach_timebase_info(&timebase);
		uint64_t periodNs = 1000000000ull / 60ull;
		uint64_t periodMach = periodNs * timebase.denom / timebase.numer;

		uint64_t hostTime = mach_absolute_time();
		CVTimeStamp now = {};
		now.version = 0;
		now.hostTime = hostTime;
		now.videoTime = hostTime / periodMach;
		now.videoTimeScale = 60;
		now.videoRefreshPeriod = 1;
		now.flags = kCVTimeStampHostTimeValid | kCVTimeStampVideoTimeValid |
		    kCVTimeStampVideoRefreshPeriodValid;
		CVTimeStamp outputTime = now;
		outputTime.hostTime = hostTime + periodMach;
        outputTime.videoTime = now.videoTime + 1;
		CVOptionFlags flagsOut = 0;
		callback(rec->link, &now, &outputTime, 0, &flagsOut, rec->userInfo);
	} else {
		rec->nullTicks++;
	}
}

/* The runloop timer's handler: re-read the state file fresh each tick. */
static void DisplayLinkMainTimerF(CFRunLoopTimerRef timer, void* info) {
	CVLinkStateRec rec;
	if (!readState(&rec))
		return;
	displayLinkTickFromRec(&rec);
	writeState(&rec);
}

/* darling-lol M58d: dispatch-source pump.
 *
 * Diagnosis this session: the runloop-timer pump only ever fires in the
 * browser process (12/s measured) — the GPU process has NO CFRunLoop default
 * mode traffic: PopupMenu/ChatWindow wait, Chromium's GPU-process message
 * loop does not service the Cocoa default runloop constantly, so the CFRunLoop
 * timer never fires there and viz *never sends a single begin frame* — the
 * compositor surfaces are created but never drawn (a 1-publish artwork per
 * run collapses). Per the M58b finding, dispatch sources DO fire from any
 * thread; the handler just couldn't see guest memory. This shim already keeps
 * its state in a HOST FILE (/dev/shm/darling-cvlink-<pid>.state) — the same
 * store that survived everything else — so a dispatch-source timer can safely
 * re-read it and invoke the callback.
 */
static void dispatchTimerFire(void* /*info*/) {
    CVStateGuard guard;CVLinkStateRec rec;
    if (guard.fd<0 || !readState(&rec)) return;
    uint64_t owner=(uintptr_t)pthread_self();
    clockWrite(guard.fd,&owner,sizeof(owner),offsetof(CVLinkStateRec,reserved));
    displayLinkTickFromRec(&rec);
    /* Preserve concurrent/reentrant registration changes; update only counters. */
    clockWrite(guard.fd,&rec.ticks,sizeof(rec.ticks)+sizeof(rec.nullTicks),offsetof(CVLinkStateRec,ticks));
    owner=0;clockWrite(guard.fd,&owner,sizeof(owner),offsetof(CVLinkStateRec,reserved));
}

/* Keep callbacks off Darling's dispatch trampoline: Chromium can leave its
 * emulated workqueue with less than a page of usable stack. */
static void *displayClockThread(void *) {
    struct { long sec, nsec; } deadline;
    if (__lolsys_syscall(1,(long)&deadline,0,0,0,0,228)<0) return NULL;
    static uint64_t cvIntervalNS = 0;
    if (!cvIntervalNS) {
        const char *hz = getenv("RCLOL_REFRESH_HZ");
        int rate = hz ? atoi(hz) : 0;
        cvIntervalNS = (rate > 0 && rate <= 1000) ? 1000000000ull / (uint64_t)rate : (1000000000ull / 144ull);
    }
    for (;;) {
        deadline.nsec += cvIntervalNS;
        if(deadline.nsec>=NSEC_PER_SEC){deadline.nsec-=NSEC_PER_SEC;++deadline.sec;}
        long result;
        do { result=__lolsys_syscall(1,1,(long)&deadline,0,0,0,230); } while(result==-4);
        if(result<0) return NULL;
        dispatchTimerFire(NULL);
        struct { long sec, nsec; } now;
        if(__lolsys_syscall(1,(long)&now,0,0,0,0,228)==0) {
            long long diffNS = ((long long)now.sec - (long long)deadline.sec) * 1000000000LL + (now.nsec - deadline.nsec);
            if (diffNS > (long long)cvIntervalNS) {
                deadline.sec = now.sec;
                deadline.nsec = now.nsec;
            }
        }
    }
}
static void InstallDispatchPump(void) {
    pthread_attr_t attr;pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr,1024*1024);
    pthread_t thread;
    if(pthread_create(&thread,&attr,displayClockThread,NULL)==0)pthread_detach(thread);
    pthread_attr_destroy(&attr);
}

CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef* displayLinkOut)
{
	uint32_t displayCount = 0;
	std::unique_ptr<CGDirectDisplayID[]> displays;

	/* darling-lol M57: tolerate a missing/incomplete display list instead of
	 * failing (Chromium dereferences a null link when this errors). */
	CGError err = CGGetActiveDisplayList(0, nullptr, &displayCount);
	if (err != kCGErrorSuccess)
		displayCount = 0;

	if (displayCount > 0) {
		displays.reset(new CGDirectDisplayID[displayCount]);
		err = CGGetActiveDisplayList(displayCount, displays.get(), &displayCount);
		if (err != kCGErrorSuccess)
			displayCount = 0;
	}

	NSMutableDictionary* self = [[NSMutableDictionary alloc] init];
	NSMutableArray* array = [NSMutableArray arrayWithCapacity: displayCount];

	for (uint32_t i = 0; i < displayCount; i++)
		[array addObject: [NSNumber numberWithInt: displays[i]]];

	/* darling-lol M57: ensure at least one display id so
	 * CVDisplayLinkGetCurrentCGDisplay() is non-zero (Chromium's
	 * DisplayLinkMac::GetForDisplay rejects a zero current display). */
	if ([array count] == 0)
		[array addObject: [NSNumber numberWithInt: 1]];

	[self setObject: array
			forKey: kDirectDisplayArray];

	registerDisplayLink((CVDisplayLinkRef)self);
	*displayLinkOut = (CVDisplayLinkRef) self;
	return kCVReturnSuccess;
}

CVReturn CVDisplayLinkStart(CVDisplayLinkRef displayLink)
{
	if (!displayLink)
		return kCVReturnInvalidArgument;
    CVStateGuard guard;

	/* Install in every process that loads CoreVideo.  The renderer may not
	 * create a CVDisplayLink of its own, so CVDisplayLinkStart is too late to
	 * be the only installation point. */
	installFrameSinkBridge();

	/* darling-lol M58b: mark the shared state file running; the runloop
	 * timer is installed once per process (the guard `started` uses a
	 * static flag rather than per-link state, since state lives in the
	 * file, not in guest memory). */
	static bool started = false;
	if (!started) {
        CVLinkStateRec rec;
        if(!readState(&rec)) memset(&rec,0,sizeof(rec));
		rec.magic = kStateMagic;
		rec.version = kStateVersion;
		rec.alive = 1;
		rec.running = 1;
		writeState(&rec);

		/* darling-lol M58d: dispatch-source pump, one per process.
		 * The old CFRunLoop timer only serviced the browser's main
		 * runloop (~12/s) and NEVER fired in the GPU process (no begin
		 * frames from viz), so frame production starved
		 * nondeterministically. Dispatch sources fire from any thread
		 * and this shim's state lives in a host file, which is exactly
		 * the store proven to cross the helper-thread visibility gap. */
		InstallDispatchPump();
		started = true;
	} else {
		CVLinkStateRec rec;
		if (readState(&rec)) {
			rec.running = 1;
			rec.alive = 1;
			writeState(&rec);
		}
	}
	return kCVReturnSuccess;
}

CVReturn CVDisplayLinkStop(CVDisplayLinkRef displayLink)
{
    if(!displayLink)return kCVReturnInvalidArgument;
    CVStateGuard guard;CVLinkStateRec rec;
    if(readState(&rec)) { rec.running=0;writeState(&rec); }
    return kCVReturnSuccess;
}

Boolean CVDisplayLinkIsRunning(CVDisplayLinkRef displayLink)
{
    if(!displayLink)return false;
	CVLinkStateRec rec;
	if (!readState(&rec))
		return false;
	return rec.running != 0;
}

CVDisplayLinkRef CVDisplayLinkRetain(CVDisplayLinkRef displayLink)
{
	/* darling-lol M57: Chromium's DisplayLinkMac retains/releases the link. */
	if (displayLink) {
        CVStateGuard guard;
		[(NSMutableDictionary*) displayLink retain];
		/* darling-lol M58e: bump the shared refs count so the pump keeps
		 * firing while any link exists. */
		CVLinkStateRec rec;
		if (readState(&rec)) {
			rec.refs++;
			rec.alive = 1;
			writeState(&rec);
		}
	}
	return displayLink;
}

void CVDisplayLinkRelease(CVDisplayLinkRef displayLink)
{
	if (!displayLink)
		return;
    CVStateGuard guard;
	/* darling-lol M58e: drop the shared refs count. When the last link of
	 * this process goes away, drop the callback registration so the leaked
	 * pump timer stops invoking a freed Chromium callback (use-after-free
	 * guard). */
	CVLinkStateRec rec;
	if (readState(&rec)) {
		if (rec.refs > 0)
			rec.refs--;
		if (rec.refs == 0 || (rec.link==displayLink && [(NSMutableDictionary*)displayLink retainCount]==1)) {
			rec.callback = NULL;
			rec.userInfo = NULL;
            rec.link=NULL;
		}
		writeState(&rec);
	}
    [(NSMutableDictionary*) displayLink release];
}

/* Creation, retain and release maintain the live link count. Stop cancels
 * callbacks; callback-side Stop is reentrant, while outside Stop/Release wait
 * for the active callback before clearing or destroying its registration. */

CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef displayLink, CVDisplayLinkOutputCallback callback, void *userInfo)
{
	if (!displayLink)
		return kCVReturnInvalidArgument;

    CVStateGuard guard;
	CVLinkStateRec rec;
	if (!readState(&rec)) {
		memset(&rec, 0, sizeof(rec));
		rec.magic = kStateMagic;
		rec.version = kStateVersion;
		rec.refs = 1;
		rec.alive = 1;
	}
	rec.link=displayLink;
	rec.callback = (void*) callback;
	rec.userInfo = userInfo;
	writeState(&rec);
	traceLog("SETOUT cb=%p pid_ok\n", (uint64_t) callback, 0);
	return kCVReturnSuccess;
}

CVReturn CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(CVDisplayLinkRef displayLink, CGLContextObj cglContext, CGLPixelFormatObj cglPixelFormat)
{
	if (!displayLink)
		return kCVReturnInvalidArgument;

	NSArray *windowArray = [[NSClassFromString(@"NSApplication") sharedApplication] windows];
	if (!windowArray)
		return kCVReturnError;

	for (NSWindow* window in windowArray)
	{
		CGWindow* cgw = [window platformWindow];
		CGLContextObj ctxt = [cgw cglContext];
		if (ctxt == cglContext)
		{
			CGDirectDisplayID displayID = [window.screen cgDirectDisplayID];
			NSMutableDictionary* self = (NSMutableDictionary*) displayLink;

			[self setObject: @[[NSNumber numberWithInt: (int)(displayID != 0 ? displayID : 1)]]
					forKey: kDirectDisplayArray];
			return kCVReturnSuccess;
		}
	}
	
	return kCVReturnError;
}

CGDirectDisplayID CVDisplayLinkGetCurrentCGDisplay( CVDisplayLinkRef CV_NONNULL displayLink )
{
	if (!displayLink)
		return kCVReturnInvalidArgument;

	NSMutableDictionary* self = (NSMutableDictionary*) displayLink;
	NSArray* ids = self[kDirectDisplayArray];

	if ([ids count] > 0)
		return (CGDirectDisplayID) [[ids firstObject] intValue];
	return kCGNullDirectDisplay;
}

CVReturn CVDisplayLinkCreateWithCGDisplay(
    CGDirectDisplayID displayID,
    CV_RETURNS_RETAINED_PARAMETER CVDisplayLinkRef CV_NULLABLE * CV_NONNULL displayLinkOut )
{
	/* darling-lol M57: Chromium's NativeWidgetMacNSWindowHost aborts (and then
	 * crashes on the null link) when this returns non-success; Darling's
	 * CGDirectDisplay ids are unreliable. Always hand back a valid object, and
	 * make sure the current display is non-zero (DisplayLinkMac::GetForDisplay
	 * rejects a zero current display). */
	if (displayLinkOut == nullptr)
		return kCVReturnInvalidArgument;

	NSMutableDictionary* self = [[NSMutableDictionary alloc] init];
	[self setObject: @[ [NSNumber numberWithInt: (int)(displayID != 0 ? displayID : 1) ] ]
			forKey: kDirectDisplayArray];

	/* Optional creation diagnostics. Creation leaves the link stopped. */
	if (getenv("RCLOL_CV_TRACE")) {
		int fd = open("/Volumes/SystemRoot/tmp/opencode/cvpump.log", 1 | 0x200 | 8, 0644);
		if (fd >= 0) {
			char msg[64];
			snprintf(msg, sizeof(msg), "CREATE_WITH_CG_DISPLAY id=%d\n", (int)(displayID));
			write(fd, msg, strlen(msg));
			close(fd);
		}
	}
	registerDisplayLink((CVDisplayLinkRef)self);
	*displayLinkOut = (CVDisplayLinkRef) self;

	return kCVReturnSuccess;
}

CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod( CVDisplayLinkRef CV_NONNULL displayLink )
{
	CVTime time = { 0, 0, kCVTimeIsIndefinite };
	CGDirectDisplayID displayId = CVDisplayLinkGetCurrentCGDisplay(displayLink);
	if (displayId == kCGNullDirectDisplay)
		return time;

	CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayId);
	if (!mode)
		return time;

	double rate = CGDisplayModeGetRefreshRate(mode);
	if (rate < 1.0)
		rate = 60.0;

	time.flags = 0;
	time.timeValue = 1.0;
	time.timeScale = rate;

	CGDisplayModeRelease(mode);
	return time;
}
