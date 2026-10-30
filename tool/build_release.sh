#!/usr/bin/env bash
# Genera el APK de publicación de Nuvora con la versión en el nombre:
#   build/release/nuvora-<versión>-arm64.apk
# y avisa si quedó firmado con la clave de depuración (la firma propia se
# configura en android/key.properties).
#
# Uso (desde la raíz del proyecto):  tool/build_release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

version=$(sed -n 's/^version: *\([0-9.]*\)+\{0,1\}.*/\1/p' pubspec.yaml)
if [[ -z "$version" ]]; then
  echo "No se encontró 'version:' en pubspec.yaml" >&2
  exit 1
fi

flutter build apk --release --split-per-abi --target-platform android-arm64

mkdir -p build/release
apk="build/release/nuvora-${version}-arm64.apk"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$apk"

echo
echo "APK:     $apk"
echo "Tamaño:  $(du -h "$apk" | cut -f1)"
echo "SHA-256: $(sha256sum "$apk" | cut -d' ' -f1)"

# apksigner está en las build-tools del SDK de Android.
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
apksigner=$(ls -d "$sdk"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)
if [[ -n "$apksigner" ]]; then
  # Según la versión de apksigner la línea es "Signer #1 certificate DN: …" o
  # "V2 Signer: certificate DN: …".
  signer=$("$apksigner" verify --print-certs "$apk" | sed -n 's/^.*[Ss]igner.*certificate DN: //p' | head -1)
  echo "Firma:   $signer"
  if [[ "$signer" == *"Android Debug"* ]]; then
    echo
    echo "AVISO: el APK está firmado con la clave de DEPURACIÓN."
    echo "       No lo publiques: configura tu clave en android/key.properties."
    exit 2
  fi
else
  echo "Firma:   no se pudo comprobar (no se encontró apksigner en $sdk)"
fi
