#ifdef __APPLE__
#import <Foundation/Foundation.h>
#endif
#import <OpenGL/OpenGL.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef CGL_MOCK_EGL
#include <OpenGL/CGLInternal.h>
#include <pthread.h>
#ifdef __APPLE__
#undef APPLE
#undef __APPLE__
#define __unix__
#define CGL_RESTORE_APPLE 1
#endif
#define EGL_NO_X11
#include <EGL/egl.h>
#ifdef CGL_RESTORE_APPLE
#define APPLE
#define __APPLE__
#undef CGL_RESTORE_APPLE
#endif

#ifndef __APPLE__
CFMutableDictionaryRef CFDictionaryCreateMutable(void *a, long c, const void *k, const void *v) { (void)a; (void)c; (void)k; (void)v; return (CFMutableDictionaryRef)(uintptr_t)0x1; }
const void *CFDictionaryGetValue(CFDictionaryRef d, const void *k) { (void)d; (void)k; return NULL; }
void CFDictionaryAddValue(CFMutableDictionaryRef d, const void *k, const void *v) { (void)d; (void)k; (void)v; }
void *_CGSNativeDisplay(CGSConnectionID cid) { (void)cid; return NULL; }
void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid) { (void)cid; (void)wid; return NULL; }
void *_CGSNativeWindowForSurfaceID(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid) { (void)cid; (void)wid; (void)sid; return NULL; }
#endif

static int mock_race_go;
static int mock_fail_make_current;
static int mock_fail_swap_interval;
static int mock_make_current_calls;
static int mock_destroyed_contexts;
static uintptr_t mock_next_context_id;
static EGLSurface mock_current_surface;
static EGLContext mock_current_context;
static EGLSurface mock_last_swapped_surface;

EGLAPI EGLDisplay EGLAPIENTRY eglGetDisplay(EGLNativeDisplayType display_id) {
    return display_id ? (EGLDisplay)display_id : EGL_NO_DISPLAY;
}

EGLAPI EGLDisplay EGLAPIENTRY eglGetPlatformDisplay(EGLenum platform, void *native_display, const EGLAttrib *attrib_list) {
    (void)platform;
    (void)attrib_list;
    return native_display ? (EGLDisplay)native_display : EGL_NO_DISPLAY;
}

EGLAPI EGLBoolean EGLAPIENTRY eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor) {
    (void)major;
    (void)minor;
    return dpy != EGL_NO_DISPLAY ? EGL_TRUE : EGL_FALSE;
}

EGLAPI EGLBoolean EGLAPIENTRY eglChooseConfig(EGLDisplay dpy, const EGLint *attrib_list, EGLConfig *configs, EGLint config_size, EGLint *num_config) {
    (void)attrib_list;
    if (dpy == EGL_NO_DISPLAY || !num_config)
        return EGL_FALSE;
    *num_config = 1;
    if (configs && config_size > 0)
        configs[0] = (EGLConfig)(uintptr_t)0x10;
    return EGL_TRUE;
}

EGLAPI EGLBoolean EGLAPIENTRY eglGetConfigAttrib(EGLDisplay dpy, EGLConfig config, EGLint attribute, EGLint *value) {
    (void)config;
    (void)attribute;
    if (dpy == EGL_NO_DISPLAY || !value)
        return EGL_FALSE;
    *value = 0;
    return EGL_TRUE;
}

EGLAPI EGLBoolean EGLAPIENTRY eglBindAPI(EGLenum api) {
    (void)api;
    return EGL_TRUE;
}

EGLAPI EGLBoolean EGLAPIENTRY eglTerminate(EGLDisplay dpy) {
    return dpy != EGL_NO_DISPLAY ? EGL_TRUE : EGL_FALSE;
}

EGLAPI EGLSurface EGLAPIENTRY eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint *attrib_list) {
    (void)config;
    (void)attrib_list;
    if (dpy == EGL_NO_DISPLAY || !win)
        return EGL_NO_SURFACE;
    return (EGLSurface)win;
}

EGLAPI EGLBoolean EGLAPIENTRY eglDestroySurface(EGLDisplay dpy, EGLSurface surface) {
    (void)surface;
    return dpy != EGL_NO_DISPLAY ? EGL_TRUE : EGL_FALSE;
}

EGLAPI EGLContext EGLAPIENTRY eglCreateContext(EGLDisplay dpy, EGLConfig config, EGLContext share_context, const EGLint *attrib_list) {
    (void)config;
    (void)share_context;
    (void)attrib_list;
    if (dpy == EGL_NO_DISPLAY)
        return EGL_NO_CONTEXT;
    return (EGLContext)(++mock_next_context_id);
}

EGLAPI EGLBoolean EGLAPIENTRY eglDestroyContext(EGLDisplay dpy, EGLContext ctx) {
    if (dpy == EGL_NO_DISPLAY || ctx == EGL_NO_CONTEXT)
        return EGL_FALSE;
    mock_destroyed_contexts++;
    return EGL_TRUE;
}

