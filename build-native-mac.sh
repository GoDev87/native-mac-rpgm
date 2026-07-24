#!/bin/bash

set -euo pipefail

APP_NAME="<APP Name>"
PACKAGE_NAME="app-name"
APP_VERSION="1.0"
BUNDLE_ID="local.app-name.game"
WINDOW_WIDTH=1280
WINDOW_HEIGHT=720

NWJS_VERSIONS_URL="https://nwjs.io/versions.json"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GAME_DIR="${1:-$SCRIPT_DIR}"
OUTPUT_APP="${2:-$GAME_DIR/$APP_NAME (Mac).app}"

if [ -f "$GAME_DIR/www/index.html" ]; then
    GAME_WEB_DIR="$GAME_DIR/www"
    GAME_LAYOUT="www"
elif [ -f "$GAME_DIR/index.html" ] && [ -d "$GAME_DIR/js" ] && [ -d "$GAME_DIR/data" ]; then
    GAME_WEB_DIR="$GAME_DIR"
    GAME_LAYOUT="flat"
else
    echo "Error: '$GAME_DIR' does not look like an RPG Maker deployment." >&2
    echo "Expected either $GAME_DIR/www/index.html or a flat deployment with" >&2
    echo "$GAME_DIR/index.html, $GAME_DIR/js, and $GAME_DIR/data." >&2
    exit 1
fi

if [ -f "$GAME_WEB_DIR/js/rmmz_managers.js" ]; then
    RPG_MAKER_ENGINE="MZ"
elif [ -f "$GAME_WEB_DIR/js/rpg_managers.js" ]; then
    RPG_MAKER_ENGINE="MV"
else
    echo "Error: could not identify RPG Maker MV or MZ in '$GAME_WEB_DIR'." >&2
    exit 1
fi

if [ -e "$OUTPUT_APP" ]; then
    echo "Error: output already exists: $OUTPUT_APP" >&2
    echo "Move it elsewhere or pass a different output path as the second argument." >&2
    exit 1
fi

case "$(uname -m)" in
    arm64)
        NWJS_PLATFORM="osx-arm64"
        ;;
    x86_64)
        NWJS_PLATFORM="osx-x64"
        ;;
    *)
        echo "Error: unsupported Mac architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

for required_command in curl unzip ditto codesign awk; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Error: required command is missing: $required_command" >&2
        exit 1
    fi
done

if [ -z "$APP_NAME" ]; then
    echo "Error: APP_NAME must not be empty." >&2
    exit 1
fi

