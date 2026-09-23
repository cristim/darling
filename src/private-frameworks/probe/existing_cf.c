// LOCAL OBSERVATION PROBE, never published.
#include "probe.h"
#ifdef PROBE_CORESERVICES
PROBE_FN(_LSModifyNotification)
PROBE_FN(_LSScheduleNotificationFunctionOnQueue_f)
PROBE_FN(_LSUnscheduleNotificationFunction)
PROBE_CFSTR(_kLSParentASNKey)
#endif
#ifdef PROBE_CORESYMBOLICATION
const CFSetCallBacks kCSTypeSetCallBacks = {0};
#endif
#ifdef PROBE_IOREPORT
PROBE_FN(IOReportChannelGetChannelID)
#endif
#ifdef PROBE_COREGRAPHICS
PROBE_FN(CGSEventIsAppUnresponsive)
#endif
