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
#ifdef PROBE_SYSTEMCONFIGURATION
PROBE_FN(SCDynamicStoreCopyKeyList)
PROBE_FN(SCDynamicStoreCreateRunLoopSource)
PROBE_FN(SCDynamicStoreKeyCreateNetworkServiceEntity)
PROBE_FN(SCError)
PROBE_FN(SCErrorString)
PROBE_FN(SCNetworkInterfaceCopyAll)
PROBE_FN(SCNetworkInterfaceGetBSDName)
PROBE_FN(SCNetworkInterfaceGetInterface)
PROBE_FN(SCNetworkInterfaceGetInterfaceType)
PROBE_FN(SCNetworkInterfaceGetLocalizedDisplayName)
PROBE_FN(SCNetworkReachabilitySetDispatchQueue)
PROBE_FN(SCNetworkServiceGetInterface)
PROBE_FN(SCNetworkServiceGetServiceID)
PROBE_FN(SCNetworkSetCopyCurrent)
PROBE_FN(SCNetworkSetCopyServices)
PROBE_FN(SCPreferencesCreateWithAuthorization)
#endif
#ifdef PROBE_CONTACTS
PROBE_CFSTR(CNContactIdentifierKey)
#endif
#ifdef PROBE_COREGRAPHICS
PROBE_FN(CGContextBeginTransparencyLayerWithRect)
#endif
#ifdef PROBE_FOUNDATION
PROBE_FN(NSLocalizedFileSizeDescription)
#endif
