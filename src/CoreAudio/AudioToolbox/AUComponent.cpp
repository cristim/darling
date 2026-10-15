/*
This file is part of Darling.

Copyright (C) 2020 Lubos Dolezel

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/


#include <AudioToolbox/AUComponent.h>
#include <AudioToolbox/AudioOutputUnit.h>
#include <CarbonCore/MacErrors.h>
#include "ComponentDispatch.h"
#include "../AudioTrace.h"

const CFStringRef kAudioComponentRegistrationsChangedNotification = CFSTR("AudioComponentRegistrationsChangedNotification");
const CFStringRef kAudioComponentInstanceInvalidationNotification = CFSTR("AudioComponentInstanceInvalidationNotification");

OSStatus AudioOutputUnitStart(AudioUnit ci)
{
    OSStatus status = dispatchCall(ci, kAudioOutputUnitStartSelect);
    rclolAudioTrace("UNIT_START unit=%p status=%d\n", (void*) ci, (int) status);
    return status;
}

OSStatus AudioOutputUnitStop(AudioUnit ci)
{
    return dispatchCall(ci, kAudioOutputUnitStopSelect);
}

OSStatus AudioUnitInitialize(AudioUnit inUnit)
{
    OSStatus status = dispatchCall(inUnit, kAudioUnitInitializeSelect);
    rclolAudioTrace("UNIT_INITIALIZE unit=%p status=%d\n", (void*) inUnit, (int) status);
    return status;
}

OSStatus AudioUnitUninitialize(AudioUnit inUnit)
{
    return dispatchCall(inUnit, kAudioUnitUninitializeSelect);
}

OSStatus
AudioUnitGetPropertyInfo(AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    UInt32 * _Nullable outDataSize,
    Boolean * _Nullable outWritable)
{
    OSStatus status = dispatchCall(inUnit, kAudioUnitGetPropertyInfoSelect, inID, inScope, inElement, outDataSize, outWritable);
    rclolAudioTrace("UNIT_PROPINFO unit=%p prop=%u scope=%u elem=%u status=%d\n", (void*) inUnit, (unsigned) inID, (unsigned) inScope, (unsigned) inElement, (int) status);
    return status;
}

OSStatus
AudioUnitGetProperty(AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    void * outData,
    UInt32 * ioDataSize)
{
    OSStatus status = dispatchCall(inUnit, kAudioUnitGetPropertySelect, inID, inScope, inElement, outData, ioDataSize);
    if (inID == 8 && status == noErr && outData && ioDataSize && *ioDataSize >= sizeof(AudioStreamBasicDescription))
    {
        const AudioStreamBasicDescription* d = static_cast<const AudioStreamBasicDescription*>(outData);
        rclolAudioTrace("UNIT_GOT_FORMAT unit=%p scope=%u elem=%u rate=%.0f id=%08x flags=%08x bpf=%u ch=%u bits=%u\n",
            (void*) inUnit, (unsigned) inScope, (unsigned) inElement, d->mSampleRate, (unsigned) d->mFormatID, (unsigned) d->mFormatFlags,
            (unsigned) d->mBytesPerFrame, (unsigned) d->mChannelsPerFrame, (unsigned) d->mBitsPerChannel);
    }
    rclolAudioTrace("UNIT_GET unit=%p prop=%u scope=%u elem=%u status=%d\n", (void*) inUnit, (unsigned) inID, (unsigned) inScope, (unsigned) inElement, (int) status);
    return status;
}

OSStatus
AudioUnitSetProperty(AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    const void * _Nullable inData,
    UInt32 inDataSize)
{
    if (inID == 8 /* kAudioUnitProperty_StreamFormat */ && inData && inDataSize >= sizeof(AudioStreamBasicDescription))
    {
        const AudioStreamBasicDescription* d = static_cast<const AudioStreamBasicDescription*>(inData);
        rclolAudioTrace("UNIT_SET_FORMAT unit=%p scope=%u elem=%u rate=%.0f id=%08x flags=%08x bpp=%u fpp=%u bpf=%u ch=%u bits=%u\n",
            (void*) inUnit, (unsigned) inScope, (unsigned) inElement, d->mSampleRate, (unsigned) d->mFormatID, (unsigned) d->mFormatFlags,
            (unsigned) d->mBytesPerPacket, (unsigned) d->mFramesPerPacket, (unsigned) d->mBytesPerFrame, (unsigned) d->mChannelsPerFrame, (unsigned) d->mBitsPerChannel);
    }
    OSStatus status = dispatchCall(inUnit, kAudioUnitSetPropertySelect, inID, inScope, inElement, inData, inDataSize);
    rclolAudioTrace("UNIT_SET unit=%p prop=%u scope=%u elem=%u size=%u status=%d\n", (void*) inUnit, (unsigned) inID, (unsigned) inScope, (unsigned) inElement, (unsigned) inDataSize, (int) status);
    return status;
}

OSStatus
AudioUnitAddPropertyListener(AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitPropertyListenerProc inProc,
    void * _Nullable inProcUserData)
{
    return dispatchCall(inUnit, kAudioUnitAddPropertyListenerSelect, inID, inProc, inProcUserData);
}

