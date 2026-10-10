# UIControl (state, enabled/selected/highlighted, target-action)

Specification, rung 3 (DocC JSON fetched 2026-10-10, Objective-C variants): uicontrol,
isenabled, isselected, ishighlighted, state-swift.property, addtarget(_:action:for:),
removetarget(_:action:for:), sendactions(for:), alltargets, allcontrolevents, event and
state constants. Declarations: `(nonatomic, getter=isEnabled) BOOL enabled` and likewise
`isSelected`, `isHighlighted`; `state` readonly; `allTargets` NSSet; `allControlEvents`
readonly UIControlEvents.

Rung 2 (values only): the numeric values of UIControlEvents and UIControlState come from the
BSD-licensed Chameleon UIControl.h; Apple's pages give names and no values. The complete
Chameleon notice is in UIControl.h.

Documented and tested: defaults enabled YES, selected NO, highlighted NO; state is a bitmask
that gains Disabled / Selected / Highlighted from the properties; addTarget may be repeated
with the same target and action; several targets and actions per event; target is not
retained; removeTarget ignores the action argument and a nil target removes events for all
targets; allTargets / allControlEvents; sendActionsForControlEvents: calls the actions of
registrations whose events intersect the mask.

Rung 6 (labelled in UIControl.m): the sender is the control and the event argument is nil;
nil-target actions go to the first responder in the chain from the control that responds to
the action (allTargets then contains NSNull, which the page documents); NULL action raises
NSInvalidArgumentException; registering zero events makes no record; sending iterates a
snapshot.

Left out: UIControlStateFocused, UIControlEventPrimaryActionTriggered,
UIControlEventMenuActionTriggered (no value source); actionsForTarget:forControlEvent:
(declaration page not fetched); sendAction:to:forEvent:, tracking methods, touchInside,
tracking, content alignment, UIAction variants, context menu, toolTip (need UIEvent/UITouch
or are outside the minimal set). No hit testing or touch handling, so events are only sent
programmatically.
