#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 Joel Winarske <joel.winarske@gmail.com>
# SPDX-FileCopyrightText: 2026 Jian De Seak

# ThreadSanitizer variant of scripts/asan.sh, which is patterned after
# https://github.com/jwinarske/bluez_native/blob/main/scripts/asan.sh.
# Adapted from bluez_native; see THIRD_PARTY_NOTICES.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-${ROOT_DIR}/build-tsan}"
CC="${CC:-$(command -v clang-21 || command -v clang)}"
CXX="${CXX:-$(command -v clang++-21 || command -v clang++)}"

cmake -S "${ROOT_DIR}/native" -B "${BUILD_DIR}" -GNinja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="-fsanitize=thread -fno-omit-frame-pointer" \
  -DCMAKE_CXX_FLAGS="-fsanitize=thread -fno-omit-frame-pointer" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=thread" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=thread" \
  -DPWT_BUILD_DART_INTEGRATION_TESTS=OFF \
  -DBUILD_TESTING=ON
cmake --build "${BUILD_DIR}" --parallel
ctest --test-dir "${BUILD_DIR}" --output-on-failure
