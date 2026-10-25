#!/bin/bash
# Patterned after https://github.com/jwinarske/bluez_native/blob/main/scripts/coverage.sh.
# Derived portions are Copyright 2026 Joel Winarske under Apache-2.0; see
# LICENSES/Apache-2.0.txt. Subsequent modifications are Copyright 2026 Jian De
# under the package's BSD-3-Clause license.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-${ROOT_DIR}/build-coverage}"

cmake -S "${ROOT_DIR}/native" -B "${BUILD_DIR}" -GNinja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS=--coverage \
  -DCMAKE_CXX_FLAGS=--coverage \
  -DCMAKE_EXE_LINKER_FLAGS=--coverage \
  -DBUILD_TESTING=ON
cmake --build "${BUILD_DIR}" --parallel
ctest --test-dir "${BUILD_DIR}" --output-on-failure

if ! find "${BUILD_DIR}" -name '*.gcda' -print -quit | grep -q .; then
  echo "No coverage data yet; native tests are introduced in later tasks."
  exit 0
fi

lcov --capture \
  --directory "${BUILD_DIR}/CMakeFiles/pipewire_telephony_native_core.dir" \
  --directory "${BUILD_DIR}/CMakeFiles/pipewire_telephony_native.dir" \
  --exclude '*/third_party/*' --exclude '/usr/*' \
  --output-file "${BUILD_DIR}/coverage.info"
lcov --summary "${BUILD_DIR}/coverage.info"
