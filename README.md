# lector-ios-shell

Shell nativo (Swift/UIKit + WKWebView) para correr una web app empaquetada en un iPad viejo con jailbreak (iOS 12+).
No contiene contenido: carga `web/index.html` desde el bundle. El IPA se arma aparte copiando la web dentro de `Lector.app/web/`.

- `main.swift`: WKWebView a pantalla completa, links externos a Safari, recarga si muere el proceso web, pantalla siempre encendida.
- `build-shell.sh`: `swiftc` directo + `ldid` (sin proyecto Xcode). Corre en GitHub Actions (macOS) y publica `Lector-shell.zip` como release.
