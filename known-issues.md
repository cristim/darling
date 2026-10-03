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

## CFString constant values that could not be established (OPEN, needs a build)

Upstream PR 1624 ("Add missing symbols", Niram7777) adds 42 exported constants to
AVFoundation, CoreMedia, CoreVideo and VideoToolbox. 27 of them are already defined on this
branch, 20 of those with a different value, so taking the PR as written would not link. The
remaining 15 are genuinely absent, but their values cannot be derived from `AGENTS.md` section 1's
escalation ladder without a build, so they were not landed either.

### Why values cannot be taken from the headers in this tree

`framework-include/<Framework>` is not Apple material. Each entry is a symlink into
`src/frameworks/<Framework>/include/`, and those files carry Darling's own GPL header and are
byte-identical to it:

    $ realpath framework-include/CoreVideo/CVImageBuffer.h
    .../src/frameworks/CoreVideo/include/CoreVideo/CVImageBuffer.h
    $ diff framework-include/CoreMedia/CoreMedia.h \
           src/frameworks/CoreMedia/include/CoreMedia/CoreMedia.h   # no output

So for these four frameworks rung 2 is circular and agrees with whatever the tree already says.
Commit afa7ad7516 ("CoreImage: correct the values of 21 attribute and category constants")
reached the same conclusion for the same reason: "The header publishes the declaration and never
the string". Apple's documentation JSON for these symbols carries `externalID`, type and platform
availability, and no value.

### Duplicate: 27 definitions the PR would add that already exist here

| framework | count | existing definition |
|-----------|-------|---------------------|
| AVFoundation | 1 | `src/frameworks/AVFoundation/constants.m:94` |
| CoreVideo | 19 | `src/frameworks/CoreVideo/src/constants.c` |
| VideoToolbox | 7 | `src/frameworks/VideoToolbox/src/VTCompressionProperties.c`, `src/frameworks/VideoToolbox/src/VideoToolbox.m` |

The VideoToolbox seven are the sharpest case. `src/frameworks/VideoToolbox/CMakeLists.txt`
compiles `src/VideoToolbox.m` and `src/VTCompressionProperties.c` into one target, so the PR's
copies are multiple definitions inside a single dylib. Git merges them without reporting a
conflict, because the surrounding lines differ. The CoreVideo nineteen land in
`src/frameworks/CoreVideo/src/constants.c` itself, which is a redefinition the compiler rejects
rather than the linker.

### Value change: 20 constants the PR would overwrite

For 19 of the twenty, the value the PR proposes is the value already here with the constant's own
family name glued in front of it. That is a mechanical signature of a string invented from the
constant's identifier, which is the defect `afa7ad7516` exists to undo, and it is why none of
these 19 can be taken:

  constant                                value here                   value the PR proposes
  kCVImageBufferColorPrimariesKey         CVImageBufferColorPrimaries  CVImageBufferColorPrimariesKey
  kCVImageBufferYCbCrMatrixKey            CVImageBufferYCbCrMatrix     CVImageBufferYCbCrMatrixKey
  kCVImageBufferTransferFunctionKey       CVImageBufferTransferFunction
                                                                  CVImageBufferTransferFunctionKey
  kCVImageBufferGammaLevelKey             CVImageBufferGammaLevel      CVImageBufferGammaLevelKey
  kCVImageBufferColorPrimaries_EBU_3213   EBU_3213                     CVImageBufferColorPrimaries_EBU_3213
  kCVImageBufferColorPrimaries_ITU_R_709_2  ITU_R_709_2                CVImageBufferColorPrimaries_ITU_R_709_2
  kCVImageBufferTransferFunction_UseGamma UseGamma                     CVImageBufferTransferFunction_UseGamma
  kCVImageBufferYCbCrMatrix_ITU_R_601_4   ITU_R_601_4                  CVImageBufferYCbCrMatrix_ITU_R_601_4
  ...and 11 more, same shape

A guest that parses one of these values out of a file and compares it against the constant takes
the wrong branch with no error, which is the outcome `afa7ad7516` calls worse than a missing
symbol.

The twentieth, `kVTProfileLevel_H264_High_AutoLevel`, is the one that breaks the pattern, and it
breaks it in the direction that looks correct. It is the case to settle first; see the last
section.

### Absent, name confirmed, value unknown: 15

