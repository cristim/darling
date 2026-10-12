#ifndef DARLING_NATIVE_PRESENT_H
#define DARLING_NATIVE_PRESENT_H
#include <stdint.h>
#define DARLING_NATIVE_PRESENT_MAGIC 0x47505532u
/* Host X11 target metadata only; no pixels, input, or account information. */
typedef struct {
 uint32_t magic,target,width,height;
 uint32_t ready,presenter,sequence,visual;
 uint32_t flags,reserved[7];
} DarlingNativePresentTarget;
#endif
