#include <stdlib.h>
#include <stdio.h>  // for fprintf(stderr, "unimplemented")

#include <pthread.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <OpenGL/DarlingNativePresent.h>
extern long __lolsys_syscall(long,long,long,long,long,long,int);

#define GL_GLEXT_PROTOTYPES 1
#include <OpenGL/OpenGL.h>
#include <OpenGL/glext.h>
#include <OpenGL/CGLInternal.h>
#include <CoreFoundation/CFDictionary.h>
#include <IOSurface/IOSurface.h>
#include <pthread.h>
#include <time.h>

// Try to get the right (generic) type definitions.
// In particular, we really want EGLNativeDisplayType to be void *,
// not int as it is if __APPLE__ is defined.
#undef APPLE
#undef __APPLE__

#define __unix__
#define EGL_NO_X11

#include <EGL/egl.h>

#define APPLE
#define __APPLE__

/* darling-lol M57bo: load the native EGL privately.
 *
 * OpenGL.framework is a load-time dependency of ANGLE's libGLESv2 (its GL
 * backend). If the native EGL were linked here, its egl* symbols would land in
 * libGLESv2's dependency symbol scope and satisfy Chromium's EGL lookups, so
 * Chromium would pair Darling's Mesa EGL with ANGLE's GL - eglMakeCurrent would
 * never make an ANGLE gl::Context current (GL_MAX_VERTEX_ATTRIBS = 0, no
 * frames). Resolving EGL through a private RTLD_LOCAL dlopen keeps it out of
 * dependents' scope, so Chromium falls back to ANGLE's own EGL. */
#include <dlfcn.h>

static EGLDisplay (*p_eglGetDisplay)(EGLNativeDisplayType);
static EGLDisplay (*p_eglGetPlatformDisplay)(EGLenum, void *, const EGLAttrib *);
static EGLBoolean (*p_eglInitialize)(EGLDisplay, EGLint *, EGLint *);
static EGLBoolean (*p_eglQuerySurface)(EGLDisplay,EGLSurface,EGLint,EGLint*);
static EGLBoolean (*p_eglGetConfigAttrib)(EGLDisplay,EGLConfig,EGLint,EGLint*);
static EGLBoolean (*p_eglChooseConfig)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *);
static EGLBoolean (*p_eglBindAPI)(EGLenum);
static EGLSurface (*p_eglCreateWindowSurface)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *);
static EGLBoolean (*p_eglDestroySurface)(EGLDisplay, EGLSurface);
static EGLBoolean (*p_eglMakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
static EGLContext (*p_eglCreateContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
static EGLBoolean (*p_eglDestroyContext)(EGLDisplay, EGLContext);
static EGLBoolean (*p_eglSwapBuffers)(EGLDisplay, EGLSurface);
static EGLBoolean (*p_eglSwapInterval)(EGLDisplay, EGLint);

static int native_egl_loaded;
static pthread_mutex_t native_egl_mutex = PTHREAD_MUTEX_INITIALIZER;

static void ensure_native_egl(void) {
    if (native_egl_loaded)
        return;
    pthread_mutex_lock(&native_egl_mutex);
    if (!native_egl_loaded) {
        void *h = dlopen("/usr/lib/native/libEGL.dylib", RTLD_NOW | RTLD_LOCAL);
        if (h) {
            p_eglGetDisplay = (EGLDisplay (*)(EGLNativeDisplayType)) dlsym(h, "eglGetDisplay");
            p_eglGetPlatformDisplay = (EGLDisplay (*)(EGLenum, void *, const EGLAttrib *)) dlsym(h, "eglGetPlatformDisplay");
            p_eglInitialize = (EGLBoolean (*)(EGLDisplay, EGLint *, EGLint *)) dlsym(h, "eglInitialize");
            p_eglQuerySurface=(EGLBoolean(*)(EGLDisplay,EGLSurface,EGLint,EGLint*))dlsym(h,"eglQuerySurface");
            p_eglGetConfigAttrib=(EGLBoolean(*)(EGLDisplay,EGLConfig,EGLint,EGLint*))dlsym(h,"eglGetConfigAttrib");
            p_eglChooseConfig = (EGLBoolean (*)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *)) dlsym(h, "eglChooseConfig");
            p_eglBindAPI = (EGLBoolean (*)(EGLenum)) dlsym(h, "eglBindAPI");
            p_eglCreateWindowSurface = (EGLSurface (*)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *)) dlsym(h, "eglCreateWindowSurface");
            p_eglDestroySurface = (EGLBoolean (*)(EGLDisplay, EGLSurface)) dlsym(h, "eglDestroySurface");
            p_eglMakeCurrent = (EGLBoolean (*)(EGLDisplay, EGLSurface, EGLSurface, EGLContext)) dlsym(h, "eglMakeCurrent");
            p_eglCreateContext = (EGLContext (*)(EGLDisplay, EGLConfig, EGLContext, const EGLint *)) dlsym(h, "eglCreateContext");
            p_eglDestroyContext = (EGLBoolean (*)(EGLDisplay, EGLContext)) dlsym(h, "eglDestroyContext");
            p_eglSwapBuffers = (EGLBoolean (*)(EGLDisplay, EGLSurface)) dlsym(h, "eglSwapBuffers");
            p_eglSwapInterval = (EGLBoolean (*)(EGLDisplay, EGLint)) dlsym(h, "eglSwapInterval");
            native_egl_loaded = 1;
        }
    }
    pthread_mutex_unlock(&native_egl_mutex);
}

static EGLDisplay display;

static EGLDisplay x11EGLDisplay(EGLNativeDisplayType native_display) {
    /* CGS/AppKit supply Xlib Display pointers. Mesa's automatic platform
     * selection can choose Wayland on a Wayland desktop and interpret the
     * Xlib pointer as a wl_display, crashing during eglInitialize. */
    if (p_eglGetPlatformDisplay)
        return p_eglGetPlatformDisplay(0x31D5 /* EGL_PLATFORM_X11 */, native_display, NULL);
    return p_eglGetDisplay(native_display);
}

