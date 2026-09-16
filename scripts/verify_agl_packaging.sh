#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBRARY="${1:-${ROOT_DIR}/build/native/libpipewire_telephony_native.so}"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

machine="$(readelf -h "${LIBRARY}" | sed -n 's/^  Machine:[[:space:]]*//p')"
"${ROOT_DIR}/scripts/validate_native_library.sh" "${LIBRARY}" "${machine}"

cmake -S "${ROOT_DIR}/linux" -B "${TEMP_DIR}/prebuilt" \
  -DPWT_PREBUILT_LIBRARY="$(realpath "${LIBRARY}")" \
  -DPWT_EXPECTED_ELF_MACHINE="${machine}"

if cmake -S "${ROOT_DIR}/linux" -B "${TEMP_DIR}/wrong-machine" \
  -DPWT_PREBUILT_LIBRARY="$(realpath "${LIBRARY}")" \
  -DPWT_EXPECTED_ELF_MACHINE="definitely-not-${machine}"; then
  echo "wrong ELF architecture was accepted" >&2
  exit 1
fi

if cmake -S "${ROOT_DIR}/native" -B "${TEMP_DIR}/host-as-target" \
  -DPWT_REQUIRE_CROSS_COMPILE=ON \
  -DPWT_BUILD_DART_INTEGRATION_TESTS=OFF \
  -DBUILD_TESTING=OFF; then
  echo "host compiler was accepted as a target toolchain" >&2
  exit 1
fi

mkdir -p "${TEMP_DIR}/wrong-abi"
printf '%s\n' 'int pwt_abi_version(void) { return 1; }' > \
  "${TEMP_DIR}/wrong-abi.c"
cc -shared -fPIC -Wl,-soname,libpipewire_telephony_native.so \
  -o "${TEMP_DIR}/wrong-abi/libpipewire_telephony_native.so" \
  "${TEMP_DIR}/wrong-abi.c"
if "${ROOT_DIR}/scripts/validate_native_library.sh" \
  "${TEMP_DIR}/wrong-abi/libpipewire_telephony_native.so" "${machine}"; then
  echo "wrong exported ABI was accepted" >&2
  exit 1
fi
