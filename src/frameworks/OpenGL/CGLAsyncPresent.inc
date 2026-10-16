/* Bounded GPU-only staging: the producer never waits for display cadence.
 * Three textures cover the currently displayed, pending, and writing frames.
 * GPU fences order both the completed producer copy and subsequent reuse. */
struct DarlingAsyncPresent {
    CGLContextObj owner;
    pthread_mutex_t mutex;
    pthread_t thread;
    int started, running, failed, displayed;
    unsigned width, height;
    GLuint textures[3], copy_fbos[2];
    int state[3]; /* 0 free, 1 pending, 2 display, 3 producer writing */
    GLsync produced[3], consumed[3];
    unsigned submissions, frames;
    uint64_t serial[3];
};
static uint64_t nativeMonotonicNS(void) {
    struct timespec now;
    if(__lolsys_syscall(1,(long)&now,0,0,0,0,228))return 0;
    return (uint64_t)now.tv_sec*1000000000ull+now.tv_nsec;
}
static void nativeWaitUntil(uint64_t deadline) {
    struct timespec wake={deadline/1000000000ull,deadline%1000000000ull};
    while(__lolsys_syscall(1,1,(long)&wake,0,0,0,230)==-4){}
}
static void *asyncPresentWorker(void *opaque) {
    struct DarlingAsyncPresent *a=opaque;
    CGLContextObj ctx=a->owner;
    int valid=p_eglBindAPI(EGL_OPENGL_API) && p_eglMakeCurrent(ctx->egl_display,
        ctx->native_present_surface,ctx->native_present_surface,ctx->native_present_context);
    GLuint fbo=0;
    if(getenv("RCLOL_GPU_DIRECT_TRACE"))fprintf(stderr,"GPU_ASYNC worker_context=%d\n",valid);
    /* The async context can wait for native VSync without blocking the
     * Chromium producer. Keep the monotonic limiter as a fallback/bound. */
    int nativeVSync=0;
    unsigned slowNativeSwaps=0;
    if(valid){
        const char *vsync=getenv("RCLOL_GPU_DIRECT_VSYNC");
        nativeVSync=vsync && vsync[0]=='1' && p_eglSwapInterval(ctx->egl_display,1);
        if(!nativeVSync)p_eglSwapInterval(ctx->egl_display,0);
        glGenFramebuffers(1,&fbo);
    }
    uint64_t deadline=nativeMonotonicNS();
    for(;;){
        pthread_mutex_lock(&a->mutex);
        int running=a->running,index=-1;
        GLsync produced=NULL;
        if(running && valid){
            for(int n=0;n<3;++n)if(a->state[n]==1 && a->produced[n] && (a->displayed<0 || a->serial[n]>a->serial[a->displayed])){
                GLenum ready=glClientWaitSync(a->produced[n],0,0);
                if(ready==GL_WAIT_FAILED){valid=0;break;}
                if((ready==GL_ALREADY_SIGNALED || ready==GL_CONDITION_SATISFIED) &&
                   (index<0 || a->serial[n]>a->serial[index]))index=n;
            }
            if(valid && index>=0){
                for(int n=0;n<3;++n)if(a->state[n]==1 && a->serial[n]<a->serial[index])a->state[n]=0;
                a->state[index]=2;produced=a->produced[index];a->produced[index]=NULL;
            }
        }
        pthread_mutex_unlock(&a->mutex);
        if(!running || !valid)break;
        DarlingNativePresentTarget *target=ctx->native_present_target;
        if(!target || __atomic_load_n(&target->magic,__ATOMIC_ACQUIRE)!=DARLING_NATIVE_PRESENT_MAGIC || target->target!=ctx->native_present_window){if(produced)glDeleteSync(produced);valid=0;break;}
        if(index>=0){
            uint64_t workStarted=nativeMonotonicNS();
            if(produced){glWaitSync(produced,0,GL_TIMEOUT_IGNORED);glDeleteSync(produced);}
            glBindFramebuffer(GL_READ_FRAMEBUFFER,fbo);
            glFramebufferTexture2D(GL_READ_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,a->textures[index],0);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER,0);glDrawBuffer(GL_BACK);glReadBuffer(GL_COLOR_ATTACHMENT0);
            glDisable(GL_SCISSOR_TEST);glDisable(GL_FRAMEBUFFER_SRGB);
            if(glCheckFramebufferStatus(GL_READ_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE){valid=0;break;}
            glBlitFramebuffer(0,a->height,a->width,0,0,0,a->width,a->height,GL_COLOR_BUFFER_BIT,GL_NEAREST);
            GLsync consumed=glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0);glFlush();
            int swapped=consumed && glGetError()==GL_NO_ERROR && p_eglSwapBuffers(ctx->egl_display,ctx->native_present_surface);
            uint64_t workFinished=nativeMonotonicNS();
            /* Xwayland may acknowledge interval 1 but throttle an occluded
             * surface to one swap per second. Two consecutive long swaps
             * select our existing bounded 60 Hz clock for this surface.
             * Keep texture ownership and the producer independent of it. */
            if(nativeVSync && swapped){
                slowNativeSwaps=workFinished-workStarted>=100000000ull?slowNativeSwaps+1:0;
                if(slowNativeSwaps>=2 && p_eglSwapInterval(ctx->egl_display,0)){
                    nativeVSync=0;
                    deadline=workFinished;
                }
            }
            pthread_mutex_lock(&a->mutex);
            a->consumed[index]=consumed;
            if(a->displayed>=0)a->state[a->displayed]=0;
            a->displayed=index;
            if(swapped)++a->frames;
            pthread_mutex_unlock(&a->mutex);
            if(!swapped){valid=0;break;}
            __atomic_store_n(&target->presenter,getpid(),__ATOMIC_RELEASE);
            __atomic_fetch_add(&target->sequence,1,__ATOMIC_RELEASE);
            __atomic_store_n(&target->ready,3,__ATOMIC_RELEASE);
            __atomic_fetch_add(&target->reserved[3],(uint32_t)((workFinished-workStarted)/1000),__ATOMIC_RELAXED);
            __atomic_store_n(&target->reserved[6],nativeVSync?0x544d4732u:0x544d4731u,__ATOMIC_RELEASE);
        }
        /* If the producer finishes just after our refresh deadline, wait for
         * that frame in short increments instead of losing a whole refresh.
         * Only a real swap advances the display clock. */
        if(index<0){__atomic_fetch_add(&target->reserved[1],1,__ATOMIC_RELAXED);nativeWaitUntil(nativeMonotonicNS()+1000000ull);continue;}
        /* Native VSync owns the refresh cadence; avoid a second clock that
         * can miss the compositor's next refresh after a variable swap wait. */
        if(nativeVSync)continue;
        /* darling-lol perf: use dynamic refresh interval from RCLOL_REFRESH_HZ
         * or default to uncapped (1ms minimum interval) when VSync is off. */
        static uint64_t refreshNS = 0;
        if (!refreshNS) {
            const char *hz = getenv("RCLOL_REFRESH_HZ");
            int rate = hz ? atoi(hz) : 0;
            refreshNS = (rate > 0 && rate <= 1000) ? 1000000000ull / (uint64_t)rate : 1000000ull;
            if (refreshNS < 1000000ull) refreshNS = 1000000ull;
        }
        deadline += refreshNS;
        uint64_t now=nativeMonotonicNS();
        /* Preserve the refresh phase across small scheduling delays. Reset only
         * after a full missed period, so lateness does not accumulate as drift. */
        if(now>deadline && now-deadline>refreshNS){__atomic_fetch_add(&target->reserved[2],1,__ATOMIC_RELAXED);deadline=now;}
        nativeWaitUntil(deadline);
    }
    if(fbo)glDeleteFramebuffers(1,&fbo);
    p_eglMakeCurrent(ctx->egl_display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
    pthread_mutex_lock(&a->mutex);a->failed=!valid;a->running=0;pthread_mutex_unlock(&a->mutex);
    if(ctx->native_present_target)__atomic_store_n(&ctx->native_present_target->ready,0,__ATOMIC_RELEASE);
    return NULL;
}
static void stopAsyncPresent(CGLContextObj ctx) {
    struct DarlingAsyncPresent *a=ctx->native_async;
    if(!a)return;
    pthread_mutex_lock(&a->mutex);a->running=0;pthread_mutex_unlock(&a->mutex);
    if(a->started)pthread_join(a->thread,NULL);
    CGLContextObj previous=CGLGetCurrentContext();
    if(p_eglMakeCurrent(ctx->egl_display,ctx->egl_surface,ctx->egl_surface,ctx->egl_context)){
        for(int n=0;n<3;++n){if(a->produced[n])glDeleteSync(a->produced[n]);if(a->consumed[n])glDeleteSync(a->consumed[n]);}
        glDeleteFramebuffers(2,a->copy_fbos);glDeleteTextures(3,a->textures);
        if(previous && previous!=ctx)p_eglMakeCurrent(previous->egl_display,previous->egl_surface,previous->egl_surface,previous->egl_context);
        else if(!previous)p_eglMakeCurrent(ctx->egl_display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
    }
    pthread_mutex_destroy(&a->mutex);free(a);ctx->native_async=NULL;
}
static int enqueueAsyncPresent(CGLContextObj ctx,GLuint texture,GLenum textureTarget,unsigned width,unsigned height) {
    struct DarlingAsyncPresent *a=ctx->native_async;
    if(a && (a->width!=width || a->height!=height)){stopAsyncPresent(ctx);a=NULL;}
    if(!a){
        a=calloc(1,sizeof(*a));if(!a)return 0;
        a->owner=ctx;a->width=width;a->height=height;a->displayed=-1;
        pthread_mutex_init(&a->mutex,NULL);
        GLint oldTexture;glGetIntegerv(GL_TEXTURE_BINDING_2D,&oldTexture);
        glGenFramebuffers(2,a->copy_fbos);glGenTextures(3,a->textures);
        for(int n=0;n<3;++n){glBindTexture(GL_TEXTURE_2D,a->textures[n]);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,width,height,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);}
        glBindTexture(GL_TEXTURE_2D,oldTexture);ctx->native_async=a;
        GLenum allocationError=glGetError();if(allocationError!=GL_NO_ERROR){if(getenv("RCLOL_GPU_DIRECT_TRACE"))fprintf(stderr,"GPU_ASYNC allocation_error=%u\n",allocationError);stopAsyncPresent(ctx);return 0;}
        a->running=1;
        pthread_attr_t attr;pthread_attr_init(&attr);pthread_attr_setstacksize(&attr,1024*1024);
        int status=pthread_create(&a->thread,&attr,asyncPresentWorker,a);pthread_attr_destroy(&attr);
        if(getenv("RCLOL_GPU_DIRECT_TRACE"))fprintf(stderr,"GPU_ASYNC worker_create=%d\n",status);
        if(status){stopAsyncPresent(ctx);return 0;}a->started=1;
    }
    pthread_mutex_lock(&a->mutex);
    if(a->failed || !a->running){pthread_mutex_unlock(&a->mutex);return 0;}
    int index=-1;
    for(int n=0;n<3;++n)if(!a->state[n]){index=n;break;}
    /* Keep an older pending frame available to finish while replacing the
     * newest pending frame with fresh producer work. Never touch display slots. */
    if(index<0)for(int n=0;n<3;++n)if(a->state[n]==1 &&
        (index<0 || a->serial[n]>a->serial[index]))index=n;
    if(index<0){pthread_mutex_unlock(&a->mutex);return 0;}
    a->state[index]=3;
    GLsync consumed=a->consumed[index],produced=a->produced[index];
    a->consumed[index]=a->produced[index]=NULL;
    pthread_mutex_unlock(&a->mutex);
    if(consumed){glWaitSync(consumed,0,GL_TIMEOUT_IGNORED);glDeleteSync(consumed);}
    if(produced)glDeleteSync(produced);
    GLint oldRead,oldDraw;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&oldRead);glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&oldDraw);
    GLboolean scissor=glIsEnabled(GL_SCISSOR_TEST),srgb=glIsEnabled(GL_FRAMEBUFFER_SRGB);
    glDisable(GL_SCISSOR_TEST);glDisable(GL_FRAMEBUFFER_SRGB);
    glBindFramebuffer(GL_READ_FRAMEBUFFER,a->copy_fbos[0]);
    glFramebufferTexture2D(GL_READ_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,textureTarget,texture,0);glReadBuffer(GL_COLOR_ATTACHMENT0);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER,a->copy_fbos[1]);
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,a->textures[index],0);glDrawBuffer(GL_COLOR_ATTACHMENT0);
    int complete=glCheckFramebufferStatus(GL_READ_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE && glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
    if(complete)glBlitFramebuffer(0,0,width,height,0,0,width,height,GL_COLOR_BUFFER_BIT,GL_NEAREST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER,oldRead);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,oldDraw);
    if(scissor)glEnable(GL_SCISSOR_TEST);if(srgb)glEnable(GL_FRAMEBUFFER_SRGB);
    produced=glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0);glFlush();
    GLenum copyError=glGetError();
    if(!complete || !produced || copyError!=GL_NO_ERROR){if(getenv("RCLOL_GPU_DIRECT_TRACE"))fprintf(stderr,"GPU_ASYNC copy_error=%u fence=%d\n",copyError,produced!=NULL);if(produced)glDeleteSync(produced);pthread_mutex_lock(&a->mutex);a->state[index]=0;pthread_mutex_unlock(&a->mutex);return 0;}
    pthread_mutex_lock(&a->mutex);
    a->produced[index]=produced;a->state[index]=1;a->serial[index]=++a->submissions;
    if(ctx->native_present_target)__atomic_fetch_add(&ctx->native_present_target->reserved[0],1,__ATOMIC_RELAXED);
    if(ctx->native_present_target){
        __atomic_store_n(&ctx->native_present_target->reserved[4],__atomic_load_n(&nativeUploadCount,__ATOMIC_RELAXED),__ATOMIC_RELAXED);
        __atomic_store_n(&ctx->native_present_target->reserved[5],__atomic_load_n(&nativeUploadMicroseconds,__ATOMIC_RELAXED),__ATOMIC_RELAXED);
    }
    pthread_mutex_unlock(&a->mutex);
    return 1;
}
