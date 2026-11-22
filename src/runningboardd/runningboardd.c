/**
 * This file is part of Darling.
 *
 * Copyright (C) 2026 Darling developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

// Stand-in for the process-lifecycle service that macOS apps look up as
// "com.apple.runningboard". Darling has no process-lifecycle management (no
// suspension, no jetsam-style policy), so there is nothing for the service to
// grant or enforce, and an empty answer would claim a grant that never happened.
// The service therefore owns the name, so the launchd lookup succeeds, and
// cancels every connection: clients get a clean XPC_ERROR_CONNECTION_INVALID
// instead of a failed lookup.

#include <dispatch/dispatch.h>
#include <xpc/xpc.h>
#include <stdlib.h>

#define SERVICE_NAME "com.apple.runningboard"

int main(void) {
	xpc_connection_t server = xpc_connection_create_mach_service(SERVICE_NAME, NULL, XPC_CONNECTION_MACH_SERVICE_LISTENER);

	xpc_connection_set_event_handler(server, ^(xpc_object_t object) {
		if (xpc_get_type(object) == XPC_TYPE_CONNECTION) {
			xpc_connection_cancel(object);
		} else if (object == XPC_ERROR_CONNECTION_INVALID) {
			exit(1);
		}
	});
	xpc_connection_resume(server);

	dispatch_main();
}