static EGLConfig config;
static int num_config;

static EGLint const attribute_list[] = {
    EGL_RED_SIZE, 1,
    EGL_GREEN_SIZE, 1,
    EGL_BLUE_SIZE, 1,
    EGL_NONE
};

struct _CGLDisplay
{
    EGLDisplay display;
    EGLConfig config;
    int num_config;
};

static CFMutableDictionaryRef g_displays;
static pthread_mutex_t g_displaysMutex = PTHREAD_MUTEX_INITIALIZER;

struct _CGLContextObj {
    GLuint retain_count;
    pthread_mutex_t lock;
    EGLContext egl_context;
    EGLDisplay egl_display;
    EGLConfig egl_config;
    EGLSurface egl_surface;
    // EGL has no function for getting the current swap interval,
    // so we need to save the last set value. The default is 1.
    int swap_interval;
    EGLSurface native_present_surface;
    EGLContext native_present_context;
    DarlingNativePresentTarget *native_present_target;
    uint32_t native_present_window;
    uint64_t native_next_present_ns;
    struct DarlingAsyncPresent *native_async;
};

struct _CGLPixelFormatObj {
    GLuint retain_count;
    CGLPixelFormatAttribute *attributes;
};

typedef struct {
    IOSurfaceID surfaceID;
    CGLContextObj context;
    GLenum target;
    GLenum format;
    GLenum type;
    GLuint texture;
    GLuint plane;
    IOSurfaceRef surface; /* non-owning, used only to invalidate this binding */
} CGLIOSurfaceBinding;

static void stopAsyncPresent(CGLContextObj context);

static CGLIOSurfaceBinding initialSurfaceBindings[256];
static CGLIOSurfaceBinding *ioSurfaceBindings = initialSurfaceBindings;
static unsigned ioSurfaceBindingCount, ioSurfaceBindingCapacity = 256;
static pthread_mutex_t ioSurfaceBindingMutex = PTHREAD_MUTEX_INITIALIZER;

static inline int attribute_has_argument(CGLPixelFormatAttribute attr) {
    switch (attr) {
    case kCGLPFAAuxBuffers:
    case kCGLPFAColorSize:
    case kCGLPFAAlphaSize:
    case kCGLPFADepthSize:
    case kCGLPFAStencilSize:
    case kCGLPFAAccumSize:
    case kCGLPFARendererID:
    case kCGLPFADisplayMask:
    case kCGLPFAOpenGLProfile:
    case kCGLPFASampleBuffers:
    case kCGLPFASamples:
        return 1;
    default:
        return 0;
   }
}

__attribute__((constructor))
static void _CGLInitialize(void)
{
    ensure_native_egl();
    g_displays = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
}

static int attributes_count(const CGLPixelFormatAttribute *attrs) {
    int result;
    for (result = 0; attrs[result] != 0; result++) {
        if (attribute_has_argument(attrs[result])) {
            result++;
        }
    }
    return result;
}

CGLError CGLRegisterNativeDisplay(void *native_display) {

    ensure_native_egl();
    display = x11EGLDisplay(native_display);

    if (display == EGL_NO_DISPLAY) {
        return kCGLBadConnection;
    }

    p_eglInitialize(display, NULL, NULL);
    p_eglChooseConfig(display, attribute_list, &config, 1, &num_config);

    p_eglBindAPI(EGL_OPENGL_API);

    return kCGLNoError;
}

/* darling-lol M57: processes that create a CGL context without first calling
 * CGLRegisterNativeDisplay (e.g. Chromium's GPU process) previously got
 * display==0/config==0 and CGLCreateContext always failed. Lazily initialise a
 * default EGL display so context creation can proceed. */
static void ensureDefaultDisplay(void) {
    ensure_native_egl();
    if (display != EGL_NO_DISPLAY && display != NULL && config != NULL)
        return;

    void *nativeDisplay=_CGSNativeDisplay(CGSMainConnectionID());
    EGLDisplay disp = x11EGLDisplay(nativeDisplay?nativeDisplay:EGL_DEFAULT_DISPLAY);
    if (disp == EGL_NO_DISPLAY) {
        fprintf(stderr, "M58DG ensureDefaultDisplay: eglGetDisplay(DEFAULT)=NO_DISPLAY (p_eglGetDisplay=%p)\n", (void*) p_eglGetDisplay);
        return;
    }

    EGLConfig cfg = NULL;
    EGLBoolean m58dg_ini = p_eglInitialize(disp, NULL, NULL);
    EGLBoolean m58dg_ch = p_eglChooseConfig(disp, attribute_list, &cfg, 1, &num_config);
    fprintf(stderr, "M58DG ensureDefaultDisplay: disp=%p eglInitialize=%d eglChooseConfig=%d cfg=%p num_config=%d\n",
        (void*) disp, (int) m58dg_ini, (int) m58dg_ch, (void*) cfg, num_config);
    if (m58dg_ini && m58dg_ch && cfg != NULL) {
        display = disp;
        config = cfg;
        p_eglBindAPI(EGL_OPENGL_API);
    }
}

static struct _CGLDisplay* getCGLDisplay(CGSConnectionID cid)
{
    struct _CGLDisplay* rv;

    ensure_native_egl();
    pthread_mutex_lock(&g_displaysMutex);
    rv = (struct _CGLDisplay*) CFDictionaryGetValue(g_displays, (const void*)(unsigned long) cid);
    pthread_mutex_unlock(&g_displaysMutex);

    if (!rv)
    {
        EGLDisplay disp = x11EGLDisplay(_CGSNativeDisplay(cid));
        if (disp == EGL_NO_DISPLAY)
            return NULL;

        rv = (struct _CGLDisplay*) malloc(sizeof(*rv));
        rv->display = disp;

        p_eglInitialize(rv->display, NULL, NULL);
        p_eglChooseConfig(rv->display, attribute_list, &rv->config, 1, &rv->num_config);

        p_eglBindAPI(EGL_OPENGL_API);

        pthread_mutex_lock(&g_displaysMutex);
        CFDictionaryAddValue(g_displays, (const void*)(unsigned long) cid, rv);
        pthread_mutex_unlock(&g_displaysMutex);
    }

