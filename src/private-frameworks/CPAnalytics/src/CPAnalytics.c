/*
	CPAnalytics.private

	Exports the symbols Photo Booth binds. See include/CPAnalytics/CPAnalytics.h
	for how the list was obtained and why nothing here is invented: the two
	functions are imported but never called, and the two keys are read as ordinary
	CFStringRef constants.
*/

#include <CoreFoundation/CoreFoundation.h>

void CPAnalyticsEventViewDidAppear(void) {
}

void CPAnalyticsEventViewDidDisappear(void) {
}

/* Keys for the payload dictionary. The app reads these when it reports a view
   event, so they are real strings rather than NULL. */
CFStringRef CPAnalyticsPayloadClassNameKey = CFSTR("CPAnalyticsPayloadClassName");
CFStringRef CPAnalyticsPayloadViewIDKey = CFSTR("CPAnalyticsPayloadViewID");
