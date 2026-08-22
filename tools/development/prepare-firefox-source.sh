#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
VERSION="153.0.4"
RELEASE_TAG="FIREFOX_153_0_4_RELEASE"
EXPECTED_COMMIT="c178247e1dfea52241a6b18b18cf3a00f8da935c"
CACHE_ROOT="${REYNARD_CACHE_ROOT:-/Volumes/Outside/project/.cache/reynard}"
ARCHIVE="$CACHE_ROOT/downloads/firefox-${VERSION}.source.tar.xz"
STAGING_ROOT="$CACHE_ROOT/firefox-source-staging"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"

if [[ ! -d /Volumes/Outside || ! -w /Volumes/Outside ]]; then
	echo "Outside volume is not mounted and writable."
	exit 1
fi

if [[ ! -f "$ARCHIVE" ]]; then
	echo "Missing verified source archive: $ARCHIVE"
	echo "Run tools/development/download-firefox-source.sh first."
	exit 1
fi

if [[ -e "$FIREFOX_DIR" ]]; then
	echo "Firefox source path already exists: $FIREFOX_DIR"
	exit 1
fi

if [[ -e "$STAGING_ROOT" ]]; then
	retired="$CACHE_ROOT/firefox-source-staging.previous.$(date +%Y%m%d%H%M%S)"
	/bin/mv "$STAGING_ROOT" "$retired"
	echo "Moved previous staging directory to $retired"
fi

mkdir -p "$STAGING_ROOT" "$ROOT_DIR/engine"
tar -xJf "$ARCHIVE" -C "$STAGING_ROOT"

extracted=("$STAGING_ROOT"/*(N/))
if (( ${#extracted} != 1 )); then
	echo "Expected one top-level source directory in the archive." >&2
	exit 1
fi

/bin/mv "${extracted[1]}" "$FIREFOX_DIR"

git -C "$FIREFOX_DIR" init
git -C "$FIREFOX_DIR" remote add origin https://github.com/mozilla-firefox/firefox

# Hash the official release files locally first. The filtered fetch then needs
# only the authoritative commit/tree metadata and any exceptional missing blob,
# rather than another full source transfer.
git -C "$FIREFOX_DIR" add -f .
git -C "$FIREFOX_DIR" \
	-c protocol.version=2 \
	fetch --filter=blob:none --depth 1 origin \
	"refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"
git -C "$FIREFOX_DIR" checkout --force --detach "$RELEASE_TAG^{}"

actual_commit="$(git -C "$FIREFOX_DIR" rev-parse HEAD)"
if [[ "$actual_commit" != "$EXPECTED_COMMIT" ]]; then
	echo "Unexpected Firefox commit." >&2
	echo "Expected: $EXPECTED_COMMIT" >&2
	echo "Actual:   $actual_commit" >&2
	exit 1
fi

if [[ -n "$(git -C "$FIREFOX_DIR" status --porcelain)" ]]; then
	echo "Prepared Firefox worktree is not clean." >&2
	git -C "$FIREFOX_DIR" status --short >&2
	exit 1
fi

git -C "$ROOT_DIR" submodule absorbgitdirs engine/firefox

echo "Prepared $RELEASE_TAG at $EXPECTED_COMMIT"
git -C "$ROOT_DIR" submodule status -- engine/firefox
