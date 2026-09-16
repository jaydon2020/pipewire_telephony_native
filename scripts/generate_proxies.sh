#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

find_xml2cpp() {
  local candidates=(
    "${ROOT_DIR}/build-codegen/tools/sdbus-c++-xml2cpp"
    "${ROOT_DIR}/build/native/third_party/sdbus-cpp/tools/sdbus-c++-xml2cpp"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if command -v sdbus-c++-xml2cpp >/dev/null 2>&1; then
    command -v sdbus-c++-xml2cpp
    return 0
  fi

  echo "sdbus-c++-xml2cpp not found; build the pinned generator first" >&2
  return 1
}

XML2CPP="$(find_xml2cpp)"
cd "${ROOT_DIR}"
mkdir -p native/generated

generate() {
  "${XML2CPP}" --proxy="native/generated/$1" "interfaces/$2"
}

generate object_manager_proxy.h org.freedesktop.DBus.ObjectManager.xml
generate audio_gateway1_proxy.h org.pipewire.Telephony.AudioGateway1.xml
generate audio_gateway_transport1_proxy.h \
  org.pipewire.Telephony.AudioGatewayTransport1.xml
generate call1_proxy.h org.pipewire.Telephony.Call1.xml
