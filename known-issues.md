# Known issues

## Darling Applications viewer + Cocotron on Wayland

### Applications viewer fixes landed (branch fix/applications-grid-icon-flip)
- Grid icons are mirrored around their own rect so rows below the first
  render upright and in place (commit 18d875e23, completing the flip fix
  landed in b23a5318b).
- Decoded app icons are cached in an NSCache across grid refreshes, so
  re-listing avoids re-reading each bundle and re-decoding its PNG/ICNS
  (commit ab2ff9068), removing the 20-30ms per-icon first-draw cost on
  scroll.
- The grid scrolls by one cell row per wheel notch instead of the coarse
  default step (commit 61c6d146a), and grid double-clicks launch by grid
  index rather than by table selection (commit 44fa9a5ca).

### TextEdit cursor drift with arrow keys (OPEN, not yet fixed)
- Symptom: in TextEdit, after using arrow keys within a line, the typing cursor
  drifts further and further from the typed text as more characters are typed on
  that line. A new line starts back at the correct position, then drifts right
  again as you type. Clicking inside a word lands the cursor in the middle of
  characters rather than at a character boundary.
- Suspected cause: NSLayoutManager/NSTextView glyph-to-character index mapping.
  Cocotron has no per-glyph char-index table on the fly; placement likely assumes
  fixed/avg glyph width (see `suggestEntryLocationForPoint:` and
  `characterIndexForGlyphAtIndex:` in `AppKit/NSTextView.subproj/NSLayoutManager.m`
  and NSTextView mouse/arrow handling).
- Confirmed NOT caused by the FreeType glyph-raster cache (commit 38757104):
  `showGlyphs:` advance semantics are byte-identical (`cached->advance >> 6`).
- TextEdit typing works on Wayland but not X11 (separate, also open).

## X11: window frame and content rect are the same rect, and no title bar is drawn

- Symptom (Stickies #158): each note's title bar is a 300x12 subwindow that lands *outside* its
  note, at parent-relative y = -60 / -68 instead of 0.
- Measured, not inferred: the app requests `req={0,188,300,12}` inside a 200pt window (correct, the
  top 12pt) but also `req={0,256,300,12}` -- 56pt *above* its own content. `-[X11SubWindow
  convertFrame:]` is exonerated: with `CGNativeBorderFrameWidthsForStyle` returning 0/0/0/0 on X11,
  the flip `parentHeight - maxY` maps each request correctly.
- Root cause: there is **no `frameForContentRect:` / `contentRectForFrame:` anywhere in the tree**
  (not even a declaration), so a window's frame and content rect are identical and no space is ever
  reserved above the content for a title bar. Consistently, `grep -i titlebar` over
  `AppKit/X11.backend/*.m` finds nothing, so **no window title bar is rendered on X11 at all** --
  confirmed visually (TextEdit's content begins directly under the menu bar despite having a title).
- Blast radius: any app that lays out a custom title bar against the window frame will misplace it
  here, so this is not a Stickies bug and will recur in other apps.
- NOT independently fixable: reserving the strip without drawing it would shrink content by ~56pt in
  every titled window and break currently-correct layouts (TextEdit et al). Fixing the geometry and
  drawing the title bar are coupled, so this is a framework change, not a local patch.

## Handover traps for the TextEdit caret/Shift work (agent x11-backend)

- `DARLING-APPS-HANDOVER-2026-09-25.md` points at worktree
  `darling-cocotron-pr-text-caret-shift` as the place to continue from. That worktree holds **no
  caret/Shift fix** and is **402 commits behind** `e9de0fe8`; its 10 commits are already-upstream
  work (storyboards, NSPopover, CoreText FreeType, menu validation, Control-key mapping). Starting
  there means rebasing 402 commits of drift for nothing.
- `fork/fix/nstextview-shift-click-selection` is no longer a clean reference for shift selection --
  its tip is now `25ff3dbd` (Control-key editing bindings), unrelated to selection.
- Both were verified by measurement. The Shift-drag fix is `e07fe8ce` on
  `fork/fix/nstextview-shift-drag`, built fresh on a current base, verified by screenshot.
