#!/bin/sh
#
# Fetch the pinned Mozilla Clang 21 / Node 22 toolchains from FirefoxCI
# (Taskcluster) and place them in the layout
# tools/development/build-gecko.sh expects. This replaces `mach bootstrap`
# for CI: bootstrap has no iOS application choice and is unlikely to work
# on a release-tag checkout, while a direct download reproduces exactly
# what `mach artifact toolchain` does (download + unpack).
#
# Resolves the `.latest` index entry on every run (task IDs expire; never
# hardcode them), downloads the artifacts, verifies the archive layout,
# extracts, and checks that the resulting binaries run.
#
# Environment:
#   REYNARD_CACHE_ROOT       cache root (default: $ROOT_DIR/../.cache/reynard)
#   REYNARD_TASKCLUSTER_ROOT Taskcluster root URL (default: FirefoxCI)
#
# Required tools: curl, python3 (JSON parsing), tar, and either a
# zstd-capable tar or unzstd (brew install zstd).

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
CACHE_ROOT="${REYNARD_CACHE_ROOT:-$ROOT_DIR/../.cache/reynard}"
TC_ROOT="${REYNARD_TASKCLUSTER_ROOT:-https://firefox-ci-tc.services.mozilla.com}"
DOWNLOAD_DIR="$CACHE_ROOT/toolchains/.downloads"

CLANG_INDEX="gecko.cache.level-3.toolchains.v3.macosx64-aarch64-clang-21.latest"
NODE_INDEX="gecko.cache.level-3.toolchains.v3.macosx64-aarch64-node-22.latest"
CLANG_ARTIFACT="public/build/clang.tar.zst"
NODE_ARTIFACT="public/build/node.tar.zst"

for required in curl python3 tar; do
	if ! command -v "$required" >/dev/null 2>&1; then
		echo "Missing required tool: $required"
		exit 1
	fi
done

mkdir -p "$DOWNLOAD_DIR"

resolve_task_id() {
	# $1 = index path. Prints the taskId from the Index findTask response.
	curl -fsSL --retry 3 "$TC_ROOT/api/index/v1/task/$1" \
		| python3 -c "import json,sys; print(json.load(sys.stdin)['taskId'])"
}

download_artifact() {
	# $1 = taskId, $2 = artifact name, $3 = output path.
	echo "Downloading $2 from task $1 ..."
	curl -fL --retry 3 -o "$3" "$TC_ROOT/api/queue/v1/task/$1/runs/0/artifacts/$2"
	ls -lh "$3"
}

list_archive() {
	# $1 = archive. Lists entries, trying native tar first, then unzstd.
	# Diagnostic only: never fails the script.
	if tar -tf "$1" 2>/dev/null; then
		return 0
	fi
	if command -v unzstd >/dev/null 2>&1; then
		unzstd -c "$1" | tar -tf - || true
		return 0
	fi
	echo "(could not list archive: no zstd-capable tar or unzstd)"
	return 0
}

extract_archive() {
	# $1 = archive, $2 = destination parent dir.
	if tar -xf "$1" -C "$2" 2>/dev/null; then
		return 0
	fi
	echo "Native tar could not extract $1; trying unzstd ..."
	if command -v unzstd >/dev/null 2>&1 && unzstd -c "$1" | tar -xf - -C "$2"; then
		return 0
	fi
	echo "Cannot extract $1: tar has no zstd support and unzstd is missing."
	echo "Install zstd (brew install zstd) and retry."
	exit 1
}

