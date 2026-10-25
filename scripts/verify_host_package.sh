#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Use pub's own file selection, including .pubignore and submodule contents.
if ! dart pub --verbose publish --dry-run > "${TEMP_DIR}/publish.log" 2>&1; then
  tail -n 60 "${TEMP_DIR}/publish.log"
  exit 1
fi
awk -v root="${ROOT_DIR}/" '
  /^FINE: Creating \.tar\.gz stream containing:/ { copying = 1; next }
  copying && /^    \| / {
    path = substr($0, 7)
    if (index(path, root) == 1) path = substr(path, length(root) + 1)
    sub(/^\.\//, "", path)
    if (path ~ /^\// || path ~ /(^|\/)\.\.(\/|$)/) exit 1
    print path
    next
  }
  copying { exit }
  END { if (!copying) exit 1 }
' "${TEMP_DIR}/publish.log" > "${TEMP_DIR}/files"
test -s "${TEMP_DIR}/files"
mkdir -p "${TEMP_DIR}/archive"
# Listed directories must not recursively reintroduce excluded files.
tar --no-recursion --verbatim-files-from -T "${TEMP_DIR}/files" -cf - | \
  tar -xf - -C "${TEMP_DIR}/archive"
for excluded in task.md ARCHITECTURE.md .git .dart_tool build coverage; do
  if [[ -e "${TEMP_DIR}/archive/${excluded}" ]]; then
    echo "Excluded local path was packaged: ${excluded}" >&2
    exit 1
  fi
done
(cd "${TEMP_DIR}/archive" && flutter pub get)
(cd "${TEMP_DIR}/archive" && dart build cli \
  --target test/support/load_bundled_library.dart \
  --output "${TEMP_DIR}/archive-cli")
(cd "${TEMP_DIR}" && \
  "${TEMP_DIR}/archive-cli/bundle/bin/load_bundled_library")
tail -n 6 "${TEMP_DIR}/publish.log"