EGLAPI EGLBoolean EGLAPIENTRY eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx) {
    (void)read;
    mock_make_current_calls++;
    if (dpy == EGL_NO_DISPLAY)
        return EGL_FALSE;
    if (mock_fail_make_current == 1 || (mock_fail_make_current == 2 && ctx == EGL_NO_CONTEXT))
        return EGL_FALSE;
    mock_current_surface = draw;
    mock_current_context = ctx;
    return EGL_TRUE;
}

EGLAPI EGLBoolean EGLAPIENTRY eglSwapInterval(EGLDisplay dpy, EGLint interval) {
    (void)interval;
    if (dpy == EGL_NO_DISPLAY || mock_fail_swap_interval)
        return EGL_FALSE;
    return EGL_TRUE;
}

EGLAPI EGLBoolean EGLAPIENTRY eglSwapBuffers(EGLDisplay dpy, EGLSurface surface) {
    mock_last_swapped_surface = surface;
    return (dpy != EGL_NO_DISPLAY && surface != EGL_NO_SURFACE && surface == mock_current_surface) ? EGL_TRUE : EGL_FALSE;
}

static void *mock_release_worker(void *arg) {
    while (!__atomic_load_n(&mock_race_go, __ATOMIC_ACQUIRE)) {}
    CGLReleaseContext((CGLContextObj)arg);
    return NULL;
}

static int run_mock_lifecycle_checks(void) {
    int failures = 0;
    CGLError error = CGLRegisterNativeDisplay((void *)(uintptr_t)0x1);
    if (error != kCGLNoError) {
        printf("register display error=%d\n", error);
        return 1;
    }

    CGLContextObj ctx1 = NULL;
    error = CGLCreateContext(NULL, NULL, &ctx1);
    if (error != kCGLNoError || ctx1 == NULL) {
        printf("mock create ctx1 error=%d\n", error);
        return 1;
    }

    CGLWindowRef win1 = (CGLWindowRef)(uintptr_t)0x101;
    CGLWindowRef win2 = (CGLWindowRef)(uintptr_t)0x102;

    mock_fail_swap_interval = 1;
    mock_last_swapped_surface = EGL_NO_SURFACE;
    error = CGLContextMakeCurrentAndAttachToWindow(ctx1, win1);
    CGLError flush_error = CGLFlushDrawable(ctx1);
    int swap_fail_initial_ok = (error == kCGLBadValue && CGLGetCurrentContext() == ctx1 &&
        flush_error == kCGLNoError && mock_last_swapped_surface == (EGLSurface)win1);
    printf("attach initial swap-interval-fail error=%d flush=%d surface_synced=%d\n",
        error, flush_error, mock_last_swapped_surface == (EGLSurface)win1);
    failures += !swap_fail_initial_ok;

    mock_fail_swap_interval = 0;
    (void)CGLContextMakeCurrentAndAttachToWindow(ctx1, win1);

    mock_fail_make_current = 1;
    mock_last_swapped_surface = EGL_NO_SURFACE;
    error = CGLContextMakeCurrentAndAttachToWindow(ctx1, win2);
    mock_fail_make_current = 0;
    flush_error = CGLFlushDrawable(ctx1);
    int make_current_rollback_ok = (error == kCGLBadContext &&
        flush_error == kCGLNoError && mock_last_swapped_surface == (EGLSurface)win1);
    printf("attach make-current-fail error=%d flush=%d restored_prev=%d\n",
        error, flush_error, mock_last_swapped_surface == (EGLSurface)win1);
    failures += !make_current_rollback_ok;

    mock_fail_swap_interval = 1;
    mock_last_swapped_surface = EGL_NO_SURFACE;
    error = CGLContextMakeCurrentAndAttachToWindow(ctx1, win2);
    mock_fail_swap_interval = 0;
    flush_error = CGLFlushDrawable(ctx1);
    int swap_fail_rebind_ok = (error == kCGLBadValue &&
        flush_error == kCGLNoError && mock_last_swapped_surface == (EGLSurface)win2);
    printf("attach rebind swap-interval-fail error=%d flush=%d surface_synced=%d\n",
        error, flush_error, mock_last_swapped_surface == (EGLSurface)win2);
    failures += !swap_fail_rebind_ok;

    CGLReleaseContext(ctx1);

    mock_destroyed_contexts = 0;
    CGLContextObj ctx2 = NULL;
    error = CGLCreateContext(NULL, NULL, &ctx2);
    if (error != kCGLNoError || ctx2 == NULL) {
        printf("mock create ctx2 error=%d\n", error);
        return failures + 1;
    }

    (void)CGLSetCurrentContext(ctx2);
    (void)CGLRetainContext(ctx2);
    (void)CGLRetainContext(ctx2);

    int calls_before = mock_make_current_calls;
    CGLReleaseContext(ctx2);
    int release_3_to_2_ok = (CGLGetContextRetainCount(ctx2) == 2 &&
        CGLGetCurrentContext() == ctx2 &&
        mock_current_context != EGL_NO_CONTEXT &&
        mock_make_current_calls == calls_before &&
        mock_destroyed_contexts == 0);
    printf("intermediate release (3->2) retain=%u kept_current=%d make_current_delta=%d\n",
        CGLGetContextRetainCount(ctx2), CGLGetCurrentContext() == ctx2,
        mock_make_current_calls - calls_before);
    failures += !release_3_to_2_ok;

    if (CGLGetCurrentContext() != ctx2)
        (void)CGLSetCurrentContext(ctx2);

    mock_fail_make_current = 2;
    calls_before = mock_make_current_calls;
    CGLReleaseContext(ctx2);
    mock_fail_make_current = 0;
    int release_2_to_1_ok = (CGLGetContextRetainCount(ctx2) == 1 &&
        CGLGetCurrentContext() == ctx2 &&
        mock_make_current_calls == calls_before &&
        mock_destroyed_contexts == 0);
    printf("intermediate release (2->1 unbind-blocked) retain=%u kept_current=%d make_current_delta=%d\n",
        CGLGetContextRetainCount(ctx2), CGLGetCurrentContext() == ctx2,
        mock_make_current_calls - calls_before);
    failures += !release_2_to_1_ok;

    while (CGLGetContextRetainCount(ctx2) > 1)
        CGLReleaseContext(ctx2);
    if (CGLGetCurrentContext() != ctx2)
        (void)CGLSetCurrentContext(ctx2);

    mock_fail_make_current = 2;
    CGLReleaseContext(ctx2);
    CGLError destroy_err = CGLDestroyContext(ctx2);
    mock_fail_make_current = 0;
    int final_unbind_fail_ok = (destroy_err == kCGLBadContext &&
        CGLGetContextRetainCount(ctx2) == 1 &&
        CGLGetCurrentContext() == ctx2 &&
        mock_destroyed_contexts == 0);
    printf("final release/destroy unbind-fail err=%d retain=%u kept_current=%d destroyed=%d\n",
        destroy_err, CGLGetContextRetainCount(ctx2), CGLGetCurrentContext() == ctx2, mock_destroyed_contexts);
    failures += !final_unbind_fail_ok;

    destroy_err = CGLDestroyContext(ctx2);
    int final_release_ok = (destroy_err == kCGLNoError &&
        CGLGetCurrentContext() == NULL &&
        mock_current_context == EGL_NO_CONTEXT &&
        mock_destroyed_contexts == 1);
    printf("final destroy ok err=%d cleared_current=%d egl_unbound=%d destroyed=%d\n",
        destroy_err, CGLGetCurrentContext() == NULL, mock_current_context == EGL_NO_CONTEXT, mock_destroyed_contexts);
    failures += !final_release_ok;

    int race_failures = 0;
    for (int iter = 0; iter < 64; ++iter) {
        mock_destroyed_contexts = 0;
        CGLContextObj ctx3 = NULL;
        if (CGLCreateContext(NULL, NULL, &ctx3) != kCGLNoError || !ctx3)
            return failures + 1;
        (void)CGLRetainContext(ctx3);
        __atomic_store_n(&mock_race_go, 0, __ATOMIC_RELAXED);
        pthread_t t1, t2;
        pthread_create(&t1, NULL, mock_release_worker, ctx3);
        pthread_create(&t2, NULL, mock_release_worker, ctx3);
        __atomic_store_n(&mock_race_go, 1, __ATOMIC_RELEASE);
        pthread_join(t1, NULL);
        pthread_join(t2, NULL);
        if (mock_destroyed_contexts != 1) {
            race_failures++;
            break;
        }
    }
    printf("concurrent release checks=64 failures=%d\n", race_failures);
    failures += race_failures;

    return failures;
}
#endif