fetch_toolchain() {
	# $1 = index path, $2 = artifact, $3 = toolchain dir name,
	# $4 = expected top-level dir, $5 = binary to verify (relative to top dir).
	index="$1"
	artifact="$2"
	name="$3"
	top="$4"
	check_bin="$5"
	tool_dir="$CACHE_ROOT/toolchains/$name"
	archive="$DOWNLOAD_DIR/$(basename "$artifact")"
	target_dir="$tool_dir/$top"

	if [ -x "$target_dir/$check_bin" ]; then
		echo "Toolchain already present: $target_dir/$check_bin (skipping download)"
		return 0
	fi

	task_id="$(resolve_task_id "$index")"
	echo "Resolved $index -> task $task_id"
	download_artifact "$task_id" "$artifact" "$archive"
	echo "Archive contents (first 10 entries):"
	list_archive "$archive" | head -10 || true
	mkdir -p "$tool_dir"
	extract_archive "$archive" "$tool_dir"

	# Adapt if the archive's single top-level directory has another name.
	if [ ! -d "$target_dir" ]; then
		entries="$(ls -A "$tool_dir")"
		set -- $entries
		if [ "$#" -eq 1 ] && [ -d "$tool_dir/$1" ]; then
			echo "Archive top directory is '$1'; renaming to '$top'."
			mv "$tool_dir/$1" "$target_dir"
		else
			echo "Unexpected archive layout in $tool_dir:"
			ls -la "$tool_dir"
			exit 1
		fi
	fi

	if [ ! -x "$target_dir/$check_bin" ]; then
		echo "Expected binary missing after extraction: $target_dir/$check_bin"
		ls -la "$target_dir/bin" 2>/dev/null || ls -la "$target_dir"
		exit 1
	fi
	echo "Fetched $name into $target_dir"
}

ensure_unversioned_clang() {
	# build-gecko.sh tests the unversioned names. If the archive ships only
	# versioned binaries (e.g. clang-21), link the unversioned names to them.
	bin_dir="$CACHE_ROOT/toolchains/macosx64-aarch64-clang-21/clang/bin"
	if [ ! -x "$bin_dir/clang" ] && [ -x "$bin_dir/clang-21" ]; then
		echo "Linking clang -> clang-21"
		ln -s clang-21 "$bin_dir/clang"
	fi
	if [ ! -x "$bin_dir/clang++" ] && [ -x "$bin_dir/clang++-21" ]; then
		echo "Linking clang++ -> clang++-21"
		ln -s clang++-21 "$bin_dir/clang++"
	fi
}

verify_toolchains() {
	clang_root="$CACHE_ROOT/toolchains/macosx64-aarch64-clang-21/clang"
	node_root="$CACHE_ROOT/toolchains/macosx64-aarch64-node-22/node"
	for bin in "$clang_root/bin/clang" "$clang_root/bin/clang++" "$node_root/bin/node"; do
		if [ ! -x "$bin" ]; then
			echo "Missing executable: $bin"
			exit 1
		fi
	done
	"$clang_root/bin/clang" --version
	"$node_root/bin/node" --version
	work="$(mktemp -d)"
	printf 'int main(void){return 0;}\n' > "$work/hello.c"
	# Mozilla clang does not know the SDK location on its own; without
	# -isysroot the linker cannot find libSystem. Point it at the macOS
	# SDK, the same way the real build does. If no SDK is found, fall
	# back to a compile-only check instead of failing the fetch.
	if sdk_root="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)" && [ -n "$sdk_root" ]; then
		"$clang_root/bin/clang" -isysroot "$sdk_root" -o "$work/hello" "$work/hello.c"
		"$work/hello"
	else
		echo "No macOS SDK found; running compile-only check."
		"$clang_root/bin/clang" -c -o "$work/hello.o" "$work/hello.c"
	fi
	rm -rf "$work"
	echo "Hello-world check with Mozilla clang: OK"
}

fetch_toolchain "$CLANG_INDEX" "$CLANG_ARTIFACT" "macosx64-aarch64-clang-21" "clang" "bin/clang"
fetch_toolchain "$NODE_INDEX" "$NODE_ARTIFACT" "macosx64-aarch64-node-22" "node" "bin/node"
ensure_unversioned_clang
verify_toolchains

echo "Toolchains ready."
du -sh "$CACHE_ROOT/toolchains" 2>/dev/null || true
df -h 2>/dev/null || true
