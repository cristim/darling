# UIControl (state, enabled/selected/highlighted, target-action)

Specification, rung 3 (DocC JSON fetched 2026-10-10, Objective-C variants): uicontrol,
isenabled, isselected, ishighlighted, state-swift.property, addtarget(_:action:for:),
removetarget(_:action:for:), sendactions(for:), alltargets, allcontrolevents, event and
state constants. Declarations: `(nonatomic, getter=isEnabled) BOOL enabled` and likewise
`isSelected`, `isHighlighted`; `state` readonly; `allTargets` NSSet; `allControlEvents`
readonly UIControlEvents.

Rung 2 (values only): UIControlEvents and UIControlState values come from the BSD Chameleon
UIControl.h (complete notice in UIControl.h); Apple's pages give names only.

Documented and tested: defaults enabled YES, selected NO, highlighted NO; state is a bitmask
that gains Disabled / Selected / Highlighted from the properties; addTarget may be repeated
with the same target and action; several targets and actions per event; target is not
retained; removeTarget ignores the action argument and a nil target removes events for all
targets; allTargets / allControlEvents; sendActionsForControlEvents: calls the actions of
registrations whose events intersect the mask.

Rung 3 (sendaction(_:to:for:) page): a nil target means the responder chain is searched; a
nil event is allowed for programmatic calls.

Rung 6 (labelled in UIControl.m): the sender is the control; the chain search starts at the
control (the pages give no starting point; UIApplication.sendAction would not fetch); nil-target actions go to the first responder in the chain from the control that responds to
the action (allTargets then contains NSNull, which the page documents); NULL action raises
NSInvalidArgumentException; registering zero events makes no record; sending iterates a
snapshot.

Left out: UIControlStateFocused and the primary/menu action events (no value source);
actionsForTarget:forControlEvent: (page unfetched); sendAction:to:forEvent:, tracking, touchInside,
content alignment, UIAction forms, context menu, toolTip. No touch handling: events are only
sent programmatically.
