#!/bin/bash
set -euo pipefail

mapfile -t bus < <(
  dbus-daemon --config-file="$1" --fork --print-address=1 --print-pid=1
)
export DBUS_SESSION_BUS_ADDRESS="${bus[0]}"
pid="${bus[1]}"
trap 'kill "${pid}" 2>/dev/null || true' EXIT

PWT_NATIVE_LIB="$2" dart test "$3"
