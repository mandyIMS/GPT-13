#!/bin/sh
#
# create-site-variants.sh — one .tipa per site from the finished
# Muse build (7 variants, per the user's own list).
#
# The engine (Gecko) is compiled once; making a per-site variant only
# relabels the finished app, so it takes minutes, not hours. Each variant
# gets its own bundle ID, display name, app icon, URL scheme and baked-in
# default site (Info.plist GPTDefaultSiteURL, read by GPTSiteStore), and is
# re-signed with ldid using the same private entitlements, so JIT keeps
# working exactly like the main package.
#
# The main package (Muse Web 測試版, com.mandyims.muse13v2) is the base
# the variants are cloned from; it stays as its own app.
#
# Called by tools/release/create-reynardgpt-tipa.sh after the main .tipa is
# created. Best effort by design: a variant failure warns and skips that
# variant; it never fails the build or the main package.
#
# Variant icons live in tools/variant-icons/<slug>/, either as a decoded
# icon.png (1024x1024) or as base64 parts icon.b64.partNN (decoded here,
# mirroring the Muse icon in tools/icon-parts/). A variant without an icon
# is skipped with a warning.
#
# Usage: sh tools/release/create-site-variants.sh
# Output: dist/ReynardGPT-<Slug>-TrollStore.tipa per variant.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
MAIN_TIPA="$ROOT_DIR/dist/ReynardGPT-TrollStore.tipa"
ICONS_DIR="$ROOT_DIR/tools/variant-icons"
ENTITLEMENTS_DIR="$ROOT_DIR/browser/ReynardGPT/Entitlements"
JIT_ENTITLEMENTS="$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements"

warn() {
    echo "VARIANTS WARNING: $*" >&2
}

# slug|Display Name|Bundle ID|URL scheme|Default site URL|Output name
# (Bundle IDs and names are the user's own list; she confirmed 2026-11-21
# that "Cloude"/"cloude" and "grmini" were typos, corrected here to
# Claude/com.mandyims.claude and com.mandyims.gemini.)

if [ ! -f "$MAIN_TIPA" ]; then
    warn "main package missing: $MAIN_TIPA"
    exit 0
fi
for required in plutil ldid unzip zip; do
    if ! command -v "$required" >/dev/null 2>&1; then
        warn "missing required tool: $required"
        exit 0
    fi
done

# Resolve a variant's 1024x1024 icon, decoding base64 parts when present.
# Prints the icon path on success; returns non-zero otherwise.
resolve_icon() {
    slug="$1"
    dir="$ICONS_DIR/$slug"
    if [ -f "$dir/icon.b64.part00" ]; then
        icon="$dir/icon.png"
        cat "$dir"/icon.b64.part* | base64 -d > "$icon" 2>/dev/null
        if [ ! -s "$icon" ]; then
            return 1
        fi
        printf '%s' "$icon"
        return 0
    fi
    if [ -f "$dir/icon.png" ]; then
        printf '%s' "$dir/icon.png"
        return 0
    fi
    return 1
}

# Rebuild the app icon catalog for one icon. The home-screen icon is baked
# into Assets.car at build time, so a loose PNG swap is not enough.
# Prints the actool output directory on success.
rebuild_icon_catalog() {
    icon="$1"
    work="$2"
    xcassets="$work/AppIcon.xcassets"
    appiconset="$xcassets/AppIcon.appiconset"
    mkdir -p "$appiconset"
    cp "$icon" "$appiconset/icon.png"
    cat > "$appiconset/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
    out="$work/actool-out"
    mkdir -p "$out"
    # Mirror the flags xcodebuild passes when it compiles the main app's
    # catalog (see a build log): actool needs the target devices to know
    # which icon slots to build. Keep actool's output so a failure is
    # visible in the log instead of a bare skip.
    if ! xcrun actool --compile "$out" --platform iphoneos \
            --minimum-deployment-target 13.0 \
            --target-device iphone --target-device ipad \
            --output-format human-readable-text \
            --output-partial-info-plist "$work/actool-info.plist" \
            --app-icon AppIcon --include-all-app-icons --compress-pngs \
            "$xcassets" > "$work/actool.log" 2>&1; then
        warn "$display: icon catalog rebuild failed"
        cat "$work/actool.log" >&2
        return 1
    fi
    if [ ! -f "$out/Assets.car" ]; then
        warn "$display: icon catalog rebuild produced no Assets.car"
        cat "$work/actool.log" >&2
        return 1
    fi
    printf '%s' "$out"
    return 0
}

# Copy entitlements, rewriting application-identifier for the variant.
# Prints the temp entitlements path on success.
variant_entitlements() {
    source="$1"
    bundle_id="$2"
    tmp="$3"
    cp "$source" "$tmp"
    if ! plutil -replace application-identifier -string "$bundle_id" "$tmp" >/dev/null 2>&1; then
        return 1
    fi
    printf '%s' "$tmp"
    return 0
}

