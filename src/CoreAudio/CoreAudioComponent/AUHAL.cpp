#include "../AudioTrace.h"
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

#include "AUHAL.h"
#include <iostream>
#include <vector>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <pthread.h>
#include <atomic>
#include <cmath>
#include <algorithm>
#include <mach/mach_time.h>

#pragma GCC visibility push(default)
AUDIOCOMPONENT_ENTRY(AUOutputBaseFactory, AUHAL);
#pragma GCC visibility pop

enum {
	kOutputBus = 0,
	kInputBus
};

AUHAL::AUHAL(AudioComponentInstance inInstance, bool supportRecording)
: AUBase(inInstance, 1, supportRecording ? 1 : 0)
{
	UInt32 propSize = sizeof(AudioDeviceID);
	AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &propSize, &m_outputDevice);
	AudioHardwareGetProperty(kAudioHardwarePropertyDefaultInputDevice, &propSize, &m_inputDevice);
}

AUHAL::~AUHAL()
{
	Stop();
}

UInt32 AUHAL::GetChannelLayoutTags(AudioUnitScope scope,AudioUnitElement element,AudioChannelLayoutTag* tags) {
    if(element!=kOutputBus || (scope!=kAudioUnitScope_Input && scope!=kAudioUnitScope_Output)) return 0;
    UInt32 channels=GetStreamFormat(scope,element).mChannelsPerFrame;
    if(tags) *tags=channels==1?kAudioChannelLayoutTag_Mono:channels==2?kAudioChannelLayoutTag_Stereo:(kAudioChannelLayoutTag_DiscreteInOrder|channels);
    return 1;
}

UInt32 AUHAL::GetAudioChannelLayout(AudioUnitScope scope,AudioUnitElement element,AudioChannelLayout* layout,Boolean& writable) {
    AudioChannelLayoutTag tag;
    if(!GetChannelLayoutTags(scope,element,&tag)) return 0;
    writable=!m_running;
    if(layout) { layout->mChannelLayoutTag=tag;layout->mChannelBitmap=0;layout->mNumberChannelDescriptions=0; }
    return offsetof(AudioChannelLayout,mChannelDescriptions);
}

OSStatus AUHAL::SetAudioChannelLayout(AudioUnitScope scope,AudioUnitElement element,const AudioChannelLayout* layout) {
    AudioChannelLayoutTag tag;
    if(!layout || !GetChannelLayoutTags(scope,element,&tag)) return kAudioUnitErr_InvalidElement;
    if(layout->mChannelLayoutTag==tag) return noErr;
    /* darling-lol: a layout is acceptable when it describes the stream's number of channels, whichever way it is written:
     * explicit channel descriptions (League sends two: left, right), a channel bitmap, or another tag with that count.
     * Only the exact tag was accepted, so the game's stereo description list was refused (-10851) and it rebuilt its
     * audio graph in a loop. */
    const UInt32 wanted=GetStreamFormat(scope,element).mChannelsPerFrame;
    UInt32 channels;
    if(layout->mChannelLayoutTag==kAudioChannelLayoutTag_UseChannelDescriptions) channels=layout->mNumberChannelDescriptions;
    else if(layout->mChannelLayoutTag==kAudioChannelLayoutTag_UseChannelBitmap) channels=__builtin_popcount(layout->mChannelBitmap);
    else channels=layout->mChannelLayoutTag&0xffff;
    return channels==wanted?noErr:kAudioUnitErr_InvalidPropertyValue;
}

bool AUHAL::CanScheduleParameters() const
{
	return true;
}

bool AUHAL::StreamFormatWritable(AudioUnitScope scope, AudioUnitElement element)
{
	return !m_running;
}

OSStatus AUHAL::Version()
{
	return 1;
}

