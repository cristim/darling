#include <stdlib.h>
#include <stdio.h>  // for fprintf(stderr, "unimplemented")

#include <pthread.h>

#include <OpenGL/OpenGL.h>
#include <OpenGL/CGLInternal.h>
#include <CoreFoundation/CFDictionary.h>
#include <pthread.h>

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

static EGLDisplay display;

static EGLConfig config;
static int num_config;
static int default_swap_interval = 1;

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
    EGLSurface egl_surface;
    // Config this context was created with. eglMakeCurrent requires the drawable's
    // config to be compatible with the context's, so CGLGetWindow needs to know it.
    EGLConfig egl_config;
    // EGL has no function for getting the current swap interval,
    // so we need to save the last set value. The default is 1.
    int swap_interval;
};

struct _CGLPixelFormatObj {
    GLuint retain_count;
    CGLPixelFormatAttribute *attributes;
    // The EGLConfig matching `attributes`. Kept on the format rather than only in the
    // process-global `config` so a window surface can be created with the same config
    // its context was created from; EGL requires the two to be compatible.
    EGLConfig egl_config;
};

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
        return 1;
    default:
        return 0;
   }
}

__attribute__((constructor))
static void _CGLInitialize(void)
{
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

// Translate a CGLPixelFormatAttribute list into EGL config attributes. Unrecognised
// attributes are skipped rather than guessed at, and the result is advisory: a
// pixel format that cannot be satisfied still yields a usable config, which is what
// the previous stub did for every request. The point is that requests which *can* be
// satisfied - buffer count, colour/depth/stencil sizes, samples - now actually reach EGL
// instead of being discarded.
static int cgl_attributes_to_egl(const CGLPixelFormatAttribute *attrs, EGLint *out, int max) {
    int n = 0;
    // Always require an OpenGL-capable config. Without this the query can return a config with no
    // OpenGL support, and eglCreateContext then fails for reasons unrelated to the caller's request.
    if (n + 2 <= max) {
        out[n++] = EGL_RENDERABLE_TYPE; out[n++] = EGL_OPENGL_BIT;
    }
    for (int i = 0; attrs[i] != 0 && n + 2 <= max; i++) {
        CGLPixelFormatAttribute a = attrs[i];
        int value = 0;
        if (attribute_has_argument(a)) value = attrs[++i];

        switch (a) {
        case kCGLPFADoubleBuffer:
            out[n++] = EGL_RENDER_BUFFER; out[n++] = EGL_BACK_BUFFER;
            break;
        case kCGLPFAColorSize:
            out[n++] = EGL_RED_SIZE; out[n++] = value;
            out[n++] = EGL_GREEN_SIZE; out[n++] = value;
            out[n++] = EGL_BLUE_SIZE; out[n++] = value;
            break;
        case kCGLPFAAlphaSize:
            out[n++] = EGL_ALPHA_SIZE; out[n++] = value;
            break;
        case kCGLPFADepthSize:
            out[n++] = EGL_DEPTH_SIZE; out[n++] = value;
            break;
        case kCGLPFAStencilSize:
            out[n++] = EGL_STENCIL_SIZE; out[n++] = value;
            break;
        case kCGLPFASamples:
        case kCGLPFAMultisample:
            if (a == kCGLPFAMultisample && value == 0) break;
            out[n++] = EGL_SAMPLES; out[n++] = value > 0 ? value : 1;
            break;
        case kCGLPFAAuxBuffers:
            // No core EGL attribute for aux buffers; ignored deliberately.
            break;
        case kCGLPFAColorFloat:
            if (value) { out[n++] = EGL_RENDERABLE_TYPE; out[n++] = EGL_OPENGL_BIT; }
            break;
        default:
            break;
        }
    }
    return n;
}

CGLError CGLRegisterNativeDisplay(void *native_display) {

    default_swap_interval = 1;
    display = eglGetDisplay(native_display);

    if (display == EGL_NO_DISPLAY) {
        return kCGLBadConnection;
    }

    eglInitialize(display, NULL, NULL);
    eglChooseConfig(display, attribute_list, &config, 1, &num_config);

    eglBindAPI(EGL_OPENGL_API);

    return kCGLNoError;
}

// Explicit-platform counterpart for backends whose native handles must not be
// interpreted using EGL's process default platform. Keep the X11 entry unchanged.
CGLError CGLRegisterNativeDisplayForPlatform(void *native_display, unsigned int platform) {
    if (!native_display)
        return kCGLBadConnection;
    EGLDisplay candidate = eglGetPlatformDisplay(platform, native_display, NULL);
    if (candidate == EGL_NO_DISPLAY)
        return kCGLBadConnection;
    EGLBoolean initialized = eglInitialize(candidate, NULL, NULL);
    if (!initialized)
        return kCGLBadConnection;
    CGLError error = kCGLBadConnection;
    const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLint count = 0;
    if (!eglChooseConfig(candidate, attributes, NULL, 0, &count) || count <= 0) {
        error = kCGLBadPixelFormat;
        goto reject;
    }
    EGLConfig *configs = calloc((size_t)count, sizeof(*configs));
    if (!configs) {
        error = kCGLBadAlloc;
        goto reject;
    }
    EGLConfig candidate_config = NULL;
    if (eglChooseConfig(candidate, attributes, configs, count, &count)) {
        for (EGLint i = 0; i < count; ++i) {
            EGLint minimum_interval;
            if (eglGetConfigAttrib(candidate, configs[i], EGL_MIN_SWAP_INTERVAL, &minimum_interval) &&
                minimum_interval == 0) {
                candidate_config = configs[i];
                break;
            }
        }
    }
    free(configs);
    if (!candidate_config) {
        error = kCGLBadPixelFormat;
        goto reject;
    }
    if (!eglBindAPI(EGL_OPENGL_API)) {
        error = kCGLBadState;
        goto reject;
    }
    // Publish only a fully initialized display/config pair. A rejected platform
    // must not corrupt an already working backend.
    display = candidate;
    config = candidate_config;
    num_config = count;
    // Layer animations may keep drawing while their parent is hidden. Waiting
    // for a Wayland frame callback on an unmapped surface can block forever.
    default_swap_interval = 0;
    return kCGLNoError;

reject:
    // A failed probe must not leak a newly initialized display. Never terminate
    // the already-published display when a repeated registration probes it.
    if (initialized && candidate != display)
        eglTerminate(candidate);
    return error;
}

static struct _CGLDisplay* getCGLDisplay(CGSConnectionID cid)
{
    struct _CGLDisplay* rv;

    pthread_mutex_lock(&g_displaysMutex);
    rv = (struct _CGLDisplay*) CFDictionaryGetValue(g_displays, (const void*)(unsigned long) cid);
    pthread_mutex_unlock(&g_displaysMutex);

    if (!rv)
    {
        EGLDisplay disp = eglGetDisplay(_CGSNativeDisplay(cid));
        if (disp == EGL_NO_DISPLAY)
            return NULL;

        rv = (struct _CGLDisplay*) malloc(sizeof(*rv));
        rv->display = disp;

        eglInitialize(rv->display, NULL, NULL);
        eglChooseConfig(rv->display, attribute_list, &rv->config, 1, &rv->num_config);

        eglBindAPI(EGL_OPENGL_API);

        pthread_mutex_lock(&g_displaysMutex);
        CFDictionaryAddValue(g_displays, (const void*)(unsigned long) cid, rv);
        pthread_mutex_unlock(&g_displaysMutex);
    }

    return rv;
}

CGLError CGLSetSurface(CGLContextObj gl, CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid)
{
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

    gl->egl_surface = eglCreateWindowSurface(disp->display, disp->config, window, NULL);
    if (gl->egl_surface == EGL_NO_SURFACE)
        return kCGLBadState;
    return kCGLNoError;
}

CGLWindowRef CGLGetWindow(void *native_window) {

    EGLNativeWindowType window = (EGLNativeWindowType) native_window;
    // Prefer the current context's config: eglMakeCurrent fails with EGL_BAD_MATCH if the
    // drawable's config differs from the context's, so the surface has to be created with
    // whichever config the context was actually built from. Fall back to the process-global
    // config when no context is current, which is the previous behaviour.
    EGLConfig surface_config = config;
    CGLContextObj current = CGLGetCurrentContext();
    if (current != NULL && current->egl_config != NULL) {
        surface_config = current->egl_config;
    }
    EGLSurface surface = eglCreateWindowSurface(display, surface_config, window, NULL);

    if (surface == EGL_NO_SURFACE) {
        // Callers only see a NULL drawable, which they report as
        // kCGLBadDrawable without saying why, so "EGL refused this window" and
        // "no window handle was passed" look identical from outside. Report the
        // EGL reason once rather than on every attempt.
        static int reported;
        if (!__sync_lock_test_and_set(&reported, 1))
            fprintf(stderr, "CGLGetWindow: eglCreateWindowSurface failed for "
                    "window %p, eglGetError 0x%x\n", native_window, eglGetError());
        return NULL;
    }

    return (CGLWindowRef) surface;
}

CGL_EXPORT void CGLDestroyWindow(CGLWindowRef window) {
    eglDestroySurface(display, (EGLSurface) window);
}

CGL_EXPORT CGLError CGLContextMakeCurrentAndAttachToWindow(CGLContextObj context, CGLWindowRef window) {
    if (!context)
        return kCGLBadContext;
    if (!window)
        return kCGLBadDrawable;
    EGLSurface previous_surface = context->egl_surface;
    context->egl_surface = (EGLSurface) window;
    CGLError error = CGLSetCurrentContext(context);
    if (error != kCGLNoError)
        context->egl_surface = previous_surface;
    return error;
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

CGLError CGLSetCurrentContext(CGLContextObj context) {
    if (context != NULL) {
        EGLSurface surface = context->egl_surface;
        if (!eglMakeCurrent(display, surface, surface, context->egl_context))
            return kCGLBadContext;
        // A context can only be made current on a drawable built from the same config; eglMakeCurrent
        // rejects a mismatch with EGL_BAD_MATCH. The CGL entry points give callers no way to see which
        // config anything resolved to, so report the first mismatch here, after the make-current,
        // which is the point where both handles are known usable.
        if (surface != EGL_NO_SURFACE) {
            static int reported;
            EGLint ctx_id = -1, surf_id = -1;
            if (!__sync_lock_test_and_set(&reported, 1) &&
                eglQueryContext(display, context->egl_context, EGL_CONFIG_ID, &ctx_id) &&
                eglQuerySurface(display, surface, EGL_CONFIG_ID, &surf_id) &&
                ctx_id != surf_id) {
                fprintf(stderr, "CGL: drawable config %d differs from context config %d\n",
                        surf_id, ctx_id);
            }
        }
        pthread_setspecific(get_current_context_key(), context);
        if (surface != EGL_NO_SURFACE && !eglSwapInterval(display, context->swap_interval))
            return kCGLBadValue;
    } else {
        if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT))
            return kCGLBadContext;
        pthread_setspecific(get_current_context_key(), NULL);
    }
    return kCGLNoError;
}

