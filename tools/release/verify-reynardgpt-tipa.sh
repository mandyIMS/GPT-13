#!/bin/sh

set -eu

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
TIPA_PATH="${1:-$ROOT_DIR/dist/ReynardGPT-TrollStore.tipa}"
CACHE_ROOT="${REYNARD_CACHE_ROOT:-$ROOT_DIR/../.cache/reynard}"
EXPECTED_VERSION="${REYNARDGPT_VERSION:-0.1.26}"

fail() {
	echo "VERIFY FAILED: $*" >&2
	exit 1
}

mkdir -p "$CACHE_ROOT"
CACHE_ROOT="$(CDPATH= cd -- "$CACHE_ROOT" && pwd -P)"
VERIFY_DIR="$CACHE_ROOT/verification/reynardgpt"

if [ ! -f "$TIPA_PATH" ]; then
	fail "missing package: $TIPA_PATH"
fi

rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
unzip -q "$TIPA_PATH" -d "$VERIFY_DIR"

APP="$VERIFY_DIR/Payload/ReynardGPT.app"
MAIN="$APP/ReynardGPT"
HELPER_APP="$APP/PlugIns/Reynard Helper.appex"
HELPER="$HELPER_APP/Reynard Helper"
GECKOVIEW="$APP/Frameworks/GeckoView.framework/GeckoView"
XUL="$APP/Frameworks/XUL"

for required in "$MAIN" "$HELPER" "$GECKOVIEW" "$XUL" "$APP/ts_ptrace_jit"; do
	[ -f "$required" ] || fail "missing required binary: $required"
	lipo -info "$required" | grep -q 'arm64' || fail "non-arm64 binary: $required"
done