// Provide data from the microphone
OSStatus AUHAL::Render(AudioUnitRenderActionFlags& ioActionFlags, const AudioTimeStamp& inTimeStamp, UInt32 inNumberFrames)
{
	std::unique_lock<std::mutex> lk(m_dataAvailableMutex);

	m_dataAvailableCV.wait(lk, [=]{ return m_dataAvailable; });

	AudioBufferList& abl = GetOutput(kInputBus)->GetBufferList();

	// TODO: Prepare for non-interleaved audio
	UInt32 howMuch = std::min<UInt32>(abl.mBuffers[0].mDataByteSize, m_bufferUsed);
	memcpy(abl.mBuffers[0].mData, m_buffer.get(), howMuch);
	abl.mBuffers[0].mDataByteSize = howMuch;

	return noErr;
}

OSStatus AUHAL::Start()
{
    if(rclolAudioTraceEnabled()) rclolAudioTrace("AUDIO_UNIT_NATIVE_START output=%d input=%d\n",m_enableOutput,m_enableInput);
	if (m_running)
		return noErr;

	if (m_enableOutput)
	{
		// std::cout << "Output is enabled, starting playback\n";
        OSStatus status=AudioDeviceCreateIOProcID(m_outputDevice,playbackCallback,this,&m_outputProcID);
        if(status) return status;

		// m_auhalData.open("/tmp/auhal.raw", std::ios_base::binary | std::ios_base::out);

		const CAStreamBasicDescription& desc = GetStreamFormat(kAudioUnitScope_Input, kOutputBus);
        AudioStreamBasicDescription hardware=desc;
        hardware.mFormatFlags&=~kAudioFormatFlagIsNonInterleaved;
        hardware.mBytesPerFrame=hardware.mChannelsPerFrame*hardware.mBitsPerChannel/8;
        hardware.mBytesPerPacket=hardware.mBytesPerFrame;
        status=AudioDeviceSetProperty(m_outputDevice,nullptr,0,false,kAudioDevicePropertyStreamFormat,sizeof(hardware),&hardware);
        if(!status) status=AudioDeviceStart(m_outputDevice,m_outputProcID);
        if(status) {AudioDeviceDestroyIOProcID(m_outputDevice,m_outputProcID);m_outputProcID=0;return status;}
	}
	if (m_enableInput)
	{
		AudioDeviceCreateIOProcID(m_inputDevice, recordCallback, this, &m_inputProcID);
		const CAStreamBasicDescription& desc = GetStreamFormat(kAudioUnitScope_Output, kInputBus);
		AudioDeviceSetProperty(m_inputDevice, nullptr, 0, true, kAudioDevicePropertyStreamFormat, sizeof(AudioStreamBasicDescription), &desc);
		AudioDeviceStart(m_inputDevice, m_inputProcID);
	}

	m_running = m_enableOutput || m_enableInput;
	return noErr;
}

OSStatus AUHAL::Stop()
{
	if (!m_running)
		return noErr;

	if (m_outputProcID)
	{
		AudioDeviceStop(m_outputDevice, m_outputProcID);
		AudioDeviceDestroyIOProcID(m_outputDevice, m_outputProcID);
		m_outputProcID=0;
	}
	if (m_inputProcID)
	{
		AudioDeviceStop(m_inputDevice, m_inputProcID);
		AudioDeviceDestroyIOProcID(m_inputDevice, m_inputProcID);
		m_inputProcID=0;
	}
	m_running=false;
	return noErr;
}

// Volume/mute/gain related property selectors (HAL device properties and AUHAL parameters).
static bool rclolVolumeRelated(UInt32 id)
{
	switch (id)
	{
		case 'volm': case 'vold': case 'vdb#': case 'mute': case 'thru':
		case 'pvol': case 'pvod': case 'mvol': case 'mbal': case 'span':
		case 'svlm': case 'smut': case 'v2db': case 'db2v':
			return true;
	}
	return false;
}

