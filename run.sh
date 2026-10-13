#!/bin/bash
# PR2a tests for missing-symbol tracing (DARLING_MISSING_SYMBOLS=log), arm64 only.
#
# Usage: MST_WORK=<dir> MST_RUNTIME=<runtime> [MST_BASE_RUNTIME=<runtime>] run.sh <test>...
#   tests: t1 t2 t4 t6 t7 tcap tesc (t1 needs MST_BASE_RUNTIME: the same runtime with the base dyld)
#   A runtime is a DESTDIR install root (<runtime>/usr/local). The tests run the non-setuid
#   launcher with DARLING_INSTALL_PREFIX in a private prefix under MST_WORK.
# Env: MST_LD (ld64, to build fixtures), DARLING_BIN (non-setuid launcher), MST_LOCKED=1 when the
#      caller already holds /tmp/agent-locks/darling-heavy-build.lock.
# Prints one PASS/FAIL line per check; exits 1 if any check failed.
set -u

lock=/tmp/agent-locks/darling-heavy-build.lock
if [ -z "${MST_LOCKED:-}" ]; then
	MST_LOCKED=1 exec flock -w 3000 "$lock" "$0" "$@"
fi

here=$(cd "$(dirname "$0")" && pwd)
W=${MST_WORK:?set MST_WORK}
RT=${MST_RUNTIME:?set MST_RUNTIME}
L=${DARLING_BIN:-/home/cristi/tmp-opencode/tooling/runtime-master/ws2/build/src/startup/darling}
case $W in /*) ;; *) echo "MST_WORK must be absolute" >&2; exit 2 ;; esac
[ -u "$L" ] && { echo "launcher is setuid, it would ignore DARLING_INSTALL_PREFIX" >&2; exit 2; }
unset DARLING_PROFILE DARLING_MISSING_SYMBOLS DARLING_MISSING_SYMBOLS_LOG DYLD_USE_CLOSURES
export TMPDIR=$W/tmp
mkdir -p "$TMPDIR"

FX=$W/fx
[ -x "$FX/main_hello" ] || "$here/build.sh" "$FX" >"$W/build-fx.log" 2>&1 || { echo "FAIL fixture build" >&2; exit 1; }
G=/Volumes/SystemRoot          # guest view of the host root
GFX=$G$FX
status=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; status=1; }

PFX=
start_prefix() {   # <runtime> <name>
	stop_prefix
	export DARLING_INSTALL_PREFIX=$1/usr/local DPREFIX=$W/pfx-$2
	mkdir -p "$DPREFIX"
	timeout 300 "$L" shell /usr/bin/true >/dev/null 2>&1 || { echo "prefix warm-up failed" >&2; exit 1; }
	PFX=$DPREFIX
	GHOME=$(timeout 120 "$L" shell /bin/sh -c 'printf %s "$HOME"')
	HHOME=$DPREFIX$GHOME         # host path of the guest HOME
}
stop_prefix() {
	[ -n "$PFX" ] && DPREFIX=$PFX "$L" shutdown >/dev/null 2>&1
	PFX=
}
trap stop_prefix EXIT

# guest <tag> <env-args...> -- <fixture> [args]: runs /usr/bin/env <env-args> <fixture> in the guest.
# Leaves $W/out/<tag>.{out,err,rc}.
guest() {
	tag=$1; shift
	envargs=()
	while [ "$1" != -- ]; do envargs+=("$1"); shift; done
	shift
	mkdir -p "$W/out"
	timeout 600 "$L" shell /usr/bin/env "${envargs[@]}" "$@" >"$W/out/$tag.out" 2>"$W/out/$tag.err"
	echo $? >"$W/out/$tag.rc"
}
rc() { cat "$W/out/$1.rc"; }

# newdir <name> [mode]: a fresh host directory under MST_WORK; prints its host path.
newdir() {
	d=$W/dirs/$1
	rm -rf "$d"
	mkdir -p "$d"
	chmod "${2:-700}" "$d"
	printf %s "$d"
}
nfiles() { find "$1" -maxdepth 1 -type f | wc -l; }

# Expected record for a missing import, paths in the guest view.
rec() {   # <sym> <lib> <from>
	printf '{"v":1,"kind":"missing","sym":"%s","lib":"%s","from":"%s","arch":"arm64"}' "$1" "$2" "$3"
}

# Checks one log directory holds exactly one file for <exe> whose content equals <expected> (one line).
check_one_record() {   # <label> <dir> <exe> <expected-line>
	files=$(find "$2" -maxdepth 1 -type f)
	n=$(printf '%s\n' "$files" | grep -c .)
	[ "$n" = 1 ] || { fail "$1: expected 1 log file, found $n"; return; }
	base=$(basename "$files")
	printf %s "$base" | grep -Eq "^$3-[0-9]+-[0-9]+\.jsonl$" || fail "$1: file name $base"
	[ "$(stat -c %a "$files")" = 600 ] || fail "$1: file mode $(stat -c %a "$files")"
	exp=$(printf '%s\n' "$4")
	if [ "$(cat "$files")" = "$exp" ] && [ "$(wc -l <"$files")" = 1 ]; then
		pass "$1: record"
	else
		fail "$1: record differs: $(head -c 400 "$files")"
	fi
	check_schema "$1" "$files"
}

# R8 / t4: every line parses, its keys are a subset of the schema, no forbidden key appears.
check_schema() {   # <label> <file>
	if ! jq -e . "$2" >/dev/null 2>&1; then fail "$1: jq rejects a line"; return; fi
	extra=$(jq -r 'keys[]' "$2" | sort -u | grep -vxE 'v|kind|sym|lib|from|arch')
	[ -z "$extra" ] || fail "$1: keys outside the schema: $extra"
	if jq -r 'keys[]' "$2" | grep -iqE 'lr|pc|sp|stack|offset|addr|deref|reg|env|ret'; then
		fail "$1: forbidden key"
	fi
	kinds=$(jq -r .kind "$2" | sort -u | grep -vxE 'missing|truncated')
	[ -z "$kinds" ] || fail "$1: unknown kind $kinds"
	[ -z "$extra" ] && pass "$1: schema"
}

no_guest() {   # <label> <tag>: the halt case: non-zero, one message, guest never ran
	if [ "$(rc "$2")" != 0 ] && ! grep -q guest-ran "$W/out/$2.out" &&
		[ "$(grep -c 'missing-symbol trace:' "$W/out/$2.err")" = 1 ]; then
		pass "$1"
	else
		fail "$1: rc=$(rc "$2") out=$(head -c 80 "$W/out/$2.out" | tr '\n' '|') err=$(head -c 300 "$W/out/$2.err" | tr '\n' '|')"
	fi
}

t1() {
	BRT=${MST_BASE_RUNTIME:?t1 needs MST_BASE_RUNTIME}
	runs="hello:main_hello data:main_data exec:main_exec:$GFX/main_data dl:main_dlopen:$GFX/b_short.bundle:3"
	logd=$(newdir t1-log)
	for rt in base:$BRT pr:$RT; do
		start_prefix "${rt#*:}" "${rt%%:*}"
		rm -rf "$HHOME/Library/Logs/Darling"
		for r in $runs; do
			IFS=: read -r name fx a1 a2 <<<"$r"
			guest "t1-${rt%%:*}-unset-$name" -- "$GFX/$fx" ${a1:+"$a1"} ${a2:+"$a2"}
			guest "t1-${rt%%:*}-empty-$name" DARLING_MISSING_SYMBOLS= DARLING_MISSING_SYMBOLS_LOG="$G$logd" -- "$GFX/$fx" ${a1:+"$a1"} ${a2:+"$a2"}
		done
		[ -e "$HHOME/Library/Logs/Darling" ] && fail "t1 ${rt%%:*}: default log directory created while off"
		stop_prefix
	done
	[ "$(nfiles "$logd")" = 0 ] || fail "t1: a log file was created while off"
	for r in $runs; do
		name=$(printf %s "$r" | cut -d: -f1)
		for v in unset empty; do
			same=1
			for ext in out err rc; do
				cmp -s "$W/out/t1-base-unset-$name.$ext" "$W/out/t1-pr-$v-$name.$ext" || same=0
			done
			[ $same = 1 ] && pass "t1 $name env $v: byte-identical to base" || fail "t1 $name env $v: differs from base"
		done
	done
}

t2() {
	start_prefix "$RT" pr
	d=$(newdir t2)
	for m in bogus Log "log " trap continue; do
		guest "t2-$m" DARLING_MISSING_SYMBOLS="$m" DARLING_MISSING_SYMBOLS_LOG="$G$d" -- "$GFX/main_hello"
		no_guest "t2 mode '$m' halts" "t2-$m"
	done
	[ "$(nfiles "$d")" = 0 ] || fail "t2: a log file was created"
}

t4() {
	start_prefix "$RT" pr
	guest t4-off-data -- "$GFX/main_data"
	guest t4-off-hello -- "$GFX/main_hello"
	d=$(newdir t4-data)
	guest t4-data DARLING_MISSING_SYMBOLS=log DARLING_MISSING_SYMBOLS_LOG="$G$d" -- "$GFX/main_data"
	check_one_record "t4 main_data (launch miss)" "$d" main_data "$(rec _d_miss "$GFX/libmst.dylib" "$GFX/main_data")"
	d=$(newdir t4-hello)
	guest t4-hello DARLING_MISSING_SYMBOLS=log DARLING_MISSING_SYMBOLS_LOG="$G$d" -- "$GFX/main_hello"
	check_one_record "t4 main_hello (lazy miss)" "$d" main_hello "$(rec _f_miss "$GFX/libmst.dylib" "$GFX/main_hello")"
	for f in data hello; do
		if cmp -s "$W/out/t4-off-$f.err" "$W/out/t4-$f.err" && cmp -s "$W/out/t4-off-$f.out" "$W/out/t4-$f.out" &&
			[ "$(rc "t4-off-$f")" = "$(rc "t4-$f")" ]; then
			pass "t4 $f: stdout, stderr and exit unchanged by tracing"
		else
			fail "t4 $f: tracing changed stdout, stderr or exit"
		fi
	done
}

t6() {
	start_prefix "$RT" pr
	d=$(newdir t6-plain)
	guest t6-plain DARLING_MISSING_SYMBOLS=log DARLING_MISSING_SYMBOLS_LOG="$G$d" -- "$GFX/main_data"
	for c in 1 2 bogus; do
		d2=$(newdir "t6-closures-$c")
		guest "t6-closures-$c" DYLD_USE_CLOSURES=$c DARLING_MISSING_SYMBOLS=log DARLING_MISSING_SYMBOLS_LOG="$G$d2" -- "$GFX/main_data"
		if cmp -s "$W/out/t6-plain.err" "$W/out/t6-closures-$c.err" && [ "$(rc t6-plain)" = "$(rc "t6-closures-$c")" ]; then
			pass "t6 DYLD_USE_CLOSURES=$c: same dyld2 error, no closure warning"
		else
			fail "t6 DYLD_USE_CLOSURES=$c: stderr differs: $(head -c 300 "$W/out/t6-closures-$c.err" | tr '\n' '|')"
		fi
		check_one_record "t6 DYLD_USE_CLOSURES=$c" "$d2" main_data "$(rec _d_miss "$GFX/libmst.dylib" "$GFX/main_data")"
	done
}

t7() {
	start_prefix "$RT" pr
	hx=$GFX/main_hello
	on=DARLING_MISSING_SYMBOLS=log
	d=$(newdir t7-target)
	ln -sfn "$d" "$W/dirs/t7-link"
	guest t7-final-symlink $on DARLING_MISSING_SYMBOLS_LOG="$G$W/dirs/t7-link" -- "$hx"
	no_guest "t7 final directory is a symlink" t7-final-symlink
	newdir t7-real >/dev/null
	mkdir -p "$W/dirs/t7-real/sub" && chmod 700 "$W/dirs/t7-real/sub"
	ln -sfn "$W/dirs/t7-real" "$W/dirs/t7-anclink"
	guest t7-ancestor-symlink $on DARLING_MISSING_SYMBOLS_LOG="$G$W/dirs/t7-anclink/sub" -- "$hx"
	no_guest "t7 symlinked ancestor" t7-ancestor-symlink
	g=$(newdir t7-groupw 770)
	guest t7-group-writable $on DARLING_MISSING_SYMBOLS_LOG="$G$g" -- "$hx"
	no_guest "t7 group-writable directory" t7-group-writable
	o=$(newdir t7-otherw 707)
	guest t7-other-writable $on DARLING_MISSING_SYMBOLS_LOG="$G$o" -- "$hx"
	no_guest "t7 other-writable directory" t7-other-writable
	a=$(newdir t7-anc-w 777)
	mkdir -p "$a/sub" && chmod 700 "$a/sub"
	guest t7-ancestor-writable $on DARLING_MISSING_SYMBOLS_LOG="$G$a/sub" -- "$hx"
	no_guest "t7 world-writable non-sticky ancestor" t7-ancestor-writable
	guest t7-relative $on DARLING_MISSING_SYMBOLS_LOG=logs -- "$hx"
	no_guest "t7 relative path" t7-relative
	guest t7-empty $on DARLING_MISSING_SYMBOLS_LOG= -- "$hx"
	no_guest "t7 empty path" t7-empty
	guest t7-dotdot $on DARLING_MISSING_SYMBOLS_LOG="$G$d/../t7-target" -- "$hx"
	no_guest "t7 .. component" t7-dotdot
	guest t7-missing $on DARLING_MISSING_SYMBOLS_LOG="$G$W/dirs/does-not-exist" -- "$hx"
	no_guest "t7 missing directory (not created)" t7-missing
	[ -e "$W/dirs/does-not-exist" ] && fail "t7 missing directory was created"
	guest t7-nohome -u HOME $on -- "$hx"
	no_guest "t7 HOME unset and no log directory" t7-nohome
	guest t7-other-user $on DARLING_MISSING_SYMBOLS_LOG=$G/usr -- "$hx"
	no_guest "t7 directory owned by another user (/usr, root)" t7-other-user
	guest t7-host-tmp $on DARLING_MISSING_SYMBOLS_LOG=$G/tmp -- "$hx"
	no_guest "t7 host /tmp" t7-host-tmp
	guest t7-guest-tmp $on DARLING_MISSING_SYMBOLS_LOG=/private/tmp -- "$hx"
	no_guest "t7 guest /private/tmp" t7-guest-tmp
	for x in "$d" "$g" "$o" "$a/sub" "$W/dirs/t7-real/sub"; do
		[ "$(nfiles "$x")" = 0 ] || fail "t7: a log file was created in $x"
	done

	# Default directory: created 0700 under the guest HOME when no directory is given.
	rm -rf "$HHOME/Library/Logs/Darling"
	guest t7-default $on -- "$GFX/main_data"
	dd=$HHOME/Library/Logs/Darling/MissingSymbols
	if [ -d "$dd" ] && [ "$(stat -c %a "$dd")" = 700 ] && [ "$(stat -c %a "$HHOME/Library/Logs/Darling")" = 700 ]; then
		pass "t7 default directory created 0700"
	else
		fail "t7 default directory: $(ls -ld "$dd" 2>&1)"
	fi
	check_one_record "t7 default directory" "$dd" main_data "$(rec _d_miss "$GFX/libmst.dylib" "$GFX/main_data")"

	e=$(newdir t7-exec)
	guest t7-exec $on DARLING_MISSING_SYMBOLS_LOG="$G$e" -- "$GFX/main_exec" "$GFX/main_data"
	ne=$(find "$e" -maxdepth 1 -name 'main_exec-*.jsonl' | wc -l)
	nd=$(find "$e" -maxdepth 1 -name 'main_data-*.jsonl' | wc -l)
	[ "$ne" = 1 ] && [ "$nd" = 1 ] && [ "$(nfiles "$e")" = 2 ] && pass "t7 main_exec: 2 files" ||
		fail "t7 main_exec: $(ls "$e" | tr '\n' ' ')"
	b=$(newdir t7-twice)
	guest t7-twice-1 $on DARLING_MISSING_SYMBOLS_LOG="$G$b" -- "$GFX/main_data"
	guest t7-twice-2 $on DARLING_MISSING_SYMBOLS_LOG="$G$b" -- "$GFX/main_data"
	[ "$(nfiles "$b")" = 2 ] && pass "t7 two runs: 2 files" || fail "t7 two runs: $(ls "$b" | tr '\n' ' ')"
}

tcap() {
	start_prefix "$RT" pr
	d=$(newdir tcap-records)
	guest tcap-records DARLING_MISSING_SYMBOLS=log DARLING_MISSING_SYMBOLS_LOG="$G$d" -- "$GFX/main_dlopen" "$GFX/b_short.bundle" 5000
	f=$(find "$d" -maxdepth 1 -type f)
	nm=$(grep -c '"kind":"missing"' "$f")
	last=$(tail -n 1 "$f")
	if [ "$nm" = 4096 ] && [ "$(wc -l <"$f")" = 4097 ] && [ "$last" = '{"v":1,"kind":"truncated"}' ] &&
		grep -q all-failed "$W/out/tcap-records.out"; then
		pass "tcap 5000 misses: 4096 records plus one truncated"
	else
		fail "tcap records: missing=$nm lines=$(wc -l <"$f") last=$last out=$(cat "$W/out/tcap-records.out")"
	fi
	check_one=$(head -n 1 "$f")
	[ "$check_one" = "$(rec _mst_flat_missing "flat namespace" "$GFX/b_short.bundle")" ] && pass "tcap flat record" ||
		fail "tcap flat record: $check_one"
	check_schema "tcap records" "$f"

	d=$(newdir tcap-bytes)
	guest tcap-bytes DARLING_MISSING_SYMBOLS=log DARLING_MISSING_SYMBOLS_LOG="$G$d" -- "$GFX/main_dlopen" "$GFX/b_long4095.bundle" 5000
	f=$(find "$d" -maxdepth 1 -type f)
	size=$(stat -c %s "$f")
	nm=$(grep -c '"kind":"missing"' "$f")
	reclen=$(head -n 1 "$f" | wc -c)
	last=$(tail -n 1 "$f")
	max=$((16 * 1024 * 1024))
	if [ "$size" -le "$max" ] && [ "$last" = '{"v":1,"kind":"truncated"}' ] && [ "$nm" -lt 4096 ] &&
		[ $((size + reclen)) -gt "$max" ]; then
		pass "tcap 16 MiB: $size bytes, $nm records of $reclen bytes, then truncated"
	else
		fail "tcap 16 MiB: size=$size records=$nm reclen=$reclen last=$last"
	fi
	sym=$(head -n 1 "$f" | jq -r .sym)
	[ ${#sym} = 4095 ] && pass "tcap 4095-byte name kept whole" || fail "tcap 4095-byte name: length ${#sym}"

	d=$(newdir tcap-name)
	guest tcap-name DARLING_MISSING_SYMBOLS=log DARLING_MISSING_SYMBOLS_LOG="$G$d" -- "$GFX/main_dlopen" "$GFX/b_long4096.bundle" 1
	exp=$(printf '{"v":1,"kind":"truncated","lib":"flat namespace","from":"%s","arch":"arm64"}' "$GFX/b_long4096.bundle")
	check_one_record "tcap 4096-byte name" "$d" main_dlopen "$exp"
}

tesc() {
	start_prefix "$RT" pr
	d=$(newdir tesc)
	guest tesc DARLING_MISSING_SYMBOLS=log DARLING_MISSING_SYMBOLS_LOG="$G$d" -- "$GFX/main_dlopen" "$GFX/b_esc.bundle" 1
	check_one_record "tesc hostile name" "$d" main_dlopen "$(python3 "$here/expect_esc.py" line "$GFX/b_esc.bundle")"
	f=$(find "$d" -maxdepth 1 -type f)
	python3 "$here/expect_esc.py" check "$f" && pass "tesc: decoded name equals the raw bytes" || fail "tesc: decoded name differs"
	LC_ALL=C grep -q '[^ -~]' "$f" && fail "tesc: non-ASCII byte in the log" || pass "tesc: log is printable ASCII"
}

[ $# -gt 0 ] || set -- t2 t4 t6 t7 tcap tesc
for t in "$@"; do
	echo "=== $t"
	"$t"
	stop_prefix
done
exit $status
