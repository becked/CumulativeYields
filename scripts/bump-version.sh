#!/bin/bash
# bump-version.sh - Bump the mod version in ModInfo.xml and scaffold CHANGELOG.md
#
# Usage:
#   ./scripts/bump-version.sh patch    # 0.1.0 -> 0.1.1
#   ./scripts/bump-version.sh minor    # 0.1.0 -> 0.2.0
#   ./scripts/bump-version.sh major    # 0.1.0 -> 1.0.0
#   ./scripts/bump-version.sh 1.2.3    # Set explicit version

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

MODINFO="ModInfo.xml"

if [ ! -f "$MODINFO" ]; then
    echo "Error: $MODINFO not found"
    exit 1
fi

# Extract current version
CURRENT=$(sed -n 's/.*<modversion>\([^<]*\)<\/modversion>.*/\1/p' "$MODINFO")
if [ -z "$CURRENT" ]; then
    echo "Error: Could not extract version from $MODINFO"
    exit 1
fi

echo "Current version: $CURRENT"

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

# Determine new version
case "${1:-}" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    "")
        echo "Usage: $0 <major|minor|patch|X.Y.Z>"
        echo ""
        echo "Examples:"
        echo "  $0 patch    # $CURRENT -> $MAJOR.$MINOR.$((PATCH + 1))"
        echo "  $0 minor    # $CURRENT -> $MAJOR.$((MINOR + 1)).0"
        echo "  $0 major    # $CURRENT -> $((MAJOR + 1)).0.0"
        echo "  $0 1.2.3    # Set explicit version"
        exit 1
        ;;
    *)
        if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IFS='.' read -r MAJOR MINOR PATCH <<< "$1"
        else
            echo "Error: Invalid version format '$1'. Expected X.Y.Z"
            exit 1
        fi
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "New version: $NEW_VERSION"

# Cross-platform sed -i (macOS requires '' argument, GNU does not)
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Update ModInfo.xml
sed_inplace "s|<modversion>$CURRENT</modversion>|<modversion>$NEW_VERSION</modversion>|" "$MODINFO"
echo "Updated $MODINFO: $CURRENT -> $NEW_VERSION"

# Scaffold CHANGELOG.md entry
if [ -f "CHANGELOG.md" ]; then
    TODAY=$(date +%Y-%m-%d)
    NEW_ENTRY="## [$NEW_VERSION] - $TODAY"

    TEMP_CHANGELOG=$(mktemp)
    awk -v entry="$NEW_ENTRY" '
        !inserted && /^## \[/ {
            print entry
            print ""
            print "- "
            print ""
            inserted = 1
        }
        { print }
    ' CHANGELOG.md > "$TEMP_CHANGELOG"
    mv "$TEMP_CHANGELOG" CHANGELOG.md

    echo "Scaffolded CHANGELOG.md entry: $NEW_ENTRY"
else
    echo ""
    echo "Note: CHANGELOG.md not found. Remember to document changes for $NEW_VERSION"
fi

# Sync modbuild from game installation (optional)
# Only runs when OLDWORLD_PATH is set and ModInfo.xml has a <modbuild> tag
if [ -f ".env" ]; then
    source ".env"
fi

OLD_BUILD=$(sed -n 's/.*<modbuild>\([^<]*\)<\/modbuild>.*/\1/p' "$MODINFO")
if [ -n "$OLDWORLD_PATH" ] && [ -n "$OLD_BUILD" ]; then
    GAME_BUILD=""
    PLIST="$OLDWORLD_PATH/OldWorld.app/Contents/Info.plist"
    if [ -f "$PLIST" ]; then
        GAME_BUILD=$(defaults read "$PLIST" CFBundleShortVersionString 2>/dev/null | awk '{print $1}')
    fi
    if [ -n "$GAME_BUILD" ]; then
        if [ "$OLD_BUILD" != "$GAME_BUILD" ]; then
            sed_inplace "s|<modbuild>$OLD_BUILD</modbuild>|<modbuild>$GAME_BUILD</modbuild>|" "$MODINFO"
            echo "Updated modbuild: $OLD_BUILD -> $GAME_BUILD"
        else
            echo "modbuild already current: $GAME_BUILD"
        fi
    else
        echo "Warning: Could not detect game build version"
    fi
fi

echo ""
echo "Done. Review changes before committing."
