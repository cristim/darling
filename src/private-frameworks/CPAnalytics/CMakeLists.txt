project(CPAnalytics)

remove_sdk_framework(CPAnalytics
    PRIVATE
)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "1.0.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(CPAnalytics
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/CPAnalytics"
    PRIVATE
)

add_framework(CPAnalytics
	FAT
	CURRENT_VERSION
	PRIVATE
	VERSION ${FRAMEWORK_VERSION}

	SOURCES
		src/CPAnalytics.c
		src/CPAnalytics.m

	DEPENDENCIES
		system
		CoreFoundation
		Foundation
)
