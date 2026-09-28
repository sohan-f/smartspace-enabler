#!/usr/bin/env bash
#
# Minimal build for the "Smartspace Enabler" LSPosed module.
#
#   aapt2  -> resources + binary AndroidManifest.xml
#   javac  -> module classes
#   d8     -> classes.dex
#   zip    -> APK (dex + META-INF/xposed metadata added)
#   zipalign (best effort) + apksigner -> signed APK
#
# Prerequisites: JDK 17 (java, javac, keytool), python3, curl, unzip, sha1sum.
# Everything else (Android build-tools 35.0.1 + platform android-35, ~126 MB) is downloaded
# once into ./.sdk and reused. No Gradle, no Android Studio, no NDK, no emulator.
#
# Overrides:
#   BUILD_TOOLS_DIR=/path/to/build-tools/<ver>   use an existing build-tools directory
#   PLATFORM_DIR=/path/to/platforms/android-35   use an existing platform directory
#
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BT_VERSION="35.0.1"
PLATFORM_NAME="android-35"
MIN_SDK=29
TARGET_SDK=35
VERSION_CODE=1
VERSION_NAME="1.0"
APK_NAME="smartspace-enabler-${VERSION_NAME}.apk"

BT_URL="https://dl.google.com/android/repository/build-tools_r35.0.1_linux.zip"
BT_SHA1="e009a9b188cfeb1d2b4c318ab5cb4f1ddc368861"
PL_URL="https://dl.google.com/android/repository/platform-35_r02.zip"
PL_SHA1="0bb560a90a7a2cbd0dd8348224d518b638fe7949"
XAPI_URL="https://repo1.maven.org/maven2/io/github/libxposed/api/102.0.0/api-102.0.0.aar"
XAPI_SHA1="cfded6d221db78fadd94d90cffaee5417a2e2047"

SDK="$PWD/.sdk"
DL="$SDK/dl"
OUT="$PWD/build"
RES="$PWD/app/src/main/res"
ASSETS="$PWD/app/src/main/assets"
MANIFEST="$PWD/app/src/main/AndroidManifest.xml"
JAVA_SRC="$PWD/app/src/main/java"
META="$PWD/app/src/main/resources"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for tool in java javac keytool python3 curl unzip sha1sum; do
  command -v "$tool" >/dev/null 2>&1 || die "missing prerequisite: $tool"
done

fetch() { # <url> <dest> <sha1>
  if [ ! -s "$2" ]; then
    echo "     downloading $(basename "$2")"
    mkdir -p "$(dirname "$2")"
    curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$1"
  fi
  echo "$3  $2" | sha1sum -c - >/dev/null || { rm -f "$2"; die "checksum mismatch: $2"; }
}

