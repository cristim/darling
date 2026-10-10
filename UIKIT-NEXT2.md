# UIKIT-NEXT2 (branch feat/uikit-next2-controls, on feat/uikit-views2 d248858f2)

Source only. Nothing built, compiled or run. Not pushed. Docs read from DocC JSON (ObjC variant
declarations), cached in ../uikit-next-docs/n3_*.json and n2_*.json.

## Done
| sha | what | test |
|-----|------|------|
| ff28aec40 | UIControl: UIControlEvents/UIControlState, enabled/selected/highlighted/state, addTarget/removeTarget/sendActionsForControlEvents:, allTargets, allControlEvents | tests/control.m, control.md |
| 4400589d4 | UIButton: buttonWithType:, buttonType, set/get title and titleColor per state | tests/button.m, button.md |
| a69fce2b5 | UIAlertController + UIAlertAction data model, no presentation | tests/alert-controller.m, alert-controller.md |

Each commit also edits src/frameworks/UIKit/CMakeLists.txt (SOURCES) and include/UIKit/UIKit.h.
tests/ is gitignored in this tree: new test files were added with `git add -f`.
UIControl.h and UIButton.h carry the complete Chameleon BSD notice because enum values come from
Chameleon (rung 2); everything else is original.

## Omitted (listed, not guessed)
- UIControl: UIControlStateFocused, UIControlEventPrimaryActionTriggered, UIControlEventMenuActionTriggered
  (no value source); actionsForTarget:forControlEvent: (page unfetched); sendAction:to:forEvent:, tracking
  methods, touchInside/tracking, content alignment, UIAction variants, context menu, toolTip.
- UIButton: UIButtonTypeSystem, Plain, Close (documented, no value source; Messages likely needs System);
  attributed titles, shadow colors, current*, titleLabel, images, configuration, drawing.
- UIAlertController/UIAlertAction: presentation, handler invocation, text fields, preferredAction, severity,
  UIAlertAction.enabled (attributes unfetched).

## Guesses and risks (rung 6, all labelled in source)
- ABI RISK: numeric values of UIAlertActionStyle and UIAlertControllerStyle constants have no source
  (declared in listing order). Needs rung 3/4 confirmation before binary clients use them.
- UIAlertController derives from UIResponder because UIViewController does not exist yet; change when it lands.
- removeTarget ignores the action argument (follows the documented text literally).
- sendActions: sender = control, event = nil, nil target resolved along the responder chain, NULL action raises.
- UIButton: exact-value state matching; nil when Normal is unset.

## Unbuilt / unverified
Everything. Possible first-compile issues: objc/message.h import path in UIControl.m, NSNull/NSSet headers,
objc_allocateClassPair/imp_implementationWithBlock in tests/control.m (harness flags), nullability warnings.
Selector-existence checks in the tests use the table spellings below; behaviour checks come from the doc text.

## Test commands for a later builder
One run per test under the heavy-build lock, as for the other UIKit tests:

    flock -w 1800 /tmp/agent-locks/darling-heavy-build.lock python3 src/frameworks/UIKit/tests/build-layout-values.py \
      --source-root . --runtime-root <runtime> --build-dir <dir> --linker <ld64> \
      --test-source src/frameworks/UIKit/tests/<control|button|alert-controller>.m

Run the produced test in a guest with the built UIKit path as argv[1]. Expected: a PASS line, exit 0.
Then build the full UIKit CMake target.

## Verified selector/constant table
Base URL: https://developer.apple.com/documentation/uikit/ (DocC data under /tutorials/data/documentation/uikit/<page>.json)