made=0
skipped=0
while IFS='|' read -r slug display bundle_id scheme site_url out; do
    [ -z "$slug" ] && continue
    helper_id="$bundle_id.helper"
    output="$ROOT_DIR/dist/ReynardGPT-$out-TrollStore.tipa"

    icon="$(resolve_icon "$slug")" || {
        warn "$display: no icon in $ICONS_DIR/$slug, skipping"
        skipped=$((skipped + 1))
        continue
    }

    work="$(mktemp -d "${TMPDIR:-/tmp}/variant-$slug.XXXXXX")" || {
        warn "$display: cannot create temp dir, skipping"
        skipped=$((skipped + 1))
        continue
    }

    # Unpack the finished main package and relabel the copy.
    if ! unzip -q "$MAIN_TIPA" -d "$work/unpacked" 2>/dev/null; then
        warn "$display: cannot unpack main package, skipping"
        rm -rf "$work"
        skipped=$((skipped + 1))
        continue
    fi
    app="$work/unpacked/Payload/ReynardGPT.app"
    info="$app/Info.plist"
    helper_app="$app/PlugIns/Reynard Helper.appex"
    helper_info="$helper_app/Info.plist"

    catalog="$(rebuild_icon_catalog "$icon" "$work")" || {
        warn "$display: icon catalog rebuild failed, skipping"
        rm -rf "$work"
        skipped=$((skipped + 1))
        continue
    }
    cp "$catalog/Assets.car" "$app/Assets.car"
    for loose in "$catalog"/AppIcon*.png; do
        [ -f "$loose" ] && cp "$loose" "$app/"
    done

    # Identity: bundle ID, display name, URL scheme, default site.
    plutil -replace CFBundleIdentifier -string "$bundle_id" "$info" >/dev/null 2>&1
    plutil -replace CFBundleDisplayName -string "$display" "$info" >/dev/null 2>&1
    plutil -replace CFBundleName -string "$display" "$info" >/dev/null 2>&1
    plutil -replace CFBundleURLTypes.0.CFBundleURLName -string "$bundle_id" "$info" >/dev/null 2>&1
    plutil -replace CFBundleURLTypes.0.CFBundleURLSchemes.0 -string "$scheme" "$info" >/dev/null 2>&1
    plutil -insert GPTDefaultSiteURL -string "$site_url" "$info" >/dev/null 2>&1 \
        || plutil -replace GPTDefaultSiteURL -string "$site_url" "$info" >/dev/null 2>&1
    plutil -replace CFBundleIdentifier -string "$helper_id" "$helper_info" >/dev/null 2>&1

    # Re-sign the relabelled executables with the same private
    # entitlements, rewritten for the variant bundle ID. The helper's
    # bundle ID must be prefixed by the app's (iOS extension rule).
    main_ent="$(variant_entitlements "$ENTITLEMENTS_DIR/ReynardGPT.private.entitlements" "$bundle_id" "$work/main.entitlements")" || {
        warn "$display: cannot prepare main entitlements, skipping"
        rm -rf "$work"
        skipped=$((skipped + 1))
        continue
    }
    helper_ent="$(variant_entitlements "$ENTITLEMENTS_DIR/ReynardGPTHelper.private.entitlements" "$helper_id" "$work/helper.entitlements")" || {
        warn "$display: cannot prepare helper entitlements, skipping"
        rm -rf "$work"
        skipped=$((skipped + 1))
        continue
    }
    ldid -S"$main_ent" "$app/ReynardGPT" 2>/dev/null
    ldid -S"$helper_ent" "$helper_app/Reynard Helper" 2>/dev/null
    ldid -S"$JIT_ENTITLEMENTS" "$app/ts_ptrace_jit" 2>/dev/null

    # Minimal per-variant checks: the JIT entitlement survived, the
    # identity and URL scheme took, and the default site is baked in.
    main_entitlements="$work/check.plist"
    if ! ldid -e "$app/ReynardGPT" > "$main_entitlements" 2>/dev/null \
        || ! plutil -extract 'com\.apple\.private\.security\.no-sandbox' raw "$main_entitlements" 2>/dev/null | grep -q true \
        || [ "$(plutil -extract CFBundleIdentifier raw "$info" 2>/dev/null)" != "$bundle_id" ] \
        || [ "$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$info" 2>/dev/null)" != "$scheme" ] \
        || [ "$(plutil -extract GPTDefaultSiteURL raw "$info" 2>/dev/null)" != "$site_url" ]; then
        warn "$display: verification failed, skipping"
        rm -rf "$work"
        skipped=$((skipped + 1))
        continue
    fi

    rm -f "$output"
    if ! (cd "$work/unpacked" && zip -qry "$output" Payload -x '._*' -x '.DS_Store' -x '__MACOSX/*'); then
        warn "$display: packaging failed, skipping"
        rm -rf "$work"
        skipped=$((skipped + 1))
        continue
    fi
    rm -rf "$work"
    made=$((made + 1))
    echo "Created site variant: $output"
done <<'VARIANTS'
muse1|Muse Web|com.mandyims.muse1|museweb|https://muse.ai/|Muse1
muse2|Mandy Muse|com.mandyims.muse2|mandymuse|https://muse.ai/|Muse2
chatgpt|ChatGPT Web|com.mandyims.chatgpt|chatgptweb|https://chatgpt.com/|ChatGPT
claude|Claude Web|com.mandyims.claude|claudeweb|https://claude.ai/|Claude
grok|Grok Web|com.mandyims.grok|grokweb|https://grok.com/|Grok
gemini|Gemini Web|com.mandyims.gemini|geminiweb|https://gemini.google.com/|Gemini
github|GitHub Web|com.mandyims.github|githubweb|https://github.com/|GitHub
VARIANTS

echo "Site variants done: $made created, $skipped skipped."
