#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/browser/ReynardGPT.xcodeproj"
SPEC_PATH="$ROOT_DIR/browser/project-reynardgpt.yml"
DIST_DIR="$ROOT_DIR/dist"
CACHE_ROOT="${REYNARD_CACHE_ROOT:-$ROOT_DIR/../.cache/reynard}"
ARCHIVE_PATH="$DIST_DIR/ReynardGPT.xcarchive"

case "$ROOT_DIR" in
	/Volumes/*/*) ;;
	*) echo "The Reynard repository is not on an external volume."; exit 1 ;;
esac
if [ ! -w "$ROOT_DIR" ]; then
	echo "The external Reynard repository is not writable."
	exit 1
fi

# Resolve the volume's canonical case. APFS is case-insensitive here, but
# Swift PCH files encode this path byte-for-byte and reject a later
# /Project-versus-/project spelling change.
mkdir -p "$CACHE_ROOT"
CACHE_ROOT="$(CDPATH= cd -- "$CACHE_ROOT" && pwd -P)"
DERIVED_DATA_DIR="$CACHE_ROOT/xcode-derived-data-reynardgpt"

for required in xcodegen xcodebuild ldid; do
	if ! command -v "$required" >/dev/null 2>&1; then
		echo "Missing required tool: $required"
		exit 1
	fi
done

if [ ! -f "$ROOT_DIR/engine/firefox/obj-aarch64-apple-ios/dist/bin/XUL" ]; then
	echo "Missing Gecko build output. Run tools/development/build-gecko.sh first."
	exit 1
fi

mkdir -p "$DIST_DIR" "$DERIVED_DATA_DIR"

xcodegen \
	--spec "$SPEC_PATH" \
	--project "$ROOT_DIR/browser" \
	--project-root "$ROOT_DIR/browser"

BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD)"

xcodebuild archive \
	-project "$PROJECT_PATH" \
	-scheme ReynardGPT \
	-configuration Release \
	-sdk iphoneos \
	-arch arm64 \
	-archivePath "$ARCHIVE_PATH" \
	-derivedDataPath "$DERIVED_DATA_DIR" \
	CURRENT_BUILD="$BUILD_NUMBER" \
	CURRENT_VERSION="0.1.26" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	AD_HOC_CODE_SIGNING_ALLOWED=YES

echo "Created archive: $ARCHIVE_PATH"
