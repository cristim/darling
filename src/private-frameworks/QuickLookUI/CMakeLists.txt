set(FRAMEWORK_VERSION "A")

generate_sdk_framework(QuickLookUI
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/QuickLookUI"
    PRIVATE
)

add_framework(QuickLookUI
    FAT
    CURRENT_VERSION
    PRIVATE
    VERSION ${FRAMEWORK_VERSION}

    SOURCES
        src/QuickLookUI.m

    DEPENDENCIES
        system
        objc
        Cocoa
)