    return rv;
}

CGLError CGLSetSurface(CGLContextObj gl, CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid)
{
    if (!gl)
        return kCGLBadContext;
    struct _CGLDisplay* disp = getCGLDisplay(cid);
    if (!disp)
        return kCGLBadConnection;

    EGLNativeWindowType window;
    if (sid)
        window = (EGLNativeWindowType) _CGSNativeWindowForSurfaceID(cid, wid, sid);
    else
        window = (EGLNativeWindowType) _CGSNativeWindowForID(cid, wid);

    if (!window)
        return kCGLBadWindow;

    gl->egl_surface = p_eglCreateWindowSurface(gl->egl_display, gl->egl_config, window, NULL);
    if (gl->egl_surface == EGL_NO_SURFACE)
        return kCGLBadState;
    return kCGLNoError;
}

CGLWindowRef CGLGetWindow(void *native_window) {

    EGLNativeWindowType window = (EGLNativeWindowType) native_window;
    EGLSurface surface = p_eglCreateWindowSurface(display, config, window, NULL);

    if (surface == EGL_NO_SURFACE) {
        return NULL;
    }

    return (CGLWindowRef) surface;
}

CGL_EXPORT void CGLDestroyWindow(CGLWindowRef window) {
    p_eglDestroySurface(display, (EGLSurface) window);
}

CGL_EXPORT CGLError CGLContextMakeCurrentAndAttachToWindow(CGLContextObj context, CGLWindowRef window) {
    if (!context)
        return kCGLBadContext;
    EGLSurface oldSurface = context->egl_surface;
    context->egl_surface = (EGLSurface) window;
    CGLError result = CGLSetCurrentContext(context);
    if (result != kCGLNoError)
        context->egl_surface = oldSurface;
    return result;
}

static pthread_key_t current_context_key;

static void make_key() {
    pthread_key_create(&current_context_key, NULL);
}

static pthread_key_t get_current_context_key() {
    static pthread_once_t key_once = PTHREAD_ONCE_INIT;
    pthread_once(&key_once, make_key);
    return current_context_key;
}

CGLContextObj CGLGetCurrentContext(void) {
    pthread_key_t key = get_current_context_key();
    return pthread_getspecific(key);
}

/* darling-lol M57: CGLGetVirtualScreen/CGLSetVirtualScreen are used by
 * Chromium's CGL backend; Darling's OpenGL did not provide them (lazy-bind
 * abort: "Symbol not found: _CGLGetVirtualScreen"). A single virtual screen. */
CGLError CGLGetVirtualScreen(CGLContextObj context, GLint *screen) {
    if (!context) return kCGLBadContext;
    if (!screen) return kCGLBadAddress;
    *screen = 0;
    return kCGLNoError;
}

CGLError CGLSetVirtualScreen(CGLContextObj context, GLint screen) {
    if (!context) return kCGLBadContext;
    return screen == 0 ? kCGLNoError : kCGLBadValue;
}

