#!/bin/bash
set -euo pipefail

mapfile -t session_bus < <(
  dbus-daemon --session --fork --print-address=1 --print-pid=1
)
mapfile -t system_bus < <(
  dbus-daemon --session --fork --print-address=1 --print-pid=1
)

export DBUS_SESSION_BUS_ADDRESS="${session_bus[0]}"
export DBUS_SYSTEM_BUS_ADDRESS="${system_bus[0]}"
export PWT_AUTO_SYSTEM_BUS_ADDRESS="${system_bus[0]}"
session_pid="${session_bus[1]}"
system_pid="${system_bus[1]}"
trap 'kill "${session_pid}" "${system_pid}" 2>/dev/null || true' EXIT

PWT_NATIVE_LIB="$1" PWT_MOCK_SERVER="$2" dart test "$3"
DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/pwt-unreachable-session-$$" \
  PWT_NATIVE_LIB="$1" \
  PWT_MOCK_SERVER="$2" \
  PWT_AUTO_SYSTEM_BUS_ADDRESS="${system_bus[0]}" \
  PWT_AUTO_UNREACHABLE_SESSION=1 \
  dart test "$3"
