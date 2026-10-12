project(OpenGL)

remove_sdk_framework(OpenGL)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "1.0.0")

set(FRAMEWORK_VERSION "A")

include(darling_framework)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PC_EGL egl)

include_directories(${PC_EGL_INCLUDE_DIRS})

generate_sdk_framework(OpenGL
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/OpenGL"
)

add_framework(OpenGL
    FAT
    CURRENT_VERSION
    VERSION ${FRAMEWORK_VERSION}

    SOURCES
        OpenGL.c

    DEPENDENCIES
        system
        GL
        GLU
        # darling-lol M57bo: EGL is deliberately NOT a link dependency. Linking
        # it here puts the native Mesa EGL in the dependency symbol scope of
        # OpenGL.framework's dependents (ANGLE's libGLESv2), so Chromium's EGL
        # lookups resolve to the native EGL instead of ANGLE's. OpenGL.c loads
        # it privately with dlopen(RTLD_LOCAL) instead.
        CoreFoundation
        CoreGraphics
        IOSurface
)

set_property(TARGET OpenGL APPEND_STRING PROPERTY LINK_FLAGS
    " -Wl,-reexport_library,${CMAKE_BINARY_DIR}/src/native/libGL.dylib \
    -Wl,-reexport_library,${CMAKE_BINARY_DIR}/src/native/libGLU.dylib ")
InstallSymlink(Versions/Current/Libraries
			"${CMAKE_INSTALL_PREFIX}/libexec/darling/System/Library/Frameworks/OpenGL.framework/Libraries")
