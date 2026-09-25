# Screenshot.app on Wayland

Issue: VibeDarling/darling#179.

Screenshot.app sends an XPC request to
`com.apple.systemuiserver.screencapture`. The LaunchDaemon in this directory
registers that service. The request contains command arguments; `-i` selects
an interactive region. The service acknowledges `nowait` requests immediately
and sends the capture request to a host-side broker through a same-user Unix
socket. One capture can run per user at a time.

Run `darling-screenshot` with `DPREFIX` set to the prefix containing the imported
Screenshot.app. The launcher starts a one-shot broker, launches Screenshot.app,
and waits for the capture. The broker uses `slurp` for interactive selection and
`grim` to save a PNG to `~/Pictures/Darling Screenshots`. Both commands and a
working Wayland display are required. Set `DARLING_SCREENSHOT_OUTPUT_DIR` to
choose another directory. For automated capture tests, set
`DARLING_SCREENSHOT_NONINTERACTIVE=1` to use the whole display even when
Screenshot.app requests interactive selection.

This implements Screenshot.app's first launch request and still leaves screen
recording and the ScreenCaptureKit API to be implemented. The broker is scoped
to one invocation. Ordinary `darling exec Screenshot` launches
without the broker will receive a capture failure; use `darling-screenshot`.
