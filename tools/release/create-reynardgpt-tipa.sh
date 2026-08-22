#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_PATH="$ROOT_DIR/dist/ReynardGPT.xcarchive"
ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/ReynardGPT.app"
WORK_DIR="$ROOT_DIR/dist/ReynardGPT-TrollStore"
PAYLOAD_APP="$WORK_DIR/Payload/ReynardGPT.app"
OUTPUT_PATH="$ROOT_DIR/dist/ReynardGPT-TrollStore.tipa"
CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"

case "$ROOT_DIR" in
	/Volumes/*/*) ;;
	*) echo "The Reynard repository is not on an external volume."; exit 1 ;;
esac
if [ ! -w "$ROOT_DIR" ]; then
	echo "The external Reynard repository is not writable."
	exit 1
fi

if [ ! -d "$ARCHIVE_APP" ]; then
	echo "Missing ReynardGPT archive app. Run tools/release/build-reynardgpt.sh first."
	exit 1
fi

if ! command -v ldid >/dev/null 2>&1; then
	echo "Missing ldid."
	exit 1
fi

rm -rf "$WORK_DIR" "$OUTPUT_PATH"
mkdir -p "$WORK_DIR/Payload"
cp -R "$ARCHIVE_APP" "$PAYLOAD_APP"

HELPER_APP="$PAYLOAD_APP/PlugIns/Reynard Helper.appex"
HELPER_BINARY="$HELPER_APP/Reynard Helper"

if [ ! -f "$PAYLOAD_APP/ReynardGPT" ] || [ ! -f "$HELPER_BINARY" ]; then
	echo "Archive is missing the app or Gecko Helper executable."
	exit 1
fi

plutil -replace CFBundleIdentifier -string com.jkleissjl.gpt13 "$PAYLOAD_APP/Info.plist"
plutil -replace CFBundleIdentifier -string com.jkleissjl.gpt13.helper "$HELPER_APP/Info.plist"

"$CLANG_PATH" \
	-arch arm64 \
	-isysroot "$SDK_PATH" \
	-miphoneos-version-min=13.0 \
	-Os \
	"$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.c" \
	-o "$PAYLOAD_APP/ts_ptrace_jit"
chmod 0755 "$PAYLOAD_APP/ts_ptrace_jit"

ldid -S"$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" \
	"$PAYLOAD_APP/ts_ptrace_jit"
ldid -S"$ROOT_DIR/browser/ReynardGPT/Entitlements/ReynardGPTHelper.private.entitlements" \
	"$HELPER_BINARY"
ldid -S"$ROOT_DIR/browser/ReynardGPT/Entitlements/ReynardGPT.private.entitlements" \
	"$PAYLOAD_APP/ReynardGPT"

if find "$PAYLOAD_APP" -iname '*OpenIn*' -print -quit | grep -q .; then
	echo "OpenIn was unexpectedly embedded in ReynardGPT."
	exit 1
fi

(
	cd "$WORK_DIR"
	zip -qry "$OUTPUT_PATH" Payload -x '._*' -x '.DS_Store' -x '__MACOSX/*'
)

echo "Created TrollStore package: $OUTPUT_PATH"
