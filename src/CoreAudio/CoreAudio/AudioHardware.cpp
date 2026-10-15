#include "../AudioTrace.h"
/*
This file is part of Darling.

Copyright (C) 2015-2020 Lubos Dolezel

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

#include <CoreAudio/AudioHardware.h>
#include "AudioHardwareImpl.h"
#include "pulse/AudioHardwareImplPA.h"
#include "pulse/AudioHardwareImplPAOutput.h"
#include "pulse/AudioHardwareImplPAInput.h"
#include <CarbonCore/MacErrors.h>
#include <dispatch/dispatch.h>
#include <memory>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <unordered_map>
#include "stub.h"

static std::unordered_map<AudioObjectID, std::unique_ptr<AudioHardwareImpl>> g_objects;

static void initObjects()
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// TODO: Or ALSA
		g_objects.insert(std::make_pair(kAudioObjectSystemObject, std::make_unique<AudioHardwareImplPA>(kAudioObjectSystemObject)));
		g_objects.insert(std::make_pair(kAudioObjectSystemObject + 1, std::make_unique<AudioHardwareImplPAOutput>(kAudioObjectSystemObject + 1)));
		g_objects.insert(std::make_pair(kAudioObjectSystemObject + 2, std::make_unique<AudioHardwareImplPAInput>(kAudioObjectSystemObject + 2)));
		g_objects.insert(std::make_pair(kAudioObjectSystemObject + 3, std::make_unique<AudioHardwareImplPAOutput>(kAudioObjectSystemObject + 3, "event")));
	});
}

static AudioHardwareImpl* GetObject(AudioObjectID objID)
{
	initObjects();

	auto it = g_objects.find(objID);
	if (it == g_objects.end())
		return nullptr;

	return it->second.get();
}

static AudioHardwareImpl* GetSystemObject()
{
	return GetObject(kAudioObjectSystemObject);
}

// Stream IDs are distinct from their owning device IDs. Chromium enumerates
// these objects to determine input/output direction before opening audio.
static OSStatus GetStreamPropertyData(AudioObjectID id,
    const AudioObjectPropertyAddress* property, UInt32* size, void* data)
{
    if (!property || !size) return paramErr;
    AudioHardwareImpl* device=GetObject(id&0xffffu);
    if (!device) return kAudioHardwareBadObjectError;
    UInt32 value;
    const void* source=&value;
    UInt32 required=sizeof(value);
    switch(property->mSelector) {
    case kAudioStreamPropertyDirection:
        value=device->id()==kAudioObjectSystemObject+2?1:0;break;
    case kAudioStreamPropertyTerminalType:
        value=0;break;
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat:
        source=&device->asbd();required=sizeof(AudioStreamBasicDescription);break;
    default:return kAudioHardwareUnknownPropertyError;
    }
    if(data) {
        if(*size<required) return kAudioHardwareBadPropertySizeError;
        memcpy(data,source,required);
    }
    *size=required;
    return noErr;
}

void AudioObjectShow(AudioObjectID inObjectID)
{
	AudioHardwareImpl* obj = GetObject(inObjectID);
	if (obj)
		obj->show();
}

Boolean AudioObjectHasProperty(AudioObjectID inObjectID,
		const AudioObjectPropertyAddress* inAddress)
{
    if((inObjectID&0xffff0000u)==0x44410000u) {
        UInt32 size=0;bool has=GetStreamPropertyData(inObjectID,inAddress,&size,nullptr)==noErr;
        rclolAudioTrace("HAS stream=%08x selector=%08x scope=%08x has=%d\n",inObjectID,inAddress->mSelector,inAddress->mScope,has);
        return has;
    }
	AudioHardwareImpl* obj = GetObject(inObjectID);
	if (!obj) {
		rclolAudioTrace("HAS object=%u selector=%08x BADOBJECT\n",inObjectID,inAddress->mSelector);
		return 0;
	}
	
	bool has=obj->hasProperty(inAddress);
	rclolAudioTrace("HAS object=%u selector=%08x scope=%08x elem=%u has=%d\n",inObjectID,inAddress->mSelector,inAddress->mScope,inAddress->mElement,has);
	return has;
}

OSStatus AudioObjectIsPropertySettable(AudioObjectID inObjectID,
		const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable)
{
	AudioHardwareImpl* obj = GetObject(inObjectID);
	if (!obj) {
		rclolAudioTrace("SETTABLE object=%08x selector=%08x BADOBJECT\n",inObjectID,inAddress->mSelector);
		return kAudioHardwareBadObjectError;
	}
	
	OSStatus status=obj->isPropertySettable(inAddress, outIsSettable);
	rclolAudioTrace("SETTABLE object=%u selector=%08x scope=%08x elem=%u status=%d settable=%d\n",inObjectID,inAddress->mSelector,inAddress->mScope,inAddress->mElement,status,status?0:*outIsSettable);
	return status;
}

OSStatus AudioObjectGetPropertyDataSize(AudioObjectID inObjectID,
		const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize,
		const void* inQualifierData, UInt32* outDataSize)
{
    if((inObjectID&0xffff0000u)==0x44410000u) {
        OSStatus status=GetStreamPropertyData(inObjectID,inAddress,outDataSize,nullptr);
        rclolAudioTrace("SIZE stream=%08x selector=%08x scope=%08x status=%d\n",inObjectID,inAddress->mSelector,inAddress->mScope,status);
        return status;
    }
	AudioHardwareImpl* obj = GetObject(inObjectID);
	if (!obj) {
		rclolAudioTrace("SIZE object=%08x selector=%08x BADOBJECT\n",inObjectID,inAddress->mSelector);
		return kAudioHardwareBadObjectError;
	}
	
	OSStatus status=obj->getPropertyDataSize(inAddress,inQualifierDataSize,inQualifierData,outDataSize);
    rclolAudioTrace("SIZE object=%u selector=%08x scope=%08x status=%d size=%u\n",inObjectID,inAddress->mSelector,inAddress->mScope,status,status?0:*outDataSize);
    return status;
}

OSStatus AudioObjectGetPropertyData(AudioObjectID inObjectID,
		const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize,
		const void* inQualifierData, UInt32* ioDataSize, void* outData)
{
    if(inObjectID==kAudioObjectSystemObject && inAddress->mSelector==kAudioHardwarePropertyDeviceForUID) {
        if(!outData || !ioDataSize || *ioDataSize<sizeof(AudioValueTranslation)) return kAudioHardwareBadPropertySizeError;
        auto* value=static_cast<AudioValueTranslation*>(outData);
        if(!value->mInputData || value->mInputDataSize!=sizeof(CFStringRef) || !value->mOutputData || value->mOutputDataSize<sizeof(AudioDeviceID)) return paramErr;
        CFStringRef wanted=*static_cast<CFStringRef*>(value->mInputData);
        AudioDeviceID found=kAudioObjectUnknown;
        AudioObjectPropertyAddress property={kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMaster};
        for(AudioDeviceID id=kAudioObjectSystemObject+1;id<=kAudioObjectSystemObject+3;++id) {
            CFStringRef uid=nullptr;UInt32 size=sizeof(uid);
            if(GetObject(id)->getPropertyData(&property,0,nullptr,&size,&uid)==noErr && uid) {
                bool match=CFEqual(uid,wanted);CFRelease(uid);
                if(match) { found=id;break; }
            }
        }
        *static_cast<AudioDeviceID*>(value->mOutputData)=found;
        value->mOutputDataSize=sizeof(found);*ioDataSize=sizeof(*value);return noErr;
    }
    if((inObjectID&0xffff0000u)==0x44410000u) {
        OSStatus status=GetStreamPropertyData(inObjectID,inAddress,ioDataSize,outData);
        rclolAudioTrace("GET stream=%08x selector=%08x scope=%08x status=%d\n",inObjectID,inAddress->mSelector,inAddress->mScope,status);
        return status;
    }
	AudioHardwareImpl* obj = GetObject(inObjectID);
	if (!obj) {
		rclolAudioTrace("GET object=%08x selector=%08x BADOBJECT\n",inObjectID,inAddress->mSelector);
		return kAudioHardwareBadObjectError;
	}
	
    static unsigned traceCount=0;
    if(rclolAudioTraceEnabled() && traceCount++<100)
        fprintf(stderr,"AUDIO_HARDWARE_GET object=%u property=%08x scope=%08x\n",inObjectID,inAddress->mSelector,inAddress->mScope);
	OSStatus status=obj->getPropertyData(inAddress,inQualifierDataSize,inQualifierData,ioDataSize,outData);
    rclolAudioTrace("GET object=%u selector=%08x scope=%08x elem=%u status=%d size=%u\n",inObjectID,inAddress->mSelector,inAddress->mScope,inAddress->mElement,status,status?0:*ioDataSize);
    return status;
}

OSStatus AudioObjectSetPropertyData(AudioObjectID inObjectID,
		const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize,
		const void* inQualifierData, UInt32 inDataSize, const void* inData)
{
	AudioHardwareImpl* obj = GetObject(inObjectID);
	if (!obj) {
		rclolAudioTrace("SET object=%08x selector=%08x scope=%08x elem=%u BADOBJECT\n",inObjectID,inAddress->mSelector,inAddress->mScope,inAddress->mElement);
		return kAudioHardwareBadObjectError;
	}
	
	OSStatus status=obj->setPropertyData(inAddress,inQualifierDataSize,inQualifierData,inDataSize,inData);
    rclolAudioTrace("SET object=%u selector=%08x scope=%08x elem=%u size=%u value=%g status=%d\n",inObjectID,inAddress->mSelector,inAddress->mScope,inAddress->mElement,inDataSize,
        (inData && inDataSize==sizeof(Float32))?(double)*(const Float32*)inData:0.0,status);
    return status;
}

OSStatus AudioObjectAddPropertyListener(AudioObjectID inObjectID,
		const AudioObjectPropertyAddress* inAddress,
		AudioObjectPropertyListenerProc inListener, void* inClientData)
{
	AudioHardwareImpl* obj = GetObject(inObjectID);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	OSStatus status=obj->addPropertyListener(inAddress,inListener,inClientData);
    rclolAudioTrace("ADD_LISTENER object=%u selector=%08x status=%d\n",inObjectID,inAddress->mSelector,status);
    return status;
}

OSStatus AudioObjectRemovePropertyListener(AudioObjectID inObjectID,
		const AudioObjectPropertyAddress* inAddress,
		AudioObjectPropertyListenerProc inListener, void* inClientData)
{
	AudioHardwareImpl* obj = GetObject(inObjectID);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->removePropertyListener(inAddress, inListener, inClientData);
}

OSStatus AudioHardwareUnload(void)
{
	return noErr;
}

OSStatus AudioHardwareCreateAggregateDevice(CFDictionaryRef, AudioObjectID* outDeviceID)
{
	STUB();
	if (outDeviceID)
		*outDeviceID = 0;
	
	return unimpErr;
}

OSStatus AudioHardwareDestroyAggregateDevice(AudioObjectID inDeviceID)
{
	STUB();
	return unimpErr;
}

OSStatus AudioHardwareGetProperty(AudioHardwarePropertyID inPropId, UInt32* ioPropertyDataSize, void* outPropertyData)
{
	if (!ioPropertyDataSize)
		return paramErr;

	return AudioDeviceGetProperty(kAudioObjectSystemObject, 0, false, inPropId, ioPropertyDataSize, outPropertyData);
}

OSStatus AudioDeviceGetProperty(AudioDeviceID inDevice, UInt32 inChannel, Boolean isInput, AudioDevicePropertyID inPropertyID, UInt32* ioPropertyDataSize, void* outPropertyData)
{
	AudioObjectPropertyAddress aopa = {
		inPropertyID,
		isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, // kAudioObjectPropertyScopeGlobal
		kAudioObjectPropertyElementMaster
	};

	return AudioObjectGetPropertyData(inDevice, &aopa, 0, nullptr, ioPropertyDataSize, outPropertyData);
}

OSStatus AudioDeviceGetPropertyInfo(AudioDeviceID inDevice, UInt32 inChannel, Boolean isInput, AudioDevicePropertyID inPropertyID, UInt32* outSize, Boolean* outWritable)
{
	AudioObjectPropertyAddress aopa = {
		inPropertyID,
		isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, // kAudioObjectPropertyScopeGlobal
		kAudioObjectPropertyElementMaster
	};

	OSStatus status;
	if (outSize)
	{
		status = AudioObjectGetPropertyDataSize(inDevice, &aopa, 0, nullptr, outSize);
		if (status != noErr)
			return status;
	}

	if (outWritable)
	{
		status = AudioObjectIsPropertySettable(inDevice, &aopa, outWritable);
	}
	return status;
}

OSStatus AudioDeviceSetProperty(AudioDeviceID inDevice, const AudioTimeStamp *inWhen, UInt32 inChannel,
	Boolean isInput, AudioDevicePropertyID inPropertyID, UInt32 inPropertyDataSize, const void *inPropertyData)
{
	AudioObjectPropertyAddress aopa = {
		inPropertyID,
		kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMaster
	};

	return AudioObjectSetPropertyData(inDevice, &aopa, 0, nullptr, inPropertyDataSize, inPropertyData);
}

OSStatus AudioHardwareGetPropertyInfo(AudioHardwarePropertyID inPropertyID, UInt32 *outSize, Boolean *outWritable)
{
	return AudioDeviceGetPropertyInfo(kAudioObjectSystemObject, 0, false, inPropertyID, outSize, outWritable);
}

OSStatus AudioDeviceCreateIOProcID(AudioObjectID inDevice,
		AudioDeviceIOProc inProc, void* inClientData,
		AudioDeviceIOProcID* outIOProcID)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->createIOProcID(inProc, inClientData, outIOProcID);
}

OSStatus AudioDeviceAddIOProc(AudioDeviceID inDevice, AudioDeviceIOProc inProc, void *inClientData)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	return obj->createIOProcID(inProc, inClientData, nullptr);
}

OSStatus AudioDeviceDestroyIOProcID(AudioObjectID inDevice,
		AudioDeviceIOProcID inIOProcID)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->destroyIOProcID(inIOProcID);
}

OSStatus AudioDeviceRemoveIOProc(AudioDeviceID inDevice, AudioDeviceIOProc inProc)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->destroyIOProcID(AudioDeviceIOProcID(inProc));
}

OSStatus AudioDeviceStart(AudioObjectID inDevice, AudioDeviceIOProcID inProcID)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->start(inProcID, nullptr, 0);
}

OSStatus AudioDeviceStartAtTime(AudioObjectID inDevice, AudioDeviceIOProcID inProcID,
		AudioTimeStamp* ioRequestedStartTime, UInt32 inFlags)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->start(inProcID, ioRequestedStartTime, inFlags);
}

OSStatus AudioDeviceStop(AudioObjectID inDevice, AudioDeviceIOProcID inProcID)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->stop(inProcID);
}

OSStatus AudioDeviceGetCurrentTime(AudioObjectID inDevice, AudioTimeStamp* outTime)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->getCurrentTime(outTime);
}

OSStatus AudioDeviceTranslateTime(AudioObjectID inDevice, const AudioTimeStamp* inTime,
		AudioTimeStamp* outTime)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->translateTime(inTime, outTime);
}

OSStatus AudioDeviceGetNearestStartTime(AudioObjectID inDevice,
		AudioTimeStamp* ioRequestedStartTime, UInt32 inFlags)
{
	AudioHardwareImpl* obj = GetObject(inDevice);
	if (!obj)
		return kAudioHardwareBadObjectError;
	
	return obj->getNearestStartTime(ioRequestedStartTime, inFlags);
}
