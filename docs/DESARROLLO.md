# Nuvora: guía técnica

Detalles de funcionamiento, desarrollo y limitaciones de Nuvora (`nuvora_scanner`). Para la presentación del producto, ver el [README](../README.md).

Stack: Flutter + OpenCV (`opencv_dart`) + SQLite (`drift`). Todo corre en el dispositivo, sin servidores.

---

## Requisitos para usar la app

| | |
|---|---|
| **Android mínimo** | **7.0 Nougat (API 24)** |
| Android objetivo | 16 (API 36) |
| Arquitectura | **arm64-v8a** (64 bits). Los teléfonos de 32 bits no están soportados en el APK actual. |
| Hardware | Cámara trasera (obligatoria según el manifest) |
| Permisos | Cámara. Importar de la galería usa el selector de fotos de Android, que no pide permiso. |
| Espacio | ~32 MB la app, más ~1–3 MB por página escaneada (original + procesada + miniatura) |

El mínimo de API 24 lo impone el plugin de cámara (CameraX) junto con el mínimo por defecto de Flutter 3.44.

## Funcionalidades en detalle

**Captura (una foto a la vez)**
- La cámara dibuja **en vivo** el borde del documento detectado (en verde cuando está estable).
- Cada foto abre la revisión en dos pasos:
  1. **Bordes:** el detector propone las esquinas y se pueden ajustar con lupa. Hay botones "Detección automática" y "Usar imagen completa".
  2. **Vista previa:** se ve cómo quedará la página (recorte + tamaño de papel + filtro + rotación). Se puede elegir el tamaño y el filtro, y girarla.
- "Agregar y seguir" guarda la página en el acto y vuelve a la cámara. "Agregar y terminar" abre el documento.
- Linterna, y enfoque y exposición al tocar.
- Importación desde la galería: las imágenes elegidas pasan de a una por la misma revisión.

**Detección de bordes (OpenCV clásico, sin red neuronal)**
- **Genera candidatos** de tres formas:
  - Contornos de varios mapas de bordes (Canny con umbrales según el gradiente, y Canny sobre la saturación).
  - Regiones claras (Otsu).
  - Líneas rectas (Hough).
- **Soporta hojas que se salen del cuadro:** los bordes de la foto cuentan como lados posibles.
- **Elige el mejor candidato** según el soporte de borde y el contraste a lo largo de cada lado, la uniformidad del interior (descarta pantallas, caras y muebles), el área y la rectangularidad.
- **Resultado medido** con el banco de fotos reales: IoU de 0.94 a 0.99 y error medio por esquina ≤ 2 % de la diagonal. Tarda 7–100 ms por foto en el PC.
- En vivo usa una versión rápida del mismo detector, en un isolate aparte, a unos 8 cuadros por segundo.
- Corrección de perspectiva. El resultado se limita a 3508 px en el lado largo (A4 a 300 dpi).

**Tamaño de papel (Carta / Oficio)**
- La perspectiva de la foto deforma las proporciones, así que la app **estima la proporción real de la hoja** a partir de sus 4 esquinas (método de Zhang y He; la distancia focal se estima del propio cuadrilátero).
- En modo **Auto** ajusta la página a **Carta** (21.6 × 27.9 cm) u **Oficio** (21.6 × 34 cm, la medida mexicana), la más cercana. Lo que no se parece a ninguno (recibos, credenciales) se deja como está.
- Si la hoja se sale de la foto, Auto solo ajusta cuando lo visible ya está a menos del 5 % de Carta u Oficio, para no deformarla de más.
- **El documento no se deforma.** Si su proporción real difiere del papel en más de 3 %, se recorta con su proporción real y se coloca sobre una hoja blanca del tamaño elegido, arriba y centrado a lo ancho, como al imprimir una carta en papel oficio. Con 3 % o menos se ajusta exacto: es error de medición y no se nota.
- Se puede elegir a mano: Auto, Carta, Oficio, A4 u Original. La elección se recuerda para la siguiente foto y se puede cambiar después en el editor de página.
- La página conserva la resolución medida en la foto (no se agranda); solo se ajusta la proporción.

**Filtros**
- **Original** y **Grises**.
- **Mejorado**, el predeterminado. Busca el aspecto de un escaneo:
  1. Quita la sombra dividiendo cada canal entre su fondo estimado.
  2. Aplica niveles (punto blanco, punto negro y curva gamma) para dejar el papel blanco puro y el texto negro.
  3. Realza un poco el color, para que firmas y sellos no queden grises.
  4. Enfoca levemente.
- **B/N**: la misma limpieza y luego un corte a blanco o negro, que conserva los trazos finos.
- El último filtro usado queda como predeterminado para la siguiente foto.

