#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
CACHE_ROOT="${REYNARD_CACHE_ROOT:-$ROOT_DIR/../.cache/reynard}"

if [[ "$ROOT_DIR" != /Volumes/*/* ]]; then
	echo "The Reynard repository is not on an external volume."
	exit 1
fi

mkdir -p "$CACHE_ROOT"
CACHE_ROOT="$(CDPATH= cd -- "$CACHE_ROOT" && pwd -P)"
TEST_DIR="${CACHE_ROOT}/tests/navigation-policy"
mkdir -p "$TEST_DIR"

xcrun swiftc \
	"$ROOT_DIR/browser/ReynardGPT/Core/GPTNavigationPolicy.swift" \
	"$ROOT_DIR/browser/ReynardGPT/Core/GPTUserAgentPolicy.swift" \
	"$ROOT_DIR/tests/ReynardGPTNavigationPolicyTests.swift" \
	-o "$TEST_DIR/ReynardGPTNavigationPolicyTests"

"$TEST_DIR/ReynardGPTNavigationPolicyTests"
