#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
PROJECT="$ROOT_DIR/browser/ReynardGPT.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
CACHE_ROOT="${REYNARD_CACHE_ROOT:-$ROOT_DIR/../.cache/reynard}"

if [[ "$ROOT_DIR" != /Volumes/*/* ]]; then
	echo "The Reynard repository is not on an external volume."
	exit 1
fi

mkdir -p "$CACHE_ROOT"
CACHE_ROOT="$(CDPATH= cd -- "$CACHE_ROOT" && pwd -P)"
DERIVED_DATA="$CACHE_ROOT/xcode-project-audit"

source_files=("$ROOT_DIR"/browser/ReynardGPT/**/*.swift(N))
xcrun swiftc -frontend -parse $source_files
mkdir -p "$DERIVED_DATA"

plutil -lint \
	"$PBXPROJ" \
	"$ROOT_DIR/browser/ReynardGPT/Resources/Info.plist" \
	"$ROOT_DIR/browser/ReynardGPT/Entitlements/ReynardGPT.entitlements" \
	"$ROOT_DIR/browser/ReynardGPT/Entitlements/ReynardGPT.private.entitlements" \
	"$ROOT_DIR/browser/ReynardGPT/Entitlements/ReynardGPTHelper.private.entitlements" \
	>/dev/null

[[ "$(plutil -extract CFBundleDisplayName raw "$ROOT_DIR/browser/ReynardGPT/Resources/Info.plist")" == "GPT" ]]
[[ "$(plutil -extract CFBundleName raw "$ROOT_DIR/browser/ReynardGPT/Resources/Info.plist")" == "GPT" ]]

icon="$ROOT_DIR/browser/ReynardGPT/Resources/Assets.xcassets/AppIcon.appiconset/icon.png"
[[ "$(sips -g pixelWidth "$icon" | awk '/pixelWidth:/ { print $2 }')" == "1024" ]]
[[ "$(sips -g pixelHeight "$icon" | awk '/pixelHeight:/ { print $2 }')" == "1024" ]]
[[ "$(sips -g hasAlpha "$icon" | awk '/hasAlpha:/ { print $2 }')" == "no" ]]

project_list="$(xcodebuild \
	-project "$PROJECT" \
	-scheme ReynardGPT \
	-derivedDataPath "$DERIVED_DATA" \
	-list)"
for target in GeckoView "Reynard Helper" ReynardGPT; do
	if [[ "$project_list" != *"$target"* ]]; then
		echo "Missing target: $target"
		exit 1
	fi
done

for forbidden in \
	"OpenIn.appex" \
	"/* BrowserViewController.swift in Sources */" \
	"/* BookmarkStore.swift in Sources */" \
	"/* HomepageViewController.swift in Sources */" \
	"/* SidebarViewController.swift in Sources */" \
	"/* TabManagerImpl.swift in Sources */"; do
	if grep -Fq "$forbidden" "$PBXPROJ"; then
		echo "Forbidden generic-browser component is present: $forbidden"
		exit 1
	fi
done

grep -Fq "Reynard Helper.appex in Embed Foundation Extensions" "$PBXPROJ"
grep -Fq "GeckoView.framework in Embed Frameworks" "$PBXPROJ"

cleaner="$ROOT_DIR/browser/ReynardGPT/Core/GPTWebsiteDataCleaner.swift"
grep -Fq "scheduleProfileReset" "$cleaner"
grep -Fq "performPendingProfileReset" "$cleaner"
grep -Fq "removeItem(at: profileRoot)" "$cleaner"
if grep -Fq "GeckoStorageController.clearData" "$cleaner"; then
	echo "Live Gecko website-data clearing path is present"
	exit 1
fi

browser_controller="$ROOT_DIR/browser/ReynardGPT/App/GPTBrowserViewController.swift"
main_swift="$ROOT_DIR/browser/ReynardGPT/main.swift"
gecko_editable="$ROOT_DIR/engine/firefox/widget/uikit/GeckoEditableSupport.mm"
gecko_editable_patch="$ROOT_DIR/patches/widget/uikit/GeckoEditableSupport.mm.patch"
grep -Fq 'LanguageSetting(codes: ["zh-CN", "zh", "en"])' "$browser_controller"
grep -Fq "keyboardWillShowNotification" "$browser_controller"
if grep -Fq "keyboardWillChangeFrameNotification" "$browser_controller"; then
	echo "Keyboard frame changes can disturb CJK marked-text composition"
	exit 1
fi
grep -Fq "unshiftedFrame.maxY - keyboardFrame.minY" "$browser_controller"
grep -Fq "geckoTopConstraint?.constant = -focusedInputOffset" "$browser_controller"
grep -Fq "geckoBottomConstraint?.constant = -focusedInputOffset" "$browser_controller"
if grep -Fq "focusedInputBottomRatio" "$browser_controller"; then
	echo "Crash-prone focused-input metrics query is present"
	exit 1
fi
grep -Fq "PermissionDelegate.setPermission(permission, value: value)" "$browser_controller"
grep -Fq "GPTDownloadsViewController" "$browser_controller"
grep -Fq 'systemName: "arrow.down.circle"' "$browser_controller"
if grep -Fq "sharePage" "$browser_controller"; then
	echo "Obsolete current-page share button is present"
	exit 1
fi

file_picker="$ROOT_DIR/browser/ReynardGPT/App/GPTFilePicker.swift"
if grep -Fq "if capture != 0" "$file_picker"; then
	echo "File picker still bypasses the attachment source menu"
	exit 1
fi

grep -Fq "GPTSitePermissionStore.clear()" "$cleaner"
grep -Fq 'setenv("REYNARD_CJK_COMPOSITION_CARET_OVERLAY", "1", 1)' "$main_swift"
grep -Fq 'setenv("REYNARD_SUPPRESS_INLINE_KEYBOARD_REPLACEMENTS", "1", 1)' "$main_swift"
grep -Fq "InlineKeyboardReplacementsSuppressed()" "$gecko_editable"
grep -Fq "UITextInputCurrentInputModeDidChangeNotification" "$gecko_editable"
grep -Fq "fallbackCompositionCaretRect" "$gecko_editable"
grep -Fq "mHasLastCompositionCaretRect" "$gecko_editable"
grep -Fq "selectionIsInsideMarkedText" "$gecko_editable"
grep -Fq "Explicitly refresh both the" "$gecko_editable"
if grep -Fq "KeyboardCorrectionsDisabled()" "$gecko_editable"; then
	echo "Keyboard traits are still globally disabling corrections"
	exit 1
fi
if grep -Fq "UITextSpellCheckingTypeNo" "$gecko_editable"; then
	echo "English keyboard suggestions are still globally disabled"
	exit 1
fi
if grep -Fq "markedRange.location == NSNotFound || markedRange.length == 0" "$gecko_editable"; then
	echo "Native CJK caret overlay is still limited to marked text"
	exit 1
fi
grep -Fq "InlineKeyboardReplacementsSuppressed()" "$gecko_editable_patch"
grep -Fq "UITextInputCurrentInputModeDidChangeNotification" "$gecko_editable_patch"
grep -Fq "fallbackCompositionCaretRect" "$gecko_editable_patch"
grep -Fq "selectionIsInsideMarkedText" "$gecko_editable_patch"
grep -Fq "Explicitly refresh both the" "$gecko_editable_patch"
if grep -Fq "KeyboardCorrectionsDisabled()" "$gecko_editable_patch"; then
	echo "Keyboard traits patch still globally disables corrections"
	exit 1
fi
if grep -Fq "markedRange.location == NSNotFound || markedRange.length == 0" "$gecko_editable_patch"; then
	echo "Native CJK caret overlay patch is still limited to marked text"
	exit 1
fi

download_store="$ROOT_DIR/browser/ReynardGPT/Core/GPTDownloadStore.swift"
grep -Fq 'appendingPathComponent("Downloads", isDirectory: true)' "$download_store"
grep -Fq "Downloads.json" "$download_store"
grep -Fq "importFile(from: temporaryURL" "$download_store"

echo "ReynardGPT project audit passed"
