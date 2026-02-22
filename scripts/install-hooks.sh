#!/bin/bash
# install-hooks.sh - Install git hooks for this project
#
# Usage: ./scripts/install-hooks.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ln -sf "$SCRIPT_DIR/validate.sh" "$PROJECT_DIR/.git/hooks/pre-commit"
echo "Installed pre-commit hook (-> scripts/validate.sh)"
