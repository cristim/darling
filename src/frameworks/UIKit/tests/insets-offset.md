# UIEdgeInsets and UIOffset

Names checked against Apple DocC JSON (developer.apple.com/tutorials/data/documentation/uikit/<page>.json),
Objective-C spellings from each symbol's navigatorTitle or occ declaration (rung 3):
uiedgeinsets (fields top, left, bottom, right), uiedgeinsets/zero (UIEdgeInsetsZero), init(top:left:bottom:right:)
(UIEdgeInsetsMake), uiedgeinsetsequaltoedgeinsets, uiedgeinsetsinsetrect, uioffset (fields horizontal, vertical),
uioffset/zero (UIOffsetZero), init(horizontal:vertical:) (UIOffsetMake), uioffsetequaltooffset.

Not implemented because the docs read do not state the format: NSStringFromUIEdgeInsets, UIEdgeInsetsFromString,
NSStringFromUIOffset, UIOffsetFromString, and the NSValue UIEdgeInsets/UIOffset categories.

Rung 6: UIEdgeInsetsInsetRect does not clamp or standardize a result with negative size (docs say only
"increments the origin and decrements the size"). Equality is exact CGFloat comparison.

The test is not built or run yet; run it with build-layout-values.py --test-source tests/insets-offset.m.