OSStatus
AudioUnitRemovePropertyListenerWithUserData(
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitPropertyListenerProc inProc,
    void * _Nullable inProcUserData)
{
    return dispatchCall(inUnit, kAudioUnitRemovePropertyListenerWithUserDataSelect, inID, inProc, inProcUserData);
}

OSStatus
AudioUnitAddRenderNotify(AudioUnit inUnit,
         AURenderCallback inProc,
         void * _Nullable inProcUserData)
{
    OSStatus status = dispatchCall(inUnit, kAudioUnitAddRenderNotifySelect, inProc, inProcUserData);
    rclolAudioTrace("UNIT_ADD_RENDER_NOTIFY unit=%p status=%d\n", (void*) inUnit, (int) status);
    return status;
}

OSStatus
AudioUnitRemoveRenderNotify(AudioUnit inUnit,
         AURenderCallback inProc,
         void * _Nullable inProcUserData)
{
    return dispatchCall(inUnit, kAudioUnitRemoveRenderNotifySelect, inProc, inProcUserData);
}

OSStatus
AudioUnitGetParameter(AudioUnit inUnit,
         AudioUnitParameterID inID,
         AudioUnitScope inScope,
         AudioUnitElement inElement,
         AudioUnitParameterValue * outValue)
{
    OSStatus status = dispatchCall(inUnit, kAudioUnitGetParameterSelect, inID, inScope, inElement, outValue);
    {
        static unsigned count = 0;
        if (rclolAudioTraceEnabled() && (count++ < 200 || count % 500 == 0))
            rclolAudioTrace("UNIT_GET_PARAM unit=%p id=%u scope=%u elem=%u value=%g status=%d\n", (void*) inUnit,
                (unsigned) inID, (unsigned) inScope, (unsigned) inElement, (outValue && !status) ? (double) *outValue : 0.0, (int) status);
    }
    return status;
}

OSStatus
AudioUnitSetParameter(AudioUnit inUnit,
         AudioUnitParameterID inID,
         AudioUnitScope inScope,
         AudioUnitElement inElement,
         AudioUnitParameterValue inValue,
         UInt32 inBufferOffsetInFrames)
{
    OSStatus status = dispatchCall(inUnit, kAudioUnitSetParameterSelect, inID, inScope, inElement, inValue, inBufferOffsetInFrames);
    {
        static unsigned count = 0;
        if (rclolAudioTraceEnabled() && (count++ < 200 || count % 500 == 0))
            rclolAudioTrace("UNIT_SET_PARAM unit=%p id=%u scope=%u elem=%u value=%g offset=%u status=%d\n", (void*) inUnit,
                (unsigned) inID, (unsigned) inScope, (unsigned) inElement, (double) inValue, (unsigned) inBufferOffsetInFrames, (int) status);
    }
    return status;
}

OSStatus
AudioUnitScheduleParameters(AudioUnit inUnit,
         const AudioUnitParameterEvent * inParameterEvent,
         UInt32 inNumParamEvents)
{
    return dispatchCall(inUnit, kAudioUnitScheduleParametersSelect, inParameterEvent, inNumParamEvents);
}

OSStatus
AudioUnitRender(AudioUnit inUnit,
         AudioUnitRenderActionFlags * _Nullable ioActionFlags,
         const AudioTimeStamp * inTimeStamp,
         UInt32 inOutputBusNumber,
         UInt32 inNumberFrames,
         AudioBufferList * ioData)
{
    return dispatchCall(inUnit, kAudioUnitRenderSelect, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
}

OSStatus
AudioUnitProcess (AudioUnit inUnit,
         AudioUnitRenderActionFlags * _Nullable ioActionFlags,
         const AudioTimeStamp * inTimeStamp,
         UInt32 inNumberFrames,
         AudioBufferList * ioData)
{
    // TODO
    return unimpErr;
}

OSStatus
AudioUnitProcessMultiple(AudioUnit inUnit,
         AudioUnitRenderActionFlags * _Nullable ioActionFlags,
         const AudioTimeStamp * inTimeStamp,
         UInt32 inNumberFrames,
         UInt32 inNumberInputBufferLists,
         const AudioBufferList * _Nonnull * _Nonnull inInputBufferLists,
         UInt32 inNumberOutputBufferLists,
         AudioBufferList * _Nonnull * _Nonnull ioOutputBufferLists)
{
    // TODO
    return unimpErr;
}

OSStatus
AudioUnitReset(AudioUnit inUnit,
         AudioUnitScope inScope,
         AudioUnitElement inElement)
{
    return dispatchCall(inUnit, kAudioUnitResetSelect, inScope, inElement);
}

OSStatus
AudioUnitExtensionSetComponentList(CFStringRef extensionIdentifier, _Nullable CFArrayRef audioComponentInfo)
{
    // TODO
    return unimpErr;
}

_Nullable CFArrayRef
AudioUnitExtensionCopyComponentList(CFStringRef extensionIdentifier)
{
    // TODO
    return nullptr;
}

