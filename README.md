# Lector para iPad (app nativa)

App nativa Swift/UIKit para leer los documentos de `lectordoc` en un iPad Air 1 con jailbreak (iOS 12). Biblioteca, lector con la jerarquía de Google Docs, modo predicación, PIN + Touch ID, batería exacta y uso de Claude. Diseño en `DESIGN.md`.
No contiene contenido: carga `web/index.html` desde el bundle. El IPA se arma aparte copiando la web dentro de `Lector.app/web/`.

- `main.swift`: WKWebView a pantalla completa, links externos a Safari, recarga si muere el proceso web, pantalla siempre encendida.
- `build-shell.sh`: `swiftc` directo + `ldid` (sin proyecto Xcode). Corre en GitHub Actions (macOS) y publica `Lector-shell.zip` como release.