OSStatus AUHAL::SetProperty(AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, const void* inData, UInt32 inDataSize)
{
	if (rclolAudioTraceEnabled() && rclolVolumeRelated(inID))
		rclolAudioTrace("AUHAL_SET_VOLPROP property=%08x scope=%u element=%u size=%u value=%g\n",inID,inScope,inElement,inDataSize,
			(inData && inDataSize==sizeof(Float32))?(double)*(const Float32*)inData:0.0);
	switch (inID)
	{
        case kAudioDevicePropertyBufferFrameSize: {
            AudioObjectPropertyAddress p={inID,kAudioObjectPropertyScopeOutput,kAudioObjectPropertyElementMaster};
            return AudioObjectSetPropertyData(m_outputDevice,&p,0,nullptr,inDataSize,inData);
        }
		case kAudioOutputUnitProperty_SetInputCallback:
		{
			ca_require(inDataSize == sizeof(AURenderCallbackStruct), InvalidPropertyValue);
			const AURenderCallbackStruct* cb = static_cast<const AURenderCallbackStruct*>(inData);
			
			m_outputAvailableCb = *cb;

			PropertyChanged(inID, inScope, inElement);
			return noErr;
		}
		case kAudioOutputUnitProperty_EnableIO:
		{
			ca_require(inDataSize == sizeof(UInt32), InvalidPropertyValue);

			const bool enable = *((const UInt32*) inData);

			if (inElement == kOutputBus)
			{
				m_enableOutput = enable;
				PropertyChanged(inID, inScope, inElement);
			}
			else if (inElement == kInputBus)
			{
				m_enableInput = enable;
				PropertyChanged(inID, inScope, inElement);
			}
			else
				return kAudioUnitErr_InvalidElement;

			return noErr;
		}
		case kAudioOutputUnitProperty_CurrentDevice:
		{
			ca_require(inDataSize == sizeof(AudioDeviceID), InvalidPropertyValue);
			const AudioDeviceID* dev = static_cast<const AudioDeviceID*>(inData);

			if (inElement == kOutputBus)
			{
				m_outputDevice = *dev;
				PropertyChanged(inID, inScope, inElement);
			}
			else if (inElement == kInputBus)
			{
				m_inputDevice = *dev;
				PropertyChanged(inID, inScope, inElement);
			}
			else
				return kAudioUnitErr_InvalidElement;
			return noErr;
		}
	}
    {
    OSStatus status=AUBase::SetProperty(inID,inScope,inElement,inData,inDataSize);
    if(status && rclolAudioTraceEnabled()) rclolAudioTrace("AUDIO_UNIT_SET property=%u scope=%u element=%u status=%d\n",inID,inScope,inElement,status);
    return status;
    }
InvalidPropertyValue:
	return kAudioUnitErr_InvalidPropertyValue;
}

OSStatus AUHAL::GetPropertyInfo(AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, UInt32& outDataSize, Boolean& outWritable)
{
	if (rclolAudioTraceEnabled() && rclolVolumeRelated(inID))
		rclolAudioTrace("AUHAL_INFO_VOLPROP property=%08x scope=%u element=%u\n",inID,inScope,inElement);
	switch (inID)
	{
        case kAudioDevicePropertyBufferFrameSize:
            outDataSize=sizeof(UInt32);outWritable=true;return noErr;
		case kAudioOutputUnitProperty_SetInputCallback:
		{
			outDataSize = sizeof(AURenderCallbackStruct);
			outWritable = true;
			break;
		}
		case kAudioOutputUnitProperty_EnableIO:
		{
			outDataSize = sizeof(UInt32);
			outWritable = true;
			return noErr;
		}
		case kAudioOutputUnitProperty_HasIO:
		{
			outDataSize = sizeof(UInt32);
			outWritable = false;
			return noErr;
		}
		case kAudioOutputUnitProperty_CurrentDevice:
		{
			outDataSize = sizeof(AudioDeviceID);
			outWritable = true;
			return noErr;
		}
	}
    OSStatus status=AUBase::GetPropertyInfo(inID,inScope,inElement,outDataSize,outWritable);
    if(status && rclolAudioTraceEnabled()) rclolAudioTrace("AUDIO_UNIT_INFO property=%u scope=%u element=%u status=%d\n",inID,inScope,inElement,status);
    return status;
}

