# Avisos de terceros

Las fuentes **Space Grotesk** (Florian Karsten y colaboradores) y **Manrope** (The Manrope Project Authors) se incluyen bajo SIL Open Font License 1.1. Sus textos se encuentran en `assets/fonts/SPACE_GROTESK_OFL.txt` y `assets/fonts/MANROPE_OFL.txt`.

Flutter y Dart conservan sus licencias originales. Las dependencias Dart usadas por el proyecto se documentarán aquí con la versión fijada en `pubspec.lock` antes de distribuir binarios. La licencia CC BY-NC 4.0 del contenido original no cambia las licencias de terceros.

Dependencias directas verificadas en el caché de `pub.dev` el 16 de noviembre de 2026:

| Paquete | Versión resuelta | Licencia |
| --- | --- | --- |
| `sqlite3` | 3.9.1 | MIT |
| `path_provider` | 2.1.6 | BSD de Flutter |
| `file_selector` | 1.1.0 | BSD de Flutter |
| `fl_chart` | 1.3.1 | MIT |
| `shared_preferences` | 2.5.6 | BSD de Flutter |
| `url_launcher` | 6.3.3 | BSD de Flutter |
| `crypto` | 3.0.8 | BSD de Dart |
| `uuid` | 4.6.0 | MIT |
| `material_ui` | 1.11.1 | BSD de Flutter |
| `data` | 0.15.2 | MIT |
| `archive` | 4.7.1 | MIT |
| `pdf` | 3.13.1 | Apache-2.0 |
| `dbus` | 0.8.0 | MPL-2.0 |
| `bonsoir` y sus adaptadores | Versiones fijadas en `pubspec.lock` | MIT |

Los textos completos de dependencias transitivas se encuentran en sus paquetes, fijados en `pubspec.lock`; la distribución binaria debe incluir el listado de licencias generado por Flutter.

La herramienta opcional `tools/verify_export.py` y el generador de referencias
usan paquetes Python que **no se incluyen ni se ejecutan en la aplicación**:

| Paquete | Licencia del proyecto | Texto oficial |
| --- | --- | --- |
| NumPy | BSD-3-Clause | [LICENSE.txt](https://github.com/numpy/numpy/blob/main/LICENSE.txt) |
| pandas | BSD-3-Clause | [LICENSE](https://github.com/pandas-dev/pandas/blob/main/LICENSE) |
| SciPy | BSD-3-Clause | [LICENSE.txt](https://github.com/scipy/scipy/blob/main/LICENSE.txt) |
| Matplotlib | Acuerdo de licencia de Matplotlib, basado en PSF | [LICENSE](https://github.com/matplotlib/matplotlib/blob/main/LICENSE/LICENSE) |

Quien redistribuya los paquetes Python instalados debe conservar además los
avisos de los componentes incluidos en cada paquete o rueda binaria.