**Documentos**
- Documentos de varias páginas: agregar páginas, reordenarlas arrastrando y borrarlas.
- Edición de cada página: cambiar filtro, girar ±90°, volver a recortar.
- Toda edición se recalcula desde la foto original, así que la calidad no se degrada.

**Biblioteca**
- Carpetas (crear, renombrar, borrar). Al borrar una carpeta, sus documentos pasan a Inicio.
- Documentos con portada, número de páginas y fecha. Renombrar, mover y borrar.
- Búsqueda por título.

**Exportar y compartir**
- PDF con el tamaño de papel de cada página (Carta, Oficio o A4, a página completa). Las páginas de tamaño libre van en A4 con la imagen centrada. Vertical u horizontal según la página, y las imágenes se incrustan sin recomprimir.
- Compartir el PDF o las imágenes por el menú nativo de Android.

**Mantenimiento automático**
- Al iniciar, borra las capturas sin guardar, los PDFs ya compartidos y las carpetas de páginas huérfanas.

## Requisitos para desarrollar

| Herramienta | Versión usada |
|---|---|
| Flutter | 3.44.4 (stable) |
| Dart | 3.12.2 |
| Java | 21 |
| Android SDK | platforms 34–36, NDK 28.2.13676358 |
| CMake / Ninja | para compilar el envoltorio nativo de OpenCV |

La **primera compilación** de cada plataforma descarga OpenCV 4.13 precompilado (necesita Internet) y compila el envoltorio nativo. Tarda unos 3–4 minutos; después queda en caché en `.dart_tool/`. Solo se compilan los módulos `core`, `imgproc` e `imgcodecs` (ver `hooks:` en `pubspec.yaml`).

```bash
flutter pub get
dart run build_runner build          # regenera el código de drift (app_database.g.dart)
flutter run                          # teléfono conectado con depuración USB
flutter test                         # 66 pruebas; corren en el host (Linux) con OpenCV nativo
flutter analyze
flutter build apk --release --split-per-abi --target-platform android-arm64
```

## Ícono

- `assets/branding/nuvora.png`: logo completo (ícono clásico y logo dentro de la app).
- `assets/branding/nuvora_foreground.png`: frente del ícono adaptativo, solo el contenido del logo sobre transparente. Se genera con `python3 tool/make_adaptive_foreground.py` (requiere Pillow).
- Los `mipmap-*` de Android se regeneran con `dart run flutter_launcher_icons` (configuración en `pubspec.yaml`).

## Estructura

```
lib/
  app/                 MaterialApp, tema y rutas (go_router)
  core/
    imaging/           pipeline de OpenCV (sin dependencias de Flutter): detección, perspectiva, filtros
    db/                tablas y base de datos drift
    storage/           FileStore: rutas de archivos y limpieza
    ui/                diálogos y formato compartidos
  features/
    library/           biblioteca, carpetas y repositorio de datos
    capture/           cámara y sesión de escaneo
    crop/              editor de esquinas y pantallas de recorte
    document/          documento, editor de página y PageService
    export/            PDF y compartir
```

**Archivos en el dispositivo** (directorio privado de la app):
- `scanner.sqlite`
- `pages/<uuid>/original.jpg`
- `pages/<uuid>/processed_r<N>.jpg`
- `pages/<uuid>/thumb_r<N>.jpg`

El esquema de la base va en la versión 2 (agrega el tamaño de papel por página); las bases v1 se migran solas al abrir la app.

La base guarda rutas relativas. El número de revisión `N` cambia con cada edición para que no se muestren imágenes cacheadas.

---

## Lo que NO cubre esta versión (limitaciones y pendientes)

### Funciones que no existen todavía
- **OCR / texto reconocido.** No hay reconocimiento de texto, búsqueda por contenido ni PDF con texto seleccionable. La columna `pages.ocr_text` está reservada para la fase 2.
- **Red neuronal para los bordes.** Está planificada como fase siguiente: DocAligner `lcnet100` (Apache-2.0, ONNX de 4.8 MB) sobre OpenCV dnn, con el detector clásico como refinamiento y respaldo. Requiere compilar OpenCV con el módulo `dnn`.
- **Captura automática** cuando el documento está estable.
- **Deshacer.** Los borrados (páginas, documentos, carpetas) son definitivos, aunque piden confirmación.
- **Herramientas de PDF:**
  - PDF con contraseña.
  - Firmas, anotaciones y marcas de agua.
  - Modo cédula/ID (dos caras en una hoja).
  - Unir o dividir documentos.
  - Exportar varios documentos a la vez.
