// Rung 4 observation program: prints documented public API values, one `key<TAB>value` per line.
// Public API only. Docs relied on (developer.apple.com):
//  /documentation/appkit/nsfont/textstyle
//  /documentation/appkit/nsfont/preferredfont(fortextstyle:options:)
//  /documentation/swiftui/font/width
//  /documentation/appkit/nsaccessibilitycustomrotor/rotortype
//  /documentation/appkit/nsaccessibilitycustomrotor/searchdirection
// Build: swiftc -O ObserveValues.swift -o observe-values
import AppKit
import Darwin
import Foundation
import SwiftUI

func line(_ key: String, _ value: Any) { print("\(key)\t\(value)") }

var utsname_ = utsname()
if uname(&utsname_) != 0 {
    fputs("uname failed\n", stderr)
    exit(EXIT_FAILURE)
}
let machine = withUnsafeBytes(of: &utsname_.machine) { raw in
    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
}
line("os", ProcessInfo.processInfo.operatingSystemVersionString)
line("arch", machine)
line("date", ISO8601DateFormatter().string(from: Date()))

let styles: [(String, NSFont.TextStyle)] = [
    ("body", .body), ("callout", .callout), ("caption1", .caption1), ("caption2", .caption2),
    ("footnote", .footnote), ("headline", .headline), ("subheadline", .subheadline),
    ("largeTitle", .largeTitle), ("title1", .title1), ("title2", .title2), ("title3", .title3),
]

print("# NSFont.TextStyle")
for (name, style) in styles {
    line("\(name).pointSize", NSFont.preferredFont(forTextStyle: style, options: [:]).pointSize)
}

print("# Font.Width")
let widths: [(String, Font.Width)] = [
    ("compressed", .compressed), ("condensed", .condensed),
    ("standard", .standard), ("expanded", .expanded),
]
for (name, width) in widths { line(name, width.value) }

print("# RotorType")
let rotorTypes: [(String, NSAccessibilityCustomRotor.RotorType)] = [
    ("custom", .custom), ("any", .any), ("link", .link), ("visitedLink", .visitedLink),
    ("heading", .heading), ("headingLevel1", .headingLevel1), ("headingLevel2", .headingLevel2),
    ("headingLevel3", .headingLevel3), ("headingLevel4", .headingLevel4),
    ("headingLevel5", .headingLevel5), ("headingLevel6", .headingLevel6),
    ("boldText", .boldText), ("italicText", .italicText), ("underlinedText", .underlinedText),
    ("misspelledWord", .misspelledWord), ("annotation", .annotation), ("image", .image),
    ("textField", .textField), ("table", .table), ("list", .list), ("landmark", .landmark),
    ("audiograph", .audiograph),
]
for (name, type) in rotorTypes { line(name, type.rawValue) }

print("# SearchDirection")
line("previous", NSAccessibilityCustomRotor.SearchDirection.previous.rawValue)
line("next", NSAccessibilityCustomRotor.SearchDirection.next.rawValue)
