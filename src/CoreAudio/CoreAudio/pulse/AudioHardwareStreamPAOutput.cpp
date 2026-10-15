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
#include "../../AudioTrace.h"

// Real CoreAudio calls an output IOProc once per IO cycle: evenly spaced at the buffer
// period, with inOutputTime.mHostTime advancing by one buffer duration per call. Clients
// such as Chromium's AUHALStream rely on that (they read the previous renderer buffer and
// request the next one on every call), so PulseAudio's bursty write requests must not
// drive the IOProc directly. Instead a dispatch timer on the PA queue ticks at the block
// period and renders at most one block per tick (plus bounded catch-up after a late wakeup).

static const unsigned kPrefillBlocks = 8;    // == tlength
static const unsigned kMaxCatchUpBlocks = 2; // extra blocks after a late wakeup
static const unsigned kServoWindowTicks = 32;

static bool rateLimited(unsigned& counter, unsigned head, unsigned every) {
	if (!rclolAudioTraceEnabled()) return false;
	unsigned n = counter++;
	return n < head || n % every == 0;
}
static unsigned g_wcbEvents = 0, g_iopEvents = 0, g_tickEvents = 0, g_paceEvents = 0;
static bool wcbShouldTrace() { return rateLimited(g_wcbEvents, 50, 1000); }
static bool iopShouldTrace() { return rateLimited(g_iopEvents, 200, 500); }
static bool tickShouldTrace() { return rateLimited(g_tickEvents, 200, 500); }
static bool paceShouldTrace() { return rateLimited(g_paceEvents, 100, 100); }

static const mach_timebase_info_data_t& timebase() {
	static mach_timebase_info_data_t tb = [] {
		mach_timebase_info_data_t t = {0, 0};
		mach_timebase_info(&t);
		if (!t.numer || !t.denom) t.numer = t.denom = 1;
		return t;
	}();
	return tb;
}
static uint64_t hostToNs(uint64_t host) {
	return uint64_t((unsigned __int128) host * timebase().numer / timebase().denom);
}
static uint64_t nsToHost(uint64_t ns) {
	return uint64_t((unsigned __int128) ns * timebase().denom / timebase().numer);
}
static uint64_t nowNs() { return hostToNs(mach_absolute_time()); }

AudioHardwareStreamPAOutput::AudioHardwareStreamPAOutput(AudioHardwareImplPA* hw, AudioDeviceIOProc callback, void* clientData)
: AudioHardwareStreamPA(hw, callback, clientData)
{
    initialize();
}

AudioHardwareStreamPAOutput::~AudioHardwareStreamPAOutput()
{
	// Normally already done by stop(); the timer must never outlive this object.
	static_cast<AudioHardwareImplPA*>(m_hw)->syncPA(^{ m_running = false; cancelTimer(); });
}

void AudioHardwareStreamPAOutput::stop()
{
	// Runs on (or synchronously with) the PA queue, so no tick is in flight unless stop()
	// was called from inside the IOProc, which renderBlock() handles via m_running.
	// Cancellation guarantees the timer handler is never invoked again.
	static_cast<AudioHardwareImplPA*>(m_hw)->syncPA(^{ m_running = false; cancelTimer(); });
	AudioHardwareStreamPA::stop();
}

void AudioHardwareStreamPAOutput::cancelTimer()
{
	if (m_timer)
	{
		dispatch_source_cancel(m_timer);
		dispatch_release(m_timer);
		m_timer = nullptr;
	}
}

uint64_t AudioHardwareStreamPAOutput::outputLatencyNs(size_t writable, bool* fromPA)
{
	pa_usec_t usec = 0;
	int negative = 0;
	if (pa_stream_get_latency(m_stream, &usec, &negative) == 0)
	{
		*fromPA = true;
		return negative ? 0 : uint64_t(usec) * 1000;
	}
	// No timing info yet: at least account for what is queued in the PA buffer.
	*fromPA = false;
	const pa_buffer_attr* attr = pa_stream_get_buffer_attr(m_stream);
	const pa_sample_spec* spec = pa_stream_get_sample_spec(m_stream);
	if (!attr || !spec || writable == size_t(-1) || attr->tlength <= writable)
		return 0;
	return uint64_t(pa_bytes_to_usec(attr->tlength - writable, spec)) * 1000;
}