CGLError CGLSetCurrentContext(CGLContextObj context) {
    ensure_native_egl();
    pthread_key_t key = get_current_context_key();
    CGLContextObj old = pthread_getspecific(key);
    EGLDisplay currentDisplay = context ? context->egl_display : old ? old->egl_display : display;
    if (!p_eglMakeCurrent)
        return kCGLBadConnection;
    if (!context && !old && !currentDisplay)
        return kCGLNoError;

    EGLBoolean success;
    if (context != NULL) {
        EGLSurface surface = context->egl_surface;
        success = p_eglMakeCurrent(currentDisplay, surface, surface, context->egl_context);
    } else {
        success = p_eglMakeCurrent(currentDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    if (!success)
        return kCGLBadState;
    pthread_setspecific(key, context);
    return kCGLNoError;
}

CGLError CGLSetFullScreen(CGLContextObj ctx) {
    printf("STUB: CGLSetFullScreen\n");

    return kCGLNoError;
}

CGLError CGLChoosePixelFormat(
    const CGLPixelFormatAttribute *attrs,
    CGLPixelFormatObj *result,
    GLint *number_of_screens
) {
    if (!attrs || !result || !number_of_screens)
        return kCGLBadAddress;
    CGLPixelFormatObj format = malloc(sizeof(struct _CGLPixelFormatObj));
    int count = attributes_count(attrs);

    format->retain_count = 1;
    format->attributes = calloc(count + 1, sizeof(CGLPixelFormatAttribute));
    for (int i = 0; i < count; i++) {
        format->attributes[i] = attrs[i];
    }

    *result = format;
    *number_of_screens = 1;

    return kCGLNoError;
}

CGLError CGLClearDrawable(CGLContextObj ctx)
{
    printf("STUB: CGLClearDrawable\n");

    return kCGLNoError;
}

CGLError CGLDescribePixelFormat(
    CGLPixelFormatObj format,
    GLint sreen_num,
    CGLPixelFormatAttribute attr,
    GLint *value
) {
    if (!format) return kCGLBadPixelFormat;
    if (!value) return kCGLBadAddress;
    if (sreen_num != 0) return kCGLBadValue;
    if (attr == kCGLPFAVirtualScreenCount) { *value = 1; return kCGLNoError; }
    for (int i = 0; format->attributes[i] != 0; i++) {
        int has_arg = attribute_has_argument(format->attributes[i]);

        if (format->attributes[i] == attr) {
            if (has_arg) {
                *value = format->attributes[i + 1];
            } else {
                *value = 1;
            }
            return kCGLNoError;
        }

        if (has_arg) {
            i++;
        }
    }

    *value = 0;
    return kCGLNoError;
}

CGLPixelFormatObj CGLRetainPixelFormat(CGLPixelFormatObj format) {
    if (format == NULL) {
        return NULL;
    }

    format->retain_count++;
    return format;
}

void CGLReleasePixelFormat(CGLPixelFormatObj format) {
    if (format == NULL) {
        return;
    }

    format->retain_count--;

    if (format->retain_count == 0) {
        free(format->attributes);
        free(format);
    }
}

CGLError CGLDestroyPixelFormat(CGLPixelFormatObj pixelFormat) {
    CGLReleasePixelFormat(pixelFormat);
    return kCGLNoError;
}

GLuint CGLGetPixelFormatRetainCount(CGLPixelFormatObj pixelFormat) {
    return pixelFormat->retain_count;
}

CGLError CGLCreateContext(CGLPixelFormatObj pixelFormat, CGLContextObj share, CGLContextObj *resultp) {
    /* Cocotron window compositing requests the default format with NULL. */
    if (!resultp)
        return kCGLBadAddress;
    *resultp = NULL;
    ensureDefaultDisplay();
    /* eglBindAPI is thread-local, even when the display is already initialized. */
    if (!display || !config || !p_eglBindAPI || !p_eglBindAPI(EGL_OPENGL_API))
        return kCGLBadConnection;

    EGLContext egl_share = EGL_NO_CONTEXT;
    EGLDisplay contextDisplay = share ? share->egl_display : display;
    EGLConfig contextConfig = share ? share->egl_config : config;
    if (share != NULL) {
        egl_share = share->egl_context;
    }
    GLint profile = 0;
    if (pixelFormat)
        CGLDescribePixelFormat(pixelFormat, 0, kCGLPFAOpenGLProfile, &profile);
    EGLint contextAttributes[] = {
        0x3098 /* EGL_CONTEXT_MAJOR_VERSION */, 3,
        0x30FB /* EGL_CONTEXT_MINOR_VERSION */, 2,
        0x30FD /* EGL_CONTEXT_OPENGL_PROFILE_MASK */, 1 /* CORE_PROFILE_BIT */,
        EGL_NONE
    };
    if (profile == 0x4100) {
        contextAttributes[1] = 4;
        contextAttributes[3] = 1;
    } else if (profile && profile != 0x1000 && profile != 0x3200) {
        return kCGLBadValue;
    }
    EGLContext egl_context = p_eglCreateContext(contextDisplay, contextConfig, egl_share,
        profile == 0x3200 || profile == 0x4100 ? contextAttributes : NULL);

    if (egl_context == EGL_NO_CONTEXT) {
        fprintf(stderr, "M58DG CGLCreateContext FAILED: display=%p config=%p share=%p p_eglCreateContext=%p\n",
            (void*) display, (void*) config, (void*) egl_share, (void*) p_eglCreateContext);
        return kCGLBadContext;
    }

    {
        static int m58dg_ok = 0;
        if (m58dg_ok++ < 5)
            fprintf(stderr, "M58DG CGLCreateContext OK display=%p config=%p ctx=%p\n",
                (void*) display, (void*) config, (void*) egl_context);
    }

    CGLContextObj context = malloc(sizeof(struct _CGLContextObj));

    context->retain_count = 1;
    pthread_mutex_init(&(context->lock), NULL);
    context->egl_context = egl_context;
    context->egl_display = contextDisplay;
    context->egl_config = contextConfig;
    context->egl_surface = NULL;
    context->swap_interval = 1;
    context->native_present_surface=EGL_NO_SURFACE;
    context->native_present_context=EGL_NO_CONTEXT;
    context->native_present_target=NULL;
    context->native_present_window=0;
    context->native_next_present_ns=0;
    context->native_async=NULL;

    *resultp = context;

    return kCGLNoError;
}

CGLContextObj CGLRetainContext(CGLContextObj context) {
    if (context == NULL) {
        return NULL;
    }

    __sync_add_and_fetch(&context->retain_count, 1);
    return context;
}

void CGLReleaseContext(CGLContextObj context) {
    if (context == NULL) {
        return;
    }

    pthread_mutex_lock(&ioSurfaceBindingMutex);
    if (__sync_sub_and_fetch(&context->retain_count, 1) != 0) {
        pthread_mutex_unlock(&ioSurfaceBindingMutex);
        return;
    }
    for (unsigned i = 0; i < ioSurfaceBindingCount; ) {
        if (ioSurfaceBindings[i].context == context)
            ioSurfaceBindings[i] = ioSurfaceBindings[--ioSurfaceBindingCount];
        else ++i;
    }
    pthread_mutex_unlock(&ioSurfaceBindingMutex);

    if (CGLGetCurrentContext() == context) {
        CGLSetCurrentContext(NULL);
    }

    pthread_mutex_destroy(&(context->lock));

    stopAsyncPresent(context);
    if(context->native_present_context!=EGL_NO_CONTEXT)p_eglDestroyContext(context->egl_display,context->native_present_context);
    if(context->native_present_surface!=EGL_NO_SURFACE)p_eglDestroySurface(context->egl_display,context->native_present_surface);
    if(context->native_present_target)__lolsys_syscall((long)context->native_present_target,sizeof(DarlingNativePresentTarget),0,0,0,0,11);
    p_eglDestroyContext(context->egl_display, context->egl_context);

    free(context);
}

GLuint CGLGetContextRetainCount(CGLContextObj context) {
    if (context == NULL) {
        return 0;
    }

    return context->retain_count;
}

CGLError CGLDestroyContext(CGLContextObj context) {
    CGLReleaseContext(context);

    return kCGLNoError;
}

CGLError CGLLockContext(CGLContextObj context) {
    pthread_mutex_lock(&(context->lock));
    return kCGLNoError;
}

CGLError CGLUnlockContext(CGLContextObj context) {
    pthread_mutex_unlock(&(context->lock));
    return kCGLNoError;
}

static int swapIntervalRequested;

CGLError CGLFlushDrawable(CGLContextObj context) {
    if (!context)
        return kCGLBadContext;
    /* darling-lol: EGL defaults to a swap interval of 1. When the window is covered or the compositor throttles it
     * (Xwayland answers about once a second), every swap blocks that long and the game's frame rate collapses to ~1 fps.
     * macOS apps get an unthrottled flush unless they ask for vsync through kCGLCPSwapInterval, which is handled in
     * CGLSetParameter; apply "no vsync" once per context here, while it is current. */
    static CGLContextObj swapIntervalContext;
    if (!swapIntervalRequested && context != swapIntervalContext && p_eglSwapInterval && CGLGetCurrentContext() == context) {
        p_eglSwapInterval(context->egl_display, 0);
        swapIntervalContext = context;
    }
    return p_eglSwapBuffers(context->egl_display, context->egl_surface) ? kCGLNoError : kCGLBadState;
}

static GLenum textureBindingEnum(GLenum target) {
    switch (target) {
    case GL_TEXTURE_2D: return GL_TEXTURE_BINDING_2D;
#ifdef GL_TEXTURE_RECTANGLE
    case GL_TEXTURE_RECTANGLE: return GL_TEXTURE_BINDING_RECTANGLE;
#endif
    default: return 0;
    }
}

/* macOS exposes IOSurfaces to CGL as texture storage. Mesa/EGL does not have
 * that CGL entry point, but Chromium only needs the pixels to reach the bound
 * texture. Upload from the shared IOSurface mapping synchronously; this also
 * preserves the cross-process IOSurface transport implemented by our shim. */
static uint64_t nativeMonotonicNS(void);
static uint32_t nativeUploadCount, nativeUploadMicroseconds;
CGLError CGLTexImageIOSurface2D(CGLContextObj context, GLenum target,
    GLenum internalFormat, GLsizei width, GLsizei height, GLenum format,
    GLenum type, IOSurfaceRef ioSurface, GLuint plane)
{
    if (!context)
        return kCGLBadContext;
    if (!ioSurface)
        return kCGLBadAddress;

    void *pixels = IOSurfaceGetBaseAddressOfPlane(ioSurface, plane);
    size_t bytesPerRow = IOSurfaceGetBytesPerRowOfPlane(ioSurface, plane);
    size_t bytesPerElement = IOSurfaceGetBytesPerElementOfPlane(ioSurface, plane);
    if (!pixels || !bytesPerRow || !bytesPerElement)
        return kCGLBadValue;

    CGLContextObj oldContext = CGLGetCurrentContext();
    if (oldContext != context) {
        CGLError result = CGLSetCurrentContext(context);
        if (result != kCGLNoError)
            return result;
    }

    uint64_t uploadStarted = nativeMonotonicNS();
    GLint oldRowLength = 0;
    GLint oldAlignment = 0;
    GLint boundTexture = 0;
    /* ANGLE can leave an unrelated probe error pending before calling this
     * CGL API. CGLTexImageIOSurface2D reports only its own operation. */
    while (glGetError() != GL_NO_ERROR) {}
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &oldRowLength);
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &oldAlignment);
    GLenum bindingEnum = textureBindingEnum(target);
    if (bindingEnum)
        glGetIntegerv(bindingEnum, &boundTexture);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, (GLint)(bytesPerRow / bytesPerElement));
    GLint allocatedWidth=0,allocatedHeight=0,allocatedFormat=0;
    glGetTexLevelParameteriv(target,0,GL_TEXTURE_WIDTH,&allocatedWidth);
    glGetTexLevelParameteriv(target,0,GL_TEXTURE_HEIGHT,&allocatedHeight);
    glGetTexLevelParameteriv(target,0,GL_TEXTURE_INTERNAL_FORMAT,&allocatedFormat);
    if(allocatedWidth==width && allocatedHeight==height && allocatedFormat==(GLint)internalFormat)
        glTexSubImage2D(target,0,0,0,width,height,format,type,pixels);
    else
        glTexImage2D(target, 0, (GLint)internalFormat, width, height, 0,
            format, type, pixels);
    GLenum error = glGetError();
    glPixelStorei(GL_UNPACK_ROW_LENGTH, oldRowLength);
    glPixelStorei(GL_UNPACK_ALIGNMENT, oldAlignment);

    if (error == GL_NO_ERROR && boundTexture != 0) {
        CGLIOSurfaceBinding binding = {
            IOSurfaceGetID(ioSurface), context, target, format, type,
            (GLuint)boundTexture, plane, ioSurface
        };
        pthread_mutex_lock(&ioSurfaceBindingMutex);
        unsigned slot = ioSurfaceBindingCount;
        for (unsigned i = 0; i < ioSurfaceBindingCount; ++i) {
            if (ioSurfaceBindings[i].surfaceID == binding.surfaceID) {
                slot = i;
                break;
            }
        }
        if (slot == ioSurfaceBindingCapacity) {
            unsigned capacity = ioSurfaceBindingCapacity * 2;
            CGLIOSurfaceBinding *larger = malloc(capacity * sizeof(*larger));
            if (larger) {
                memcpy(larger, ioSurfaceBindings, ioSurfaceBindingCount * sizeof(*larger));
                if (ioSurfaceBindings != initialSurfaceBindings) free(ioSurfaceBindings);
                ioSurfaceBindings = larger;
                ioSurfaceBindingCapacity = capacity;
            }
        }
        if (slot < ioSurfaceBindingCapacity) {
            ioSurfaceBindings[slot] = binding;
            if (slot == ioSurfaceBindingCount) ++ioSurfaceBindingCount;
        } else error = GL_OUT_OF_MEMORY;
        pthread_mutex_unlock(&ioSurfaceBindingMutex);
    }

    CGLError restore = kCGLNoError;
    if (oldContext != context)
        restore = CGLSetCurrentContext(oldContext);
    if (error != GL_NO_ERROR)
        fprintf(stderr, "CGLTexImageIOSurface2D glTexImage2D error=0x%x target=0x%x format=0x%x type=0x%x %dx%d\n",
            error, target, format, type, width, height);
    __atomic_fetch_add(&nativeUploadCount,1,__ATOMIC_RELAXED);
    __atomic_fetch_add(&nativeUploadMicroseconds,(uint32_t)((nativeMonotonicNS()-uploadStarted)/1000),__ATOMIC_RELAXED);
    return error == GL_NO_ERROR ? restore : kCGLBadState;
}

