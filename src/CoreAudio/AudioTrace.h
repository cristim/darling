#ifndef RCLOL_AUDIO_TRACE_H
#define RCLOL_AUDIO_TRACE_H
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <ctime>
#include <atomic>
#include <unistd.h>
// Opt-in API/status diagnostics only; never records audio samples or names.
// Enabled by env RCLOL_AUDIO_TRACE or by the existence of /tmp/rclol-audio-trace
// or /Users/Shared/rclol-audio-trace (the latter survives /tmp wipes at launch).
// A negative result is re-checked at most once every ~2 seconds; a positive
// result is cached for the life of the process.
static inline bool rclolAudioTraceEnabled() {
    static std::atomic<bool> enabled{false};
    static std::atomic<long long> nextCheckMs{0};
    if (enabled.load(std::memory_order_relaxed)) return true;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    long long nowMs = (long long) ts.tv_sec * 1000 + ts.tv_nsec / 1000000 + 1;
    if (nowMs < nextCheckMs.load(std::memory_order_relaxed)) return false;
    nextCheckMs.store(nowMs + 2000, std::memory_order_relaxed);
    if (getenv("RCLOL_AUDIO_TRACE") != nullptr ||
        access("/tmp/rclol-audio-trace", F_OK) == 0 ||
        access("/Users/Shared/rclol-audio-trace", F_OK) == 0) {
        enabled.store(true, std::memory_order_relaxed);
        return true;
    }
    return false;
}
static inline void rclolAudioTrace(const char* format, ...) {
    if (!rclolAudioTraceEnabled()) return;
    static FILE* file=[] { FILE* f=fopen("/tmp/rclol-audio-api.log","a"); if(f) setvbuf(f,nullptr,_IOLBF,0); return f; }();
    if(!file) return;
    va_list args;va_start(args,format);fprintf(file,"pid=%d ",getpid());vfprintf(file,format,args);va_end(args);
}
#endif
