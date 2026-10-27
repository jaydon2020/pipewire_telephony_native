#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 Joel Winarske <joel.winarske@gmail.com>
# SPDX-FileCopyrightText: 2026 Jian De Seak

# Patterned after
# https://github.com/jwinarske/bluez_native/blob/main/scripts/clang_format.sh.
# Adapted from bluez_native; see THIRD_PARTY_NOTICES.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-check}"
CLANG_FORMAT="${CLANG_FORMAT:-$(command -v clang-format-21 || command -v clang-format)}"

mapfile -t FILES < <(
  find "${ROOT_DIR}/native/include" "${ROOT_DIR}/native/src" "${ROOT_DIR}/native/test" \
    -type f \( -name '*.c' -o -name '*.cpp' -o -name '*.h' \) \
    ! -path '*/internal/*' \
    ! -name 'dart_api.h' \
    ! -name 'dart_api_dl.h' \
    ! -name 'dart_api_dl.c' \
    ! -name 'dart_native_api.h' \
    ! -name 'dart_version.h' | sort
)

case "${MODE}" in
  check)
    "${CLANG_FORMAT}" --dry-run --Werror "${FILES[@]}"
    ;;
  fix)
    "${CLANG_FORMAT}" -i "${FILES[@]}"
    ;;
  *)
    echo "usage: $0 [check|fix]" >&2
    exit 2
    ;;
esac
