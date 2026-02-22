#!/bin/bash
# modio-upload.sh - Upload mod to mod.io
#
# Prerequisites:
#   1. Get an OAuth2 access token from https://mod.io/me/access (read+write)
#   2. .env file with MODIO_ACCESS_TOKEN, MODIO_GAME_ID (MODIO_MOD_ID created automatically on first run)
#
# Usage: ./scripts/modio-upload.sh [--dry-run] [changelog]
# Examples:
#   ./scripts/modio-upload.sh                    # Upload with version from ModInfo.xml, changelog from CHANGELOG.md
#   ./scripts/modio-upload.sh "Fixed bug X"      # Upload with custom changelog message
#   ./scripts/modio-upload.sh --dry-run           # Preview without uploading
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

# Check required variables
if [ -z "$MODIO_ACCESS_TOKEN" ]; then
    echo "Error: MODIO_ACCESS_TOKEN not set in .env"
    echo "Get one from https://mod.io/me/access (OAuth 2 section, read+write)"
    exit 1
fi

if [ -z "$MODIO_GAME_ID" ]; then
    echo "Error: MODIO_GAME_ID must be set in .env"
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

# Read mod metadata from ModInfo.xml
MOD_NAME=$(sed -n 's/.*<displayName>\([^<]*\)<\/displayName>.*/\1/p' ModInfo.xml)
MOD_SUMMARY=$(sed -n 's/.*<description>\([^<]*\)<\/description>.*/\1/p' ModInfo.xml)
if [ -z "$MOD_NAME" ]; then
    echo "Error: Could not extract mod name from ModInfo.xml"
    exit 1
fi

# Read description from file if available
if [ -f "mod-description.html" ]; then
    DESCRIPTION=$(cat mod-description.html)
else
    DESCRIPTION=""
fi

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "=== Dry run summary ==="
    echo "Version: $VERSION"
    echo "Changelog: ${CHANGELOG:-"(none)"}"
    echo ""
    echo "Files to upload:"
    ls Infos/ ModInfo.xml logo-512.png
    echo ""
    echo "Dry run complete — nothing was uploaded."
    exit 0
fi

# Step 1: Create or update mod profile
if [ -z "$MODIO_MOD_ID" ]; then
    # Create new mod
    echo ""
    echo "=== Creating new mod on mod.io ==="

    CURL_CREATE_ARGS=(
        -X POST
        "https://api.mod.io/v1/games/$MODIO_GAME_ID/mods"
        -H "Authorization: Bearer $MODIO_ACCESS_TOKEN"
        -H "Accept: application/json"
        --form-string "name=$MOD_NAME"
        --form-string "summary=$MOD_SUMMARY"
        -F "logo=@logo-512.png"
    )
    if [ -n "$DESCRIPTION" ]; then
        CURL_CREATE_ARGS+=(--form-string "description=$DESCRIPTION")
    fi

    RESPONSE=$(curl -sS -w "\n%{http_code}" "${CURL_CREATE_ARGS[@]}")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "201" ]; then
        MODIO_MOD_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
        echo "Mod created successfully! Mod ID: $MODIO_MOD_ID"

        # Save mod ID to .env for future runs
        if grep -q '^#\?MODIO_MOD_ID=' .env; then
            sed -i '' "s/^#\\{0,1\\}MODIO_MOD_ID=.*/MODIO_MOD_ID=\"$MODIO_MOD_ID\"/" .env
        else
            echo "MODIO_MOD_ID=\"$MODIO_MOD_ID\"" >> .env
        fi
        echo "Saved MODIO_MOD_ID=$MODIO_MOD_ID to .env"
    else
        echo "Mod creation failed (HTTP $HTTP_CODE)"
        echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
        exit 1
    fi
else
    # Update existing mod profile
    echo ""
    echo "=== Updating mod profile (text fields) ==="
    echo "Including description from mod-description.html"

    FORM_DATA="name=$(printf '%s' "$MOD_NAME" | jq -sRr @uri)"
    FORM_DATA+="&summary=$(printf '%s' "$MOD_SUMMARY" | jq -sRr @uri)"
    if [ -n "$DESCRIPTION" ]; then
        FORM_DATA+="&description=$(printf '%s' "$DESCRIPTION" | jq -sRr @uri)"
    fi

    RESPONSE=$(curl -sS -w "\n%{http_code}" -X PUT \
        "https://api.mod.io/v1/games/$MODIO_GAME_ID/mods/$MODIO_MOD_ID" \
        -H "Authorization: Bearer $MODIO_ACCESS_TOKEN" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Accept: application/json" \
        -d "$FORM_DATA")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        echo "Profile text fields updated successfully"
    else
        echo "Warning: Profile update failed (HTTP $HTTP_CODE)"
        echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    fi
fi

# Step 2: Upload logo
if [ -f "logo-512.png" ]; then
    echo ""
    echo "=== Uploading logo ==="

    RESPONSE=$(curl -sS -w "\n%{http_code}" -X POST \
        "https://api.mod.io/v1/games/$MODIO_GAME_ID/mods/$MODIO_MOD_ID/media" \
        -H "Authorization: Bearer $MODIO_ACCESS_TOKEN" \
        -H "Accept: application/json" \
        -F "logo=@logo-512.png")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "201" ]; then
        echo "Logo uploaded successfully"
    else
        echo "Warning: Logo upload failed (HTTP $HTTP_CODE)"
        echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    fi
else
    echo "Warning: logo-512.png not found, skipping logo upload"
fi

# Step 3: Prepare and upload modfile
echo ""
echo "=== Preparing upload package ==="
rm -rf modio_content modio_upload.zip
mkdir -p modio_content

cp ModInfo.xml modio_content/
[ -f logo-512.png ] && cp logo-512.png modio_content/
cp -r Infos modio_content/

# Copy built DLLs if C# mod
if [ -n "$CSPROJ" ]; then
    cp "$PROJECT_DIR"/bin/*.dll modio_content/
fi

echo "Content prepared:"
ls -la modio_content/

# Create zip file
echo ""
echo "=== Creating zip file ==="
cd modio_content
zip -r ../modio_upload.zip .
cd ..
echo "Created modio_upload.zip ($(du -h modio_upload.zip | cut -f1))"

# Upload modfile
echo ""
echo "=== Uploading modfile to mod.io ==="
echo "Game ID: $MODIO_GAME_ID"
echo "Mod ID: $MODIO_MOD_ID"

CURL_ARGS=(
    -X POST
    "https://api.mod.io/v1/games/$MODIO_GAME_ID/mods/$MODIO_MOD_ID/files"
    -H "Authorization: Bearer $MODIO_ACCESS_TOKEN"
    -H "Accept: application/json"
    -F "filedata=@modio_upload.zip"
)

if [ -n "$VERSION" ]; then
    echo "Version: $VERSION"
    CURL_ARGS+=(-F "version=$VERSION")
fi

if [ -n "$CHANGELOG" ]; then
    echo "Changelog: $CHANGELOG"
    CURL_ARGS+=(-F "changelog=$CHANGELOG")
fi

echo ""

# Execute upload
RESPONSE=$(curl -sS -w "\n%{http_code}" "${CURL_ARGS[@]}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "201" ]; then
    echo "Modfile upload successful!"
    echo ""
    echo "Response:"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
else
    echo "Modfile upload failed (HTTP $HTTP_CODE)"
    echo ""
    echo "Response:"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    exit 1
fi

# Cleanup
rm -rf modio_content modio_upload.zip

echo ""
echo "=== Upload complete ==="