CGLError CGLEnable(CGLContextObj ctx, CGLContextEnable pname) {
    return kCGLNoError;
}

CGLError CGLDisable(CGLContextObj ctx, CGLContextEnable pname) {
    return kCGLNoError;
}

CGLError CGLIsEnabled(CGLContextObj ctx, CGLContextEnable pname, GLint *enable) {
    if (enable) *enable = 0;
    return kCGLNoError;
}

const char *CGLErrorString(CGLError error) {
    switch (error) {
    case kCGLNoError: return "no error";
    case kCGLBadAttribute: return "invalid pixel format attribute";
    case kCGLBadProperty: return "invalid renderer property";
    case kCGLBadPixelFormat: return "invalid pixel format";
    case kCGLBadRendererInfo: return "invalid renderer info";
    case kCGLBadContext: return "invalid context";
    case kCGLBadDrawable: return "invalid drawable";
    case kCGLBadDisplay: return "invalid display";
    case kCGLBadState: return "invalid context state";
    case kCGLBadValue: return "invalid numerical value";
    case kCGLBadMatch: return "invalid share context";
    case kCGLBadEnumeration: return "invalid enumerant";
    case kCGLBadOffScreen: return "invalid offscreen drawable";
    case kCGLBadFullScreen: return "invalid fullscreen drawable";
    case kCGLBadWindow: return "invalid window";
    case kCGLBadAddress: return "invalid pointer";
    case kCGLBadCodeModule: return "invalid code module";
    case kCGLBadAlloc: return "memory allocation failure";
    case kCGLBadConnection: return "invalid CoreGraphics connection";
    default: return "unknown error";
    }
}