/* Called before IOSurface storage is destroyed; no owning surface reference. */
void CGLForgetIOSurface(IOSurfaceRef surface) {
    pthread_mutex_lock(&ioSurfaceBindingMutex);
    for (unsigned i = 0; i < ioSurfaceBindingCount; ) {
        if (ioSurfaceBindings[i].surface == surface)
            ioSurfaceBindings[i] = ioSurfaceBindings[--ioSurfaceBindingCount];
        else ++i;
    }
    pthread_mutex_unlock(&ioSurfaceBindingMutex);
}

#include "CGLAsyncPresent.inc"

/* Present a flattened compositor texture directly. The native transport
 * acknowledges suspension of CPU writes before the first GL swap. Fallback
 * leaves the existing readback path available and restores all GL bindings. */
CGL_EXPORT int CGLPresentIOSurface(IOSurfaceRef surface) {
    if(!surface || !getenv("RCLOL_GPU_DIRECT_PRESENT") || IOSurfaceGetPlaneCount(surface)>1 ||
       IOSurfaceGetBytesPerElement(surface)!=4)return 0;
    size_t width=IOSurfaceGetWidth(surface),height=IOSurfaceGetHeight(surface);
    if(width<256 || height<256)return 0;
    CGLIOSurfaceBinding binding={0};IOSurfaceID id=IOSurfaceGetID(surface);
    pthread_mutex_lock(&ioSurfaceBindingMutex);
    for(unsigned i=0;i<ioSurfaceBindingCount;++i)if(ioSurfaceBindings[i].surfaceID==id){
        binding=ioSurfaceBindings[i];CGLRetainContext(binding.context);break;
    }
    pthread_mutex_unlock(&ioSurfaceBindingMutex);
    if(!binding.context)return 0;
    CGLContextObj ctx=binding.context;
    if(CGLGetCurrentContext()!=ctx){CGLReleaseContext(ctx);return 0;}
    if(!ctx->native_present_target){
        char path[128];snprintf(path,sizeof(path),"/dev/shm/darling-ca-gpu-target-%u-%zu-%zu",getuid(),width,height);
        int fd=(int)__lolsys_syscall((long)path,2,0,0,0,0,2);if(getenv("RCLOL_GPU_DIRECT_TRACE"))fprintf(stderr,"GPU_DIRECT target_open=%d uid=%u size=%zux%zu\n",fd,getuid(),width,height);if(fd>=0){
            struct stat metadata;
            long mapped=-1;
            if(fstat(fd,&metadata)==0 && metadata.st_size>=sizeof(DarlingNativePresentTarget) && metadata.st_uid==getuid())
                mapped=__lolsys_syscall(0,sizeof(DarlingNativePresentTarget),3,1,fd,0,9);
            if(mapped>0 || mapped < -4095)ctx->native_present_target=(void*)mapped;__lolsys_syscall(fd,0,0,0,0,0,3);
        }
    }
    DarlingNativePresentTarget *target=ctx->native_present_target;
    /* A Chromium context renders several windows. An unrelated surface must
     * use readback without stopping the active window's async presenter. */
    if(target && __atomic_load_n(&target->magic,__ATOMIC_ACQUIRE)==DARLING_NATIVE_PRESENT_MAGIC &&
       target->target && (target->width!=width || target->height!=height)) {
        CGLReleaseContext(ctx);return 0;
    }
    if(!target || __atomic_load_n(&target->magic,__ATOMIC_ACQUIRE)!=DARLING_NATIVE_PRESENT_MAGIC ||
       !target->target){
        stopAsyncPresent(ctx);
        if(target){__lolsys_syscall((long)target,sizeof(DarlingNativePresentTarget),0,0,0,0,11);ctx->native_present_target=NULL;ctx->native_present_window=0;}
        CGLReleaseContext(ctx);return 0;
    }
    if(ctx->native_present_window!=target->target){
        stopAsyncPresent(ctx);
        if(ctx->native_present_context!=EGL_NO_CONTEXT)p_eglDestroyContext(ctx->egl_display,ctx->native_present_context);
        if(ctx->native_present_surface!=EGL_NO_SURFACE)p_eglDestroySurface(ctx->egl_display,ctx->native_present_surface);
        ctx->native_present_surface=EGL_NO_SURFACE;ctx->native_present_context=EGL_NO_CONTEXT;
        EGLint attrs[]={EGL_SURFACE_TYPE,EGL_WINDOW_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_BIT,EGL_NONE};
        EGLConfig *candidates=NULL,cfg=NULL;EGLint count=0,selectedVisual=0;
        if(p_eglChooseConfig(ctx->egl_display,attrs,NULL,0,&count) && count>0 && count<=65536)
            candidates=calloc(count,sizeof(*candidates));
        if(candidates && p_eglChooseConfig(ctx->egl_display,attrs,candidates,count,&count) && p_eglGetConfigAttrib){
            for(EGLint n=0;n<count;++n){EGLint visual=0;
                if(p_eglGetConfigAttrib(ctx->egl_display,candidates[n],EGL_NATIVE_VISUAL_ID,&visual) && visual==(EGLint)target->visual){cfg=candidates[n];selectedVisual=visual;break;}
            }
        }
        free(candidates);
        if(cfg){
            ctx->native_present_surface=p_eglCreateWindowSurface(ctx->egl_display,cfg,(EGLNativeWindowType)(uintptr_t)target->target,NULL);
            EGLint contextAttrs[]={0x3098,3,0x30FB,2,0x30FD,1,EGL_NONE};
            ctx->native_present_context=p_eglCreateContext(ctx->egl_display,cfg,ctx->egl_context,contextAttrs);
        }
        if(getenv("RCLOL_GPU_DIRECT_TRACE"))fprintf(stderr,"GPU_DIRECT selected_visual=%d requested_visual=%u\n",selectedVisual,target->visual);
        EGLint actualWidth=0,actualHeight=0;
        if(ctx->native_present_surface!=EGL_NO_SURFACE){p_eglQuerySurface(ctx->egl_display,ctx->native_present_surface,EGL_WIDTH,&actualWidth);p_eglQuerySurface(ctx->egl_display,ctx->native_present_surface,EGL_HEIGHT,&actualHeight);}
        if(getenv("RCLOL_GPU_DIRECT_TRACE"))fprintf(stderr,"GPU_DIRECT native_size=%dx%d requested=%zux%zu\n",actualWidth,actualHeight,width,height);
        ctx->native_present_window=target->target;
        if(getenv("RCLOL_GPU_DIRECT_TRACE"))fprintf(stderr,"GPU_DIRECT surface_created=%d shared_context=%d visual=%u target=%u\n",ctx->native_present_surface!=EGL_NO_SURFACE,ctx->native_present_context!=EGL_NO_CONTEXT,target->visual,target->target);
    }
    if(ctx->native_present_surface==EGL_NO_SURFACE || ctx->native_present_context==EGL_NO_CONTEXT){CGLReleaseContext(ctx);return 0;}
    uint32_t ready=__atomic_load_n(&target->ready,__ATOMIC_ACQUIRE);
    if(!ready){__atomic_store_n(&target->ready,1,__ATOMIC_RELEASE);
        for(unsigned n=0;n<40 && __atomic_load_n(&target->ready,__ATOMIC_ACQUIRE)==1;++n)usleep(500);
        if(__atomic_load_n(&target->ready,__ATOMIC_ACQUIRE)!=2){__atomic_store_n(&target->ready,0,__ATOMIC_RELEASE);CGLReleaseContext(ctx);return 0;}
    }
    /* Bound the producer independently of async display cadence when testing
     * unthrottled begin frames. Keep waits on the owning GPU thread and use
     * absolute monotonic deadlines; async staging remains bounded to three. */
    if(getenv("RCLOL_GPU_DIRECT_PACE")){
        struct timespec now;
        if(__lolsys_syscall(1,(long)&now,0,0,0,0,228)==0){
            uint64_t current=(uint64_t)now.tv_sec*1000000000ull+now.tv_nsec;
            uint64_t deadline=ctx->native_next_present_ns;
            uint64_t paceNS=nativeRefreshIntervalNS();
            if(!deadline || (current>deadline && current-deadline>paceNS))deadline=current;
            if(deadline>current){
                struct timespec wake={deadline/1000000000ull,deadline%1000000000ull};
                while(__lolsys_syscall(1,1,(long)&wake,0,0,0,230)==-4){}
            }
            ctx->native_next_present_ns=deadline+paceNS;
        }
    }
    if(getenv("RCLOL_GPU_DIRECT_ASYNC")){int queued=enqueueAsyncPresent(ctx,binding.texture,binding.target,width,height);if(!queued){stopAsyncPresent(ctx);__atomic_store_n(&target->ready,0,__ATOMIC_RELEASE);}CGLReleaseContext(ctx);return queued;}
    GLsync completion=glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0);glFlush();
    int ok=0;GLsync presented=NULL;
    if(completion && p_eglMakeCurrent(ctx->egl_display,ctx->native_present_surface,ctx->native_present_surface,ctx->native_present_context)){
        glWaitSync(completion,0,GL_TIMEOUT_IGNORED);glDeleteSync(completion);completion=NULL;
        p_eglSwapInterval(ctx->egl_display,0);
        GLuint fbo=0;glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_READ_FRAMEBUFFER,fbo);
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,binding.target,binding.texture,0);
        if(glCheckFramebufferStatus(GL_READ_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE){
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER,0);glDrawBuffer(GL_BACK);glReadBuffer(GL_COLOR_ATTACHMENT0);
            glDisable(GL_SCISSOR_TEST);glDisable(GL_FRAMEBUFFER_SRGB);
            glBlitFramebuffer(0,height,width,0,0,0,width,height,GL_COLOR_BUFFER_BIT,GL_NEAREST);
            /* The producer fence and EGL swap order GPU work without a CPU wait. */
            static unsigned syntheticSamples;
            int inspect=target->flags==0x54455354 && getenv("RCLOL_GPU_DIRECT_SYNTHETIC_TEST") && syntheticSamples++==10;
            if(inspect){
                unsigned char rgba[4];glReadPixels(0,0,1,1,GL_RGBA,GL_UNSIGNED_BYTE,rgba);
                fprintf(stderr,"DIRECT_SHARED_SOURCE rgba=%u,%u,%u,%u\n",rgba[0],rgba[1],rgba[2],rgba[3]);
                glBindFramebuffer(GL_READ_FRAMEBUFFER,0);glReadBuffer(GL_BACK);glReadPixels(0,0,1,1,GL_RGBA,GL_UNSIGNED_BYTE,rgba);
                fprintf(stderr,"DIRECT_SHARED_BACK rgba=%u,%u,%u,%u\n",rgba[0],rgba[1],rgba[2],rgba[3]);
            }
            presented=glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0);glFlush();
            if(presented && glGetError()==GL_NO_ERROR){ok=p_eglSwapBuffers(ctx->egl_display,ctx->native_present_surface);
                static unsigned traceCount;
                if(getenv("RCLOL_GPU_DIRECT_TRACE") && traceCount++<3)fprintf(stderr,"GPU_DIRECT swap_result=%d swap_fn=%p surface=%p\n",ok,(void*)p_eglSwapBuffers,(void*)ctx->native_present_surface);
            }
            if(inspect){unsigned char rgba[4];glReadBuffer(GL_FRONT);glReadPixels(0,0,1,1,GL_RGBA,GL_UNSIGNED_BYTE,rgba);
                fprintf(stderr,"DIRECT_SHARED_FRONT rgba=%u,%u,%u,%u error=%u\n",rgba[0],rgba[1],rgba[2],rgba[3],glGetError());}
        }
        glBindFramebuffer(GL_READ_FRAMEBUFFER,0);glDeleteFramebuffers(1,&fbo);
        if(!p_eglMakeCurrent(ctx->egl_display,ctx->egl_surface,ctx->egl_surface,ctx->egl_context))ok=0;
        else if(presented){glWaitSync(presented,0,GL_TIMEOUT_IGNORED);glDeleteSync(presented);presented=NULL;}
        if(presented)glDeleteSync(presented);
    }
    if(completion)glDeleteSync(completion);
    __atomic_store_n(&target->ready,ok?3:0,__ATOMIC_RELEASE);
    if(ok){__atomic_add_fetch(&target->sequence,1,__ATOMIC_RELEASE);target->presenter=(uint32_t)getpid();}
    CGLReleaseContext(ctx);return ok;
}