OSStatus AUHAL::GetProperty(AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, void* outData)
{
	if (rclolAudioTraceEnabled() && rclolVolumeRelated(inID))
		rclolAudioTrace("AUHAL_GET_VOLPROP property=%08x scope=%u element=%u\n",inID,inScope,inElement);
	switch (inID)
	{
        case kAudioDevicePropertyBufferFrameSize: {
            AudioObjectPropertyAddress p={inID,kAudioObjectPropertyScopeOutput,kAudioObjectPropertyElementMaster};
            UInt32 size=sizeof(UInt32);
            return AudioObjectGetPropertyData(m_outputDevice,&p,0,nullptr,&size,outData);
        }
		case kAudioOutputUnitProperty_SetInputCallback:
		{
			memcpy(outData, &m_outputAvailableCb, sizeof(m_outputAvailableCb));
			return noErr;
		}
		case kAudioOutputUnitProperty_EnableIO:
		case kAudioOutputUnitProperty_HasIO:
		{
			if (inElement == kOutputBus)
			{
				UInt32 value = m_enableOutput;
				memcpy(outData, &value, sizeof(value));
			}
			else if (inElement == kInputBus)
			{
				UInt32 value = m_enableInput;
				memcpy(outData, &value, sizeof(value));
			}
			else
				return kAudioUnitErr_InvalidElement;
			return noErr;
		}
		case kAudioOutputUnitProperty_CurrentDevice:
		{
			if (inElement == kOutputBus)
			{
				memcpy(outData, &m_outputDevice, sizeof(m_outputDevice));
			}
			else if (inElement == kInputBus)
			{
				memcpy(outData, &m_inputDevice, sizeof(m_inputDevice));
			}
			else
				return kAudioUnitErr_InvalidElement;
			return noErr;
		}
	}
	return AUBase::GetProperty(inID, inScope, inElement, outData);
}

OSStatus AUHAL::playbackCallback(AudioObjectID inObjectID,
	const AudioTimeStamp* inNow, const AudioBufferList* inInputData,
	const AudioTimeStamp* inInputTime,
	AudioBufferList* outOutputData, const AudioTimeStamp* inOutputTime,
	void* inClientData)
{
	AUHAL* This = static_cast<AUHAL*>(inClientData);
	return This->doPlayback(inNow, outOutputData, inOutputTime);
}

OSStatus AUHAL::recordCallback(AudioObjectID inObjectID,
	const AudioTimeStamp* inNow, const AudioBufferList* inInputData,
	const AudioTimeStamp* inInputTime,
	AudioBufferList* outOutputData, const AudioTimeStamp* inOutputTime,
	void* inClientData)
{
	AUHAL* This = static_cast<AUHAL*>(inClientData);
	return This->doRecord(inNow, inInputData, inInputTime);
}

