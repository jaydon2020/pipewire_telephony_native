#!/bin/bash
set -euo pipefail

mapfile -t bus < <(
  dbus-daemon --session --fork --print-address=1 --print-pid=1
)
export DBUS_SESSION_BUS_ADDRESS="${bus[0]}"
bus_pid="${bus[1]}"
trap 'kill "${bus_pid}" 2>/dev/null || true' EXIT

PWT_NATIVE_LIB="$1" PWT_MOCK_SERVER="$2" \
  flutter test --timeout 30s test/telephony_screen_test.dart
