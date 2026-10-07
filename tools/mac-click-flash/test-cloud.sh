#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_DIR=$(mktemp -d /private/tmp/pebble-cloud-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc "$SCRIPT_DIR/CloudTranscriber.swift" "$SCRIPT_DIR/tests/cloud/main.swift" -o "$TEST_DIR/test"
"$TEST_DIR/test"
