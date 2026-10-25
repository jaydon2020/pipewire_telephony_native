#!/bin/bash
# Patterned after https://github.com/jwinarske/bluez_native/blob/main/scripts/asan.sh.
# Derived portions are Copyright 2026 Joel Winarske under Apache-2.0; see
# LICENSES/Apache-2.0.txt. Subsequent modifications are Copyright 2026 Jian De
# under the package's BSD-3-Clause license.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-${ROOT_DIR}/build-asan}"
CC="${CC:-$(command -v clang-21 || command -v clang)}"
CXX="${CXX:-$(command -v clang++-21 || command -v clang++)}"

cmake -S "${ROOT_DIR}/native" -B "${BUILD_DIR}" -GNinja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined" \
  -DPWT_BUILD_DART_INTEGRATION_TESTS=OFF \
  -DBUILD_TESTING=ON
cmake --build "${BUILD_DIR}" --parallel
ctest --test-dir "${BUILD_DIR}" --output-on-failure
