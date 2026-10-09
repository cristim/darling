# UIView geometry (frame, bounds, center, transform)

Specification, rung 3 (DocC JSON fetched 2026-10-09, Objective-C variants):
https://developer.apple.com/documentation/uikit/uiview and its frame, bounds, center,
transform and init(frame:) pages. No Chameleon code was copied.

Documented and tested: initial bounds origin (0,0) with the frame's size; center is the frame
centre; setting center moves the frame origin; setting frame changes center and the size of
bounds; changing the bounds size resizes about the centre; default transform is the identity;
transforms leave center and bounds alone and act about the centre (anchor point default).

Rung 6 guesses, each labelled in the source:

- `-init` forwards to `initWithFrame:CGRectZero`.
- frame under a non-identity transform: the pages call it undefined, so the bounding box of
  the transformed bounds (translation included) is returned and the setter ignores the
  transform.

Left out: the bounds origin's effect on children (only matters with subviews, see the
conversion commit), transform3D and everything layer-backed, animation, autoresizing,
layout, draw(_:), contentMode.
