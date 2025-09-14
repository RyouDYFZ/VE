#!/bin/bash
set -euo pipefail

PROJECT_NAME="VisualEffectBridge"
TARGET_NAME="VisualEffectBridge"
SCHEME="$TARGET_NAME"
CONFIGURATION="Release"
BUILD_DIR="./build"
UNIVERSAL_DIR="$BUILD_DIR/universal"
OUTPUT_DYLIB="$BUILD_DIR/libVisualEffectBridge.dylib"

rm -rf "$BUILD_DIR"
mkdir -p "$UNIVERSAL_DIR"

ARCHS=("x86_64" "arm64")

for ARCH in "${ARCHS[@]}"; do
    echo "ARCH $ARCH"
    xcodebuild -project "$PROJECT_NAME.xcodeproj" \
               -scheme "$SCHEME" \
               -configuration "$CONFIGURATION" \
               -arch $ARCH \
               BUILD_DIR="$BUILD_DIR/$ARCH" \
               clean build
done

X86_DYLIB="$BUILD_DIR/x86_64/$CONFIGURATION/$TARGET_NAME.dylib"
ARM_DYLIB="$BUILD_DIR/arm64/$CONFIGURATION/$TARGET_NAME.dylib"

if [[ ! -f "$X86_DYLIB" ]]; then
    echo "Unable to find x86_64 dylib: $X86_DYLIB"
    exit 1
fi
if [[ ! -f "$ARM_DYLIB" ]]; then
    echo "Unable to find arm64 dylib: $ARM_DYLIB"
    exit 1
fi

echo "Merging to universal dylib..."
lipo -create -output "$OUTPUT_DYLIB" "$X86_DYLIB" "$ARM_DYLIB"

echo "DONE: $OUTPUT_DYLIB"

echo "ARCH"
lipo -info "$OUTPUT_DYLIB"

# CODESIGN
# codesign --force --sign "TEAM ID" "$OUTPUT_DYLIB"