| ObjC name | Page |
|---|---|
| UIControl (class) | uicontrol |
| state (property) | uicontrol/state-swift.property |
| enabled (property) | uicontrol/isenabled |
| selected | uicontrol/isselected |
| highlighted | uicontrol/ishighlighted |
| UIControlStateNormal | uicontrol/state-swift.struct/normal |
| UIControlStateHighlighted | uicontrol/state-swift.struct/highlighted |
| UIControlStateDisabled | uicontrol/state-swift.struct/disabled |
| UIControlStateSelected | uicontrol/state-swift.struct/selected |
| UIControlStateFocused | uicontrol/state-swift.struct/focused |
| UIControlStateApplication | uicontrol/state-swift.struct/application |
| UIControlStateReserved | uicontrol/state-swift.struct/reserved |
| UIControlEventTouchDown | uicontrol/event/touchdown |
| UIControlEventTouchDownRepeat | uicontrol/event/touchdownrepeat |
| UIControlEventTouchDragInside | uicontrol/event/touchdraginside |
| UIControlEventTouchDragOutside | uicontrol/event/touchdragoutside |
| UIControlEventTouchDragEnter | uicontrol/event/touchdragenter |
| UIControlEventTouchDragExit | uicontrol/event/touchdragexit |
| UIControlEventTouchUpInside | uicontrol/event/touchupinside |
| UIControlEventTouchUpOutside | uicontrol/event/touchupoutside |
| UIControlEventTouchCancel | uicontrol/event/touchcancel |
| UIControlEventValueChanged | uicontrol/event/valuechanged |
| UIControlEventPrimaryActionTriggered | uicontrol/event/primaryactiontriggered |
| UIControlEventMenuActionTriggered | uicontrol/event/menuactiontriggered |
| UIControlEventEditingDidBegin / EditingChanged / EditingDidEnd / EditingDidEndOnExit | uicontrol/event/editingdidbegin, editingchanged, editingdidend, editingdidendonexit |
| UIControlEventAllTouchEvents / AllEditingEvents / ApplicationReserved / SystemReserved / AllEvents | uicontrol/event/alltouchevents, alleditingevents, applicationreserved, systemreserved, allevents |
| -addTarget:action:forControlEvents: | uicontrol/addtarget(_:action:for:) |
| -removeTarget:action:forControlEvents: | uicontrol/removetarget(_:action:for:) |
| -sendActionsForControlEvents: | uicontrol/sendactions(for:) |
| allTargets (property) | uicontrol/alltargets |
| allControlEvents (property) | uicontrol/allcontrolevents |
| -actionsForTarget:forControlEvent: | uicontrol/actions(fortarget:forcontrolevent:) |
| UIButton (class) | uibutton |
| +buttonWithType: | uibutton/init(type:) |
| UIButtonTypeCustom, System, DetailDisclosure, InfoLight, InfoDark, ContactAdd, Plain, Close, RoundedRect | uibutton/buttontype-swift.enum/<lowercase name> |
| buttonType (property) | uibutton/buttontype-swift.property |
| -setTitle:forState: | uibutton/settitle(_:for:) |
| -titleForState: | uibutton/title(for:) |
| -setTitleColor:forState: | uibutton/settitlecolor(_:for:) |
| -titleColorForState: | uibutton/titlecolor(for:) |
| UIAlertController (class) | uialertcontroller |
| +alertControllerWithTitle:message:preferredStyle: | uialertcontroller/init(title:message:preferredstyle:) |
| title, message, preferredStyle (properties) | uialertcontroller/title, /message, /preferredstyle |
| -addAction: ; actions (property) | uialertcontroller/addaction(_:), /actions |
| UIAlertControllerStyleActionSheet, UIAlertControllerStyleAlert | uialertcontroller/style/actionsheet, /style/alert |
| UIAlertAction (class) | uialertaction |
| +actionWithTitle:style:handler: | uialertaction/init(title:style:handler:) |
| title, style, enabled (properties) | uialertaction/title, /style-swift.property, /isenabled |
| UIAlertActionStyleDefault, Cancel, Destructive | uialertaction/style-swift.enum/default, /cancel, /destructive |

Notes: UIControl getter spellings isEnabled/isSelected/isHighlighted and isHighlighted/isEnabled/isSelected are verified in the declarations (fetched 2026-10-10). The ObjC property names are `enabled`, `selected`, `highlighted` (the Swift names are
isEnabled etc.). Getter selectors isEnabled/isSelected/isHighlighted: the docs show only the
property name; the `is` getter spelling is NOT verified from these pages, so leave it to a header
check (rung 2) or declare via `@property (getter=isEnabled)` only after confirming.