if [[ ! "$PACKAGE_NAME" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "Error: invalid PACKAGE_NAME: '$PACKAGE_NAME'" >&2
    echo "Use lowercase letters, numbers, dots, underscores, or hyphens." >&2
    exit 1
fi

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "Error: invalid APP_VERSION: '$APP_VERSION'" >&2
    echo "Use one to three numeric components, for example: 1.10 or 1.10.0" >&2
    exit 1
fi

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
    echo "Error: invalid BUNDLE_ID: '$BUNDLE_ID'" >&2
    exit 1
fi

if [[ ! "$WINDOW_WIDTH" =~ ^[1-9][0-9]*$ ]] || [[ ! "$WINDOW_HEIGHT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: WINDOW_WIDTH and WINDOW_HEIGHT must be positive integers." >&2
    exit 1
fi

if [ -z "${NWJS_VERSION:-}" ]; then
    echo "Fetching the latest stable NW.js version..."
    if ! NWJS_VERSION="$(
        curl --fail --silent --show-error --location "$NWJS_VERSIONS_URL" |
            awk -F'"' '
                !found && /^[[:space:]]*"stable"[[:space:]]*:/ {
                    print $4
                    found = 1
                }
            '
    )"; then
        echo "Error: could not fetch NW.js version information from $NWJS_VERSIONS_URL" >&2
        exit 1
    fi
fi

NWJS_VERSION="${NWJS_VERSION#v}"
if [[ ! "$NWJS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "Error: invalid NW.js version: '${NWJS_VERSION:-<empty>}'" >&2
    exit 1
fi

BUILD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/$PACKAGE_NAME-native.XXXXXX")"

cleanup() {
    if [ -n "${BUILD_TMP:-}" ] && [ -d "$BUILD_TMP" ]; then
        case "$BUILD_TMP" in
            "${TMPDIR:-/tmp}/$PACKAGE_NAME-native."*)
                rm -rf -- "$BUILD_TMP"
                ;;
        esac
    fi
}
trap cleanup EXIT HUP INT TERM

ARCHIVE_NAME="nwjs-sdk-v$NWJS_VERSION-$NWJS_PLATFORM.zip"
DOWNLOAD_URL="https://dl.nwjs.io/v$NWJS_VERSION/$ARCHIVE_NAME"
ARCHIVE_PATH="$BUILD_TMP/$ARCHIVE_NAME"
RUNTIME_DIR="$BUILD_TMP/nwjs-sdk-v$NWJS_VERSION-$NWJS_PLATFORM"
RUNTIME_APP="$RUNTIME_DIR/nwjs.app"

echo "Downloading official NW.js $NWJS_VERSION for $NWJS_PLATFORM..."
curl --fail --location --progress-bar "$DOWNLOAD_URL" --output "$ARCHIVE_PATH"

echo "Extracting the native runtime..."
unzip -q "$ARCHIVE_PATH" -d "$BUILD_TMP"

if [ ! -d "$RUNTIME_APP" ]; then
    echo "Error: the downloaded archive did not contain the expected nwjs.app." >&2
    exit 1
fi

echo "Creating $OUTPUT_APP..."
ditto "$RUNTIME_APP" "$OUTPUT_APP"

APP_NW="$OUTPUT_APP/Contents/Resources/app.nw"
mkdir -p "$APP_NW"

echo "Copying RPG Maker $RPG_MAKER_ENGINE game data ($GAME_LAYOUT layout)..."
if [ "$GAME_LAYOUT" = "www" ]; then
    ditto "$GAME_WEB_DIR" "$APP_NW"
else
    # Windows RPG Maker deployments put the web game and NW.js runtime in the
    # same directory. Copy the game while leaving the Windows runtime behind.
    for source_path in "$GAME_WEB_DIR"/*; do
        [ -e "$source_path" ] || continue
        source_name="$(basename "$source_path")"

        if [ -d "$source_path" ]; then
            case "$source_name" in
                Dictionaries|locales|swiftshader|*.app)
                    continue
                    ;;
            esac
        else
            case "$source_name" in
                package.json|build-native-mac.sh|credits.html|*.exe|*.dll|*.pak|*.dat|*.log)
                    continue
                    ;;
            esac
        fi

        ditto "$source_path" "$APP_NW/$source_name"
    done
fi

cat > "$APP_NW/package.json" <<JSON
{
  "name": "$PACKAGE_NAME",
  "version": "$APP_VERSION",
  "main": "index.html",
  "js-flags": "--expose-gc",
  "chromium-args": "--force-color-profile=srgb --disable-devtools",
  "window": {
    "title": "$APP_NAME",
    "toolbar": false,
    "width": $WINDOW_WIDTH,
    "height": $WINDOW_HEIGHT,
    "position": "center",
    "resizable": true,
    "icon": "icon/icon.png"
  }
}
JSON

# RPG Maker normally saves beside the game files. A signed Mac app should not
# modify its own bundle, so this hook redirects saves to NW.js Application Support
# and copies any existing Windows saves there on the first launch.
SAVE_HOOK="$BUILD_TMP/mac-save-hook.js"
if [ "$RPG_MAKER_ENGINE" = "MZ" ]; then
    cat > "$SAVE_HOOK" <<'JAVASCRIPT'
if (process.platform === "darwin" && typeof nw === "object") {
    const fs = require("fs");
    const path = require("path");
    const savePath = path.join(nw.App.dataPath, "save");
    const bundledSavePath = path.join(
        path.dirname(process.mainModule.filename),
        "save"
    );
    if (!fs.existsSync(savePath)) {
        fs.mkdirSync(savePath, { recursive: true });
    }
    if (fs.existsSync(bundledSavePath)) {
        for (const filename of fs.readdirSync(bundledSavePath)) {
            const source = path.join(bundledSavePath, filename);
            const destination = path.join(savePath, filename);
            if (/\.rmmzsave$/i.test(filename) && !fs.existsSync(destination)) {
                fs.copyFileSync(source, destination);
            }
        }
    }
    StorageManager.fileDirectoryPath = function() {
        return savePath + path.sep;
    };
}
JAVASCRIPT

    cat "$SAVE_HOOK" >> "$APP_NW/js/rmmz_managers.js"
else
    cat > "$SAVE_HOOK" <<'JAVASCRIPT'
    if (process.platform === 'darwin') {
        var fs = require('fs');
        var path = require('path');
        var savePath = path.join(nw.App.dataPath, 'save');
        var bundledSavePath = path.join(
            path.dirname(process.mainModule.filename),
            'save'
        );
        if (!fs.existsSync(savePath)) {
            fs.mkdirSync(savePath, { recursive: true });
        }
        if (fs.existsSync(bundledSavePath)) {
            fs.readdirSync(bundledSavePath).forEach(function(filename) {
                var source = path.join(bundledSavePath, filename);
                var destination = path.join(savePath, filename);
                if (/\.rpgsave$/i.test(filename) && !fs.existsSync(destination)) {
                    fs.copyFileSync(source, destination);
                }
            });
        }
        StorageManager.localFileDirectoryPath = function() {
            return savePath + path.sep;
        };
    }
JAVASCRIPT

    MAIN_JS="$APP_NW/js/main.js"
    PATCHED_MAIN="$BUILD_TMP/main.js"
    if ! awk -v save_hook="$SAVE_HOOK" '
        !inserted && $0 ~ /^[[:space:]]*window\.onload = function\(\) \{/ {
            sub(/\r$/, "", $0)
            print $0
            while ((getline hook_line < save_hook) > 0) {
                print hook_line
            }
            close(save_hook)
            inserted = 1
            next
        }
        { print }
        END {
            if (!inserted) {
                exit 42
            }
        }
    ' "$MAIN_JS" > "$PATCHED_MAIN"; then
        echo "Error: could not find RPG Maker's window.onload hook in $MAIN_JS" >&2
        exit 1
    fi
    mv "$PATCHED_MAIN" "$MAIN_JS"
fi

INFO_PLIST="$OUTPUT_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$INFO_PLIST"

echo "Applying an ad-hoc local signature..."
codesign --force --deep --sign - --timestamp=none "$OUTPUT_APP"
codesign --verify --deep --strict "$OUTPUT_APP"

echo
echo "Native Mac app created successfully:"
echo "$OUTPUT_APP"
echo
echo "Double-click it in Finder to play. Existing saves are imported on first launch."
