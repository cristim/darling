#ifndef RCLOL_AUDIO_TRACE_H
#define RCLOL_AUDIO_TRACE_H
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <unistd.h>
// Opt-in API/status diagnostics only; never records audio samples or names.
static inline void rclolAudioTrace(const char* format, ...) {
    if (!getenv("RCLOL_AUDIO_TRACE")) return;
    static FILE* file=[] { FILE* f=fopen("/tmp/rclol-audio-api.log","a"); if(f) setvbuf(f,nullptr,_IOLBF,0); return f; }();
    if(!file) return;
    va_list args;va_start(args,format);fprintf(file,"pid=%d ",getpid());vfprintf(file,format,args);va_end(args);
}
#endif
