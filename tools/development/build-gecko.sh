#!/bin/sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"
CACHE_ROOT="${REYNARD_CACHE_ROOT:-$ROOT_DIR/../.cache/reynard}"
CLANG_ROOT="${REYNARD_CLANG_ROOT:-$CACHE_ROOT/toolchains/macosx64-aarch64-clang-21/clang}"
NODE_ROOT="${REYNARD_NODE_ROOT:-$CACHE_ROOT/toolchains/macosx64-aarch64-node-22/node}"
MACOS_SDK_ROOT="${REYNARD_MACOS_SDK_ROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
MOZCONFIG_PATH="$FIREFOX_DIR/.mozconfig"
MOZCONFIG_BACKUP="$FIREFOX_DIR/.mozconfig.reynard-backup"

TARGET="${REYNARD_GECKO_TARGET:-aarch64-apple-ios}"
BUILD_JOBS="${REYNARD_BUILD_JOBS:-2}"
CARGO_JOBS="${REYNARD_CARGO_JOBS:-1}"

if [ ! -d /Volumes/Outside ] || [ ! -w /Volumes/Outside ]; then
	echo "Outside volume is not mounted and writable; refusing to use internal storage."
	exit 1
fi

export MOZBUILD_STATE_PATH="${MOZBUILD_STATE_PATH:-$CACHE_ROOT/mozbuild}"
mkdir -p "$MOZBUILD_STATE_PATH"

if [ ! -x "$CLANG_ROOT/bin/clang" ] || [ ! -x "$CLANG_ROOT/bin/clang++" ]; then
	echo "Missing Mozilla Clang toolchain at $CLANG_ROOT"
	echo "Install macosx64-aarch64-clang-21 in the external cache first."
	exit 1
fi

if [ ! -x "$NODE_ROOT/bin/node" ]; then
	echo "Missing Mozilla Node.js toolchain at $NODE_ROOT"
	exit 1
fi

# Xcode 15's iPhoneOS SDK ships libSystem XPC symbols but omits the private
# xpc headers used by Gecko's iOS process bootstrap. Keep the iPhoneOS SDK as
# the sysroot and use the matching macOS SDK headers only as a final fallback.
if [ ! -f "$MACOS_SDK_ROOT/usr/include/xpc/xpc.h" ]; then
	echo "Missing XPC compatibility headers in macOS SDK: $MACOS_SDK_ROOT"
	exit 1
fi

export CC="$CLANG_ROOT/bin/clang"
export CXX="$CLANG_ROOT/bin/clang++"
export HOST_CC="$CLANG_ROOT/bin/clang"
export HOST_CXX="$CLANG_ROOT/bin/clang++"
export NODEJS="$NODE_ROOT/bin/node"
export PATH="$NODE_ROOT/bin:$PATH"
export CARGO_BUILD_JOBS="$CARGO_JOBS"
export CFLAGS="${CFLAGS:-} -idirafter $MACOS_SDK_ROOT/usr/include"
export CXXFLAGS="${CXXFLAGS:-} -idirafter $MACOS_SDK_ROOT/usr/include"
# Firefox 153 unconditionally enables final-crate Rust LTO in release builds.
# On the 8 GB M1 build host that exhausts memory and swap; the C/C++ build is
# still optimized and release-configured, while only this redundant Rust LTO
# pass is disabled by our small source compatibility patch.
export REYNARD_DISABLE_RUST_LTO=1

cd "$ROOT_DIR"

if [ ! -d "$FIREFOX_DIR" ]; then
	echo "Missing firefox source at $FIREFOX_DIR"
	echo "Add the submodule, then run tools/development/update-gecko.sh."
	exit 1
fi

if [ -e "$MOZCONFIG_BACKUP" ]; then
	echo "Refusing to overwrite existing backup: $MOZCONFIG_BACKUP"
	exit 1
fi

if [ -f "$MOZCONFIG_PATH" ]; then
	mv "$MOZCONFIG_PATH" "$MOZCONFIG_BACKUP"
fi

cleanup() {
	rm -f "$MOZCONFIG_PATH"
	if [ -f "$MOZCONFIG_BACKUP" ]; then
		mv "$MOZCONFIG_BACKUP" "$MOZCONFIG_PATH"
	fi
}
trap cleanup EXIT

{
	echo "ac_add_options --enable-application=mobile/ios"
	echo "ac_add_options --target=$TARGET"
	echo "ac_add_options --enable-ios-target=13.0"
	echo "ac_add_options --enable-webrtc"
	echo "ac_add_options --enable-optimize"
	echo "ac_add_options --enable-release"
	echo "ac_add_options --enable-rust-simd"
	echo "ac_add_options --without-wasm-sandboxed-libraries"
	echo "ac_add_options --disable-debug"
	echo "ac_add_options --disable-tests"
	if [ "${1:-}" = "--disable-jemalloc" ]; then
		echo "ac_add_options --disable-jemalloc"
	fi
} > "$MOZCONFIG_PATH"

if ! rustup target list | grep -q "^$TARGET (installed)"; then
	rustup target add "$TARGET"
fi

cd "$FIREFOX_DIR"
./mach build --jobs "$BUILD_JOBS"