Names and types are confirmed at rung 3, by Apple's own documentation pages:

  CoreMedia, page "Format Description Constants"
    kCMFormatDescriptionExtension_ContentLightLevelInfo
    kCMFormatDescriptionExtension_Depth
    kCMFormatDescriptionExtension_FormatName
    kCMFormatDescriptionExtension_FullRangeVideo
    kCMFormatDescriptionExtension_MasteringDisplayColorVolume
    kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
    kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
  CoreMedia, individual pages
    kCMFormatDescriptionColorPrimaries_DCI_P3      "the DCI P3 color primary"
    kCMFormatDescriptionColorPrimaries_ITU_R_2020  "the ITU R 2020 color primary"
    kCMFormatDescriptionColorPrimaries_P3_D65      "the P3 D65 color primary"
    kCMFormatDescriptionTransferFunction_ITU_R_2020
    kCMFormatDescriptionTransferFunction_SMPTE_ST_428_1
    kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
    kCMSampleAttachmentKey_IsDependedOnByOthers     "whether other samples depend on this
                                                    sample for decoding", type CFBoolean
  CoreVideo, page "Image Buffer Transfer Function Constants"
    kCVImageBufferTransferFunction_sRGB

Apple's pages list no value for any of them, so rungs 1 to 3 stop here. Rungs 4 and 5 both need
something this tree does not have: a runtime to call, or a build to read symbol and string data
out of. Only rung 6 is left, and rung 6 is not the right tool here, because a constant that
resolves but compares unequal is worse than a missing symbol. afa7ad7516 says so directly, and
its own verification was a guest program that read each constant out of an installed framework
and compared it. That is the check these 15 need before they land.

`kCMSampleAttachmentKey_IsDependedOnByOthers = CFSTR("IsDependedOnByOthers")` is the one value
in the whole PR that matches this tree's convention, since the sibling
`kCMFormatDescriptionExtension_*` and `kCMSampleAttachmentKey_NotSync` at
`src/frameworks/CoreMedia/src/CoreMedia.c` use the short spelling. Sibling agreement is not
evidence about Apple's value, so it stays out until it is observed.

### The one case to settle first

`kVTProfileLevel_H264_High_AutoLevel` is the single constant in PR 1624 whose proposed value
looks more plausible than the one already here, so it is worth separating from the rest. On this
branch it is defined once, as `CFSTR("H264_High_AutoLevel")`, at
`src/frameworks/VideoToolbox/src/VTCompressionProperties.c`, while its two siblings in the same
framework are both `CFSTR("AutoLevel")`:

  src/frameworks/VideoToolbox/src/VideoToolbox.m:35  kVTProfileLevel_H264_Baseline_AutoLevel  "AutoLevel"
  src/frameworks/VideoToolbox/src/VideoToolbox.m:36  kVTProfileLevel_H264_Main_AutoLevel     "AutoLevel"
  src/frameworks/VideoToolbox/src/VTCompressionProperties.c:26
                                                          kVTProfileLevel_H264_High_AutoLevel  "H264_High_AutoLevel"

All three name the same thing, an automatically chosen level, and Apple's
`VTCompressionProperties.h` declares all three next to each other. Either the High one is wrong
here, or the naming is coincidence. PR 1624 proposes `"AutoLevel"`, which would make the three
agree, and it is also the single one of the twenty value changes whose proposed string is not just
the existing value with the family name glued on, so it is the only one of the twenty with a
positive reason to prefer it. That is still a consistency argument about this tree rather than
evidence about Apple's value, and the same PR gets the other 19 wrong. Settle it by observation
before changing it: one guest program reading each constant out of an installed VideoToolbox.
## Carbon event loop

### RunApplicationEventLoop is still an immediate-return stub
- `src/frameworks/Carbon/src/Carbon.c:150` returns at once. A guest calling it
  resumes on the next line instead of entering an event loop.
- Upstream PR #1780 (draft, `Lazerbeak12345`) replaces the stub with a blocking
  `CFRunLoopRun()` in `src/frameworks/Carbon/HIToolbox/src/CarbonEvents.c`, and
  was held back rather than integrated: its only commit is titled
  `DO NOT MERGE! feat: implement Carbon EventLoop`, and of the seven functions it
  declares in `CarbonEventsCore.h` four (`GetCurrentEventLoop`,
  `RunCurrentEventLoop`, `QuitEventLoop`, `QuitApplicationEventLoop`) have no
  definition, only commented-out bodies. A declaration with no definition in a
  shipped dylib is a latent link failure for any guest that calls it.
- Landing the blocking version without a way to stop it would be worse than the
  stub. On the main thread `CFRunLoopRun` does block indefinitely, not return:
  `__CFRunLoopModeIsEmpty` treats the main loop's default mode as non-empty
  because it is a member of `commonModes` (`corefoundation/CFRunLoop.c:837`, and
  the default mode is seeded into `commonModes` at `CFRunLoop.c:1334`), so the
  early return for an empty mode at `CFRunLoop.c:2664` is not taken and
  `__CFRunLoopRun` waits on the port set with an infinite timeout. With
  `QuitApplicationEventLoop` and `QuitEventLoop` unimplemented, nothing can call
  `CFRunLoopStop`, so a guest reaching `RunApplicationEventLoop` would hang
  forever instead of returning. That also affects
  `python/2.7/.../carbonevt/_CarbonEvtmodule.c:1860`, which calls it from
  `CarbonEvents.RunApplicationEventLoop()`.
