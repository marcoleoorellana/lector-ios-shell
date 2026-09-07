# DESIGN.md — Lector

Sistema de diseño de la app nativa Lector (iPad Air 1, iOS 12). Minimalista al estilo Geist: estructura antes que decoración. Un solo acento: negro.

## Tipografía
- **Figtree** en todo (interfaz y lectura), empaquetada en `fonts/`. Pesos: 400, 500, 600, 700 + cursivas reales.
- Lectura: 19 px base (ajustable 14–30), interlineado 1.45, medida 640 px. Predicación: 27 px base, medida 720 px.
- Metadatos (fechas, %, cronómetro, etiquetas de sección): monoespaciada del sistema 12–13 px, numerales tabulares, mayúsculas con tracking 0.06em.
- Jerarquía de los documentos: viene de Google Docs (`styles.json`, estilos con nombre). Tamaños en pt escalados con amortiguación (`1 + (pt/normal − 1) × 0.55`) para que el Título no ocupe media pantalla. Negrita, cursiva y subrayado se respetan tal cual.

## Color
| Rol | Claro | Sepia | Oscuro |
|---|---|---|---|
| Fondo | #FFFFFF | #F7F3EA | #000000 |
| Texto | #171717 | #2B2620 | #EDEDED |
| Secundario | #666666 | #6E6558 | #A1A1A1 |
| Líneas | #EBEBEB | #E6DFD2 | #2A2A2A |

Resaltados de Docs (`mark.tone-*`): mismo tono al 35% de opacidad + subrayado de 2 px del mismo color. En predicación, 55%. Amarillo = palabra clave, cian = versículo/afirmación, lima = cita de autor, lavanda = nota, naranja = subtítulo, verde = título. El fondo gris del Encabezado 1 de Docs se convierte en una barra lateral de 4 px #434343.

## Espacio y superficies
- Escala 4 · 8 · 12 · 16 · 24 · 32 · 48. Márgenes laterales 32. Objetivos táctiles ≥ 44.
- Sin sombras, sin degradados, sin tarjetas. Separación por líneas de 1 px y espacio. Radio 8 solo en controles.
- Movimiento: solo las transiciones del sistema.

## Anti-patrones
Chips de colores, íconos rellenos, badges, tarjetas con borde de color, emoji en la interfaz, fondos de color en encabezados, más de un acento.
