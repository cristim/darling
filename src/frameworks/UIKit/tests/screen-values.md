# Before-window public UIScreen proof

This component implements only `+[UIScreen mainScreen]`, `+[UIScreen screens]`,
readonly `bounds` and `scale`. It is authored from Apple's public
[UIScreen](https://developer.apple.com/documentation/uikit/uiscreen),
[main screen](https://developer.apple.com/documentation/uikit/uiscreen/main),
[screens](https://developer.apple.com/documentation/uikit/uiscreen/screens),
[bounds](https://developer.apple.com/documentation/uikit/uiscreen/bounds), and
[scale](https://developer.apple.com/documentation/uikit/uiscreen/scale) contracts
(clean-room rung 3). The main display occupies array index 0; bounds are points and
scale converts point dimensions to display pixels. It declares no unsupported
UIKit application, scene, window, responder, status-bar or coordinate-space API.

Rung2/OSS: tracked Cocotron NSScreen.h/.m, NSDisplay.m and
Wayland.backend/WaylandDisplay.m. `NSScreen screens` obtains actual backend screens;
Wayland creates `WaylandScreen` objects, reads logical geometry, sets their
`_waylandScale` from wl_output state, and overrides backingScaleFactor to return
it. The base NSScreen getter instead returns1. Merely finding the getter proves
nothing about compositor metadata. The runtime and header source revisions must
be recorded separately; no Apple machine code is examined.

## Explicit local adaptations and failure policy

Darling normalizes UIScreen bounds origin to(0,0), preserving NSScreen logical
width/height. This is a documented desktop adaptation, not an inferred Apple
implementation. Wrappers query actual NSScreen metadata; there is no fabricated
resolution or fallback scale. This first proof covers stable, isolated single
outputs at integer scales1 and2; no multi-output identity/hotplug/change/rotation,
fractional scale, nativeBounds/nativeScale or stable wrapper-identity claim.

Unavailable display/backend failures propagate from AppKit. An empty native list
raises NSWindowServerCommunicationException. A backend inheriting the known
hardcoded NSScreen scale getter is explicitly unsupported and raises
NSInternalInconsistencyException; this also rejects the current Wayland backend's
plain-NSScreen no-mode synthetic geometry fallback. Invalid/nonfinite geometry,
nonpositive dimensions or invalid/nonpositive scale raise that same local
consistency diagnostic. Direct init raises NSInvalidArgumentException rather
than exposing an unbacked object. These are documented Darling failure policies
(rung 6), not claims of Apple's unspecified error ABI. No new magic error codes.
Bitmap-context scale0 remains unsupported until the UIKit owner adopts this
independently verified real screen primitive; this component changes no bitmap code.

## Fixture

`screen-values.m` runs against a real Wayland-backed AppKit screen with no window
open, and checks the following. SCREEN_EXPECT_WIDTH/HEIGHT/SCALE come from the
compositor's measured output, never from assumed values.

- no NSApplication windows before or after the screen queries
- UIScreen bounds origin 0,0 and size and scale equal the native screen
- `mainScreen` and `screens` return the same wrapper objects on repeated calls
- stub NSScreen subclasses: empty list, inherited base scale getter, zero or NaN
  geometry and zero scale each raise; direct `init` raises; a screen at a non-zero
  origin reports bounds origin 0,0
