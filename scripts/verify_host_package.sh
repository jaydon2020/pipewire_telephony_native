#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_REF="${PWT_ARCHIVE_REF:-HEAD}"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

cd "${ROOT_DIR}"
cp lib/src/ffi/bindings_generated.dart "${TEMP_DIR}/bindings_generated.dart"
cp -r native/generated "${TEMP_DIR}/generated"
dart run ffigen --config ffigen.yaml
"${ROOT_DIR}/scripts/generate_proxies.sh"
diff -u "${TEMP_DIR}/bindings_generated.dart" lib/src/ffi/bindings_generated.dart
diff -ru "${TEMP_DIR}/generated" native/generated

(cd example/flutter_telephony && flutter build linux --debug)
BUNDLE="${ROOT_DIR}/example/flutter_telephony/build/linux/x64/debug/bundle"
LIBRARY="${BUNDLE}/lib/libpipewire_telephony_native.so"
test -f "${LIBRARY}"

expected=$'pwt_abi_version\npwt_client_create\npwt_client_destroy\npwt_client_start\npwt_client_stop\npwt_client_submit\npwt_free\npwt_initialize_dart_api_dl\npwt_library_path'
actual="$(nm -D --defined-only "${LIBRARY}" | awk '{print $3}' | sort)"
test "${actual}" = "${expected}"

dart compile exe test/support/load_bundled_library.dart \
  -o "${BUNDLE}/load_bundled_library"
sibling_libraries=()
for candidate in \
  "${ROOT_DIR}/../bluez_native/lib/libbluez_nc.so" \
  "${ROOT_DIR}/../bluez_media_native/build/libbluez_media_native.so" \
  "${ROOT_DIR}/../bluez_obex_native/build/libbluez_obex_native.so"; do
  [[ -f "${candidate}" ]] && sibling_libraries+=("${candidate}")
done
unset PWT_NATIVE_LIB
(cd "${TEMP_DIR}" && "${BUNDLE}/load_bundled_library" "${sibling_libraries[@]}")

mkdir -p "${TEMP_DIR}/archive"
git archive "${ARCHIVE_REF}" | tar -x -C "${TEMP_DIR}/archive"
mkdir -p "${TEMP_DIR}/archive/native/third_party/sdbus-cpp"
git -C native/third_party/sdbus-cpp archive HEAD | \
  tar -x -C "${TEMP_DIR}/archive/native/third_party/sdbus-cpp"
cmake -S "${TEMP_DIR}/archive/native" -B "${TEMP_DIR}/archive-build" \
  -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
  -DPWT_BUILD_DART_INTEGRATION_TESTS=OFF
cmake --build "${TEMP_DIR}/archive-build" --parallel
test -f "${TEMP_DIR}/archive-build/libpipewire_telephony_native.so"
