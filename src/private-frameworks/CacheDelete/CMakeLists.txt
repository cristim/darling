project(CacheDelete)

remove_sdk_framework(CacheDelete
    PRIVATE
)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "1.0.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(CacheDelete
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/CacheDelete"
    PRIVATE
)

add_framework(CacheDelete
	FAT
	CURRENT_VERSION
	PRIVATE
	VERSION ${FRAMEWORK_VERSION}

	SOURCES
		src/CacheDelete.c

	DEPENDENCIES
		system
		CoreFoundation
)
