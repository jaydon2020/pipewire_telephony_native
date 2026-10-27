#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 Joel Winarske <joel.winarske@gmail.com>
# SPDX-FileCopyrightText: 2026 Jian De Seak

# Patterned after
# https://github.com/jwinarske/bluez_native/blob/main/scripts/coverage.sh.
# Adapted from bluez_native; see THIRD_PARTY_NOTICES.md.
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
