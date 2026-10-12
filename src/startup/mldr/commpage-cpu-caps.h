#ifndef MLDR_COMMPAGE_CPU_CAPS_H
#define MLDR_COMMPAGE_CPU_CAPS_H
#include <stdint.h>

/* CPUID leaf 1 uses EDX for legacy SIMD and ECX for newer SIMD. AVX
 * also needs the operating system to save both XMM and YMM state. */
static inline uint64_t commpage_decode_cpu_caps(uint32_t ecx1, uint32_t edx1,
    uint32_t ebx7, uint64_t xcr0, int long_mode)
{
    uint64_t caps = long_mode ? k64Bit : 0;
#define FEATURE(reg, bit, cap) do { if ((reg) & (UINT32_C(1) << (bit))) caps |= (cap); } while (0)
    FEATURE(edx1, 23, kHasMMX);
    FEATURE(edx1, 25, kHasSSE);
    FEATURE(edx1, 26, kHasSSE2);
    FEATURE(ecx1, 0, kHasSSE3);
    FEATURE(ecx1, 9, kHasSupplementalSSE3);
    FEATURE(ecx1, 19, kHasSSE4_1);
    FEATURE(ecx1, 20, kHasSSE4_2);
    FEATURE(ecx1, 25, kHasAES);
    FEATURE(ecx1, 30, kHasRDRAND);
    const uint32_t avx_requirements = (UINT32_C(1) << 26) | (UINT32_C(1) << 27) | (UINT32_C(1) << 28);
    const int avx_usable = (ecx1 & avx_requirements) == avx_requirements && (xcr0 & 6) == 6;
    if (avx_usable) {
        caps |= kHasAVX1_0;
        FEATURE(ecx1, 12, kHasFMA);
        FEATURE(ecx1, 29, kHasF16C);
        FEATURE(ebx7, 5, kHasAVX2_0);
    }
    FEATURE(ebx7, 9, kHasENFSTRG);
    FEATURE(ebx7, 3, kHasBMI1);
    FEATURE(ebx7, 8, kHasBMI2);
    FEATURE(ebx7, 11, kHasRTM);
    FEATURE(ebx7, 4, kHasHLE);
    FEATURE(ebx7, 18, kHasRDSEED);
    FEATURE(ebx7, 19, kHasADX);
    FEATURE(ebx7, 14, kHasMPX);
    FEATURE(ebx7, 2, kHasSGX);
#undef FEATURE
    return caps;
}
#endif
