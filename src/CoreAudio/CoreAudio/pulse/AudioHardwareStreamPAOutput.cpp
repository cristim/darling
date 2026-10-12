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

#include "AudioHardwareStreamPAOutput.h"
#include "AudioHardwareImplPA.h"
#include <iostream>
#include <algorithm>
#include <mach/mach_time.h>

AudioHardwareStreamPAOutput::AudioHardwareStreamPAOutput(AudioHardwareImplPA* hw, AudioDeviceIOProc callback, void* clientData)
: AudioHardwareStreamPA(hw, callback, clientData)
{
    initialize();
}

void AudioHardwareStreamPAOutput::paStreamWriteCB(pa_stream* s, size_t length, void* self)
{
	AudioHardwareStreamPAOutput* This = static_cast<AudioHardwareStreamPAOutput*>(self);

	if (!This->m_running)
	{
		pa_stream_cork(This->m_stream, true, [](pa_stream*, int, void*) {}, nullptr);
		return;
	}

	// std::cout << "AudioHardwareStreamPAOutput::paStreamWriteCB()\n";

	AudioTimeStamp fake = {0};
	AudioBufferList* abl = static_cast<AudioBufferList*>(alloca(sizeof(AudioBufferList) + sizeof(AudioBuffer)));

	size_t done = 0;

	while (done < length && This->m_running)
	{
		// Non-interleaved (planar) audio would have multiple buffers, but PA doesn't even support that AFAIK
		abl->mNumberBuffers = 1;

		abl->mBuffers[0].mNumberChannels = 2;
		// abl->mBuffers[0].mData = This->m_buffer;

		// std::cout << "AudioHardwareStreamPAOutput() length req=" << length << ", done=" << done << std::endl;
		size_t rqsize = std::min<UInt32>(This->m_bufferSize, length-done);
        if(pa_stream_begin_write(This->m_stream,(void**)&abl->mBuffers[0].mData,&rqsize)<0 || !rqsize) break;

		abl->mBuffers[0].mDataByteSize = rqsize;
        fake.mHostTime=mach_absolute_time();
        fake.mSampleTime=This->m_frames;
        fake.mFlags=kAudioTimeStampHostTimeValid|kAudioTimeStampSampleTimeValid;

		// Call the client for more data
		OSStatus status = This->m_callback(This->m_hw->id(), &fake, nullptr, nullptr, abl, &fake, This->m_clientData);
        if (!This->m_running) {
            // The client stopped/disconnected the stream during its IOProc.
            pa_stream_cancel_write(s);
            return;
        }
		if (status != noErr || !abl->mBuffers[0].mDataByteSize)
		{
			// std::cerr << "AudioDeviceIOProc returned " << status << ", corking...\n";

			pa_stream_cork(This->m_stream, true, [](pa_stream*, int, void*) {}, nullptr);
			pa_stream_cancel_write(This->m_stream);
			break;
		}
		else
		{
			if (This->m_convertSignedUnsigned)
				This->transformSignedUnsigned(abl);
				
			// std::cout << "AudioHardwareStreamPAOutput::paStreamWriteCB(): got " << abl->mBuffers[0].mDataByteSize << " bytes\n";
			int rv = pa_stream_write(This->m_stream, abl->mBuffers[0].mData, abl->mBuffers[0].mDataByteSize, nullptr, 0, PA_SEEK_RELATIVE);
			if (rv != 0)
			{
				// std::cerr << "pa_stream_write() failed\n";
				break;
			}
			//else
			//	std::cout << "pa_stream_write() OK\n";
		}

		done += abl->mBuffers[0].mDataByteSize;
        if(This->m_hw->asbd().mBytesPerFrame) This->m_frames+=abl->mBuffers[0].mDataByteSize/This->m_hw->asbd().mBytesPerFrame;
	}
}

void AudioHardwareStreamPAOutput::start()
{
	struct pa_buffer_attr battr;

	battr.fragsize = uint32_t(-1);
	battr.maxlength = uint32_t(m_bufferSize);
	battr.minreq = uint32_t(-1);
	battr.prebuf = battr.maxlength;
	battr.tlength = uint32_t(-1);

	pa_stream_set_write_callback(m_stream, paStreamWriteCB, this);

	pa_stream_connect_playback(m_stream, nullptr, &battr, pa_stream_flags_t(PA_STREAM_INTERPOLATE_TIMING
                                 |PA_STREAM_ADJUST_LATENCY
                                 |PA_STREAM_AUTO_TIMING_UPDATE) /* PA_STREAM_START_CORKED */,
			nullptr, nullptr);

	// pa_stream_cork(m_stream, false, [](pa_stream*, int, void*) {}, nullptr);
	AudioHardwareStreamPA::start();
}
