#!/bin/bash
set -euo pipefail

library="${1:?usage: validate_native_library.sh LIBRARY EXPECTED_ELF_MACHINE}"
expected_machine="${2:?usage: validate_native_library.sh LIBRARY EXPECTED_ELF_MACHINE}"

[[ -f "${library}" ]] || {
  echo "library does not exist: ${library}" >&2
  exit 1
}
[[ "$(basename "${library}")" == 'libpipewire_telephony_native.so' ]] || {
  echo "library filename must be libpipewire_telephony_native.so" >&2
  exit 1
}

machine="$(readelf -h "${library}" | sed -n 's/^  Machine:[[:space:]]*//p')"
[[ "${machine}" == "${expected_machine}" ]] || {
  echo "ELF machine is '${machine}', expected '${expected_machine}'" >&2
  exit 1
}

dynamic="$(readelf -d "${library}")"
grep -Fq 'Library soname: [libpipewire_telephony_native.so]' <<<"${dynamic}" || {
  echo "missing libpipewire_telephony_native.so SONAME" >&2
  exit 1
}
if grep -Eq '\((RPATH|RUNPATH)\)' <<<"${dynamic}"; then
  echo "prebuilt library must not contain RPATH or RUNPATH" >&2
  exit 1
fi
while IFS= read -r dependency; do
  case "${dependency}" in
    libc.so.*|libdl.so.*|libgcc_s.so.*|libm.so.*|libpthread.so.*|librt.so.*|\
      libstdc++.so.*|libsystemd.so.*|ld-linux*.so.*) ;;
    *)
      echo "unexpected direct runtime dependency: ${dependency}" >&2
      exit 1
      ;;
  esac
done < <(sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' <<<"${dynamic}")

expected=$'pwt_abi_version\npwt_client_create\npwt_client_destroy\npwt_client_start\npwt_client_stop\npwt_client_submit\npwt_free\npwt_initialize_dart_api_dl\npwt_library_path'
actual="$(nm -D --defined-only --format=posix "${library}" | awk '{print $1}' | sort)"
[[ "${actual}" == "${expected}" ]] || {
  echo "exported C ABI does not match the required pwt symbol set" >&2
  diff -u <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") || true
  exit 1
}

printf 'validated %s (%s)\n' "${library}" "${machine}"
