project(runningboardd)

add_darling_executable(runningboardd runningboardd.c)

install(
	TARGETS
		runningboardd
	DESTINATION
		libexec/darling/usr/libexec
)

install(
	FILES
		resources/com.apple.runningboard.plist
	DESTINATION
		libexec/darling/System/Library/LaunchDaemons
)
