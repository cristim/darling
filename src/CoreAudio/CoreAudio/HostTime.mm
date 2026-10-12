#include "CoreAudio/HostTime.h"
#include "stub.h"
#include <mach/mach_time.h>

#ifdef __cplusplus
extern "C" {
#endif

UInt64 AudioGetCurrentHostTime(void)
{
    return mach_absolute_time();
}

UInt64 AudioConvertHostTimeToNanos(UInt64 inHostTime)
{
    static mach_timebase_info_data_t sTimebase = { 0, 0 };
    if (sTimebase.denom == 0)
        (void)mach_timebase_info(&sTimebase);
    return inHostTime * sTimebase.numer / sTimebase.denom;
}

UInt64 AudioConvertNanosToHostTime(UInt64 inNanos)
{
    static mach_timebase_info_data_t sTimebase = { 0, 0 };
    if (sTimebase.denom == 0)
        (void)mach_timebase_info(&sTimebase);
    return inNanos * sTimebase.denom / sTimebase.numer;
}

#ifdef __cplusplus
}
#endif