static int run_checks(int argc, char **argv) {
    if (argc>1 && strcmp(argv[1],"flush")==0) {
        CGLError error=CGLFlushDrawable(NULL);
        printf("null flush error=%d expected=%d\n",error,kCGLBadContext);
        return error!=kCGLBadContext;
    }
    CGLContextObj context=(CGLContextObj)(uintptr_t)1;
    CGLError error=CGLCreateContext(NULL,NULL,&context);
    int failures=(error!=kCGLBadContext || context!=NULL);
    printf("no-display create error=%d cleared=%d\n",error,context==NULL);
    error=CGLCreateContext(NULL,NULL,NULL);
    failures+=(error!=kCGLBadAddress);
    printf("null output error=%d expected=%d\n",error,kCGLBadAddress);
    printf("creation checks=2 failures=%d\n",failures);
    error=CGLDestroyContext(NULL);
    failures+=(error!=kCGLBadContext);
    printf("null destroy error=%d expected=%d\n",error,kCGLBadContext);
#ifdef CGL_MOCK_EGL
    failures += run_mock_lifecycle_checks();
    printf("total failures=%d\n", failures);
#endif
    return failures!=0;
}

int main(int argc,char **argv) {
#ifdef __APPLE__
    @autoreleasepool {
        return run_checks(argc, argv);
    }
#else
    return run_checks(argc, argv);
#endif
}
