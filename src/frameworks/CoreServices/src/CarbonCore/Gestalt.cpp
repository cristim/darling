/*
This file is part of Darling.

Copyright (C) 2012-2013 Lubos Dolezel

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

#include <CarbonCore/MacErrors.h>
#include <cstring>
#include <cstdio>
#include <sys/sysctl.h>
#include <CarbonCore/Gestalt.h>

OSStatus Gestalt(uint32_t type, int* value)
{
	if (!value)
		return paramErr;
	*value = 0;
	switch (type)
	{
	case gestaltSystemVersion:
	case gestaltSystemVersionMajor:
	case gestaltSystemVersionMinor:
	case gestaltSystemVersionPatch:
	{
        // Darwin's kernel release is not the macOS product version.
        char version[64] = {};
        size_t version_len = sizeof(version);
        int major = 0, minor = 0, patch = 0;
        if (sysctlbyname("kern.osproductversion", version, &version_len, nullptr, 0) != 0)
            return gestaltUnknownErr;
        version[sizeof(version) - 1] = '\0';
        if (sscanf(version, "%d.%d.%d", &major, &minor, &patch) < 1 ||
            major < 0 || major > 99 || minor < 0 || patch < 0)
            return gestaltUnknownErr;

        if (type == gestaltSystemVersion) {
            // Legacy packed BCD: minor and bug-fix components saturate at 9.
            const int packedMajor = ((major / 10) << 4) | (major % 10);
            *value = (packedMajor << 8) | ((minor > 9 ? 9 : minor) << 4) |
                     (patch > 9 ? 9 : patch);
        } else if (type == gestaltSystemVersionMajor)
            *value = major;
        else if (type == gestaltSystemVersionMinor)
            *value = minor;
        else
            *value = patch;
        // Version selectors must not fall through to the architecture case.
        return 0;
    }
	case gestaltSysArchitecture:
#ifdef __powerpc__
		*value = gestaltPowerPC;
#elif defined(__x86_64__) || defined(__i386__)
		*value = gestaltIntel;
#endif
		break;
	default:
		*value = 0;
		return unimpErr;
	}
	return 0;
}
