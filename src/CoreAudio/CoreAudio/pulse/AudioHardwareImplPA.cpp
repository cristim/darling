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

#include "AudioHardwareImplPA.h"
#include "../stub.h"
#include "AudioHardwareStreamPA.h"
#include "PADispatchMainLoop.h"
#include <CoreFoundation/CFBundle.h>
#include <CoreFoundation/CFString.h>
#include <iostream>
#include <mutex>
#include <thread>
#include <condition_variable>
#include <chrono>

AudioHardwareImplPA::AudioHardwareImplPA(AudioObjectID myId, const char* paRole)
: AudioHardwareImpl(myId), m_paRole(paRole)
{
	m_name = CFSTR("PulseAudio");
	m_manufacturer = CFSTR("PulseAudio");
	m_uid = CFSTR("PulseAudio:SystemObject");
}

AudioHardwareImplPA::~AudioHardwareImplPA()
{
    for(auto& stream:m_streams) stream.second->stop();
    m_streams.clear();
    if(m_context && m_loop) {
        m_loop->sync(^{ pa_context_disconnect(m_context);pa_context_unref(m_context); });
        m_context=nullptr;
    }
}

void AudioHardwareImplPA::syncPA(void (^block)(void)) {
    if(m_loop) m_loop->sync(block);else block();
}

OSStatus AudioHardwareImplPA::stop(AudioDeviceIOProcID inProcID) {
    __block OSStatus result = noErr;
    syncPA(^{
        auto it = m_streams.find(inProcID);
        if (it == m_streams.end()) {
            result = kAudioHardwareNotRunningError;
            return;
        }
        auto* stream = it->second.release();
        m_streams.erase(it);
        stream->stop();
        // An IOProc may stop itself. Keep its C++ stream alive until the
        // current PulseAudio callback has unwound on this serial queue.
        m_loop->async(^{ delete stream; });
    });
    return result;
}

OSStatus AudioHardwareImplPA::getPropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize,
	const void* inQualifierData, UInt32* ioDataSize, void* outData)
{
	switch (inAddress->mSelector)
	{
		case kAudioDevicePropertyStreams:
        {
            if (m_myId == kAudioObjectSystemObject) return kAudioHardwareUnknownPropertyError;
            bool input=m_myId==kAudioObjectSystemObject+2;
            bool matches=inAddress->mScope==kAudioObjectPropertyScopeGlobal ||
                inAddress->mScope==(input?kAudioObjectPropertyScopeInput:kAudioObjectPropertyScopeOutput);
            UInt32 size=matches?sizeof(AudioStreamID):0;
            if(outData && *ioDataSize<size) return kAudioHardwareBadPropertySizeError;
            if(outData && size) *(AudioStreamID*)outData=0x44410000u|m_myId;
            *ioDataSize=size;
            return noErr;
        }
		// BEGIN kAudioObjectSystemObject properties
		case kAudioHardwarePropertyDefaultInputDevice: // returns AudioDeviceID
			if (AudioDeviceID* devId = static_cast<AudioDeviceID*>(outData); devId && *ioDataSize >= sizeof(AudioDeviceID))
			{
				*devId = kAudioObjectSystemObject + 2;
			}
			*ioDataSize = sizeof(AudioDeviceID);
			return kAudioHardwareNoError;
		case kAudioHardwarePropertyDefaultOutputDevice: // returns AudioDeviceID
			if (AudioDeviceID* devId = static_cast<AudioDeviceID*>(outData); devId && *ioDataSize >= sizeof(AudioDeviceID))
			{
				*devId = kAudioObjectSystemObject + 1;
			}
			*ioDataSize = sizeof(AudioDeviceID);
			return kAudioHardwareNoError;
		case kAudioHardwarePropertyDefaultSystemOutputDevice:
			if (AudioDeviceID* devId = static_cast<AudioDeviceID*>(outData); devId && *ioDataSize >= sizeof(AudioDeviceID))
			{
				*devId = kAudioObjectSystemObject + 3;
			}
			*ioDataSize = sizeof(AudioDeviceID);
			return kAudioHardwareNoError;
		case kAudioHardwarePropertyDevices:
		{
			if (AudioDeviceID* devId = static_cast<AudioDeviceID*>(outData); devId && *ioDataSize >= 2*sizeof(AudioDeviceID))
			{
				devId[0] = kAudioObjectSystemObject + 1; // output
				devId[1] = kAudioObjectSystemObject + 2; // input
			}
			*ioDataSize = sizeof(AudioDeviceID) * 2;
			return kAudioHardwareNoError;
		}
		case kAudioDevicePropertyVolumeDecibelsToScalar:
		{
			if (Float32* vol = static_cast<Float32*>(outData); vol && *ioDataSize == sizeof(Float32))
			{
				*vol = pa_sw_volume_to_linear(pa_sw_volume_from_dB(*vol));
			}
			*ioDataSize = sizeof(Float32);
			return kAudioHardwareNoError;
		}
		case kAudioDevicePropertyVolumeScalarToDecibels:
		{
			if (Float32* vol = static_cast<Float32*>(outData); vol && *ioDataSize == sizeof(Float32))
			{
				*vol = pa_sw_volume_to_dB(pa_sw_volume_from_linear(*vol));
			}
			*ioDataSize = sizeof(Float32);
			return kAudioHardwareNoError;
		}
	}

	return AudioHardwareImpl::getPropertyData(inAddress, inQualifierDataSize, inQualifierData, ioDataSize, outData);
}
	
