#!/bin/sh
# Builds the authored PR2a fixtures for arm64 (opcode encoding, SDK 11.0).
# Usage: build.sh <outdir>      Env: MST_LD (ld64)
# Layout: <outdir>/{main_hello,main_data,main_exec,main_dlopen,libmst.dylib (empty),
#                   b_short.bundle,b_long4095.bundle,b_long4096.bundle,b_esc.bundle}
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build.sh <outdir>}
ld=${MST_LD:?set MST_LD to the ld64 binary}
ver="-platform_version macos 11.0 11.0"
cc="clang -target arm64-apple-macos11 -ffreestanding -nostdinc -O1 -fno-stack-protector"
obj=$out/obj
mkdir -p "$obj"

for n in sysstub libmstreal libmstempty main_hello main_data main_exec main_dlopen; do
	$cc -c "$here/fx/$n.c" -o "$obj/$n.o"
done
"$ld" -arch arm64 -dylib $ver -install_name /usr/lib/libSystem.B.dylib -compatibility_version 1 \
	-o "$obj/libSystem.B.dylib" "$obj/sysstub.o"
"$ld" -arch arm64 -dylib $ver -install_name @executable_path/libmst.dylib -o "$obj/libmstreal.dylib" "$obj/libmstreal.o"
"$ld" -arch arm64 -dylib $ver -install_name @executable_path/libmst.dylib -o "$out/libmst.dylib" "$obj/libmstempty.o"
for m in main_hello main_data main_exec main_dlopen; do
	"$ld" -arch arm64 $ver -e _main -o "$out/$m" "$obj/$m.o" "$obj/libmstreal.dylib" "$obj/libSystem.B.dylib"
done

# Flat-namespace bundles whose one import nobody exports.
bundle() {
	$cc -c "$here/fx/bundle.c" -DMST_NAME="$2" -o "$obj/$1.o"
	"$ld" -arch arm64 -bundle $ver -undefined dynamic_lookup -o "$out/$1.bundle" "$obj/$1.o"
}
long() {
	python3 -c 'import sys; print("_" + "A" * (int(sys.argv[1]) - 1))' "$1"
}
bundle b_short _mst_flat_missing
bundle b_long4095 "$(long 4095)"
bundle b_long4096 "$(long 4096)"
bundle b_esc _MSTESC_PLACEHOLDER_0123456789
python3 "$here/patch_name.py" "$out/b_esc.bundle" _MSTESC_PLACEHOLDER_0123456789
echo "built into $out"
