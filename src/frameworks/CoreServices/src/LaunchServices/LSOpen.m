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


#include <LaunchServices/LaunchServices.h>
#include <LaunchServices/LaunchServicesPriv.h>
#include <CarbonCore/MacErrors.h>
#include "LSHostOpen.h"
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

// darling-lol M2a: minimal bundle launching.
// Supports: file URLs (or bare POSIX paths) pointing at .app bundles,
// optionally with an explicit target app via inAppParams->application.
// The bundle's executable is spawned directly with the emulated posix_spawn
// (no launchd job registration yet — see _LSLaunchApplication).
// NOT yet supported (documented deviations):
//  - AppleEvent delivery (oapp/odoc): the app is spawned bare, as if launched
//    by hand. Apps waiting for their initial event will park. Needs #425/#937.
//  - inAppParams->argv / ->environment: not propagated (_LSLaunchApplication
//    takes no argv yet).
//  - inRole / launch flags (kLSLaunchNewInstance etc.): every launch spawns a
//    new instance; no running-app registry, so outPSNs is left untouched.
//  - non-bundle documents without an explicit application: there is no default
//    handler database yet (needs UTI/LaunchServices DB).
static OSStatus
LSOpenOneURL(CFURLRef url, const LSApplicationParameters *params)
{
	CFStringRef pathStr;
	char path[4096];
	struct stat st;
	CFURLRef appURL = NULL;
	OSStatus status;

	if (url == NULL)
		return paramErr;

	if ((params == NULL || params->application == NULL) && _LSIsHostOpenURL(url))
		return _LSOpenURLOnHost(url);

	// open(1) builds URLs via +URLWithString from a raw path, which may yield
	// a scheme-less URL object. CFURLCopyFileSystemPath works either way.
	pathStr = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle);
	if (pathStr == NULL)
		return paramErr;

	if (!CFStringGetCString(pathStr, path, sizeof(path), kCFStringEncodingUTF8))
	{
		CFRelease(pathStr);
		return paramErr;
	}
	CFRelease(pathStr);

	if (params != NULL && params->application != NULL)
	{
		// Explicit target application wins; the URLs become its documents
		// (delivered as argv once M2c lands; for now they are dropped).
		char appPath[4096];
		CFStringRef appStr;
		status = FSRefMakePath(params->application, (UInt8*) appPath, sizeof(appPath) - 1);
		if (status != noErr)
			return status;
		appStr = CFStringCreateWithCString(NULL, appPath, kCFStringEncodingUTF8);
		appURL = CFURLCreateWithFileSystemPath(NULL, appStr, kCFURLPOSIXPathStyle, TRUE);
		CFRelease(appStr);
	}
	else
	{
		size_t len = strlen(path);
		Boolean looksLikeBundle = FALSE;

		if (len > 4 && strcasecmp(path + len - 4, ".app") == 0)
			looksLikeBundle = TRUE;
		else if (stat(path, &st) == 0 && S_ISDIR(st.st_mode))
		{
			// Bundle without .app suffix (e.g. helper apps, frameworks-as-apps).
			char plist[4096 + 32];
			snprintf(plist, sizeof(plist), "%s/Contents/Info.plist", path);
			if (stat(plist, &st) == 0)
				looksLikeBundle = TRUE;
		}

		if (!looksLikeBundle)
			return kLSApplicationNotFoundErr; // no default-handler DB yet

		CFStringRef tmp = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
		appURL = CFURLCreateWithFileSystemPath(NULL, tmp, kCFURLPOSIXPathStyle, TRUE);
		CFRelease(tmp);
	}

	if (appURL == NULL)
		return paramErr;

	status = _LSLaunchApplication(appURL);
	CFRelease(appURL);

	// _LSLaunchApplication returns 1 on failure instead of a MacErrors code.
	if (status != noErr)
		status = fnfErr;
	return status;
}

