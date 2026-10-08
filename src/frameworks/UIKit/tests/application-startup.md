# UIApplicationMain startup fixture (drafted, never compiled or run)

Run `application-startup` once per `UIAPP_FIXTURE_MODE`. The failure policy is a Darling
host policy, not UIKit behaviour. Every failure mode expects exit status 1, exactly one
stderr line `UIApplicationMain: <cause>`, and no `will`/`did` line.

| Mode | Setup | Expected |
| --- | --- | --- |
| ok | default | `shared-before-launch-nil=1`, then `will 1 main=1 shared=1 state=1 opts=0`, `did 1 after-will=1 delegate-identity=1 class=UIApplication`, `state-active=1`, `state-inactive=1`, `timer`, `terminate will=1 did=1`; exit 0 |
| custom-principal | principal FixtureApplication | same as ok, with `class=FixtureApplication` |
| nil-delegate | no delegate class | loop runs; `nil-delegate shared=1 delegate-nil=1`; exit 0 |
| bad-principal | principal NSObject | cause names the principal class |
| bad-delegate | delegate does not conform | cause names the delegate class |
| missing-delegate | unknown delegate name | cause names the delegate class |
| throw-will / throw-did | delegate raises | `exception in willFinishLaunching` / `didFinishLaunching` |
| duplicate | second call from did-finish | `already called` |
| off-main | call on a secondary thread | `must be called on the main thread` |
| run-loop-returns | timer calls `[NSApp stop:]` | `run loop returned` |
| no display | invalid WAYLAND_DISPLAY | `no display` |
| document argument | pass a non-dash argument | `document arguments are unsupported` |
| splash | bundle contains a `splash` image | `unsupported splash image` |
| UIMainStoryboardFile, UIApplicationSceneManifest, NSMainNibFile, CFBundleDocumentTypes | run inside a bundle whose Info.plist sets the key | `unsupported configured resource <key>` |

Fail-before: the base tree has no UIApplicationMain, so every mode fails to link.
Deletion probes, one per policy branch: delete the check, rebuild, and the matching mode
must then misbehave (start the loop, or exit with another status). A mode that still
passes means the check is dead or the mode does not exercise it.

The `will` BOOL NO return must not stop `did`. Native window and pixels are out of scope
here; the AppKit-authored window fixture from FTServices covers them. The Cocotron
`NSOpen` default is not read by this entry point and is a documented exclusion.
