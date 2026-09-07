#!/usr/bin/env bash
# Compila la app (binario + Info.plist + fuentes, firmada con ldid) SIN contenido.
# El IPA final se arma en Windows con lectordoc/scripts/make-ipa.mjs. Uso: ./build-shell.sh [build_number]
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${1:-1}"
export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "SDK: $SDKROOT"
APP=out/Lector.app
rm -rf out && mkdir -p "$APP/fonts"

xcrun -sdk iphoneos swiftc -sdk "$SDKROOT" -target arm64-apple-ios12.0 -O \
  -framework UIKit -framework WebKit -framework LocalAuthentication -framework Security -framework IOKit \
  -o "$APP/Lector" Sources/*.swift

file "$APP/Lector"
otool -l "$APP/Lector" | grep -q 'platform 2\|LC_VERSION_MIN_IPHONEOS' || { echo "ERROR: el binario no es de iOS"; exit 1; }

sed "s/BUILD_NUMBER/$BUILD/" Info.plist > "$APP/Info.plist"
cp fonts/*.ttf fonts/OFL.txt "$APP/fonts/"
ldid -Sentitlements.plist -Icom.marcoleoorellana.lector "$APP/Lector"
ldid -e "$APP/Lector" | head -8
(cd out && zip -qr ../Lector-shell.zip Lector.app)
ls -la Lector-shell.zip
