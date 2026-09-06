#!/usr/bin/env bash
# Compila el shell (binario + Info.plist + entitlements firmadas con ldid) SIN contenido.
# El IPA final se arma en Windows con lectordoc/scripts/make-ipa.mjs. Uso: ./build-shell.sh [build_number]
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${1:-1}"
export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "SDK: $SDKROOT"
APP=out/Lector.app
rm -rf out && mkdir -p "$APP"

xcrun -sdk iphoneos swiftc -sdk "$SDKROOT" -target arm64-apple-ios12.0 -O -o "$APP/Lector" main.swift

# Verificacion: tiene que ser Mach-O arm64 para iOS, no macOS.
file "$APP/Lector"
otool -l "$APP/Lector" | grep -A4 'LC_BUILD_VERSION\|LC_VERSION_MIN_IPHONEOS' | head -8
otool -l "$APP/Lector" | grep -q 'platform 2\|LC_VERSION_MIN_IPHONEOS' || { echo "ERROR: el binario no es de iOS"; exit 1; }

sed "s/BUILD_NUMBER/$BUILD/" Info.plist > "$APP/Info.plist"
ldid -Sentitlements.plist -Icom.marcoleoorellana.lector "$APP/Lector"
ldid -e "$APP/Lector" | head -12
(cd out && zip -qr ../Lector-shell.zip Lector.app)
ls -la Lector-shell.zip
