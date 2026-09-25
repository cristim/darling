#!/usr/bin/env bash
set -euo pipefail

# Build the Swift Symbols compatibility framework in an isolated staging root.
# Requires a Swift compiler targeting Darwin and the matching SDK/runtime.
: "${SYMBOLS_SWIFTC:?set SYMBOLS_SWIFTC to the Darwin-capable swiftc}"
: "${SYMBOLS_SDK:?set SYMBOLS_SDK to the Darwin SDK}"
: "${SYMBOLS_RESOURCE_DIR:?set SYMBOLS_RESOURCE_DIR to the Darwin Swift resource directory}"
: "${SYMBOLS_OUTPUT_ROOT:?set SYMBOLS_OUTPUT_ROOT to a writable staging root}"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_file="$script_dir/../../src/frameworks/Symbols/src/Symbols.swift"
framework="$SYMBOLS_OUTPUT_ROOT/System/Library/Frameworks/Symbols.framework"
version="$framework/Versions/A"
modules="$version/Modules/Symbols.swiftmodule"
mkdir -p "$modules"

flags=(
    -target "${SYMBOLS_TARGET:-arm64-apple-macosx26.0}"
    -sdk "$SYMBOLS_SDK"
    -resource-dir "$SYMBOLS_RESOURCE_DIR"
    -module-name Symbols
    -enable-library-evolution
    -emit-library
    -emit-module
    -emit-module-path "$modules/arm64-apple-macos.swiftmodule"
    -emit-module-interface-path "$modules/arm64-apple-macos.swiftinterface"
    -Xlinker -install_name
    -Xlinker /System/Library/Frameworks/Symbols.framework/Versions/A/Symbols
    -o "$version/Symbols"
)
if [[ -n "${SYMBOLS_DARWIN_LINKER:-}" ]]; then
    flags+=("-use-ld=$SYMBOLS_DARWIN_LINKER")
fi
if [[ -n "${SYMBOLS_LINK_SYSROOT:-}" ]]; then
    flags+=(-Xlinker -syslibroot -Xlinker "$SYMBOLS_LINK_SYSROOT")
fi
if [[ -n "${SYMBOLS_LIBRARY_DIR:-}" ]]; then
    flags+=("-L$SYMBOLS_LIBRARY_DIR")
fi
"$SYMBOLS_SWIFTC" "${flags[@]}" "$source_file"
ln -sfn A "$framework/Versions/Current"
ln -sfn Versions/Current/Symbols "$framework/Symbols"
ln -sfn Versions/Current/Modules "$framework/Modules"
