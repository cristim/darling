# Screenshot XPC capture service

macOS 26 Screenshot.app sends an asynchronous request to
`com.apple.systemuiserver.screencapture` with this dictionary:

```
message: uint64 1
nowait: true
args: ["-uUpi"]
```

The service captures the X11 root window and writes a PNG to the requesting
user's Desktop. It returns an XPC dictionary with `status: 0` on success or a
negative status on failure. A working `DISPLAY` must be present in launchd's
environment before it starts the service. For a separate X server, set it with
`launchctl setenv DISPLAY :N`.

This handles one full screen image for the observed request. Screenshot.app's
interactive toolbar, area/window selection, and video recording are not yet
implemented. Darling also needs the launchd repeated-bootstrap-lookup fix to
handle subsequent requests from new Screenshot.app processes.

The backend uses XGetImage and libpng. libpng receives a write callback rather
than a Darwin `FILE*`; the native libpng wrapper cannot write directly to a
Darwin stdio stream.
