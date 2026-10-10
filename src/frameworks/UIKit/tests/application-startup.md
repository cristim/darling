# UIApplicationMain startup fixture

Run `application-startup` once per `UIAPP_FIXTURE_MODE` under a Wayland display. The failure
policy is a Darling host policy, not UIKit behaviour: a failure exits 1 with exactly one stderr
line `UIApplicationMain: <cause>`, and the run loop never starts.

| Mode | Setup | Expected |
| --- | --- | --- |
| ok | default | `shared-before-launch-nil=1`, `will 1 main=1 shared=1 state=1 opts=0`, `did 1 after-will=1 delegate-identity=1 class=UIApplication`, `state-active=1`, `state-inactive=1`, `timer`, `terminate will=1 did=1`; exit 0 |
| app-subclass | principal ShapeApplication (overrides `-init`), delegate ShapeDelegate (a UIResponder with did-finish and terminate only) | `shape did main=1 init=1 class=ShapeApplication shared=1 delegate-identity=1 delegate-class=ShapeDelegate state=1`, `shape terminate init=1`; exit 0 |
| self-delegate | one UIApplication subclass named as both principal and delegate (documented: the subclass may be its own delegate) | `self did init=1 delegate-is-app=1 shared-is-app=1`; exit 0. Before the fix a second instance was created (init=2, delegate-is-app=0) |
| nil-delegate | no delegate class | `nil-delegate shared=1 delegate-nil=1`; exit 0 |
| bad-principal | principal NSObject | cause names the principal class; no will/did |
| bad-delegate, missing-delegate | delegate does not conform / unknown name | cause names the delegate class; no will/did |
| throw-will | will-finish raises | `exception in willFinishLaunching`; no will/did line |
| throw-init | principal `-init` raises | `exception in application or delegate init`; no will/did |
| throw-did | did-finish raises | `will 1 ...`, then `exception in didFinishLaunching` |
| duplicate | second call from did-finish | `will 1`, `did 1`, both state lines, then `already called` |
| off-main | call on a secondary thread | `must be called on the main thread` |
| no-display | `WAYLAND_DISPLAY` names an absent socket | `screen query failed: NSWindowServerCommunicationException: ...` |
| arguments | `docfile.txt`; `-AppleLanguages (en)` | as ok: arguments are not opened as documents |
| bundle-control | inside a bundle with a plain Info.plist | as ok |
| splash | bundle has `Resources/splash.png` | `unsupported splash image` |
| bundle-NSMainNibFile, bundle-UIMainStoryboardFile | bundle Info.plist sets the key | `unsupported configured resource <key>` |
| bundle-UIApplicationSceneManifest | bundle Info.plist sets the key | `UIKit: UIApplicationSceneManifest is not supported; launching without scene sessions`, then as ok |
| bundle-CFBundleDocumentTypes | bundle Info.plist sets the key | as ok |
| run-loop-returns | timer calls `[NSApp stop:]` | `run loop returned` (UNPROVEN, see below) |

Exceptions from
`applicationWillTerminate:` happen after launch and are caught and logged by AppKit.

## Limits

- `run-loop-returns` is UNPROVEN: on Wayland `-[NSApplication run]` does not return after a
  timer-only `[NSApp stop:]` wakeup (VibeDarling/darling#1127), so the branch never runs.
- The state lines follow notifications the fixture posts itself: they prove the bridge mapping,
  not that the backend posts them on real focus changes.
- AppKit reads arguments from `/proc/self/cmdline`, not the `argv` passed in.
- Fail-before is a link failure (the base tree has no `UIApplicationMain`); deletion probes
  cover each policy branch instead.
