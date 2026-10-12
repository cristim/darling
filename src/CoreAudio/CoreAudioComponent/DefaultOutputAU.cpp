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
#include "DefaultOutputAU.h"

#include <cstring>
#include <stdlib.h>
#pragma GCC visibility push(default)
AUDIOCOMPONENT_ENTRY(AUOutputBaseFactory, DefaultOutputAU);
#pragma GCC visibility pop

enum {
	kOutputBus = 0,
	kInputBus
};

DefaultOutputAU::DefaultOutputAU(AudioComponentInstance inInstance)
: AUHAL(inInstance)
{
}

/* darling-lol: League's game process sets the default device as the current device of its DefaultOutput unit. Refusing that
 * (kAudioUnitErr_InvalidProperty) made it throw its audio graph away and build a new one in a loop, so it never played
 * anything. Accepting it harmless: the unit plays on the default device anyway.
 *
 * Only the game process gets this. With the property accepted everywhere, the League client's Vanguard module went to its
 * error state (MvgState 5, status -101) on every launch (2 of 2, 2026-10-11) and the client could not start a match;
 * with the old behaviour it connected again (state 0). */
static bool callerIsLeagueGame()
{
	static const bool game = []{
		const char* name = getprogname();
		return name && strcmp(name, "LeagueofLegends") == 0;
	}();
	return game;
}

OSStatus DefaultOutputAU::GetPropertyInfo(AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, UInt32& outDataSize, Boolean& outWritable)
{
	OSStatus status = AUHAL::GetPropertyInfo(inID, inScope, inElement, outDataSize, outWritable);

	if (inID == kAudioOutputUnitProperty_CurrentDevice && !callerIsLeagueGame())
		outWritable = false;

	return status;
}

OSStatus DefaultOutputAU::SetProperty(AudioUnitPropertyID inID, AudioUnitScope inScope,
	AudioUnitElement inElement, const void* inData, UInt32 inDataSize)
{
	switch (inID)
	{
		case kAudioOutputUnitProperty_CurrentDevice:
			if (!callerIsLeagueGame())
				return kAudioUnitErr_InvalidProperty;
			break;
	}
	return AUHAL::SetProperty(inID, inScope, inElement, inData, inDataSize);
}
