#!/bin/sh

set -eu

GECKO_DIST_BIN="${GECKO_DIST}/bin"
APP_BUNDLE="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
FRAMEWORKS_DIR="${APP_BUNDLE}/Frameworks"
GECKOVIEW_FW="${FRAMEWORKS_DIR}/GeckoView.framework"
GECKOVIEW_FW_FRAMEWORKS="${GECKOVIEW_FW}/Frameworks"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY_NAME:--}}"
DEFAULT_THEME_SRC="${SRCROOT}/../engine/firefox/toolkit/mozapps/extensions/default-theme"

mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}"

# copy dylibs and XUL, then sign
cp -fL "${GECKO_DIST_BIN}/"*.dylib "${FRAMEWORKS_DIR}/"
cp -fL "${GECKO_DIST_BIN}/XUL" "${FRAMEWORKS_DIR}/XUL"

for file in "${FRAMEWORKS_DIR}/XUL" "${FRAMEWORKS_DIR}/"*.dylib; do
	if [ -f "${file}" ]; then
		codesign --force --sign "${SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements "${file}"
	fi
done

# Copy runtime data, excluding link inputs, tests, and host/build utilities that
# GeckoView never executes on iOS. Keeping these tools would add attack surface
# and make the ChatGPT wrapper look like a general development browser bundle.
rsync -prtlL --delete \
	--exclude "XUL" \
	--exclude "*.dylib" \
	--exclude "Test*" \
	--exclude "test_*" \
	--exclude "*_unittest" \
	--exclude "certutil" \
	--exclude "pk12util" \
	--exclude "xpcshell" \
	--exclude "nsinstall" \
	--exclude "gmp-fake/" \
	--exclude "gmp-fakeopenh264/" \
	--exclude "dependentlibs.list.gtest" \
	--exclude ".lldbinit" \
	--exclude ".purgecaches" \
	"${GECKO_DIST_BIN}/" "${GECKOVIEW_FW_FRAMEWORKS}"

# Gecko's dist directory also contains two runtime executables. Xcode only
# signs the framework binary itself, so sign these explicitly before sealing
# the framework bundle. Unsigned nested Mach-O files can be rejected by iOS
# before Gecko ever gets a chance to launch them.
for file in \
	"${GECKOVIEW_FW_FRAMEWORKS}/pingsender" \
	"${GECKOVIEW_FW_FRAMEWORKS}/plugin-container"; do
	if [ -f "${file}" ]; then
		codesign --force --sign "${SIGN_IDENTITY}" "${file}"
	fi
done

# default theme missing error fix
mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}/default-theme"
cp -RfL "${DEFAULT_THEME_SRC}/" "${GECKOVIEW_FW_FRAMEWORKS}/default-theme/"
echo "resource default-theme file:default-theme/" >> "${GECKOVIEW_FW_FRAMEWORKS}/chrome.manifest"

# sign the GeckoView.framework
codesign --force --sign "${SIGN_IDENTITY}" "${GECKOVIEW_FW}"
