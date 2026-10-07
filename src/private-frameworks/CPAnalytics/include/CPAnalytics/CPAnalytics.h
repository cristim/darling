/*
	CPAnalytics.private

	Apple's private framework that Photo Booth links for its "CPAnalyticsPayload"
	view-tracking events. The app imports exactly five symbols from it and calls
	none of them on any path this build reaches, but dyld still has to bind them or
	the process will not start.

	Symbols bound by Photo Booth (read off `nm -u`, both slices):

	    _CPAnalyticsEventViewDidAppear
	    _CPAnalyticsEventViewDidDisappear
	    _CPAnalyticsPayloadClassNameKey
	    _CPAnalyticsPayloadViewIDKey
	    _OBJC_CLASS_$_CPAnalytics

	There is no SDK header for this framework, so nothing here is guessed from a
	prototype: the two functions are only ever imported, never called, so they are
	exported with the simplest signature that satisfies the bind. The two keys are
	real CFStringRefs because the app reads them if it ever builds a payload
	dictionary, and the class is a real Objective-C class so messaging it works.
*/

#ifndef CPANALYTICS_H
#define CPANALYTICS_H

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Imported by the app but never called on any path it reaches here. */
void CPAnalyticsEventViewDidAppear(void);
void CPAnalyticsEventViewDidDisappear(void);

#ifdef __cplusplus
}
#endif

#endif
