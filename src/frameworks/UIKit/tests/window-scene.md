# UIWindowScene (minimal)

Specification, rung 3 (DocC JSON fetched 2026-10-09):
https://developer.apple.com/documentation/uikit/uiwindowscene

Implemented: class UIWindowScene with `windows` and `keyWindow`. The page says a window
scene manages windows and tells apps not to create scene objects directly. UIWindow does
not exist in this tree, so `windows` is always empty and `keyWindow` is nil; that is
the truthful state, not a default standing in for a lifecycle.

Deliberately left out:

- `screen`: documented non-optional UIScreen; UIScreen is owned by another agent, and
  returning nil would contradict the documented type. Add once UIScreen lands and a
  scene can be tied to one.
- UIScene superclass: documented, but a UIScene with no session, delegate or
  activation state would be an empty shim. UIWindowScene derives from NSObject for now,
  so isKindOfClass:UIScene fails; unresolved until UIScene is implemented.
- traitCollection, sizeRestrictions, screenshotService, activityItemsConfigurationSource,
  isFullScreen, windowingBehaviors, effectiveGeometry, requestGeometryUpdate, focusSystem,
  statusBarManager, titlebar, displayLink: each needs a type or lifecycle not present.
- UIWindowSceneDelegate and the Info.plist driven creation path.