AudioHardwareStreamPAOutput::RenderResult AudioHardwareStreamPAOutput::renderBlock(bool trace)
{
	if (!m_running || m_corked || !m_stream || !m_blockBytes)
		return RenderResult::Stopped;

	const size_t writable = pa_stream_writable_size(m_stream);
	if (writable == size_t(-1) || writable < m_blockBytes)
		return RenderResult::NoSpace;

	AudioBufferList* abl = static_cast<AudioBufferList*>(alloca(sizeof(AudioBufferList) + sizeof(AudioBuffer)));
	// Non-interleaved (planar) audio would have multiple buffers, but PA doesn't even support that AFAIK
	abl->mNumberBuffers = 1;
	abl->mBuffers[0].mNumberChannels = m_hw->asbd().mChannelsPerFrame;

	size_t rqsize = m_blockBytes;
	if (pa_stream_begin_write(m_stream, (void**)&abl->mBuffers[0].mData, &rqsize) < 0 || !rqsize)
	{
		if (paceShouldTrace()) rclolAudioTrace("PA_OUT begin_write failed rqsize=%zu\n", rqsize);
		return RenderResult::NoSpace;
	}
	if (rqsize < m_blockBytes)
	{
		// Never hand the client a partial block (real HALs use a fixed frame count).
		if (paceShouldTrace()) rclolAudioTrace("PA_OUT granted rqsize=%zu < block=%zu: cancel\n", rqsize, m_blockBytes);
		pa_stream_cancel_write(m_stream);
		return RenderResult::NoSpace;
	}
	abl->mBuffers[0].mDataByteSize = m_blockBytes;

	bool latencyFromPA = false;
	const uint64_t latencyNs = outputLatencyNs(writable, &latencyFromPA);
	const double rate = m_hw->asbd().mSampleRate;
	const double latencyFrames = rate > 0 ? double(latencyNs) * rate / 1e9 : 0;
	const uint64_t nowHost = mach_absolute_time();

	AudioTimeStamp now = {0};
	now.mHostTime = nowHost;
	// Device position currently being played: the block about to be rendered starts
	// latencyFrames after it, matching the host-time difference below.
	now.mSampleTime = std::max(0.0, double(m_frames) - latencyFrames);
	now.mRateScalar = 1.0;
	now.mFlags = kAudioTimeStampHostTimeValid | kAudioTimeStampSampleTimeValid | kAudioTimeStampRateScalarValid;

	AudioTimeStamp output = now;
	output.mHostTime = nowHost + nsToHost(latencyNs);
	output.mSampleTime = double(m_frames);

	const double dHostMs = m_lastIOProcHost ? double(hostToNs(nowHost - m_lastIOProcHost)) / 1e6 : 0;
	m_lastIOProcHost = nowHost;

	OSStatus status = m_callback(m_hw->id(), &now, nullptr, nullptr, abl, &output, m_clientData);
	if (trace)
		rclolAudioTrace("PA_OUT iop dHostMs=%.3f writable=%zu latencyMs=%.2f(%s) frames=%llu status=%d size=%u\n",
			dHostMs, writable, double(latencyNs) / 1e6, latencyFromPA ? "pa" : "est",
			(unsigned long long) m_frames, (int) status, (unsigned) abl->mBuffers[0].mDataByteSize);

	if (!m_running)
	{
		// The client stopped/disconnected the stream during its IOProc.
		pa_stream_cancel_write(m_stream);
		return RenderResult::Stopped;
	}
	if (status != noErr || !abl->mBuffers[0].mDataByteSize)
	{
		if (paceShouldTrace()) rclolAudioTrace("PA_OUT IOProc failed/empty status=%d size=%u: CORK\n", (int) status,
			(unsigned) abl->mBuffers[0].mDataByteSize);
		pa_stream_cancel_write(m_stream);
		pa_stream_cork(m_stream, true, [](pa_stream*, int, void*) {}, nullptr);
		m_corked = true;
		return RenderResult::Stopped;
	}

	if (m_convertSignedUnsigned)
		transformSignedUnsigned(abl);

	// Always submit exactly one block so the sample clock stays block-aligned.
	int rv = pa_stream_write(m_stream, abl->mBuffers[0].mData, m_blockBytes, nullptr, 0, PA_SEEK_RELATIVE);
	if (rv != 0)
	{
		if (paceShouldTrace()) rclolAudioTrace("PA_OUT pa_stream_write rv=%d\n", rv);
		return RenderResult::NoSpace;
	}
	m_frames += m_blockFrames;
	return RenderResult::Written;
}

