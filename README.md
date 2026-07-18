# Native macOS builds for RPG Maker MV

`build-native-mac.sh` turns an RPG Maker MV deployment into a native macOS
application. It downloads the official NW.js runtime for the Mac running the
script, copies the game into it, redirects save files outside the signed app
bundle, and applies an ad-hoc signature for local use.

## Requirements

- macOS on Apple Silicon (`arm64`) or Intel (`x86_64`)
- An RPG Maker MV deployment containing `www/index.html`
- An internet connection to download NW.js
- The standard macOS command-line tools used by the script: `curl`, `unzip`,
  `ditto`, `codesign`, and `awk`

The game deployment must also retain RPG Maker MV's usual
`www/js/main.js` file. The script patches this file in the generated app to
store saves in the user's Application Support directory.

## Configure the app

Before building, edit the values at the top of `build-native-mac.sh`:

```bash
APP_NAME="My Game"
PACKAGE_NAME="my-game"
APP_VERSION="1.0"
BUNDLE_ID="com.example.my-game"
WINDOW_WIDTH=1280
WINDOW_HEIGHT=720
```

- `APP_NAME` is the name shown in Finder and in the game window.
- `PACKAGE_NAME` identifies the NW.js application. Use lowercase letters,
  numbers, dots, underscores, or hyphens.
- `APP_VERSION` accepts one to three numeric components, such as `1`, `1.2`,
  or `1.2.3`.
- `BUNDLE_ID` must be a dot-separated identifier, conventionally written in
  reverse-domain form.
- `WINDOW_WIDTH` and `WINDOW_HEIGHT` set the initial window size in pixels.

The configured icon path is `www/icon/icon.png`, matching the default RPG Maker
MV deployment layout.

## Build

Make the script executable if necessary:

```bash
chmod +x build-native-mac.sh
```

If the script is inside the deployed game's directory, run:

```bash
./build-native-mac.sh
```

You can instead pass the deployment directory and an optional output path:

```bash
./build-native-mac.sh "/path/to/My Game" "/path/to/My Game.app"
```

The arguments are:

1. The directory containing `www/index.html`. It defaults to the directory
   containing the script.
2. The destination `.app` path. It defaults to
   `<game directory>/<APP_NAME> (Mac).app`.

The destination must not already exist. This protects an existing build from
being overwritten; move or remove it before rebuilding, or provide another
output path.

By default, the script fetches the latest stable NW.js version. To make builds
repeatable or select a known-compatible runtime, set `NWJS_VERSION` explicitly:

```bash
NWJS_VERSION=0.100.0 ./build-native-mac.sh "/path/to/My Game"
```

Both `0.100.0` and `v0.100.0` formats are accepted.

## Output and save files

The generated app uses the NW.js build matching the current machine:

- Apple Silicon Mac: `osx-arm64`
- Intel Mac: `osx-x64`

This creates a single-architecture app, not a universal binary. Running the
script from an Intel shell under Rosetta on Apple Silicon may therefore produce
an Intel build.

RPG Maker MV normally writes saves beside the game files. Modifying a signed app
bundle invalidates its signature, so the generated app writes saves to
`nw.App.dataPath/save` in the user's Application Support area instead. On
launch, any `.rpgsave` files bundled in `www/save` are copied there when a file
with the same name does not already exist. Existing user saves are never
overwritten by this import.

## Signing and distribution

The app receives an ad-hoc signature suitable for local use. It is not signed
with an Apple Developer ID and is not notarized. Public distribution may still
trigger Gatekeeper warnings and requires a proper Developer ID signing and
notarization workflow.

## Troubleshooting

### The directory does not look like an RPG Maker MV deployment

Pass the deployment directory itself, not its `www` subdirectory. The expected
file is `<deployment directory>/www/index.html`.

### The output already exists

Move the old `.app`, remove it if it is no longer needed, or pass a different
destination as the second argument. The script deliberately does not replace
existing output.

### The `window.onload` hook cannot be found

The generated deployment's `www/js/main.js` differs from the standard RPG Maker
MV layout or has been modified. Restore the normal `window.onload = function() {`
entry point, or adapt the save-hook insertion in the script to the custom file.

### NW.js cannot be downloaded

Check the internet connection and the requested version. If the latest runtime
is incompatible with the game, retry with a pinned `NWJS_VERSION` known to work
with its plugins.
