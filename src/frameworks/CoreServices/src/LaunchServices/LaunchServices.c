/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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
#include "LSHostOpen.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <spawn.h>

extern char** environ;

static void get_main_executable_info(CFURLRef appURL, CFStringRef *exec, CFStringRef *bundleName);

static int verbose = 0;

__attribute__((constructor)) static void initme(void) {
	verbose = getenv("STUB_VERBOSE") != NULL;
}

OSStatus LSRegisterURL(CFURLRef inURL, Boolean inUpdate)
{
	if (verbose)
		printf("STUB: LSRegisterURL\n");
	return 0;
}

OSStatus LSOpenFromURLSpec(const LSLaunchURLSpec *inLaunchSpec, CFURLRef *outLaunchedURL)
{
	CFStringRef scheme, extension;
	CFIndex count, i;
	CFURLRef url;
	CFRange range;
	OSStatus ret = 0, temp;

	/* Inspect scheme of URL */
	count = CFArrayGetCount(inLaunchSpec->itemURLs);
	for (i = 0; i < count; i++)
	{
		url = CFArrayGetValueAtIndex(inLaunchSpec->itemURLs, i);
		scheme = CFURLCopyScheme(url);
		range = CFRangeMake(0, CFStringGetLength(scheme));

		if (CFStringCompareWithOptions(scheme, CFSTR("file"), range, kCFCompareCaseInsensitive) == kCFCompareEqualTo)
		{
			/* First check if it's a "mac thing", if not forward to xdg-open */

			/* Check for .app suffix */
			extension = CFURLCopyPathExtension(url);
			if (extension != NULL)
				range = CFRangeMake(0, CFStringGetLength(extension));
			if (extension != NULL && (CFStringCompareWithOptions(extension, CFSTR("app"), range, kCFCompareCaseInsensitive) == kCFCompareEqualTo))
			{
				temp = _LSLaunchApplication(url);
				if (temp)
					ret = temp;
			}
			else
			{
				printf("TODO: forward to xdg-open\n");
				ret = 1;
			}

			if (extension != NULL)
				CFRelease(extension);
		}
		else if (_LSIsHostOpenURL(url))
		{
			temp = _LSOpenURLOnHost(url);
			if (temp)
				ret = temp;
		}
		else
		{
			printf("We can't handle this scheme yet\n");
			ret = kLSApplicationNotFoundErr;
		}
		CFRelease(scheme);
	}
	return ret;
}

OSStatus _LSLaunchApplication(CFURLRef appPath)
{
	CFStringRef executable, bundleName;
	CFIndex nameSize, execSize;
	CFURLRef pre, url_plus_exec;
	pid_t pid;
	char *name, *exec, *argv[2];

	/* Read info.plist, find path to main executable */
	get_main_executable_info(appPath, &executable, &bundleName);
	if (executable == NULL)
	{
		return 1;
	}
	else
	{
		url_plus_exec = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, appPath, CFSTR("Contents"), TRUE);
		pre = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, url_plus_exec, CFSTR("MacOS"), TRUE);
		CFRelease(url_plus_exec);
		url_plus_exec = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, pre, executable, FALSE);
		CFRelease(pre);
		/* Launch the executable. NB: CFURLGetString would give back a
		 * percent-encoded file:// URL, which is not spawnable; extract the
		 * POSIX path instead. */
		CFRelease(executable);
		executable = CFURLCopyFileSystemPath(url_plus_exec, kCFURLPOSIXPathStyle);
		CFRelease(url_plus_exec);
		if (executable == NULL)
			return 1;

		/* Try to use CFBundleName first */
		if (bundleName == NULL)
			bundleName = CFStringCreateCopy(kCFAllocatorDefault, executable);
		nameSize = CFStringGetMaximumSizeOfFileSystemRepresentation(bundleName);
		name = malloc(nameSize);
		CFStringGetFileSystemRepresentation(bundleName, name, nameSize);
		execSize = CFStringGetMaximumSizeOfFileSystemRepresentation(executable);
		exec = malloc(execSize);
		CFStringGetFileSystemRepresentation(executable, exec, execSize);
		argv[0] = exec;
		argv[1] = NULL;
		/* Launch the executable directly. The macOS-correct route is
		 * spawn_via_launchd (launchd job registration, -W waiting, PSN
		 * tracking), but Darling's vproc_mig_spawn2 currently fails the
		 * request (EIO) and nothing in-tree exercises it, so spawn the
		 * child ourselves via the emulated posix_spawn. */
		int err = posix_spawn(&pid, exec, NULL, NULL, argv, environ);
		if (err != 0)
		{
			printf("%s: Failed to posix_spawn: %s\n", exec, strerror(err));
			return 1;
		}
		free(name);
		free(exec);
		CFRelease(executable);

	}
	if (bundleName != NULL)
		CFRelease(bundleName);
	return 0;
}

static void get_main_executable_info(CFURLRef appURL, CFStringRef *exec, CFStringRef *bundleName)
{
	CFURLRef pre = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, appURL, CFSTR("Contents"), TRUE);
	CFURLRef info_plist_url = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, pre, CFSTR("Info.plist"), FALSE);
	CFReadStreamRef rs = CFReadStreamCreateWithFile(kCFAllocatorDefault, info_plist_url);
	CFDictionaryRef info_plist;
	CFStringRef ret = NULL;

	/* TODO: Simplify by using CFBundleGetInfoDictionary */

	*exec = NULL;
	*bundleName = NULL;

	CFRelease(pre);

	if (!CFReadStreamOpen(rs))
	{
		printf("Failed to read Info.plist\n");
		goto err_pre_info;
	}

	info_plist = CFPropertyListCreateWithStream(kCFAllocatorDefault, rs, 0, 0, NULL, NULL);

	if (CFGetTypeID(info_plist) != CFDictionaryGetTypeID())
	{
		printf("Root object of Info.plist not CFDictionaryRef!\n");
		goto err;
	}

	ret = CFDictionaryGetValue(info_plist, CFSTR("CFBundleExecutable"));
	if (ret != NULL)
		ret = CFStringCreateCopy(kCFAllocatorDefault, ret);

	*exec = ret;

	ret = CFDictionaryGetValue(info_plist, CFSTR("CFBundleName"));
	if (ret != NULL)
		*bundleName = CFStringCreateCopy(kCFAllocatorDefault, ret);

err:
	CFRelease(info_plist);
err_pre_info:
	CFRelease(rs);
	CFRelease(info_plist_url);
}

OSStatus LSSetDefaultHandlerForURLScheme(CFStringRef inURLScheme, CFStringRef inHandlerBundleID)
{
	/* Darling has no shared LaunchServices database yet; accept and
	 * ignore (callers such as Discord's URL-scheme registration only
	 * need the call to succeed). */
	(void)inURLScheme;
	(void)inHandlerBundleID;
	if (verbose)
		printf("STUB: LSSetDefaultHandlerForURLScheme\n");
	return noErr;
}

OSStatus LSSetDefaultRoleHandlerForContentType(CFStringRef inContentType, LSRolesMask inRole, CFStringRef inHandlerBundleID)
{
	(void)inContentType;
	(void)inRole;
	(void)inHandlerBundleID;
	if (verbose)
		printf("STUB: LSSetDefaultRoleHandlerForContentType\n");
	return noErr;
}
