#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${OE_CMAKE_TOOLCHAIN_FILE:?source the AGL SDK environment setup first}"
: "${SDKTARGETSYSROOT:?AGL SDK did not define SDKTARGETSYSROOT}"
: "${PKG_CONFIG_SYSROOT_DIR:?AGL SDK did not define PKG_CONFIG_SYSROOT_DIR}"
: "${PWT_EXPECTED_ELF_MACHINE:?set the readelf Machine value for the AGL target}"

[[ -f "${OE_CMAKE_TOOLCHAIN_FILE}" ]] || {
  echo "toolchain file does not exist: ${OE_CMAKE_TOOLCHAIN_FILE}" >&2
  exit 1
}
[[ -d "${SDKTARGETSYSROOT}" ]] || {
  echo "target sysroot does not exist: ${SDKTARGETSYSROOT}" >&2
  exit 1
}

target_name="${MACHINE:-agl-target}"
build_dir="${1:-${ROOT_DIR}/build/agl-${target_name}}"
cmake -S "${ROOT_DIR}/native" -B "${build_dir}" -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="${OE_CMAKE_TOOLCHAIN_FILE}" \
  -DPWT_REQUIRE_CROSS_COMPILE=ON \
  -DPWT_BUILD_DART_INTEGRATION_TESTS=OFF \
  -DBUILD_TESTING=OFF
cmake --build "${build_dir}" --parallel
"${ROOT_DIR}/scripts/validate_native_library.sh" \
  "${build_dir}/libpipewire_telephony_native.so" \
  "${PWT_EXPECTED_ELF_MACHINE}"