OSStatus AudioHardwareImplPA::setPropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize,
	const void* inQualifierData, UInt32 inDataSize, const void* inData)
{
	return AudioHardwareImpl::setPropertyData(inAddress, inQualifierDataSize, inQualifierData, inDataSize, inData);
}

AudioHardwareStream* AudioHardwareImplPA::createStream(AudioDeviceIOProc callback, void* clientData)
{
	// Must be called on a subclass instance
	return nullptr;
}

extern "C" char ***_NSGetArgv(void);

struct PAContextReady {
    std::mutex mutex;
    std::condition_variable condition;
    bool finished=false;
};

static void paContextStateCB(pa_context* context,void* userdata) {
    auto state=pa_context_get_state(context);
    if(state!=PA_CONTEXT_READY && state!=PA_CONTEXT_FAILED && state!=PA_CONTEXT_TERMINATED) return;
    auto* ready=static_cast<PAContextReady*>(userdata);
    std::lock_guard<std::mutex> lock(ready->mutex);
    ready->finished=true;
    ready->condition.notify_one();
}

void AudioHardwareImplPA::getPAContext(void (^cb)(pa_context*)) {
    // Serialize initial connection and reuse. The callback always runs on the
    // PulseAudio queue after readiness, with the stream fully constructed.
    static std::mutex creationMutex;
    std::unique_lock<std::mutex> creationLock(creationMutex);
    if(!m_context) {
        pa_proplist* properties=pa_proplist_new();
        pa_proplist_sets(properties,PA_PROP_APPLICATION_NAME,"Darling CoreAudio");
        pa_proplist_sets(properties,PA_PROP_APPLICATION_ID,"org.darlinghq.coreaudio");
        if(m_paRole) pa_proplist_sets(properties,PA_PROP_MEDIA_ROLE,m_paRole);
        m_loop.reset(new PADispatchMainLoop);
        m_context=pa_context_new_with_proplist(m_loop->getAPI(),"Darling CoreAudio",properties);
        pa_proplist_free(properties);
        if(!m_context) { cb(nullptr);return; }
        PAContextReady ready;
        pa_context_set_state_callback(m_context,paContextStateCB,&ready);
        int connected=pa_context_connect(m_context,nullptr,PA_CONTEXT_NOFLAGS,nullptr);
        m_loop->resume();
        if(connected>=0) {
            std::unique_lock<std::mutex> lock(ready.mutex);
            ready.condition.wait_for(lock,std::chrono::seconds(10),[&]{return ready.finished;});
        }
        // Remove the stack-backed readiness callback before leaving its scope.
        m_loop->sync(^{pa_context_set_state_callback(m_context,nullptr,nullptr);});
    }
    m_loop->sync(^{cb(pa_context_get_state(m_context)==PA_CONTEXT_READY?m_context:nullptr);});
}

pa_sample_spec AudioHardwareImplPA::paSampleSpecForASBD(const AudioStreamBasicDescription& asbd, bool* convertSignedUnsigned)
{
	const bool isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat;
	const bool isSigned = asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger;
	const bool isBE = asbd.mFormatFlags & kAudioFormatFlagIsBigEndian;
	
	pa_sample_spec spec;
	
	spec.rate = asbd.mSampleRate;
	spec.channels = asbd.mChannelsPerFrame;
	spec.format = PA_SAMPLE_INVALID;

	if (convertSignedUnsigned)
		*convertSignedUnsigned = false;
	
	if (asbd.mFormatID == kAudioFormatLinearPCM)
	{
		if (isFloat)
			spec.format = isBE ? PA_SAMPLE_FLOAT32BE : PA_SAMPLE_FLOAT32LE;
		else
		{
			switch (asbd.mBitsPerChannel)
			{
				case 8:
					if (convertSignedUnsigned)
						*convertSignedUnsigned = isSigned;
					spec.format = PA_SAMPLE_U8;
					break;
				case 16:
					if (convertSignedUnsigned)
						*convertSignedUnsigned = !isSigned;
					
					spec.format = isBE ? PA_SAMPLE_S16BE : PA_SAMPLE_S16LE;
					break;
				case 24:
					if (convertSignedUnsigned)
						*convertSignedUnsigned = !isSigned;
					
					if (asbd.mFormatFlags & kAudioFormatFlagIsPacked)
						spec.format = isBE ? PA_SAMPLE_S24BE : PA_SAMPLE_S24LE;
					else
						spec.format = isBE ? PA_SAMPLE_S24_32BE : PA_SAMPLE_S24_32LE;
					break;
				case 32:
					if (convertSignedUnsigned)
						*convertSignedUnsigned = !isSigned;
					
					spec.format = isBE ? PA_SAMPLE_S32BE : PA_SAMPLE_S32LE;
					break;
			}
		}
	}
	
	return spec;
}

bool AudioHardwareImplPA::validateFormat(const AudioStreamBasicDescription* asbd) const
{
	pa_sample_spec spec = paSampleSpecForASBD(*asbd);
	return pa_sample_spec_valid(&spec);
}
