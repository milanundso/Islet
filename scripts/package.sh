#!/bin/sh
set -e
cd "$(dirname "$0")/.."
version=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Islet.xcodeproj/project.pbxproj | head -1)
xcodebuild -project Islet.xcodeproj -scheme Islet -configuration Release -derivedDataPath build build
mkdir -p dist
rm -f "dist/Islet-$version.zip"
ditto -c -k --keepParent build/Build/Products/Release/Islet.app "dist/Islet-$version.zip"
echo "dist/Islet-$version.zip"
