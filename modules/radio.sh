#!/bin/bash
#
# SVXLinkJP Radio Module
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

exec "$BASE_DIR/menu/radio_menu.sh"
