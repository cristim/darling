/*
 * Screenshot.app sends a command to this systemuiserver Mach service.
 * The host broker is started by darling-screenshot and owns the Wayland display.
 *
 * Copyright (C) 2026 Darling developers
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <dispatch/dispatch.h>
#include <xpc/xpc.h>
#include <xpc/connection.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int begin_capture(uid_t uid, int interactive)
{
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;

	struct sockaddr_un address = { .sun_family = AF_UNIX };
	snprintf(address.sun_path, sizeof(address.sun_path),
		"/tmp/darling-screenshot-%lu.sock", (unsigned long)uid);
	if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
		close(fd);
		return -1;
	}

	const char *request = interactive ? "CAPTURE_INTERACTIVE\n" : "CAPTURE\n";
	size_t length = strlen(request);
	if (write(fd, request, length) != (ssize_t)length) {
		close(fd);
		return -1;
	}

	return fd;
}

static int finish_capture(int fd)
{
	char reply[256] = {0};
	ssize_t count = read(fd, reply, sizeof(reply) - 1);
	close(fd);
	return (count >= 3 && strncmp(reply, "OK ", 3) == 0) ? 0 : -1;
}

static int requests_interaction(xpc_object_t message)
{
	xpc_object_t args = xpc_dictionary_get_value(message, "args");
	if (!args || xpc_get_type(args) != XPC_TYPE_ARRAY)
		return 0;
	for (size_t i = 0; i < xpc_array_get_count(args); i++) {
		const char *argument = xpc_array_get_string(args, i);
		if (argument && argument[0] == '-' && strchr(argument + 1, 'i'))
			return 1;
	}
	return 0;
}

int main(void)
{
	xpc_connection_t listener = xpc_connection_create_mach_service(
		"com.apple.systemuiserver.screencapture", NULL,
		XPC_CONNECTION_MACH_SERVICE_LISTENER);
	if (!listener)
		return 1;

	xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
		if (xpc_get_type(peer) != XPC_TYPE_CONNECTION)
			return;
		xpc_connection_set_event_handler(peer, ^(xpc_object_t message) {
			if (xpc_get_type(message) != XPC_TYPE_DICTIONARY)
				return;
			if (xpc_dictionary_get_uint64(message, "message") != 1)
				return;

			int interactive = requests_interaction(message);
			uid_t uid = xpc_connection_get_euid(peer);
			int capture_fd = begin_capture(uid, interactive);
			xpc_object_t reply = xpc_dictionary_create_reply(message);
			if (reply) {
				xpc_dictionary_set_bool(reply, "accepted", capture_fd >= 0);
				xpc_connection_send_message(
					xpc_dictionary_get_remote_connection(message), reply);
				xpc_release(reply);
			}

			// Screenshot sends `nowait: true`; keep its acknowledgement immediate.
			if (capture_fd >= 0) {
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					if (finish_capture(capture_fd) != 0)
						fprintf(stderr, "screencapture-service: capture failed\n");
				});
			} else {
				fprintf(stderr, "screencapture-service: capture broker unavailable\n");
			}
		});
		xpc_connection_resume(peer);
	});
	xpc_connection_resume(listener);
	dispatch_main();
}
