project(APFS)

remove_sdk_framework(APFS
    PRIVATE
)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "1.0.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(APFS
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/APFS"
    PRIVATE
)

add_framework(APFS
	FAT
	CURRENT_VERSION
	PRIVATE
	VERSION ${FRAMEWORK_VERSION}

	SOURCES
		src/APFS.c

	DEPENDENCIES
		system
		CoreFoundation
)