CGLError CGLReadbackIOSurface(IOSurfaceRef ioSurface) {
    if (!ioSurface)
        return kCGLBadAddress;
    IOSurfaceID surfaceID = IOSurfaceGetID(ioSurface);
    CGLIOSurfaceBinding binding = {0};
    pthread_mutex_lock(&ioSurfaceBindingMutex);
    for (unsigned i = 0; i < ioSurfaceBindingCount; ++i) {
        if (ioSurfaceBindings[i].surfaceID == surfaceID) {
            binding = ioSurfaceBindings[i];
            CGLRetainContext(binding.context);
            break;
        }
    }
    pthread_mutex_unlock(&ioSurfaceBindingMutex);
    if (!binding.context || !binding.texture)
        return kCGLBadValue;

    void *pixels = IOSurfaceGetBaseAddressOfPlane(ioSurface, binding.plane);
    size_t bytesPerRow = IOSurfaceGetBytesPerRowOfPlane(ioSurface, binding.plane);
    size_t bytesPerElement = IOSurfaceGetBytesPerElementOfPlane(ioSurface, binding.plane);
    GLenum bindingEnum = textureBindingEnum(binding.target);
    if (!pixels || !bytesPerRow || !bytesPerElement || !bindingEnum) {
        CGLReleaseContext(binding.context);
        return kCGLBadValue;
    }

    CGLContextObj oldContext = CGLGetCurrentContext();
    if (oldContext != binding.context) {
        CGLError result = CGLSetCurrentContext(binding.context);
        if (result != kCGLNoError) {
            CGLReleaseContext(binding.context);
            return result;
        }
    }
    GLint oldTexture = 0, oldRowLength = 0, oldAlignment = 0;
    while (glGetError() != GL_NO_ERROR) {}
    glGetIntegerv(bindingEnum, &oldTexture);
    glGetIntegerv(GL_PACK_ROW_LENGTH, &oldRowLength);
    glGetIntegerv(GL_PACK_ALIGNMENT, &oldAlignment);
    glBindTexture(binding.target, binding.texture);
    glFinish();
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ROW_LENGTH, (GLint)(bytesPerRow / bytesPerElement));
    IOSurfaceLock(ioSurface, 0, NULL);
    glGetTexImage(binding.target, 0, binding.format, binding.type, pixels);
    GLenum error = glGetError();
    typedef kern_return_t (*GPUUnlockFn)(IOSurfaceRef);
    GPUUnlockFn gpuUnlock = (GPUUnlockFn)dlsym(RTLD_DEFAULT, "_IOSurfaceUnlockGPUReadback");
    if (gpuUnlock) gpuUnlock(ioSurface);
    else IOSurfaceUnlock(ioSurface, 0, NULL);
    glPixelStorei(GL_PACK_ROW_LENGTH, oldRowLength);
    glPixelStorei(GL_PACK_ALIGNMENT, oldAlignment);
    glBindTexture(binding.target, (GLuint)oldTexture);
    CGLError restore = kCGLNoError;
    if (oldContext != binding.context)
        restore = CGLSetCurrentContext(oldContext);
    CGLReleaseContext(binding.context);
    return error == GL_NO_ERROR ? restore : kCGLBadState;
}

