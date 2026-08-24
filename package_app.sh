#!/bin/bash

# Build Arguments
VERSION=$1

if [ -z "$VERSION" ]; then
    # Default to Test Build if no version specified
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    VERSION="0.0.0-test.$TIMESTAMP"
    BUILD_TYPE="test"
    echo "⚠️  No version specified. Creating TEST build: $VERSION"
else
    # Official Release
    BUILD_TYPE="release"
    echo "🚀 Creating OFFICIAL RELEASE: $VERSION"
fi

# Configuration
APP_NAME="PlayIPTV"
ICON_SOURCE="app_icon.png"
BUILD_DIR=".build/release"
OUTPUT_DIR="."

# Ensure we have an icon source
if [ ! -f "AppIcon.icns" ] && [ ! -f "$ICON_SOURCE" ]; then
    echo "Error: Neither AppIcon.icns nor $ICON_SOURCE found!"
    exit 1
fi

# Build Loop
build_for_arch() {
    ARCH=$1
    echo "========================================"
    echo "🚀 Starting build for architecture: $ARCH"
    echo "========================================"

    # output specific to arch
    BUILD_PATH=".build/${ARCH}-apple-macosx/release"
    
    echo "🔨 Compiling..."
    swift build -c release --arch "$ARCH"

    if [ $? -ne 0 ]; then
        echo "❌ Build failed for $ARCH."
        return 1
    fi

    echo "📦 Creating $APP_NAME.app bundle for $ARCH..."

    # Create structure (Standard name inside the zip)
    APP_BUNDLE="$RELEASE_DIR/${APP_NAME}.app"
    CONTENTS="$APP_BUNDLE/Contents"
    MACOS="$CONTENTS/MacOS"
    RESOURCES="$CONTENTS/Resources"
    FRAMEWORKS="$CONTENTS/Frameworks"

    rm -rf "$APP_BUNDLE"
    mkdir -p "$MACOS"
    mkdir -p "$RESOURCES"
    mkdir -p "$FRAMEWORKS"

    # Copy binary
    if [ -f "$BUILD_PATH/$APP_NAME" ]; then
        cp "$BUILD_PATH/$APP_NAME" "$MACOS/$APP_NAME" # Ensure binary name inside bundle is standard
    else
        echo "❌ Error: Binary not found at $BUILD_PATH/$APP_NAME"
        return 1
    fi

    # Copy Frameworks (VLCKit)
    # Find VLCKit.framework in specific arch build dir
    VLCKIT_PATH=$(find .build/${ARCH}-apple-macosx -name "VLCKit.framework" -type d | grep "release" | head -n 1)
    
    if [ -z "$VLCKIT_PATH" ]; then
         echo "⚠️ Warning: VLCKit.framework not found in specific path. Searching broader..."
         VLCKIT_PATH=$(find .build -name "VLCKit.framework" -type d | head -n 1)
    fi

    if [ -n "$VLCKIT_PATH" ]; then
        echo "📦 Bundling VLCKit from $VLCKIT_PATH..."
        cp -R "$VLCKIT_PATH" "$FRAMEWORKS/"
    else
        echo "❌ Error: Could not find VLCKit.framework"
        return 1
    fi

    # Create Info.plist (allows http:// IPTV/EPG servers)
    cp "Sources/PlayIPTV/Info.plist" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"

    echo "🎨 Setting up AppIcon..."
    # Pre-generated icon check
    if [ -f "AppIcon.icns" ]; then
         cp "AppIcon.icns" "$RESOURCES/AppIcon.icns"
    fi

    echo "🔐 Ad-hoc code signing..."
    codesign --force --deep --sign - "$APP_BUNDLE"

    # Create DMG instead of ZIP
    if [ "$BUILD_TYPE" == "release" ]; then
        DMG_NAME="${APP_NAME}_v${VERSION}_${ARCH}.dmg"
    else
        # Version already contains "test" (e.g. 0.0.0-test.TIMESTAMP)
        DMG_NAME="${APP_NAME}_${VERSION}_${ARCH}.dmg"
    fi
    
    echo "📦 Creating DMG installer: $DMG_NAME..."
    
    # Create temporary directory for DMG contents
    DMG_TEMP="$RELEASE_DIR/dmg_temp"
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"
    
    # Copy app to temp directory
    cp -R "$APP_BUNDLE" "$DMG_TEMP/"
    
    # Create Applications symlink
    ln -s /Applications "$DMG_TEMP/Applications"
    
    # Create temporary DMG for styling
    TEMP_DMG="$RELEASE_DIR/temp.dmg"
    rm -f "$TEMP_DMG"
    
    # Create writable DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDRW \
        -fs HFS+ \
        -size 200m \
        "$TEMP_DMG"
    
    # Mount the DMG
    MOUNT_DIR="/Volumes/$APP_NAME"
    
    # Clean up any existing mount first
    if [ -d "$MOUNT_DIR" ]; then
        echo "🧹 Cleaning up existing mount..."
        hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
        sleep 1
    fi
    
    echo "📂 Mounting DMG..."
    MOUNT_OUTPUT=$(hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse)
    DEVICE=$(echo "$MOUNT_OUTPUT" | grep "/dev/disk" | head -1 | awk '{print $1}')
    
    echo "   Mounted at: $MOUNT_DIR (device: $DEVICE)"
    
    # Wait for mount
    sleep 2
    
    # Use AppleScript to style the DMG window
    echo "🎨 Styling DMG window..."
    osascript <<EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 700, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        
        -- Position app icon on the left
        set position of item "$APP_NAME.app" of container window to {150, 200}
        
        -- Position Applications symlink on the right
        set position of item "Applications" of container window to {450, 200}
        
        update without registering applications
        delay 2
    end tell
    -- Close only the installer window
    close (every window whose name is "$APP_NAME")
end tell
EOF
    
    # Give Finder time to close
    sleep 3
    
    # Unmount the DMG using the device path
    echo "📤 Unmounting DMG..."
    UNMOUNT_ATTEMPTS=0
    MAX_ATTEMPTS=5
    
    while [ $UNMOUNT_ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if hdiutil detach "$DEVICE" 2>/dev/null; then
            echo "✅ DMG unmounted successfully"
            break
        else
            UNMOUNT_ATTEMPTS=$((UNMOUNT_ATTEMPTS + 1))
            echo "⚠️  Unmount attempt $UNMOUNT_ATTEMPTS failed, retrying..."
            sleep 2
            
            if [ $UNMOUNT_ATTEMPTS -eq $MAX_ATTEMPTS ]; then
                echo "🔨 Force unmounting..."
                hdiutil detach "$DEVICE" -force || {
                    echo "⚠️  Force unmount failed, trying mount point..."
                    hdiutil detach "$MOUNT_DIR" -force
                }
                sleep 2
            fi
        fi
    done
    
    # Convert to compressed read-only DMG
    rm -f "$RELEASE_DIR/$DMG_NAME"
    hdiutil convert "$TEMP_DMG" -format UDZO -o "$RELEASE_DIR/$DMG_NAME"
    
    # Clean up
    rm -f "$TEMP_DMG"
    rm -rf "$DMG_TEMP"
    
    echo "✅ Finished $ARCH"
}

# Updates to Main Execution
# 1. Prepare output dir
RELEASE_DIR="Releases"
mkdir -p "$RELEASE_DIR"

# 2. Prepare Icon globally if needed (to avoid re-generating per arch)
if [ ! -f "AppIcon.icns" ] && [ -f "$ICON_SOURCE" ]; then
    echo "🎨 Generating AppIcon.icns from source..."
    ICONSET="PlayIPTV.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" &>/dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" &>/dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" &>/dev/null
    sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" &>/dev/null
    sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" &>/dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" &>/dev/null
    sips -z 256 256   "$ICONSET/icon_256x256.png" &>/dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" &>/dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" &>/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" &>/dev/null
    iconutil -c icns "$ICONSET" -o "AppIcon.icns"
    rm -rf "$ICONSET"
fi

# 3. Run Builds
# 3. Run Builds
build_for_arch "arm64"

echo ""
echo "🎉 Build complete!"
echo "📂 Artifacts in $RELEASE_DIR/"
echo "   - DMG Installer: $RELEASE_DIR/${APP_NAME}*${ARCH}.dmg"
echo ""
echo "🚀 To Release on GitHub:"
echo "1. Go to your repo -> Releases -> Draft a new release"
echo "2. Tag it as v$VERSION"
echo "3. Upload the DMG file from $RELEASE_DIR/"