# Audit every executable Mach-O in the package, not just the five entry
# points. This catches accidentally bundled host tools, simulator slices, a
# dependency built for a newer iOS, and unsigned nested Gecko executables.
MACHO_LIST="$VERIFY_DIR/macho-files.txt"
find "$APP" -type f -perm -111 -print > "$MACHO_LIST"
while IFS= read -r binary; do
	file "$binary" | grep -q 'Mach-O' || continue
	relative_path=${binary#"$APP"/}
	architectures=$(lipo -info "$binary")
	echo "$architectures" | grep -q 'arm64' \
		|| fail "Mach-O lacks arm64: $relative_path"
	echo "$architectures" | grep -Eq 'x86_64|i386|armv7' \
		&& fail "Mach-O contains an unexpected architecture: $relative_path"

	minimum_os=$(otool -l "$binary" | awk '
		$1 == "cmd" && $2 == "LC_BUILD_VERSION" { build = 1; legacy = 0; next }
		build && $1 == "minos" { print $2; exit }
		$1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" { legacy = 1; build = 0; next }
		legacy && $1 == "version" { print $2; exit }
	')
	[ -n "$minimum_os" ] || fail "Mach-O has no iOS minimum version: $relative_path"
	echo "$minimum_os" | awk -F. '
		($1 + 0) < 15 { exit 0 }
		($1 + 0) == 15 && ($2 + 0) <= 3 { exit 0 }
		{ exit 1 }
	' || fail "Mach-O requires iOS $minimum_os: $relative_path"

	# The three TrollStore executables are signed later with ldid and are
	# validated through their entitlements below. Everything else should retain
	# a valid ad-hoc signature from the Xcode archive.
	case "$binary" in
		"$MAIN"|"$HELPER"|"$APP/ts_ptrace_jit") ;;
		*) codesign --verify --strict "$binary" >/dev/null 2>&1 \
			|| fail "invalid or missing nested Mach-O signature: $relative_path" ;;
	esac

	otool -L "$binary" | tail -n +2 | awk '{ print $1 }' | while IFS= read -r dependency; do
		case "$dependency" in
			@rpath/*)
				relative_dependency=${dependency#@rpath/}
				if [ ! -e "$APP/Frameworks/$relative_dependency" ]; then
					case "$relative_dependency" in
						libswift*.dylib) ;; # supplied by /usr/lib/swift on iOS
						*) fail "unresolved dependency $dependency in $relative_path" ;;
					esac
				fi
				;;
			/System/Library/*|/usr/lib/*) ;;
			*) fail "unexpected dependency $dependency in $relative_path" ;;
		esac
	done
done < "$MACHO_LIST"

[ "$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")" = "com.mandyims.muse13v2" ] \
	|| fail "unexpected app bundle identifier"
[ "$(plutil -extract CFBundleDisplayName raw "$APP/Info.plist")" = "Muse Web 測試版" ] \
	|| fail "unexpected app display name"
[ "$(plutil -extract CFBundleName raw "$APP/Info.plist")" = "Muse Web 測試版" ] \
	|| fail "unexpected app bundle name"
[ "$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")" = "$EXPECTED_VERSION" ] \
	|| fail "unexpected app version"
[ "$(plutil -extract CFBundleIdentifier raw "$HELPER_APP/Info.plist")" = "com.mandyims.muse13v2.helper" ] \
	|| fail "unexpected Helper bundle identifier"
[ "$(plutil -extract CFBundlePackageType raw "$HELPER_APP/Info.plist")" = "XPC!" ] \
	|| fail "unexpected Helper package type"
[ "$(plutil -extract MinimumOSVersion raw "$APP/Info.plist")" = "13.0" ] \
	|| fail "unexpected app minimum OS"
[ "$(plutil -extract MinimumOSVersion raw "$HELPER_APP/Info.plist")" = "13.0" ] \
	|| fail "unexpected Helper minimum OS"

plutil -extract CFBundleURLTypes xml1 -o - "$APP/Info.plist" | grep -q '<string>muse13v2</string>' \
	|| fail "missing muse13v2 URL scheme"
for permission in NSCameraUsageDescription NSMicrophoneUsageDescription NSPhotoLibraryUsageDescription; do
	plutil -extract "$permission" raw "$APP/Info.plist" >/dev/null \
		|| fail "missing $permission"
done

otool -l "$MAIN" | grep -A8 LC_BUILD_VERSION | grep -q 'minos 13.0' \
	|| fail "main executable minimum OS is not 13.0"

[ -f "$APP/Assets.car" ] || fail "compiled asset catalog is missing"
[ -f "$APP/AppIcon60x60@2x.png" ] || fail "iPhone app icon is missing"
plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw "$APP/Info.plist" \
	| grep -qx AppIcon || fail "AppIcon is not configured as the primary icon"

MAIN_ENTITLEMENTS="$VERIFY_DIR/main-entitlements.plist"
HELPER_ENTITLEMENTS="$VERIFY_DIR/helper-entitlements.plist"
JIT_ENTITLEMENTS="$VERIFY_DIR/jit-entitlements.plist"
ldid -e "$MAIN" > "$MAIN_ENTITLEMENTS"
ldid -e "$HELPER" > "$HELPER_ENTITLEMENTS"
ldid -e "$APP/ts_ptrace_jit" > "$JIT_ENTITLEMENTS"
plutil -extract 'com\.apple\.private\.security\.no-sandbox' raw "$MAIN_ENTITLEMENTS" | grep -q true \
	|| fail "main executable lacks no-sandbox entitlement"
plutil -extract 'com\.apple\.private\.security\.storage\.AppDataContainers' raw "$MAIN_ENTITLEMENTS" | grep -q true \
	|| fail "main executable cannot access its TrollStore data container"
plutil -extract platform-application raw "$MAIN_ENTITLEMENTS" | grep -q true \
	|| fail "main executable lacks platform-application entitlement"
plutil -extract platform-application raw "$HELPER_ENTITLEMENTS" | grep -q true \
	|| fail "Helper lacks platform-application entitlement"
plutil -extract 'com\.apple\.private\.security\.no-sandbox' raw "$JIT_ENTITLEMENTS" | grep -q true \
	|| fail "ptrace helper lacks no-sandbox entitlement"
plutil -extract 'com\.apple\.private\.security\.container-required' raw "$JIT_ENTITLEMENTS" | grep -q false \
	|| fail "ptrace helper unexpectedly requires an app container"

if find "$APP" -iname '*OpenIn*' -print -quit | grep -q .; then
	fail "OpenIn extension or resource is present"
fi

for excluded_runtime_tool in certutil pk12util xpcshell nsinstall gmp-fake gmp-fakeopenh264; do
	if find "$APP/Frameworks/GeckoView.framework/Frameworks" -name "$excluded_runtime_tool" -print -quit | grep -q .; then
		fail "non-runtime Gecko build tool is present: $excluded_runtime_tool"
	fi
done

# Inspect app-owned resources only. Gecko's runtime contains internal assets
# such as PDF.js's bookmark button; those are engine functionality, not the
# removed Reynard browser UI.
if find "$APP" \
	-path "$APP/Frameworks" -prune -o \
	-path "$APP/PlugIns" -prune -o \
	\( -iname '*bookmark*' -o -iname '*homepage*' -o -iname '*sidebar*' \) \
	-print -quit | grep -q .; then
	fail "generic browser UI resources are present"
fi

codesign --verify --verbose=2 "$APP/Frameworks/GeckoView.framework" >/dev/null 2>&1 \
	|| fail "GeckoView framework signature is invalid"

echo "ReynardGPT package verification passed"
echo "Package: $TIPA_PATH"
echo "Size: $(stat -f '%z' "$TIPA_PATH") bytes"
echo "SHA-256: $(shasum -a 256 "$TIPA_PATH" | awk '{print $1}')"
