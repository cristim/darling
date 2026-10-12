/* Minimal AudioConverter for Darling's CoreAudio framework.
 *
 * Apple's CoreAudio re-exports these AudioToolbox entry points, and
 * third-party code (e.g. Discord voice) binds them against CoreAudio.
 * AudioToolbox cannot be re-exported here (it depends on CoreAudio),
 * so this TU provides small self-contained implementations:
 *  - format-identical conversion works (direct frame copy);
 *  - anything else returns kAudioConverterErr_InvalidInputSize/
 *    codec-unavailable rather than crashing the caller at bind time.
 */
#include <CoreAudio/CoreAudioTypes.h>
#include <AudioToolbox/AudioConverter.h>
#include <CarbonCore/MacErrors.h>
#include <stdlib.h>
#include <string.h>

struct DarlingAudioConverter {
    AudioStreamBasicDescription src;
    AudioStreamBasicDescription dst;
};

OSStatus AudioConverterNew(const AudioStreamBasicDescription* inSourceFormat,
                           const AudioStreamBasicDescription* inDestinationFormat,
                           AudioConverterRef* outAudioConverter) {
    struct DarlingAudioConverter* c;
    if (!inSourceFormat || !inDestinationFormat || !outAudioConverter)
        return paramErr;
    c = (struct DarlingAudioConverter*)malloc(sizeof(*c));
    if (!c)
        return memFullErr;
    c->src = *inSourceFormat;
    c->dst = *inDestinationFormat;
    *outAudioConverter = (AudioConverterRef)c;
    return noErr;
}

OSStatus AudioConverterDispose(AudioConverterRef inAudioConverter) {
    if (!inAudioConverter)
        return paramErr;
    free(inAudioConverter);
    return noErr;
}

static int asbd_equal(const AudioStreamBasicDescription* a,
                      const AudioStreamBasicDescription* b) {
    return a->mSampleRate == b->mSampleRate &&
           a->mFormatID == b->mFormatID &&
           a->mFormatFlags == b->mFormatFlags &&
           a->mBytesPerPacket == b->mBytesPerPacket &&
           a->mFramesPerPacket == b->mFramesPerPacket &&
           a->mBytesPerFrame == b->mBytesPerFrame &&
           a->mChannelsPerFrame == b->mChannelsPerFrame &&
           a->mBitsPerChannel == b->mBitsPerChannel;
}

OSStatus AudioConverterFillComplexBuffer(AudioConverterRef inAudioConverter,
                                         AudioConverterComplexInputDataProc inInputDataProc,
                                         void* inInputDataProcUserData,
                                         UInt32* ioOutputDataPacketSize,
                                         AudioBufferList* outOutputData,
                                         AudioStreamPacketDescription* outPacketDescription) {
    struct DarlingAudioConverter* c = (struct DarlingAudioConverter*)inAudioConverter;
    AudioBufferList inBuf;
    UInt32 packets, bytes;
    OSStatus st;

    (void)outPacketDescription;
    if (!c || !inInputDataProc || !ioOutputDataPacketSize || !outOutputData)
        return paramErr;
    if (!asbd_equal(&c->src, &c->dst))
        return kAudioConverterErr_UnspecifiedError;
    if (c->src.mBytesPerPacket == 0 || outOutputData->mNumberBuffers < 1)
        return paramErr;

    packets = *ioOutputDataPacketSize;
    bytes = packets * c->src.mBytesPerPacket;
    if (bytes > outOutputData->mBuffers[0].mDataByteSize)
        bytes = outOutputData->mBuffers[0].mDataByteSize;

    inBuf.mNumberBuffers = 1;
    inBuf.mBuffers[0].mNumberChannels = c->src.mChannelsPerFrame;
    inBuf.mBuffers[0].mDataByteSize = bytes;
    inBuf.mBuffers[0].mData = outOutputData->mBuffers[0].mData;
    st = inInputDataProc((AudioConverterRef)c, &packets, &inBuf, NULL, inInputDataProcUserData);
    if (st != noErr)
        return st;
    *ioOutputDataPacketSize = packets;
    outOutputData->mBuffers[0].mDataByteSize = packets * c->dst.mBytesPerPacket;
    return noErr;
}
