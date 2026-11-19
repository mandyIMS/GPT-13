#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
SUBMODULE_PATH="engine/firefox"
PATCH_DIR="${ROOT_DIR}/patches"

cd "$ROOT_DIR"

if [[ ! -f "engine/release.txt" ]]; then
	echo "Cannot get Firefox release tag: Missing engine/release.txt."
	exit 1
fi

RELEASE_TAG="$(tr -d '\000\r' < "engine/release.txt" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

if [[ -z "$RELEASE_TAG" ]]; then
	echo "Cannot get Firefox release tag: engine/release.txt is empty."
	exit 1
fi

if ! git submodule status -- "$SUBMODULE_PATH" >/dev/null 2>&1; then
	echo "Missing submodule $SUBMODULE_PATH. Add it first, then run tools/development/update-gecko.sh."
	exit 1
fi

if ! git -C "$SUBMODULE_PATH" rev-parse -q --verify "$RELEASE_TAG^{commit}" >/dev/null 2>&1; then
	echo "Tag $RELEASE_TAG does not exist in $SUBMODULE_PATH."
	echo "Run tools/development/update-gecko.sh to fetch and checkout the release tag."
	exit 1
fi

RELEASE_COMMIT="$(git -C "$SUBMODULE_PATH" rev-parse "$RELEASE_TAG^{commit}")"
HEAD_COMMIT="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"

if [[ "$HEAD_COMMIT" != "$RELEASE_COMMIT" ]]; then
	CURRENT_TAG="$(git -C "$SUBMODULE_PATH" describe --tags --exact-match HEAD 2>/dev/null || echo "no-exact-tag")"
	echo "Submodule HEAD ($HEAD_COMMIT, tag: $CURRENT_TAG) does not match engine/release.txt ($RELEASE_TAG -> $RELEASE_COMMIT)."
	echo "Run tools/development/update-gecko.sh to sync the submodule commit before applying patches."
	exit 1
fi

if [[ ! -d "$PATCH_DIR" ]]; then
	echo "Missing patches directory: $PATCH_DIR."
	exit 1
fi

# Overlay the backported input-rewrite patches over patches/. The adapted
# patches ship as base64 parts (one patch exceeds the file-write size
# limit) and are reassembled here, before the patch list is built.
BACKPORT_PARTS_DIR="${ROOT_DIR}/tools/backport-parts"
BACKPORT_ARCHIVE="${TMPDIR:-/tmp}/backport-patches.tar.gz"
cat "$BACKPORT_PARTS_DIR"/backport.b64.part* | base64 -d > "$BACKPORT_ARCHIVE"
if [[ ! -s "$BACKPORT_ARCHIVE" ]]; then
	echo "Backport archive decode failed: archive is empty."
	exit 1
fi
tar -xzf "$BACKPORT_ARCHIVE" -C "$ROOT_DIR"
rm -f "$BACKPORT_ARCHIVE"
# The rewrite removes Picture-in-Picture support; its old patches must not
# be applied. (ContentCache/PuppetWidget were restored: the August
# APZCCallbackHelper patch calls PuppetWidget::AdjustIMECacheForScroll,
# which lives in those patches.)
rm -f \
	"$PATCH_DIR/widget/uikit/PictureInPictureSupport.h.patch" \
	"$PATCH_DIR/widget/uikit/PictureInPictureSupport.mm.patch"

if [[ -n "$(git -C "$SUBMODULE_PATH" status --porcelain)" ]]; then
	echo "$SUBMODULE_PATH has uncommitted changes. Commit, stash, or reset before applying patches."
	exit 1
fi

setopt null_glob
patch_files=("$PATCH_DIR"/**/*.patch)

if (( ${#patch_files[@]} == 0 )); then
	echo "No patch files found in $PATCH_DIR."
	exit 0
fi

echo "Applying patches to $SUBMODULE_PATH..."
for patch_file in $patch_files; do
	rel_path="${patch_file#$PATCH_DIR/}"
	echo "Applying $rel_path..."

	if ! git -C "$SUBMODULE_PATH" apply --3way --whitespace=nowarn "$patch_file"; then
		echo "Failed to apply $rel_path."
		if [[ "${CI:-}" == "true" ]] || [[ ! -t 0 ]]; then
			echo "Non-interactive run: stopping. Resolve conflicts in $SUBMODULE_PATH manually."
			exit 1
		fi
		echo "Resolve conflicts in $SUBMODULE_PATH, then press Enter to continue or type q to stop."
		read -r response
		if [[ "$response" == "q" || "$response" == "Q" ]]; then
			exit 1
		fi
	fi
done

echo "Finished applying patches."
