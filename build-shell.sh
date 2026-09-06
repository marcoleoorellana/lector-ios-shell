#!/usr/bin/env bash
# Compila el shell (binario + Info.plist + entitlements firmadas con ldid) SIN contenido.
# El IPA final se arma en Windows con lectordoc/scripts/make-ipa.mjs. Uso: ./build-shell.sh [build_number]
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${1:-1}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
APP=out/Lector.app
rm -rf out && mkdir -p "$APP"
swiftc -sdk "$SDK" -target arm64-apple-ios12.0 -O -o "$APP/Lector" main.swift
sed "s/BUILD_NUMBER/$BUILD/" Info.plist > "$APP/Info.plist"
ldid -S entitlements.plist "$APP/Lector"
(cd out && zip -qr ../Lector-shell.zip Lector.app)
ls -la Lector-shell.zip