CGLError CGLTexImageIOSurface2D(CGLContextObj ctx, GLenum target, GLenum internal_format,
                                GLsizei width, GLsizei height, GLenum format, GLenum type,
                                void *ioSurface, GLuint plane)
{
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
    CGLPixelFormatObj format = malloc(sizeof(struct _CGLPixelFormatObj));
    int count = attributes_count(attrs);

    format->egl_config = NULL;
    format->retain_count = 1;
    format->attributes = malloc(sizeof(CGLPixelFormatAttribute) * count);
    for (int i = 0; i < count; i++) {
        format->attributes[i] = attrs[i];
    }

    // Resolve the request against the current display. Fall back to the process-global
    // config when nothing matches, so an unsatisfiable request degrades to the old
    // behaviour instead of failing to produce a drawable at all.
    if (display != EGL_NO_DISPLAY && display != NULL) {
        EGLint egl_attrs[64];
        int n = cgl_attributes_to_egl(format->attributes, egl_attrs, 64);
        EGLint found = 0;
        if (n > 0 && eglChooseConfig(display, egl_attrs, NULL, 0, &found) && found > 0) {
            EGLConfig *configs = calloc((size_t)found, sizeof(*configs));
            if (configs != NULL) {
                if (eglChooseConfig(display, egl_attrs, configs, found, &found)) {
                    format->egl_config = configs[0];
                }
                free(configs);
            }
        }
    }
    if (format->egl_config == NULL) {
        format->egl_config = config;
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

CGLError CGLUpdateContext(CGLContextObj ctx)
{
    return kCGLNoError;
}

CGLError CGLDescribePixelFormat(
    CGLPixelFormatObj format,
    GLint sreen_num,
    CGLPixelFormatAttribute attr,
    GLint *value
) {
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

    if (resultp == NULL)
        return kCGLBadAddress;
    *resultp = NULL;

    EGLContext egl_share = EGL_NO_CONTEXT;
    if (share != NULL) {
        egl_share = share->egl_context;
    }
    // Honour the format the caller actually asked for. This used to always use the
    // process-global config, which made every app's pixel-format attributes dead letters.
    EGLConfig context_config = pixelFormat != NULL && pixelFormat->egl_config != NULL
        ? pixelFormat->egl_config
        : config;
    EGLContext egl_context = eglCreateContext(display, context_config, egl_share, NULL);

    if (egl_context == EGL_NO_CONTEXT) {
        return kCGLBadContext;
    }

    CGLContextObj context = malloc(sizeof(struct _CGLContextObj));

    if (context == NULL) {
        eglDestroyContext(display, egl_context);
        return kCGLBadAlloc;
    }

    context->retain_count = 1;
    pthread_mutex_init(&(context->lock), NULL);
    context->egl_context = egl_context;
    context->egl_surface = NULL;
    context->egl_config = context_config;
    context->swap_interval = default_swap_interval;

    *resultp = context;

    return kCGLNoError;
}

CGLContextObj CGLRetainContext(CGLContextObj context) {
    if (context == NULL) {
        return NULL;
    }

    context->retain_count++;
    return context;
}

void CGLReleaseContext(CGLContextObj context) {
    if (context == NULL) {
        return;
    }

    if (CGLGetCurrentContext() == context) {
        // Do not free a context while EGL/TLS still identify it as current.
        // A failed unbind leaves ownership with the caller for a later retry.
        if (CGLSetCurrentContext(NULL) != kCGLNoError)
            return;
    }

    context->retain_count--;

    if (context->retain_count != 0) {
        return;
    }

    pthread_mutex_destroy(&(context->lock));

    eglDestroyContext(display, context->egl_context);

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

CGLError CGLFlushDrawable(CGLContextObj context) {
    if (context == NULL)
        return kCGLBadContext;
    if (context->egl_surface == EGL_NO_SURFACE)
        return kCGLBadDrawable;
    return eglSwapBuffers(display, context->egl_surface) ? kCGLNoError : kCGLBadDrawable;
}

CGLError CGLSetParameter(CGLContextObj context, CGLContextParameter parameter, const GLint *value) {
    if (!value)
        return kCGLBadAddress;

    if (parameter == kCGLCPSwapInterval)
    {
        GLint v = *value;
        EGLBoolean success = eglSwapInterval(display, v);
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

CGLError CGLDescribeRenderer(CGLRendererInfoObj rend, long rend_num, CGLRendererProperty prop, long *value) {
    return kCGLNoError;
}

CGLError CGLQueryRendererInfo(unsigned long display_mask, CGLRendererInfoObj *rend, long *nrend) {
    return kCGLNoError;
}

CGLError CGLDestroyRendererInfo(CGLRendererInfoObj rend) {
    return kCGLNoError;
}
