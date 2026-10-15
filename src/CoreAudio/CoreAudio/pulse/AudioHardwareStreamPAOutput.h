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

#ifndef AUDIOHARDWARESTREAMPAOUTPUT_H
#define AUDIOHARDWARESTREAMPAOUTPUT_H
#include "AudioHardwareStreamPA.h"
#include <dispatch/dispatch.h>
#include <cstdint>

class AudioHardwareStreamPAOutput : public AudioHardwareStreamPA
{
public:
	AudioHardwareStreamPAOutput(AudioHardwareImplPA* hw, AudioDeviceIOProc callback, void* clientData);
	~AudioHardwareStreamPAOutput();
	void stop() override;
private:
	enum class RenderResult { Written, NoSpace, Stopped };

	uint64_t m_frames = 0;
	void start() override;
	static void paStreamWriteCB(pa_stream* s, size_t length, void* self);

	// IO cycle pacing; everything below is only touched on the PA queue.
	void cancelTimer();
	void prefill();
	void tick();
	void armTimer(uint64_t nowNs);
	uint64_t deadlineNs() const;
	RenderResult renderBlock(bool trace);
	uint64_t outputLatencyNs(size_t writable, bool* fromPA);

	dispatch_source_t m_timer = nullptr;
	size_t m_blockBytes = 0;
	uint32_t m_blockFrames = 0;
	double m_periodNs = 0;
	bool m_primed = false;
	bool m_corked = false;
	// Deadline k is m_anchorNs + k * m_periodNs - m_advanceNs.
	uint64_t m_anchorNs = 0;
	uint64_t m_tickIndex = 0;
	double m_advanceNs = 0;
	// Drift servo: smallest writable size seen over the current window of ticks.
	size_t m_windowMinWritable = SIZE_MAX;
	unsigned m_windowTicks = 0;
	double m_servoStepNs = 0;
	uint64_t m_lastIOProcHost = 0;
};

#endif /* AUDIOHARDWARESTREAMPA_H */
