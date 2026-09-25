# Screenshot XPC capture service

macOS 26 Screenshot.app sends an asynchronous request to
`com.apple.systemuiserver.screencapture` with this dictionary:

```
message: uint64 1
nowait: true
args: ["-uUpi"]
```

The service captures the X11 root window and writes a PNG to the requesting
user's Desktop. For the observed `-uUpi` request, it grabs the pointer, shows a
crosshair and a drag rectangle, then saves the selected region. Escape cancels
the selection. Requests without `-i` save the full screen. It returns an XPC
dictionary with `status: 0` on success or a negative status on failure. A
working `DISPLAY` must be present in launchd's environment before it starts
the service. For a separate X server, set it with `launchctl setenv DISPLAY :N`.

On arm64 hosts, Screenshot.app's arm64e executable also needs Darling's
`DARLING_DISABLE_PTRAUTH=1` compatibility switch because its signed Swift
function pointers cross into arm64 Swift libraries. With that switch set on
the Screenshot.app invocation, two consecutive invocations saved valid PNGs
in an isolated Xvfb prefix.

This handles drag selection for the observed request. Screenshot.app's toolbar,
window selection, and video recording are not yet implemented. Darling also
needs the launchd repeated-bootstrap-lookup fix to handle subsequent requests
from new Screenshot.app processes.

The backend uses XGetImage and libpng. libpng receives a write callback rather
than a Darwin `FILE*`; the native libpng wrapper cannot write directly to a
Darwin stdio stream.
