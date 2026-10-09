# UIView hierarchy

Specification, rung 3 (DocC JSON fetched 2026-10-09, Objective-C variants): uiview/superview,
subviews, addsubview, removefromsuperview, insertsubview (atIndex, aboveSubview, belowSubview),
bringsubviewtofront, sendsubviewtoback, exchangesubview, isdescendant, viewwithtag,
willmove(toSuperview:), didmovetosuperview, didaddsubview, willremovesubview. No Chameleon code.

Documented and tested: subviews are ordered back to front (index 0 is back-most); a view has one
superview and moving it removes it from the old one; addSubview: sets the next responder to the
receiver; bring/send move to the end/beginning of subviews; exchange swaps positions without
changing superviews; isDescendantOfView: is true for the view itself; viewWithTag: searches the
receiver and its subviews; the four callbacks are called and do nothing by default.

Rung 6 guesses, labelled in UIView.m:

- Exceptions: nil, self or an ancestor passed to an insertion raises NSInvalidArgumentException; an
  index outside the available range and bad exchange indices raise NSRangeException; an
  above/below sibling that is not a subview of the receiver raises NSInvalidArgumentException.
- Re-adding an existing subview removes and re-inserts it (moves it to the end for addSubview:);
  insertSubview:atIndex: addresses the subviews with that view already taken out.
- bring/send for a view that is not a subview is ignored.
- Callback order inside one operation; the test only asserts the arguments and the superview
  value visible in each callback, not the order between callbacks.
- viewWithTag: tie-break: receiver first, then depth-first in subview order.
- The reference to the superview is non-owning and cleared in dealloc; subviews are owned.

Left out: willMove(toWindow:)/didMoveToWindow (no UIWindow), autoresizing and layout on
hierarchy changes, constraint removal on removeFromSuperview (no Auto Layout), responder chain past
the superview (view controllers, windows), layer sublayer management.
