#!/bin/bash
# validate.sh - Validate mod content before deployment
#
# Checks:
#   - text-*-add.xml files have UTF-8 BOM (ef bb bf)
#   - All XML files in Infos/ are well-formed
#   - ModInfo.xml is well-formed and has a <modversion> tag
#
# Usage: ./scripts/validate.sh
# Exit code: 0 on success, 1 on failure

REAL_PATH="$(readlink "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

ERRORS=0

echo "=== Validating mod content ===" >&2

# Check ModInfo.xml exists and is well-formed
if [ ! -f "ModInfo.xml" ]; then
    echo "FAIL: ModInfo.xml not found" >&2
    ERRORS=$((ERRORS + 1))
else
    if ! xmllint --noout ModInfo.xml 2>/dev/null; then
        echo "FAIL: ModInfo.xml is not well-formed XML" >&2
        ERRORS=$((ERRORS + 1))
    fi

    VERSION=$(sed -n 's/.*<modversion>\([^<]*\)<\/modversion>.*/\1/p' ModInfo.xml)
    if [ -z "$VERSION" ]; then
        echo "FAIL: ModInfo.xml missing <modversion> tag" >&2
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check Infos/ directory exists
if [ ! -d "Infos" ]; then
    echo "FAIL: Infos/ directory not found" >&2
    ERRORS=$((ERRORS + 1))
else
    # Check all XML files in Infos/ are well-formed
    for xml_file in Infos/*.xml; do
        [ -f "$xml_file" ] || continue
        if ! xmllint --noout "$xml_file" 2>/dev/null; then
            echo "FAIL: $xml_file is not well-formed XML" >&2
            ERRORS=$((ERRORS + 1))
        fi
    done

    # Check text XML files have UTF-8 BOM
    for text_file in Infos/text*-add.xml; do
        [ -f "$text_file" ] || continue
        BOM=$(xxd -l 3 -p "$text_file")
        if [ "$BOM" != "efbbbf" ]; then
            echo "FAIL: $text_file missing UTF-8 BOM (found: $BOM)" >&2
            echo "  Fix: printf '\\xef\\xbb\\xbf' > temp.xml && cat $text_file >> temp.xml && mv temp.xml $text_file" >&2
            ERRORS=$((ERRORS + 1))
        fi
    done
fi

if [ "$ERRORS" -gt 0 ]; then
    echo "" >&2
    echo "Validation failed with $ERRORS error(s)" >&2
    exit 1
else
    echo "All checks passed" >&2
    exit 0
fi
