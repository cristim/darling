project(screenshot-service)

set(CMAKE_INSTALL_DEFAULT_COMPONENT_NAME "gui")

add_darling_executable(screencapture-service screencapture-service.c)
target_include_directories(screencapture-service PRIVATE
	${CMAKE_SOURCE_DIR}/src/external/libxpc/include
)
target_compile_options(screencapture-service PRIVATE -fblocks)
target_link_libraries(screencapture-service xpc libdispatch_shared objc)

install(TARGETS screencapture-service DESTINATION libexec/darling/usr/libexec)
install(FILES com.apple.systemuiserver.screencapture.plist
	DESTINATION libexec/darling/System/Library/LaunchDaemons)
install(PROGRAMS host-broker.py DESTINATION libexec/darling
	RENAME darling-screenshot-broker)
install(PROGRAMS darling-screenshot DESTINATION bin)
