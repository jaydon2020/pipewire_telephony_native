#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 Joel Winarske <joel.winarske@gmail.com>
# SPDX-FileCopyrightText: 2026 Jian De

# Patterned after
# https://github.com/jwinarske/bluez_native/blob/main/scripts/clang_tidy.sh.
# Adapted from bluez_native; see THIRD_PARTY_NOTICES.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-${ROOT_DIR}/build/native}"
CLANG_TIDY="${CLANG_TIDY:-$(command -v clang-tidy-21 || command -v clang-tidy-19 || command -v clang-tidy)}"

if [[ ! -f "${BUILD_DIR}/compile_commands.json" ]]; then
  echo "compile_commands.json not found in ${BUILD_DIR}" >&2
  exit 1
fi

mapfile -t FILES < <(
  find "${ROOT_DIR}/native/src" "${ROOT_DIR}/native/test" \
    -type f \( -name '*.c' -o -name '*.cpp' \) \
    ! -name 'dart_api_dl.c' | sort
)

"${CLANG_TIDY}" -p "${BUILD_DIR}" --warnings-as-errors='*' "${FILES[@]}"
