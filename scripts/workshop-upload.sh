#!/bin/bash
# workshop-upload.sh - Upload mod to Steam Workshop via SteamCMD
#
# Prerequisites:
#   1. Install SteamCMD: brew install steamcmd
#   2. Have Steam Guard ready (you'll need to authenticate)
#   3. .env file with STEAM_USERNAME and optionally STEAM_WORKSHOP_ID
#   4. workshop.vdf template in project root
#
# Usage: ./scripts/workshop-upload.sh [--dry-run] [changelog]
# Examples:
#   ./scripts/workshop-upload.sh                    # Upload with changelog from CHANGELOG.md
#   ./scripts/workshop-upload.sh "Fixed bug X"      # Upload with custom changelog message
#   ./scripts/workshop-upload.sh --dry-run           # Preview without uploading
#
# Version is always read from ModInfo.xml.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Load .env
if [ -f ".env" ]; then
    source ".env"
else
    echo "Error: .env file not found"
    exit 1
fi

# Parse flags
DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    shift
fi

# Validate mod content
"$SCRIPT_DIR/validate.sh" || exit 1

# Build C# mod if project file exists
CSPROJ=$(ls "$PROJECT_DIR"/*.csproj 2>/dev/null | head -1)
if [ -n "$CSPROJ" ]; then
    if [ -z "$OLDWORLD_PATH" ]; then
        echo "Error: OLDWORLD_PATH not set in .env (required for C# build)"
        exit 1
    fi
    echo ""
    echo "=== Building C# mod ==="
    dotnet build "$CSPROJ" -c Release -p:OldWorldPath="$OLDWORLD_PATH"
fi

# Read version from ModInfo.xml (single source of truth)
VERSION=$(sed -n 's/.*<modversion>\([^<]*\)<\/modversion>.*/\1/p' ModInfo.xml)
if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from ModInfo.xml"
    exit 1
fi
echo "Version: $VERSION"

# Changelog: use argument if provided, otherwise extract from CHANGELOG.md
CHANGELOG="${1:-}"
if [ -z "$CHANGELOG" ] && [ -f "CHANGELOG.md" ]; then
    CHANGELOG=$(awk -v ver="$VERSION" '
        /^## \[/ {
            if (found) exit
            if ($0 ~ "\\[" ver "\\]") { found=1; next }
        }
        found && /^## \[/ { exit }
        found { print }
    ' CHANGELOG.md | sed '/^$/d' | head -20)
fi

# Format changenote with version prefix
if [ -n "$CHANGELOG" ]; then
    CHANGENOTE="v$VERSION

$CHANGELOG"
else
    CHANGENOTE="v$VERSION"
fi

# Prepare workshop content folder
echo ""
echo "=== Preparing workshop content ==="
rm -rf workshop_content
mkdir -p workshop_content

cp ModInfo.xml workshop_content/
[ -f logo-512.png ] && cp logo-512.png workshop_content/
cp -r Infos workshop_content/

# Copy built DLLs if C# mod
if [ -n "$CSPROJ" ]; then
    cp "$PROJECT_DIR"/bin/*.dll workshop_content/
fi

echo "Content staged:"
ls -la workshop_content/

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "Changenote:"
    echo "$CHANGENOTE"
    echo ""
    echo "Dry run complete — nothing was uploaded."
    rm -rf workshop_content
    exit 0
fi

# Get publishedfileid from .env (required for updates)
PUBLISHED_ID="$STEAM_WORKSHOP_ID"

# Create temp VDF with absolute paths (SteamCMD needs them)
echo ""
echo "=== Generating upload VDF ==="

if [ ! -f "workshop.vdf" ]; then
    echo "Error: workshop.vdf template not found"
    echo "Create a workshop.vdf file in the project root"
    exit 1
fi

# Convert mod-description.html to BBCode for Steam Workshop
if [ -f "mod-description.html" ]; then
    DESCRIPTION=$(sed \
        -e 's|<p>\(.*\)</p>|\1|' \
        -e 's|<h2>\(.*\)</h2>|[h2]\1[/h2]|' \
        -e 's|<ul>|[list]|' \
        -e 's|</ul>|[/list]|' \
        -e 's|<li>\(.*\)</li>|[*] \1|' \
        mod-description.html | sed "s/\"/'/g")
    echo "Description converted from mod-description.html"
else
    echo "Warning: mod-description.html not found, skipping description"
    DESCRIPTION=""
fi

# Sanitize changenote for VDF format
ESCAPED_CHANGENOTE=$(printf '%s' "$CHANGENOTE" | sed "s/\"/'/g")

# Build VDF by processing line by line, inserting correct paths
{
    while IFS= read -r line; do
        case "$line" in
            *'"contentfolder"'*)
                printf '\t"contentfolder"\t\t"%s"\n' "$PROJECT_DIR/workshop_content"
                ;;
            *'"previewfile"'*)
                printf '\t"previewfile"\t\t"%s"\n' "$PROJECT_DIR/logo-512.png"
                ;;
            *'"publishedfileid"'*)
                printf '\t"publishedfileid"\t\t"%s"\n' "$PUBLISHED_ID"
                ;;
            *'"description"'*)
                printf '\t"description"\t\t"%s"\n' "$DESCRIPTION"
                ;;
            *'"changenote"'*)
                printf '\t"changenote"\t\t"%s"\n' "$ESCAPED_CHANGENOTE"
                ;;
            *)
                printf '%s\n' "$line"
                ;;
        esac
    done < workshop.vdf
} > workshop_upload.vdf
VDF_FILE="workshop_upload.vdf"

echo "Changenote: $(echo "$CHANGENOTE" | head -1)..."

if [ -n "$PUBLISHED_ID" ]; then
    echo "Updating existing item: $PUBLISHED_ID"
else
    echo "Creating new workshop item"
fi

echo ""
echo "=== Uploading to Steam Workshop ==="

# Get Steam username
if [ -n "$STEAM_USERNAME" ]; then
    USERNAME="$STEAM_USERNAME"
else
    read -p "Steam username: " USERNAME
fi

echo "Logging in as: $USERNAME"
echo "(You may be prompted for password and Steam Guard code)"
echo ""

# Run SteamCMD
steamcmd +login "$USERNAME" +workshop_build_item "$PROJECT_DIR/$VDF_FILE" +quit

# Cleanup temp file
rm -f workshop_upload.vdf

echo ""
echo "=== Upload complete ==="
echo ""
echo "If this was a new upload, note the 'publishedfileid' from the output above."
echo "Add it to your .env file as STEAM_WORKSHOP_ID for future updates."
