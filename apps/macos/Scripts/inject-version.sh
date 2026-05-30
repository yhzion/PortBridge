#!/bin/sh
# Inject version metadata into the built Info.plist.
#
# Tagged build:  CFBundleShortVersionString = latest tag (v0.1.0 -> 0.1.0)
#                CFBundleVersion           = total commit count
# Untagged dev:  CFBundleShortVersionString = 0.0.0
#                CFBundleVersion           = dev-<short-sha>  (or dev-local if no git)
#
# Runs as the last build phase of the PortBridge target so it overwrites the
# Info.plist that ProcessInfoPlistFile placed inside the .app bundle.

set -eu

PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

if [ ! -f "$PLIST" ]; then
    echo "warning: inject-version: Info.plist not found at $PLIST — skipping"
    exit 0
fi

cd "$SRCROOT"

if tag=$(git describe --tags --abbrev=0 2>/dev/null) \
   && count=$(git rev-list --count HEAD 2>/dev/null); then
    short_version="${tag#v}"
    build_number="$count"
else
    short_version="0.0.0"
    if sha=$(git rev-parse --short HEAD 2>/dev/null); then
        build_number="dev-$sha"
    else
        build_number="dev-local"
    fi
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $short_version" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$PLIST"

echo "inject-version: $short_version ($build_number) -> $PLIST"