find_build_tools() { # echoes first dir containing a usable aapt2
  local d
  for d in "${BUILD_TOOLS_DIR:-}" \
           "$SDK/build-tools/$BT_VERSION" "$SDK"/build-tools/* \
           "${ANDROID_HOME:-}/build-tools/$BT_VERSION" "${ANDROID_HOME:-}"/build-tools/*; do
    [ -n "$d" ] && [ -x "$d/aapt2" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

find_platform() { # echoes first dir containing android.jar
  local d
  for d in "${PLATFORM_DIR:-}" \
           "$SDK/platforms/$PLATFORM_NAME" "$SDK"/platforms/* \
           "${ANDROID_HOME:-}/platforms/$PLATFORM_NAME" "${ANDROID_HOME:-}"/platforms/*; do
    [ -n "$d" ] && [ -f "$d/android.jar" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

# ---------------------------------------------------------------- bootstrap
BT="$(find_build_tools || true)"
if [ -z "$BT" ]; then
  log "Downloading Android SDK Build-Tools $BT_VERSION"
  fetch "$BT_URL" "$DL/build-tools.zip" "$BT_SHA1"
  mkdir -p "$SDK/build-tools"
  unzip -q -o "$DL/build-tools.zip" -d "$SDK/build-tools"
  rm -f "$DL/build-tools.zip"
  BT="$(find_build_tools || true)"
  [ -n "$BT" ] || die "build-tools not found after extraction"
fi

PLAT="$(find_platform || true)"
if [ -z "$PLAT" ]; then
  log "Downloading Android SDK Platform $PLATFORM_NAME"
  fetch "$PL_URL" "$DL/platform.zip" "$PL_SHA1"
  mkdir -p "$SDK/platforms"
  unzip -q -o "$DL/platform.zip" -d "$SDK/platforms"
  rm -f "$DL/platform.zip"
  PLAT="$(find_platform || true)"
  [ -n "$PLAT" ] || die "platform not found after extraction"
fi

XAPI_JAR="$SDK/libxposed-api-102.jar"
if [ ! -s "$XAPI_JAR" ]; then
  log "Downloading libxposed API 102 (compile-only dependency)"
  fetch "$XAPI_URL" "$DL/xapi.aar" "$XAPI_SHA1"
  unzip -p "$DL/xapi.aar" classes.jar > "$XAPI_JAR"
  rm -f "$DL/xapi.aar"
fi

AAPT2="$BT/aapt2"
D8="$BT/d8"
APKSIGNER="$BT/apksigner"
ZIPALIGN="$BT/zipalign"
ANDROID_JAR="$PLAT/android.jar"

[ -x "$AAPT2" ] || die "aapt2 not found in $BT"
"$AAPT2" version >/dev/null 2>&1 || die \
  "aapt2 ($AAPT2) cannot run on this host ($(uname -m)). Google only ships x86_64 Linux
   build-tools - build on CI (GitHub Actions workflow in .github/workflows/build.yml),
   on an x86_64 machine, or point BUILD_TOOLS_DIR at a native build-tools."

echo "build-tools : $BT"
echo "platform    : $PLAT"
echo "libxposed   : $XAPI_JAR"

# ---------------------------------------------------------------- build
rm -rf "$OUT"
mkdir -p "$OUT/classes" "$OUT/dex"

log "[1/6] resources (aapt2 compile + link)"
if [ -d "$RES" ] && [ -n "$(ls -A "$RES" 2>/dev/null)" ]; then
  "$AAPT2" compile --dir "$RES" -o "$OUT/res.zip"
  RES_ARG="$OUT/res.zip"
else
  RES_ARG=""
fi

"$AAPT2" link -o "$OUT/base.apk" -I "$ANDROID_JAR" \
  --manifest "$MANIFEST" \
  --min-sdk-version "$MIN_SDK" --target-sdk-version "$TARGET_SDK" \
  --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" \
  -A "$ASSETS" \
  $RES_ARG

log "[2/6] javac"
find "$JAVA_SRC" -name '*.java' > "$OUT/sources.txt"
javac -source 8 -target 8 -Xlint:-options -nowarn \
  -classpath "$ANDROID_JAR:$XAPI_JAR" \
  -d "$OUT/classes" @"$OUT/sources.txt"
find "$OUT/classes" -name '*.class'

log "[3/6] d8 (classes.dex)"
"$D8" --release --min-api "$MIN_SDK" \
  --lib "$ANDROID_JAR" \
  --classpath "$XAPI_JAR" \
  --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')
ls -la "$OUT/dex/classes.dex"

log "[4/6] package"
python3 tools/pack.py "$OUT/base.apk" "$OUT/staged.apk" \
  "$OUT/dex/classes.dex:classes.dex" \
  "$META/META-INF/xposed/java_init.list:META-INF/xposed/java_init.list" \
  "$META/META-INF/xposed/module.prop:META-INF/xposed/module.prop" \
  "$META/META-INF/xposed/scope.list:META-INF/xposed/scope.list"

log "[5/6] zipalign"
if "$ZIPALIGN" -f 4 "$OUT/staged.apk" "$OUT/aligned.apk" 2>/dev/null; then
  echo "     4-byte alignment applied"
else
  echo "     skipped: zipalign binary not runnable on $(uname -m) (not required to install)"
  cp "$OUT/staged.apk" "$OUT/aligned.apk"
fi

log "[6/6] sign"
# Kept outside build/ so consecutive builds keep the same signature (build/ is wiped).
KS="${MODULE_KEYSTORE:-$SDK/smartspace-enabler.keystore}"
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
    -alias smartspace-enabler -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Smartspace Enabler, OU=SmartspaceEnabler, O=SmartspaceEnabler, L=Unknown, ST=Unknown, C=US" \
    >/dev/null 2>&1
fi
"$APKSIGNER" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT/$APK_NAME" "$OUT/aligned.apk"

# ---------------------------------------------------------------- verify
log "verify"
{
  echo "== aapt2 dump badging =="
  "$AAPT2" dump badging "$OUT/$APK_NAME" | sed -n '1,8p'
  echo
  echo "== apksigner verify =="
  "$APKSIGNER" verify --verbose --print-certs "$OUT/$APK_NAME" | sed -n '1,14p'
  echo
  echo "== structure =="
  python3 tools/verify.py "$OUT/$APK_NAME"
  echo
  echo "== sha256 =="
  sha256sum "$OUT/$APK_NAME"
} | tee "$OUT/summary.txt"

log "Done: build/$APK_NAME"