- **Pantalla de ajustes.** El tamaño de página "ajustado a la imagen" existe en el código (`PdfPageSize.fitImage`), pero no hay opción en la interfaz. La calidad JPEG y la resolución máxima son fijas.
- **Carpetas anidadas en la interfaz.** La base de datos las soporta, pero la UI solo maneja un nivel.
- **Ordenar** la biblioteca por nombre o fecha a elección. Hoy siempre aparece primero lo más reciente.
- **Guardar el PDF en Descargas.** Solo se puede compartir; el archivo exportado vive en la caché y se borra al reiniciar la app.

### Datos y respaldo
- **No hay respaldo ni sincronización.** Todo vive en el almacenamiento privado de la app, así que **desinstalarla o borrar sus datos elimina todos los documentos**. Tampoco hay exportación o importación de la biblioteca completa.
- No hay cifrado de la base ni de las imágenes más allá del aislamiento de Android.

### Plataformas y distribución
- **Solo Android.** No hay proyecto iOS, web ni escritorio. El código Dart es portable, pero iOS requiere una Mac para compilar.
- **Solo arm64.** Para 32 bits (armeabi-v7a) o emuladores x86_64 hay que agregar `--target-platform android-arm,android-x64`. Cada arquitectura nueva compila su propia versión de OpenCV.
- **Firma.** El release se firma con la clave de `android/key.properties` (fuera de git). Si ese archivo no existe, se usa la clave de depuración. `tool/build_release.sh` genera el APK de publicación y avisa si quedó firmado con la clave de depuración.
- **Identidad visual.** El id de Android es `dev.cervz.nuvora`. El ícono del launcher se genera desde `assets/branding/` (ver "Ícono" más arriba).
- **Tamaño.** El APK pesa ~32 MB porque Android guarda sin comprimir `libflutter.so` (~11 MB) y `libdartcv.so` (~11 MB). En Play Store con App Bundle la descarga sería menor.
- **Permisos de los plugins.** Además de la cámara, los plugins agregan `ACCESS_NETWORK_STATE` y `READ_EXTERNAL_STORAGE`. La app no los usa. Se quitaron `RECORD_AUDIO` y `WRITE_EXTERNAL_STORAGE`, y no se declara `INTERNET`.

### Calidad y pruebas
- **Calibración con pocas fotos.** El detector se ajustó con solo 6 fotos reales (`test/fixtures/real/`, fuera de git porque contienen datos personales). Falta probarlo con más casos: poca luz, hojas arrugadas, hoja blanca sobre mesa blanca, varias hojas encimadas o recibos angostos.
- **Contorno en vivo sin verificar en el teléfono.** La conversión de coordenadas del sensor a la pantalla asume la orientación habitual de la cámara trasera, y la pantalla de cámara se bloquea en vertical. En algunos equipos CameraX no admite el análisis en vivo junto con la foto a máxima resolución; en ese caso no se muestra el contorno, pero la foto sí se detecta.
- **Filtros calibrados con pocas fotos.** "Mejorado" y "B/N" se ajustaron con las mismas 6 fotos, que además vienen comprimidas por WhatsApp. Con el banco `test/imaging/filter_bench_test.dart`, "Mejorado" deja entre 81 % y 93 % de la página en blanco puro y el texto casi negro. Falta probarlos con papel de color, fotos con poca luz y documentos con imágenes o fotografías.
- **Tamaño de papel automático.** La estimación de proporción supone que el centro óptico está en el centro de la foto y que la imagen no está recortada. Las fotos recortadas (por ejemplo, las que reenvía WhatsApp) o los modos de cámara 16:9/20:9 pueden desviar un poco la estimación. Si Auto se equivoca entre Carta y Oficio, se puede elegir a mano.
- **Sin pruebas de integración** del flujo completo en el dispositivo (`integration_test`), ni de las pantallas de cámara, recorte y documento.
- **Rendimiento y memoria** no medidos en teléfonos de gama baja ni con documentos grandes (20+ páginas).
- **Accesibilidad** no auditada (TalkBack, contraste, tamaños de texto grandes).
- **Diseño para tablets y horizontal** no adaptado.
- **Idioma.** Los textos están fijos en español, sin internacionalización (`intl`/ARB).

### Comportamientos a tener en cuenta
- Las páginas se guardan al tocar "Agregar", así que lo agregado no se pierde si se cierra la app. Solo se pierde la foto que estaba en revisión.
- Un documento puede quedar sin páginas si se borran todas; no se elimina automáticamente.
- La búsqueda solo compara el título, sin ignorar acentos ("recibo" no encuentra "Recibó").
- No hay forma de cancelar de golpe una importación de muchas imágenes: hay que descartarlas de a una o tocar "Agregar y terminar".
- Si se niega el permiso de cámara de forma permanente, la app solo explica cómo activarlo en Ajustes; no abre los ajustes directamente.