// Diagnostic only: classify each rendered block (see AUDIO_BLOCK_STATE).
void AUHAL::traceBlock(const AudioTimeStamp* inNow, const AudioTimeStamp* inOutputTime, OSStatus result,
    const CAStreamBasicDescription& desc, UInt32 nFrames, AudioBufferList* out)
{
    static std::atomic<unsigned> stateLines(0);
    static mach_timebase_info_data_t tb={0,0};
    if(!tb.denom) mach_timebase_info(&tb);
    BlockTrace& t=m_blockTrace;
    const unsigned long long cb=++t.callbacks;
    if(result) {
        if(++t.pullFailures<=50 || t.pullFailures%200==0)
            rclolAudioTrace("AUDIO_PULL_FAIL unit=%p cb=%llu status=%d frames=%u count=%llu\n",
                (void*)this,cb,(int)result,nFrames,t.pullFailures);
        return;
    }
    if(!desc.IsFloat() || desc.mBitsPerChannel!=32 || !nFrames || !desc.mChannelsPerFrame) return;
    const bool planar=desc.mFormatFlags&kAudioFormatFlagIsNonInterleaved;
    const UInt32 ch=desc.mChannelsPerFrame;
    const float* base=planar?(const float*)m_playbackSamples.data():(const float*)out->mBuffers[0].mData;
    if(!base) return;
    auto at=[&](UInt32 c,UInt32 f)->float { return planar?base[(size_t)c*nFrames+f]:base[(size_t)f*ch+c]; };
    float peak[2]={0,0}; double sq[2]={0,0}; bool halves[2]={true,true}; bool zero=true;
    const UInt32 half=nFrames/2;
    for(UInt32 c=0;c<ch && c<2;++c) {
        for(UInt32 f=0;f<nFrames;++f) {
            float v=at(c,f);
            if(v!=0 || std::signbit(v)) { if(v!=0) zero=false; }
            peak[c]=std::max(peak[c],std::abs(v)); sq[c]+=(double)v*v;
            if(f<half && (nFrames&1)==0) {
                float w=at(c,f+half);
                if(memcmp(&v,&w,4)) halves[c]=false;
            }
        }
    }
    const bool halvesSame=(nFrames&1)==0 && halves[0] && (ch<2 || halves[1]);
    const double rms0=sqrt(sq[0]/nFrames), rms1=ch>1?sqrt(sq[1]/nFrames):0;
    bool same=false;
    const size_t total=(size_t)nFrames*ch;
    if(t.havePrev && t.prev.size()==total) {
        same=true;
        for(UInt32 c=0;c<ch&&same;++c) for(UInt32 f=0;f<nFrames;++f) {
            float v=at(c,f);
            if(memcmp(&v,&t.prev[(size_t)c*nFrames+f],4)) { same=false; break; }
        }
    }
    // 0 silent, 1 live, 2 repeat-of-previous-nonsilent, 3 halves-identical-nonsilent
    int state=zero?0:same?2:halvesSame?3:1;
    t.prev.resize(total);
    for(UInt32 c=0;c<ch;++c) for(UInt32 f=0;f<nFrames;++f) t.prev[(size_t)c*nFrames+f]=at(c,f);
    t.havePrev=true;
    ++t.stateCounts[state];
    static const char* names[4]={"silent","live","repeat","halves"};
    double dSample=0, dHostMs=0;
    const double sample=inOutputTime->mSampleTime;
    if(t.haveTime) {
        dSample=sample-t.lastSample;
        dHostMs=(double)(inOutputTime->mHostTime-t.lastHost)*tb.numer/tb.denom/1e6;
        if(dHostMs>t.maxGapMs) t.maxGapMs=dHostMs;
    }
    t.haveTime=true; t.lastSample=sample; t.lastHost=inOutputTime->mHostTime;
    const bool transition=state!=t.state;
    if(transition && t.state>=0 && stateLines.fetch_add(1)<2000)
        rclolAudioTrace("AUDIO_BLOCK_STATE unit=%p from=%s to=%s cb=%llu frames=%u peakL=%g peakR=%g rmsL=%g rmsR=%g\n",
            (void*)this,names[t.state],names[state],cb,nFrames,peak[0],peak[1],rms0,rms1);
    if(cb<=40 || cb%200==0 || transition)
        rclolAudioTrace("AUDIO_BLOCK unit=%p cb=%llu state=%s frames=%u peakL=%g peakR=%g rmsL=%g rmsR=%g "
            "halvesL=%d halvesR=%d same=%d zero=%d outSample=%.0f nowSample=%.0f dSample=%.0f outHost=%llu nowHost=%llu "
            "dHostMs=%.3f maxGapMs=%.3f\n",
            (void*)this,cb,names[state],nFrames,peak[0],peak[1],rms0,rms1,(int)halves[0],(int)halves[1],(int)same,(int)zero,
            sample,inNow->mSampleTime,dSample,(unsigned long long)inOutputTime->mHostTime,
            (unsigned long long)inNow->mHostTime,dHostMs,t.maxGapMs);
    if(cb%2000==0)
        rclolAudioTrace("AUDIO_BLOCK_SUMMARY unit=%p cb=%llu silent=%llu live=%llu repeat=%llu halves=%llu pullFail=%llu maxGapMs=%.3f\n",
            (void*)this,cb,t.stateCounts[0],t.stateCounts[1],t.stateCounts[2],t.stateCounts[3],t.pullFailures,t.maxGapMs);
    t.state=state;
}

