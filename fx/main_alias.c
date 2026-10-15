#include "guest_api.h"

#ifndef ALIAS_EXPECT
#error ALIAS_EXPECT must name the authored leaf value
#endif
extern int x(void);
extern volatile int mst_alias_trigger;

int main(void)
{
	if ( mst_alias_trigger != 1 || x() != ALIAS_EXPECT )
		return 20;
	return emit(1, "alias-control-complete\n");
}
