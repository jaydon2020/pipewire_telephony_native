#!/bin/bash
set -euo pipefail

dbus-run-session -- env \
  PWT_NATIVE_LIB="$1" \
  PWT_MOCK_SERVER="$2" \
  dart test "$3"
