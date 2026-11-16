# Compilación

Instale Flutter estable y las herramientas de cada sistema. Para Android configure Android SDK y firma propia; ejecute `flutter build apk --release --split-per-abi`. Para Windows use un host Windows con Visual Studio C++ y `flutter build windows --release`. Para Linux instale GTK 3, CMake, Ninja y Clang y ejecute `flutter build linux --release`. Distribuya los bundles completos y compruebe checksums. No suba llaves privadas.

Tras compilar Android y Linux, `bash scripts/package_local_artifacts.sh` genera tres APK, un tarball Linux y `dist/SHA256SUMS`. Compruebe el contenido con `cd dist && sha256sum -c SHA256SUMS`. Los artefactos locales están excluidos de Git.

El proyecto generado por Flutter usa actualmente la clave de depuración para el tipo `release` de Gradle. Los APK de CI sirven para evaluación, **no para publicación**. Antes de una distribución oficial configure un keystore de producción fuera del repositorio, sustituya la firma de Gradle y repita el build en CI. El empaquetado Windows debe hacerse y probarse en un runner Windows; no se infiere desde el build Linux.
