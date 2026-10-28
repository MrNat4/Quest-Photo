#!/usr/bin/env bash
# Build with prebuilt Godot templates; no Gradle or network access is used here.
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
QUEST_BUILD_ROOT="${QUEST_BUILD_ROOT:-$PROJECT_DIR/.build}"
QUEST_ANDROID_SDK="${QUEST_ANDROID_SDK:-/workspace/toolchain/android-sdk}"
QUEST_JAVA_SDK="${QUEST_JAVA_SDK:-/workspace/toolchain/jdk-17}"
QUEST_EXPORT_TEMPLATES="${QUEST_EXPORT_TEMPLATES:-/workspace/toolchain/templates/4.6.3.stable}"
QUEST_BUILD_TOOLS="${QUEST_BUILD_TOOLS:-35.0.1}"
export QUEST_BUILD_ROOT QUEST_ANDROID_SDK QUEST_JAVA_SDK QUEST_EXPORT_TEMPLATES QUEST_BUILD_TOOLS

if [[ "${1:-}" != "" && "${1:-}" != "--check" ]]; then
  echo "Usage: tools/build_android.sh [--check]" >&2
  exit 2
fi
command -v "$GODOT_BIN" >/dev/null || { echo "Missing Godot 4.6.3 executable." >&2; exit 2; }
version="$("$GODOT_BIN" --version 2>/dev/null)"
if [[ "$version" != 4.6.3.stable.* ]]; then
  echo "Expected Godot 4.6.3.stable, found: $version" >&2
  exit 2
fi
python3 - <<'PY'
import os
from pathlib import Path
sdk = Path(os.environ['QUEST_ANDROID_SDK'])
jdk = Path(os.environ['QUEST_JAVA_SDK'])
templates = Path(os.environ['QUEST_EXPORT_TEMPLATES'])
build_tools = sdk / 'build-tools' / os.environ['QUEST_BUILD_TOOLS']
required = [
    jdk / 'bin/java', jdk / 'bin/javac', jdk / 'bin/keytool', jdk / 'bin/jarsigner',
    sdk / 'platform-tools/adb', build_tools / 'apksigner', build_tools / 'zipalign',
    build_tools / 'aapt', templates / 'android_debug.apk', templates / 'android_release.apk',
]
missing = [str(p) for p in required if not p.is_file()]
if missing:
    print('Android build unavailable; missing dependencies:')
    print('\n'.join('  ' + p for p in missing))
    print('See docs/BUILD.md. No APK was generated.')
    raise SystemExit(2)
print('Android toolchain preflight passed.')
PY
if [[ "${1:-}" == "--check" ]]; then
  exit 0
fi

# Isolated editor settings keep this build from changing the developer's profile.
export XDG_CONFIG_HOME="$QUEST_BUILD_ROOT/config"
export XDG_DATA_HOME="$QUEST_BUILD_ROOT/data"
export XDG_CACHE_HOME="$QUEST_BUILD_ROOT/cache"
mkdir -p "$XDG_CONFIG_HOME/godot" "$XDG_DATA_HOME/godot/export_templates/4.6.3.stable" "$XDG_CACHE_HOME" "$PROJECT_DIR/build"
python3 - <<'PY'
import json
import os
from pathlib import Path
cfg = Path(os.environ['XDG_CONFIG_HOME']) / 'godot/editor_settings-4.6.tres'
sdk = os.environ['QUEST_ANDROID_SDK']
jdk = os.environ['QUEST_JAVA_SDK']
cfg.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    + 'export/android/android_sdk_path = ' + json.dumps(sdk) + '\n'
    + 'export/android/java_sdk_path = ' + json.dumps(jdk) + '\n')
target = Path(os.environ['XDG_DATA_HOME']) / 'godot/export_templates/4.6.3.stable'
for name in ('android_debug.apk', 'android_release.apk', 'version.txt'):
    source = Path(os.environ['QUEST_EXPORT_TEMPLATES']) / name
    dest = target / name
    if source.is_file() and not dest.exists():
        dest.symlink_to(source.resolve())
PY
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$QUEST_BUILD_ROOT/debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"
if [[ ! -f "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ]]; then
  "$QUEST_JAVA_SDK/bin/keytool" -genkeypair -noprompt -keystore "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" \
    -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 \
    -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'
fi
"$GODOT_BIN" --headless --xr-mode off --editor --path "$PROJECT_DIR" --import --quit
"$GODOT_BIN" --headless --xr-mode off --path "$PROJECT_DIR" --export-debug 'Quest 3' "$PROJECT_DIR/build/quest-photo-0.2.0-debug.apk"
apk="$PROJECT_DIR/build/quest-photo-0.2.0-debug.apk"
test -s "$apk"
"$QUEST_ANDROID_SDK/build-tools/$QUEST_BUILD_TOOLS/apksigner" verify --verbose "$apk"
"$QUEST_ANDROID_SDK/build-tools/$QUEST_BUILD_TOOLS/aapt" dump permissions "$apk" > "$PROJECT_DIR/build/apk-permissions.txt"
if rg -q 'android.permission.INTERNET' "$PROJECT_DIR/build/apk-permissions.txt"; then
  echo 'Unexpected INTERNET permission in APK; inspect export settings.' >&2
  exit 3
fi
"$QUEST_ANDROID_SDK/build-tools/$QUEST_BUILD_TOOLS/aapt" dump badging "$apk" > "$PROJECT_DIR/build/apk-badging.txt"
sha256sum "$apk" | tee "$PROJECT_DIR/build/apk.sha256"
echo 'APK built and signature verified. Quest headset testing is still required.'