OSStatus AUHAL::doPlayback(const AudioTimeStamp* inNow, AudioBufferList* outOutputData, const AudioTimeStamp* inOutputTime)
{
	// std::cout << "AUHAL::DoPlayback()\n";
    static unsigned stackTraces=0;
    if(rclolAudioTraceEnabled() && stackTraces++<2)
        rclolAudioTrace("AUDIO_CALLBACK_STACK bytes=%zu\n",pthread_get_stacksize_np(pthread_self()));
	if (!HasInput(0))
	{
		// std::cerr << "No connection\n";
		return kAudioUnitErr_NoConnection;
	}

	OSStatus result = noErr;
	AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PreRender;
	const CAStreamBasicDescription& desc = GetStreamFormat(kAudioUnitScope_Input, kOutputBus);

    if(outOutputData->mNumberBuffers!=1 || !desc.mChannelsPerFrame ||
        !desc.mBitsPerChannel || desc.mBitsPerChannel%8) return kAudioUnitErr_FormatNotSupported;
    UInt32 sampleBytes=desc.mBitsPerChannel/8;
    UInt32 frameBytes=desc.mChannelsPerFrame*sampleBytes;
    UInt32 nFrames=outOutputData->mBuffers[0].mDataByteSize/frameBytes;
    if(desc.mFormatFlags&kAudioFormatFlagIsNonInterleaved) {
        m_playbackSamples.resize(nFrames*frameBytes);
        // Preserve fresh-buffer silence for callbacks that leave samples unwritten.
        std::fill(m_playbackSamples.begin(),m_playbackSamples.end(),0);
        m_playbackBufferList.resize(offsetof(AudioBufferList,mBuffers)+desc.mChannelsPerFrame*sizeof(AudioBuffer));
        AudioBufferList* planar=(AudioBufferList*)m_playbackBufferList.data();
        planar->mNumberBuffers=desc.mChannelsPerFrame;
        for(UInt32 c=0;c<desc.mChannelsPerFrame;++c) {
            planar->mBuffers[c].mNumberChannels=1;
            planar->mBuffers[c].mDataByteSize=nFrames*sampleBytes;
            planar->mBuffers[c].mData=m_playbackSamples.data()+c*nFrames*sampleBytes;
        }
        result=GetInput(kOutputBus)->PullInputWithBufferList(flags,*inNow,kOutputBus,nFrames,planar);
        if(!result) {
            auto* destination=(unsigned char*)outOutputData->mBuffers[0].mData;
            for(UInt32 f=0;f<nFrames;++f) for(UInt32 c=0;c<desc.mChannelsPerFrame;++c)
                memcpy(destination+f*frameBytes+c*sampleBytes,
                    (unsigned char*)planar->mBuffers[c].mData+f*sampleBytes,sampleBytes);
        }
    } else {
        result=GetInput(kOutputBus)->PullInputWithBufferList(flags,*inNow,kOutputBus,nFrames,outOutputData);
    }

    if(rclolAudioTraceEnabled()) traceBlock(inNow,inOutputTime,result,desc,nFrames,outOutputData);

    // Diagnostic: Chromium's audio source can start handing out one identical
    // block forever (heard as static). Log the timestamp Darling supplied at the
    // moment that begins, so we can tell whether our clock inputs look sane.
    {
        const unsigned char* produced;
        size_t producedBytes;
        if(desc.mFormatFlags&kAudioFormatFlagIsNonInterleaved) {
            produced=m_playbackSamples.data();
            producedBytes=(size_t)nFrames*frameBytes;
        } else {
            produced=(const unsigned char*)outOutputData->mBuffers[0].mData;
            producedBytes=outOutputData->mBuffers[0].mDataByteSize;
        }
        uint64_t sum=1469598103934665603ull;
        for(size_t i=0;i<producedBytes;++i) sum=(sum^produced[i])*1099511628211ull;
        static uint64_t lastSum=0;
        static unsigned repeatRun=0;
        if(producedBytes && sum==lastSum) {
            ++repeatRun;
            if(rclolAudioTraceEnabled() && (repeatRun==2 || repeatRun%500==0))
                rclolAudioTrace("AUDIO_INPUT_REPEAT frames=%u run=%u host=%llu sample=%.0f flags=%u\n",
                    nFrames,repeatRun,(unsigned long long)inOutputTime->mHostTime,inOutputTime->mSampleTime,
                    (unsigned)inOutputTime->mFlags);
        } else {
            repeatRun=0;
        }
        lastSum=sum;
    }

    static unsigned traceRenders=0;
    if (rclolAudioTraceEnabled() && traceRenders++ < 16) {
        float peak=0;
        if (!result && desc.IsFloat() && sampleBytes==4) {
            const float* samples=static_cast<const float*>(outOutputData->mBuffers[0].mData);
            for(UInt32 i=0;i<outOutputData->mBuffers[0].mDataByteSize/4;++i)
                peak=std::max(peak,std::abs(samples[i]));
        }
        rclolAudioTrace("AUDIO_RENDER status=%d flags=%u frames=%u peak=%g\n",result,flags,nFrames,peak);
    }
	// std::cout << "Pull result: " << result << std::endl;
	// std::cout << "Bytes: " << outOutputData->mBuffers[0].mDataByteSize << std::endl;
	// m_auhalData.write((char*) outOutputData->mBuffers[0].mData, outOutputData->mBuffers[0].mDataByteSize);
	// m_auhalData.flush();

	return result;
}