uint64_t AudioHardwareStreamPAOutput::deadlineNs() const
{
	return m_anchorNs + uint64_t(std::max(0.0, double(m_tickIndex) * m_periodNs - m_advanceNs));
}

void AudioHardwareStreamPAOutput::armTimer(uint64_t now)
{
	if (!m_timer)
		return;
	const uint64_t deadline = deadlineNs();
	const int64_t delta = deadline > now ? int64_t(deadline - now) : 0;
	dispatch_source_set_timer(m_timer, dispatch_time(DISPATCH_TIME_NOW, delta), DISPATCH_TIME_FOREVER, 100 * NSEC_PER_USEC);
}

void AudioHardwareStreamPAOutput::prefill()
{
	if (!m_running || m_corked || m_primed || !m_stream || pa_stream_get_state(m_stream) != PA_STREAM_READY)
		return;

	// The only burst: fill the target buffer once at start.
	unsigned blocks = 0;
	RenderResult r = RenderResult::Written;
	while (blocks < kPrefillBlocks && (r = renderBlock(iopShouldTrace())) == RenderResult::Written)
		++blocks;
	if (rclolAudioTraceEnabled())
		rclolAudioTrace("PA_OUT prefill blocks=%u result=%d periodMs=%.3f blockFrames=%u\n", blocks, (int) r,
			m_periodNs / 1e6, m_blockFrames);
	if (r == RenderResult::Stopped || !blocks)
		return;

	m_primed = true;
	m_anchorNs = nowNs();
	m_tickIndex = 1;
	m_advanceNs = 0;
	armTimer(m_anchorNs);
}

void AudioHardwareStreamPAOutput::tick()
{
	if (!m_running || m_corked || !m_timer)
		return;
	if (!m_primed)
	{
		prefill();
		return;
	}

	uint64_t now = nowNs();
	uint64_t deadline = deadlineNs();
	if (now < deadline)
	{
		// Early wakeup (leeway); wait for the real deadline.
		armTimer(now);
		return;
	}

	const bool trace = tickShouldTrace();
	const size_t writable = pa_stream_writable_size(m_stream);
	if (writable != size_t(-1))
		m_windowMinWritable = std::min(m_windowMinWritable, writable);

	const uint64_t behind = uint64_t(double(now - deadline) / m_periodNs);
	unsigned toRender = 1;
	if (behind > kMaxCatchUpBlocks)
	{
		// Far behind (stalled queue, suspended process): don't burst, restart the clock.
		if (paceShouldTrace())
			rclolAudioTrace("PA_OUT reanchor lateMs=%.3f behindBlocks=%llu\n", double(now - deadline) / 1e6,
				(unsigned long long) behind);
		m_anchorNs = now;
		m_tickIndex = 0;
		m_advanceNs = 0;
	}
	else if (behind)
	{
		toRender += unsigned(behind);
		if (paceShouldTrace())
			rclolAudioTrace("PA_OUT catchup lateMs=%.3f blocks=%u\n", double(now - deadline) / 1e6, toRender);
	}

	if (trace)
		rclolAudioTrace("PA_OUT tick lateMs=%.3f writable=%zu render=%u\n", double(now - deadline) / 1e6, writable, toRender);

	for (unsigned i = 0; i < toRender; i++)
	{
		RenderResult r = renderBlock(iopShouldTrace());
		if (r == RenderResult::Stopped)
			return; // also covers stop() from inside the IOProc (timer already cancelled)
		if (r == RenderResult::NoSpace && paceShouldTrace())
			rclolAudioTrace("PA_OUT skip: writable=%zu < block=%zu\n", pa_stream_writable_size(m_stream), m_blockBytes);
		// The IO cycle elapses either way; a skipped cycle means PA is consuming slower than us.
		++m_tickIndex;
	}

	// Drift servo: the PA sink clock isn't our clock. If the buffer stayed under-filled for a
	// whole window (min writable >= 2 blocks), run ~6% faster for the next window. Each tick
	// stays a single, evenly spaced IOProc call.
	if (++m_windowTicks >= kServoWindowTicks)
	{
		const bool low = m_windowMinWritable != SIZE_MAX && m_windowMinWritable >= 2 * m_blockBytes;
		const double step = low ? m_periodNs / 16 : 0;
		if (step != m_servoStepNs && paceShouldTrace())
			rclolAudioTrace("PA_OUT servo minWritable=%zu step=%s\n", m_windowMinWritable, low ? "fast" : "off");
		m_servoStepNs = step;
		m_windowMinWritable = SIZE_MAX;
		m_windowTicks = 0;
	}
	m_advanceNs += m_servoStepNs;

	armTimer(nowNs());
}