OSStatus
LSOpenURLsWithRole(
  CFArrayRef inURLs,
  LSRolesMask inRole,
  const AEKeyDesc * inAEParam,
  const LSApplicationParameters * inAppParams,
  ProcessSerialNumber * outPSNs,
  CFIndex inMaxPSNCount)
{
	CFIndex count, i, launched = 0;
	OSStatus status, firstErr = noErr;

	(void) inRole;
	(void) inAEParam;
	(void) outPSNs;
	(void) inMaxPSNCount;

	if (inURLs == NULL || (count = CFArrayGetCount(inURLs)) <= 0)
		return paramErr;

	for (i = 0; i < count; i++)
	{
		status = LSOpenOneURL(CFArrayGetValueAtIndex(inURLs, i), inAppParams);
		if (status == noErr)
			launched++;
		else if (launched == 0 && firstErr == noErr)
			firstErr = status;
	}

	return launched > 0 ? noErr : firstErr;
}

OSStatus
LSOpenItemsWithRole(
  const FSRef * inItems,
  CFIndex inItemCount,
  LSRolesMask inRole,
  const AEKeyDesc * inAEParam,
  const LSApplicationParameters * inAppParams,
  ProcessSerialNumber * outPSNs,
  CFIndex inMaxPSNCount)
{

	CFURLRef* urls = (CFURLRef*) malloc(inItemCount * sizeof(CFURLRef));

	for (CFIndex i = 0; i < inItemCount; i++)
	{
		char path[4096];

		OSStatus status = FSRefMakePath(&inItems[i], (UInt8*) path, sizeof(path)-1);
		if (status != noErr)
		{
			for (CFIndex j; j < i; j++)
				CFRelease(urls[j]);
			free(urls);
			return status;
		}

		CFStringRef urlStr = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
		urls[i] = CFURLCreateWithFileSystemPath(NULL, urlStr, kCFURLPOSIXPathStyle, FALSE);
		CFRelease(urlStr);
	}

	CFArrayRef urlArray = CFArrayCreate(NULL, (const void**) urls, inItemCount, &kCFTypeArrayCallBacks);
	for (CFIndex i; i < inItemCount; i++)
		CFRelease(urls[i]);
	free(urls);

	OSStatus status = LSOpenURLsWithRole(urlArray, inRole, inAEParam, inAppParams, outPSNs, inMaxPSNCount);

	CFRelease(urlArray);

	return status;
}

OSStatus LSOpenFSRef(const FSRef *inRef, FSRef *outLaunchedRef)
{
	char path[4096];

	OSStatus status = FSRefMakePath(inRef, (UInt8*) path, sizeof(path)-1);
	if (status != noErr)
		return status;

	CFStringRef urlStr = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL, urlStr, kCFURLPOSIXPathStyle, FALSE);
	CFRelease(urlStr);
	
	CFURLRef launchedUrl;
	status = LSOpenCFURLRef(url, &launchedUrl);

	CFRelease(url);

	if (status != noErr)
		return status;

	if (outLaunchedRef)
	{
		CFStringRef path = CFURLCopyFileSystemPath(launchedUrl, kCFURLPOSIXPathStyle);
		status = FSPathMakeRef((const UInt8*) CFStringGetCStringPtr(path, kCFStringEncodingUTF8), outLaunchedRef, NULL);
		CFRelease(path);
	}
	
	CFRelease(launchedUrl);
	return status;
}

OSStatus LSOpenCFURLRef(CFURLRef inURL, CFURLRef *outLaunchedURL)
{
	OSStatus ret;
	LSLaunchURLSpec spec;

	memset(&spec, 0, sizeof(spec));

	spec.itemURLs = CFArrayCreate(kCFAllocatorDefault, (const void**)&inURL, 1, NULL);
	ret = LSOpenFromURLSpec(&spec, outLaunchedURL);
	CFRelease(spec.itemURLs);
	
	return ret;
}

/*
OSStatus LSOpenApplication(const LSApplicationParameters *appParams, ProcessSerialNumber *outPSN)
{

}
*/

/*
OSStatus
LSOpenFromURLSpec(
  const LSLaunchURLSpec * inLaunchSpec,
  _Nullable CFURLRef *_Nullable outLaunchedURL)
{
}
*/
