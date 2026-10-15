# observe-values

Rung 4 observation program (see compliance ruling RULING-rung4-observed-values.md). It calls public
AppKit/SwiftUI API only and prints the documented return values, one `key<TAB>value` per line.

The complete observation set is:

- `NSFont.TextStyle`: `body`, `callout`, `caption1`, `caption2`, `footnote`, `headline`,
  `subheadline`, `largeTitle`, `title1`, `title2`, and `title3`, each reported as `pointSize`.
- `Font.Width`: `compressed`, `condensed`, `standard`, and `expanded`, each reported as `value`.
- `NSAccessibilityCustomRotor.RotorType`: `custom`, `any`, `link`, `visitedLink`, `heading`,
  `headingLevel1` through `headingLevel6`, `boldText`, `italicText`, `underlinedText`,
  `misspelledWord`, `annotation`, `image`, `textField`, `table`, `list`, `landmark`, and
  `audiograph`, each reported as `rawValue`.
- `NSAccessibilityCustomRotor.SearchDirection`: `previous` and `next`, each reported as
  `rawValue`.

If any listed public case is unavailable in the selected macOS SDK, keep the compile error and report
it verbatim. Do not omit that case or substitute a value. The program records the actual OS version
and architecture. Its `NSFont` point sizes are observations of AppKit; mapping those styles to
SwiftUI text styles remains the explicit assumption documented in the tracer-driven symbol plan.

## Before the run

The observation target is not confirmed. macOS 26.0 is only a candidate from a recovered compiler
triple. Do not run this program until the target macOS version is confirmed. Commit this source
first so its provenance path is real: `tools/observe-values/ObserveValues.swift`.

## Run (on the Mac only; the swiftc build runs on the user's Mac, never on the Linux host)

After the target is confirmed and this source is committed, run in the
`tools/observe-values/` directory:

    swiftc -O ObserveValues.swift -o observe-values && ./observe-values > observed-values.txt

Leave the system text size and accessibility display settings at their defaults.

## Paste back

- `observed-values.txt`
- the macOS version, and a statement that the system text size and accessibility display settings
  were at their defaults
- if the build fails, the compiler error verbatim

No AppKit/SwiftUI typecheck or Mac execution has been performed yet. The earlier scratch copy only
received a Linux syntax parse, which does not validate these SDK APIs.

## Provenance line for commits and the symbol list

    rung 4, observed on macOS <version> (<arch>), program <repo-relative path>, run by the user on <date>

For pointSize values also note that the text-size setting was the default. Re-run if the target
macOS version changes.