void AudioHardwareStreamPAOutput::paStreamWriteCB(pa_stream* s, size_t length, void* self)
{
	AudioHardwareStreamPAOutput* This = static_cast<AudioHardwareStreamPAOutput*>(self);

	if (!This->m_running)
	{
		if (wcbShouldTrace()) rclolAudioTrace("PA_WRITE_CB length=%zu not-running: corking\n", length);
		pa_stream_cork(This->m_stream, true, [](pa_stream*, int, void*) {}, nullptr);
		return;
	}

	// Rendering is paced by the IO timer; the write request only triggers the initial prefill.
	if (wcbShouldTrace())
		rclolAudioTrace("PA_WRITE_CB length=%zu writable=%zu primed=%d corked=%d\n", length,
			pa_stream_writable_size(s), This->m_primed, This->m_corked);
	if (!This->m_timer)
	{
		// No pacing timer could be created: fall back to rendering whole blocks on demand.
		while (This->renderBlock(iopShouldTrace()) == RenderResult::Written) {}
		return;
	}
	if (!This->m_primed)
		This->prefill();
}

void AudioHardwareStreamPAOutput::start()
{
	struct pa_buffer_attr battr;

	battr.fragsize = uint32_t(-1);
	// Size the server buffer in whole IOProc blocks so every IO cycle can supply one.
	uint32_t bpf = m_hw->asbd().mBytesPerFrame;
	uint32_t block = bpf ? (m_hw->bufferSize() / bpf) * bpf : m_bufferSize;
	if (!block)
		block = m_bufferSize;
	// ~46 ms target at 256 frames/44.1 kHz: a 2-block target underran, since each
	// block waits on a cross-process round trip to the client's renderer.
	battr.maxlength = block * 16;
	battr.minreq = block;
	battr.prebuf = block * 2;
	battr.tlength = block * kPrefillBlocks;

	// Real HALs always call the IOProc with the same frame count (kAudioDevicePropertyBufferFrameSize).
	m_blockFrames = bpf ? m_hw->bufferSize() / bpf : 0;
	m_blockBytes = size_t(m_blockFrames) * bpf;
	const double rate = m_hw->asbd().mSampleRate;
	m_periodNs = rate > 0 ? double(m_blockFrames) * 1e9 / rate : 0;

	// start() runs on the PA queue, so the timer shares its serialization with all pa_* calls.
	// Disabled: Darling's dispatch timers fire 3-35 ms late (one stalled 30 s), which starved
	// PA into silence. Render on PA's write requests instead; the output timestamps still
	// come from PA's latency, so blocks within one request get correctly spaced play times.
	static const bool kUsePacingTimer = false;
	dispatch_queue_t queue = static_cast<AudioHardwareImplPA*>(m_hw)->paQueue();
	if (kUsePacingTimer && queue && m_blockBytes && m_periodNs > 0)
	{
		m_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
		if (m_timer)
		{
			dispatch_source_set_event_handler(m_timer, ^{ tick(); });
			// Resumed immediately (a suspended source can't be released); armed after prefill.
			dispatch_source_set_timer(m_timer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
			dispatch_resume(m_timer);
		}
	}
	if (rclolAudioTraceEnabled())
		rclolAudioTrace("PA_OUT start block=%zu frames=%u periodMs=%.3f timer=%d\n", m_blockBytes, m_blockFrames,
			m_periodNs / 1e6, m_timer != nullptr);

	pa_stream_set_write_callback(m_stream, paStreamWriteCB, this);

	pa_stream_connect_playback(m_stream, nullptr, &battr, pa_stream_flags_t(PA_STREAM_INTERPOLATE_TIMING
                                 |PA_STREAM_ADJUST_LATENCY
                                 |PA_STREAM_AUTO_TIMING_UPDATE) /* PA_STREAM_START_CORKED */,
			nullptr, nullptr);

	AudioHardwareStreamPA::start();
}
