#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_FILE="$SCRIPT_DIR/pick-template-browser.swift"
OUTPUT_BIN="$SCRIPT_DIR/pick-template-browser"

if [ ! -f "$SWIFT_FILE" ]; then
    echo "Error: $SWIFT_FILE not found."
    exit 1
fi

swiftc -O -gnone "$SWIFT_FILE" -o "$OUTPUT_BIN"
echo "Compiled $SWIFT_FILE to $OUTPUT_BIN"