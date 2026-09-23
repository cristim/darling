// LOCAL OBSERVATION PROBE, never published.
#include "probe.h"
#ifdef PROBE_LSS
PROBE_FN(_LSForceQuitApplication)
PROBE_CFSTR(_kLSForceQuitApplicationPresentFirstForceQuitDialogKey)
#endif
#ifdef PROBE_RSD
PROBE_FN(remote_device_copy_property)
PROBE_FN(remote_device_copy_unique_of_type)
#endif
#ifdef PROBE_SYSSTATS
PROBE_FN(systemstats_get_battery_charge_graph)
PROBE_FN(systemstats_get_top_coalitions)
#endif
#ifdef PROBE_SAFEEJECT
@interface SafeEjectGPU : NSObject @end
@implementation SafeEjectGPU
PROBE_FORWARDING
@end
#endif
#ifdef PROBE_ACSE
@interface AssetCacheMetricsReader : NSObject @end
@implementation AssetCacheMetricsReader
PROBE_FORWARDING
@end
@interface AssetCacheServicesManager : NSObject @end
@implementation AssetCacheServicesManager
PROBE_FORWARDING
@end
NSString *const kACMetricsDatabaseDirectory = @"probe:kACMetricsDatabaseDirectory";
NSString *const kACMetricsDatabaseName = @"probe:kACMetricsDatabaseName";
#endif
#ifdef PROBE_AOSKIT
PROBE_FN(AOSAccountCreate)
PROBE_FN(AOSTransactionGetError)
PROBE_FN(AOSTransactionGetResult)
PROBE_FN(AOSTransactionSuccessful)
PROBE_FN(_AOSAccountRetrieveInfo)
PROBE_CFSTR(kAOSAppleAccountInfoKey)
PROBE_CFSTR(kAOSErrorDomain)
PROBE_CFSTR(kAOSMMeInfoKey)
PROBE_CFSTR(kAOSPersonIDKey)
PROBE_CFSTR(kAOSTokensKey)
PROBE_CFSTR(kAOSURLKey)
#endif
#ifdef PROBE_SUGGESTIONS
#endif
