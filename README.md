# Lector para iPad (app nativa)

App **nativa Swift/UIKit** (no un shell alrededor de una web) para leer los documentos de `lectordoc` en un iPad Air 1 con jailbreak (iOS 12). Biblioteca, lector con la jerarquía de Google Docs, modo predicación, PIN + Touch ID, batería exacta por IORegistry y uso de Claude. Diseño en `DESIGN.md`.

El único WebView es el del lector: renderiza el HTML del documento envuelto en CSS propio, con **Figtree** embebida como `data:` URI. El resto de la interfaz es UIKit.

## Contenido

No vive en este repo. El IPA se arma copiando `content/` dentro de `Lector.app/content/`:

- `content/docs.json` — manifiesto (`id`, `slug`, `title`, `path`, `minutes`, `modifiedTime`…). Los `path` tienen que empezar con `docs/`.
- `content/docs/*.html` — cada documento.
- `content/styles.json` — estilos con nombre de Google Docs (tamaños en pt, negrita/cursiva/subrayado).

En Ajustes se puede configurar un origen HTTP para sincronizar esos tres artefactos sin rearmar el IPA.

## Fuentes

- `Sources/main.swift` — AppDelegate: navigation controller, PIN al abrir, cubierta opaca en segundo plano.
- `Sources/LibraryViewController.swift` — biblioteca, "seguir leyendo", búsqueda, pull to refresh.
- `Sources/ReaderViewController.swift` — lector (WKWebView + CSS propio), predicación, progreso, popover "Aa".
- `Sources/Content.swift` — manifiesto, HTML, progreso y sincronización remota.
- `Sources/Theme.swift` — paletas, tipografía y preferencias.
- `Sources/Pin.swift`, `Battery.swift`, `ClaudeUsage.swift`, `SettingsViewController.swift`, `DebugSnap.swift`.

## Build e instalación

1. `build-shell.sh` compila con `swiftc` directo + `ldid` (sin proyecto Xcode) y publica `Lector-shell.zip`. Corre en GitHub Actions (macOS); **no hay compilador local en Windows**.
2. `lectordoc/scripts/make-ipa.mjs` toma ese `Lector.app`, le mete `content/` y arma el IPA.
3. Se instala en el iPad con `pymobiledevice3`.

## Detalles

- **PIN**: por defecto `224466` (el mismo de la PWA). Se guarda solo el hash, nunca sale del iPad; 5 fallos seguidos = 30 s de espera.
- **Depuración por snapshot**: con `Documents/snap.on` presente, la app guarda `Documents/snap.png` cada 2 s (se lee por SSH). `Documents/snap.open` con un id de doc lo abre al arrancar, y `snap.preach` entra en predicación. Se pausa en segundo plano.