CGLError CGLSetParameter(CGLContextObj context, CGLContextParameter parameter, const GLint *value) {
    if (!value)
        return kCGLBadAddress;

    if (parameter == kCGLCPSwapInterval)
    {
        swapIntervalRequested = 1;
        GLint v = *value;
        EGLBoolean success = p_eglSwapInterval(display, v);
        if (success)
            context->swap_interval = v;
        return success ? kCGLNoError : kCGLBadValue;
    }
    fprintf(stderr, "CGLSetParameter unimplemented for parameter %d\n", parameter);
    return kCGLNoError;
}

CGLError CGLGetParameter(CGLContextObj context, CGLContextParameter parameter, GLint *value) {
    if (!value)
        return kCGLBadAddress;

    if (parameter == kCGLCPSwapInterval)
    {
        *value = context->swap_interval;
        return kCGLNoError;
    }
    fprintf(stderr, "CGLGetParameter unimplemented for parameter %d\n", parameter);
    return kCGLNoError;
}

CGLError CGLDescribeRenderer(CGLRendererInfoObj rend, GLint rend_num, CGLRendererProperty prop, GLint *value) {
    if (!value) return kCGLBadAddress;
    *value = 0;
    return kCGLBadRendererInfo;
}

CGLError CGLQueryRendererInfo(GLuint display_mask, CGLRendererInfoObj *rend, GLint *nrend) {
    if (!rend || !nrend) return kCGLBadAddress;
    *rend = NULL;
    *nrend = 0;
    return kCGLBadRendererInfo;
}

CGLError CGLDestroyRendererInfo(CGLRendererInfoObj rend) {
    return kCGLNoError;
}
