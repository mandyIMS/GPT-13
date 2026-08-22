#!/bin/zsh

set -euo pipefail

VERSION="153.0.4"
TOTAL_SIZE=803207992
EXPECTED_SHA512="9081beed7f08797c2128094169cf95af4a35e208fd22bba709bfb1a19e15d15aa484fccae71154d2ae0ff955bf629cd634cc7ed6b180371aea792daf7c689ff7"
URL="https://archive.mozilla.org/pub/firefox/releases/${VERSION}/source/firefox-${VERSION}.source.tar.xz"
CACHE_ROOT="${REYNARD_CACHE_ROOT:-/Volumes/Outside/project/.cache/reynard}"
DOWNLOAD_DIR="$CACHE_ROOT/downloads"
ARCHIVE="$DOWNLOAD_DIR/firefox-${VERSION}.source.tar.xz"
PART_DIR="$DOWNLOAD_DIR/firefox-${VERSION}.parts"
PARENT_PART_COUNT=8
PARENT_PART_SIZE=$(( (TOTAL_SIZE + PARENT_PART_COUNT - 1) / PARENT_PART_COUNT ))
PART_COUNT=16

if [[ ! -d /Volumes/Outside || ! -w /Volumes/Outside ]]; then
	echo "Outside volume is not mounted and writable."
	exit 1
fi

mkdir -p "$DOWNLOAD_DIR" "$PART_DIR"

if [[ -f "$ARCHIVE" ]] && \
   [[ "$(stat -f '%z' "$ARCHIVE")" -eq "$TOTAL_SIZE" ]] && \
   [[ "$(shasum -a 512 "$ARCHIVE" | awk '{print $1}')" == "$EXPECTED_SHA512" ]]; then
	echo "Firefox source archive is already complete and verified: $ARCHIVE"
	exit 0
fi

# A previous single-stream download always starts at byte zero, so it can seed
# the first range without discarding valid data.
if [[ -f "$ARCHIVE" && ! -f "$PART_DIR/part-0" ]]; then
	archive_size="$(stat -f '%z' "$ARCHIVE")"
	if (( archive_size > 0 && archive_size <= PARENT_PART_SIZE / 2 )); then
		/bin/mv "$ARCHIVE" "$PART_DIR/part-0"
	fi
fi

# Migrate an interrupted 8-range run. Each existing file contains the start of
# its old 100 MB parent range, which is exactly the even child range after the
# split. Descending order prevents destination-name collisions.
if [[ -f "$PART_DIR/part-7" && ! -e "$PART_DIR/part-14" ]]; then
	for legacy_index in {7..1}; do
		/bin/mv \
			"$PART_DIR/part-$legacy_index" \
			"$PART_DIR/part-$(( legacy_index * 2 ))"
	done
fi

download_part() {
	local index="$1"
	local parent_index=$(( index / 2 ))
	local parent_start=$(( parent_index * PARENT_PART_SIZE ))
	local parent_end=$(( parent_start + PARENT_PART_SIZE - 1 ))
	local parent_length
	local first_child_length
	local start
	local end
	local part="$PART_DIR/part-$index"
	local expected
	local current
	local range_start

	if (( parent_end >= TOTAL_SIZE )); then
		parent_end=$(( TOTAL_SIZE - 1 ))
	fi
	parent_length=$(( parent_end - parent_start + 1 ))
	first_child_length=$(( (parent_length + 1) / 2 ))
	if (( index % 2 == 0 )); then
		start=$parent_start
		end=$(( parent_start + first_child_length - 1 ))
	else
		start=$(( parent_start + first_child_length ))
		end=$parent_end
	fi
	expected=$(( end - start + 1 ))

	while true; do
		current=0
		if [[ -f "$part" ]]; then
			current="$(stat -f '%z' "$part")"
		fi

		if (( current == expected )); then
			break
	fi
		if (( current > expected )); then
			echo "Part $index is larger than expected; move it aside and retry." >&2
			return 1
		fi

		range_start=$(( start + current ))
		echo "Part $index: requesting bytes $range_start-$end"
		if ! curl \
			--http1.1 \
			--fail \
			--location \
			--silent \
			--show-error \
			--connect-timeout 30 \
			--range "$range_start-$end" \
			"$URL" >> "$part"; then
			echo "Part $index interrupted; resuming from its current size."
		fi
	done

	echo "Part $index complete ($expected bytes)"
}

pids=()
for index in {0..15}; do
	download_part "$index" &
	pids+=("$!")
done

failed=0
for pid in $pids; do
	if ! wait "$pid"; then
		failed=1
	fi
done
(( failed == 0 )) || exit 1

staging="$DOWNLOAD_DIR/firefox-${VERSION}.source.tar.xz.staging"
: > "$staging"
for index in {0..15}; do
	/bin/cat "$PART_DIR/part-$index" >> "$staging"
done

[[ "$(stat -f '%z' "$staging")" -eq "$TOTAL_SIZE" ]] || {
	echo "Combined archive has an unexpected size." >&2
	exit 1
}

actual_sha512="$(shasum -a 512 "$staging" | awk '{print $1}')"
[[ "$actual_sha512" == "$EXPECTED_SHA512" ]] || {
	echo "Firefox source SHA-512 mismatch." >&2
	echo "Expected: $EXPECTED_SHA512" >&2
	echo "Actual:   $actual_sha512" >&2
	exit 1
}

/bin/mv "$staging" "$ARCHIVE"
echo "Firefox source archive verified: $ARCHIVE"
