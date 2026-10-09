# UIView state properties (tag, hidden, alpha, opaque, clipsToBounds, backgroundColor, window)

Specification, rung 3 (DocC JSON fetched 2026-10-09, Objective-C variants): uiview/tag,
ishidden, alpha, isopaque, clipstobounds, backgroundcolor, window. Declarations:
`@property (nonatomic, getter=isHidden) BOOL hidden`, `(nonatomic, getter=isOpaque) BOOL opaque`,
`(nonatomic, copy, nullable) UIColor *backgroundColor`, `(nonatomic, readonly, nullable) UIWindow *window`.
No Chameleon code was copied.

Documented defaults tested: tag 0, hidden NO, opaque YES, clipsToBounds NO, backgroundColor nil.

Rung 6: alpha defaults to 1.0 (the pages give the range 0.0 to 1.0 but no default) and is stored
without clamping.

`window` is always nil: the page says nil until the view is in a window, and no UIWindow exists
in this tree. Remove the constant when UIWindow lands.

Left out: hidden's effect on descendants, input events and first responder (needs hit testing and
responder tracking), alpha compositing, opaque's drawing hint, clipping (all need drawing), animation.
