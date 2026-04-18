#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="Core Principles"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

swiftc -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" main.swift
cp Info.plist "$APP_BUNDLE/Contents/"

echo "Built $APP_BUNDLE"

# Create DMG
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"
echo "Created $DMG_PATH"
