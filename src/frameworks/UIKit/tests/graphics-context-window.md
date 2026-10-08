# Native UIGraphics bridge paint fixture

This authored AppKit fixture proves that the public context bridge can paint an
existing AppKit window context. It does not implement UIKit windows/views or prove
Messages UI. It requires a runtime with the native Wayland AppKit backend and a
UIKit artifact exporting UIGraphicsPushContext, UIGraphicsPopContext and
UIGraphicsGetCurrentContext.

Specification provenance: clean-room rung 3, Apple's public
[push](https://developer.apple.com/documentation/uikit/uigraphicspushcontext(_:)),
[pop](https://developer.apple.com/documentation/uikit/uigraphicspopcontext()) and
[current context](https://developer.apple.com/documentation/uikit/uigraphicsgetcurrentcontext())
contracts; rung 2, existing Cocotron AppKit NSApplication, NSWindow, NSView and
NSGraphicsContext declarations and implementations. The colors, rectangles and
checks are authored synthetic test inputs, not inferred private behavior.

Compile graphics-context-window.m with the same pinned headers and Darwin linker
mapping as the offscreen graphics-context.m regression, linking AppKit,
CoreGraphics, Foundation, objc and system. Serialize compilation under the shared
heavy-build lock. Use a clean committed artifact; do not install into shared runtime.

Run a separate headless Sway instance with task-local XDG_RUNTIME_DIR,
WLR_BACKENDS=headless, WLR_RENDERER=pixman, WLR_LIBINPUT_NO_DEVICES=1 and config:

```
xwayland disable
output HEADLESS-1 mode 640x480 scale 1
seat seat0 fallback true
default_border none
```

Use a fresh Darling DPREFIX, bootstrap shell true with the immutable non-setuid
snapshot launcher, then replace its host-home symlinks with empty directories.
Select DARLING_APPKIT_BACKEND=wayland and the isolated WAYLAND_DISPLAY/runtime.
Launch through guest env, supplying the UIKit artifact in UIGRAPHICS_LIBRARY:

```
darling shell /usr/bin/env UIGRAPHICS_LIBRARY=/Volumes/SystemRoot/<UIKit-artifact> /Volumes/SystemRoot/<graphics-context-window>
```

Do not pass the dylib as a positional argument: AppKit interprets document
arguments during finishLaunching. The fixture requires no document arguments.
Its 45-second authored timer checks at least one draw and a nil current context
after an explicitly empty context round-trip, then restores the saved AppKit
context and exits 0. Every draw verifies AppKit context/port restoration.

Before the timer expires, use the isolated Sway IPC get_tree and grim HEADLESS-1
capture. Require the fixture's native xdg_shell surface with Xwayland disabled.
The screenshot must contain contiguous, exact opaque RGB rectangles:

| Rectangle | RGB | Size | Pixel count |
| --- | --- | --- | --- |
| red | 255,0,0 | 80x80 | 6400 |
| green | 0,255,0 | 80x80 | 6400 |
| blue | 0,0,255 | 80x40 | 3200 |

Green starts 100 pixels right of red; blue starts 100 pixels below red. Absolute
screen position depends on compositor placement. Check the full rectangles,
not only a draw log or surface liveness. The white view background and window
chrome are not counted as rectangle pixels. Shut down only this prefix with
darling shutdown, and exit only the owned compositor through its IPC socket.

Recorded private run: snapshot runtime-display-link-e68d60cb; UIKit owner commit
d5191cb13, item-committed-build/UIKit SHA256
e572886a4520f7867ce2fc139db04c61a344b055b0439025b49b704743793599.
The first successful screenshot had red bounds[220,180,300,260], green
[320,180,400,260], blue[220,280,300,320] and the exact counts above. Initial
attempts exposed an SDK macro name collision, an overlong Sway IPC path and
AppKit document-argument handling; only fixture/setup code was corrected.
No renderer, existing UIKit implementation, account or user data was changed.
Exact build commands, source/runtime/dependency/artifact hashes, guest log,
compositor tree and screenshot remain private scratch evidence in the owning
agent's native-proof directory; no compiled output or screenshots are committed.

AppKit may retain a current context outside drawRect. The timer sets an explicit
nil baseline for its balanced push/pop check, then restores the saved AppKit
context. It does not require the AppKit run loop to leave its context nil.
