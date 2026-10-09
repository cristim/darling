# UIKIT-NEXT2 (branch feat/uikit-next2, from feat/uikit-next 7006cdd17)

Source/notes only. Nothing built or run. Not pushed. No class code was written: see "Blocked".

## Done
- Clone and branch created.
- Selector/constant table below, checked against Apple's DocC JSON (ObjC names come from each
  symbol's `navigatorTitle` in developer.apple.com/tutorials/data/documentation/uikit/<page>.json;
  raw pages cached in ../uikit-next-docs/n2_*.json, extractor n2_ex.py).
- No file copied from Chameleon, so the truncated-BSD-notice finding does not apply here. Any later
  Chameleon-derived file must carry the complete LICENSE.Chameleon notice including the final
  disclaimer line and the closing comment terminator. Every value the docs do not state is rung 6
  and must be labelled so in code and commit body.

## Blocked (nothing implemented)
`UIControl : UIView`, `UIButton : UIControl`, `UIAlertController : UIViewController`
(superclasses confirmed from the doc hierarchy pages n2_uiview.json / n2_uiviewcontroller.json
and UIControl/UIButton pages). The branch has UIResponder, UIColor, UIImage, UIDevice,
UIWindowScene, geometry and graphics contexts, but NO UIView and NO UIViewController
(`git ls-tree` on feat/uikit-next, include/UIKit has no UIView*.h). Per instructions no stub base
class was invented. Needed first, as separate work:
1. UIView (Chameleon UIView.h/.m + UIView+UIPrivate.h, UIViewLayoutManager, UIViewAnimationGroup,
   UIViewAdapter are BSD-3; they depend on CALayer-backed rendering, UIKitView/NSView hosting,
   UIScreen, UIWindow, UITouch/UIEvent). A minimal documented subset (init/initWithFrame:, frame,
   bounds, superview, subviews, addSubview:, tag) on top of the existing UIResponder is the smallest
   base that UIControl needs; rendering omitted.
2. UIViewController (Chameleon UIViewController.*) with at least title and presentViewController:
   animated:completion: as a no-op-free documented surface, for UIAlertController only.
3. UIEvent and UITouch types (only for UIControl tracking methods; those can stay omitted).
Then UIControl, UIButton, UIAlertController/UIAlertAction can be written from the table.

## Planned minimal surface (all verified below), omissions
- UIControl: state, enabled, selected, highlighted, addTarget:action:forControlEvents:,
  removeTarget:action:forControlEvents:, sendActionsForControlEvents:, allTargets, allControlEvents,
  actionsForTarget:forControlEvent:. Omitted: tracking methods, sendAction:to:forEvent:, UIAction
  variants, alignment, context menu, toolTip, symbol animation, touchInside/tracking.
- UIButton: buttonWithType:, setTitle:forState:, titleForState:, setTitleColor:forState:,
  titleColorForState:. Omitted: currentTitle*, attributed titles, shadow colors, titleLabel,
  configuration, rendering.
- UIAlertController/UIAlertAction: as in the table; presentation, textFields, preferredAction,
  severity omitted.
- Numeric values of UIControlState/Event/ButtonType/Style enums: the DocC pages checked did not
  show them; NOT verified, leave out until confirmed (do not take them from Chameleon without
  labelling rung 2/BSD-source and checking the doc names).
- Per-state storage semantics (what titleForState: returns for an unset state) is not stated in the
  pages read; any fallback is rung 6.

## Unbuilt / unverified
Everything. Selector-table rows are checked against doc JSON only; return/argument types were not
cross-checked beyond the Swift declaration in the same page. Tests must be written from this
table's spelling, not from the implementation.

## Test commands for a later builder
After the base classes land, mirror feat/uikit-next:
    flock -w 1800 /tmp/agent-locks/darling-heavy-build.lock python3 src/frameworks/UIKit/tests/build-layout-values.py \
      --source-root . --runtime-root <runtime> --build-dir <dir> --linker <ld64> \
      --test-source src/frameworks/UIKit/tests/<control|button|alert-controller>.m
Tests should use `respondsToSelector:` with the table's selector strings first.

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

Note the ObjC property names are `enabled`, `selected`, `highlighted` (the Swift names are
isEnabled etc.). Getter selectors isEnabled/isSelected/isHighlighted: the docs show only the
property name; the `is` getter spelling is NOT verified from these pages, so leave it to a header
check (rung 2) or declare via `@property (getter=isEnabled)` only after confirming.
