# UIView coordinate conversion

Specification, rung 3 (DocC JSON fetched 2026-10-09, Objective-C variants):
uiview/convert(_:to:) and convert(_:from:) for CGPoint and CGRect, plus uiview/transform and bounds
for the geometry rules. The convert pages read give only the return values ("converted to the
coordinate system of view", "to the local coordinate system (bounds) of the receiver"). No Chameleon code.

Documented and tested: points and rectangles convert between a view's bounds space and another view's;
the transform acts about the centre; bounds origin (0,0) and centre give frame-origin offsets.

Rung 6 guesses, labelled in UIView.m and the test:

- nil view: the top-most ancestor's bounds space (the page-level meaning, window coordinates, needs UIWindow).
- A non-zero bounds origin moves the child point at the view's centre; no page read states this.
- A rectangle converts to the bounding box of its four converted corners.
- Views in different hierarchies, or a view with a non-invertible transform on the path in the
  from-direction, raise NSInvalidArgumentException; the pages read do not cover either.

Left out: hit testing (hitTest:withEvent:, pointInside:withEvent:), which needs UIEvent;
conversion through layer transforms (transform3D, sublayerTransform), and UICoordinateSpace.