OSStatus AUHAL::doRecord(const AudioTimeStamp* inNow, const AudioBufferList* inInputData, const AudioTimeStamp* inInputTime)
{
	// TODO: Prepare for non-interleaved audio
	std::unique_lock<std::mutex> lk(m_dataAvailableMutex);

	if (m_bufferSize < inInputData->mBuffers[0].mDataByteSize)
	{
		m_buffer.reset(new uint8_t[inInputData->mBuffers[0].mDataByteSize]);
		m_bufferSize = inInputData->mBuffers[0].mDataByteSize;
	}

	m_bufferUsed = inInputData->mBuffers[0].mDataByteSize;
	memcpy(m_buffer.get(), inInputData->mBuffers[0].mData, m_bufferUsed);

	m_dataAvailable = true;

	lk.unlock();
	m_dataAvailableCV.notify_one();

	if (m_outputAvailableCb.inputProc)
	{
		AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PostRender;
		const CAStreamBasicDescription& desc = GetStreamFormat(kAudioUnitScope_Output, kInputBus);
		UInt32 numFrames = m_bufferUsed / desc.mBytesPerFrame;

		m_outputAvailableCb.inputProc(m_outputAvailableCb.inputProcRefCon, &flags, inInputTime, kInputBus, numFrames, nullptr);
	}

	return noErr;
}

// AUDispatch.cpp doesn't implement dispatch code for AudioOutputUnits
OSStatus AUHAL::ComponentEntryDispatch(ComponentParameters *params, AUHAL *This)
{
	if (This == NULL) return kAudio_ParamError;

	OSStatus result = noErr;

	switch (params->what)
	{
		case kComponentCanDoSelect:
			switch (GetSelectorForCanDo(params))
			{
				case kAudioOutputUnitStartSelect:
				case kAudioOutputUnitStopSelect:
					return 1;
			}
			break;
		case kAudioOutputUnitStartSelect:
		{
			CAMutex::Locker lock(This->GetMutex());
			return This->Start();
		}
		case kAudioOutputUnitStopSelect:
		{
			CAMutex::Locker lock(This->GetMutex());
			return This->Stop();
		}
	}

	return AUBase::ComponentEntryDispatch(params, This);
}
