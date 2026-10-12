#include <HIToolbox/Events.h>

UInt8 LMGetKbdType(void)
{
	return 0;
}

UInt8 LMGetKbdLast(void)
{
	// Darling exposes one logical keyboard through its current XKB layout.
	// Its last-used keyboard type is therefore the current keyboard type.
	return LMGetKbdType();
}
