#!/bin/bash
set -euo pipefail

mapfile -t bus < <(
  dbus-daemon --session --fork --print-address=1 --print-pid=1
)
export DBUS_SESSION_BUS_ADDRESS="${bus[0]}"
export PWT_TEST_BUS_PID="${bus[1]}"
trap 'kill "${PWT_TEST_BUS_PID}" 2>/dev/null || true' EXIT

PWT_NATIVE_LIB="$1" PWT_MOCK_SERVER="$2" dart test "$3"
