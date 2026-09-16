# AGL native build and packaging

Source the matching AGL/Yocto SDK environment before configuring. The SDK must
provide `OE_CMAKE_TOOLCHAIN_FILE`, `SDKTARGETSYSROOT`, and
`PKG_CONFIG_SYSROOT_DIR`; target `libsystemd` headers and pkg-config metadata
must be present in that sysroot. Use a build directory dedicated to the target:

```sh
source /opt/agl-sdk/environment-setup-<target>
export PWT_EXPECTED_ELF_MACHINE=AArch64
./scripts/build_agl.sh
```

The script requires CMake to report a cross-build with a sysroot, disables all
tests that would execute target binaries on the host, and validates the output
ELF machine, SONAME, lack of runtime search paths, and exact public C ABI. Set
`PWT_EXPECTED_ELF_MACHINE` to the `Machine` value printed by the SDK's target
artifact through `readelf -h`; do not assume AArch64 for every AGL board.

To bundle a library produced by the SDK or a Yocto recipe, pass its absolute
path and expected machine to the Flutter Linux CMake configure:

```sh
-DPWT_PREBUILT_LIBRARY=/absolute/target/libpipewire_telephony_native.so
-DPWT_EXPECTED_ELF_MACHINE=AArch64
```

The configure fails for a missing or relative path, wrong architecture, wrong
SONAME, extra/missing C ABI symbols, or embedded RPATH/RUNPATH. The source-build
and prebuilt paths both bundle a file named `libpipewire_telephony_native.so`.

Offline Yocto builds must fetch the sdbus-c++ submodule before `do_configure`.
Use a submodule-aware fetch (`gitsm`) or include the pinned submodule contents in
the source archive. Glaze is already supplied as its pinned header-only tree.
Neither CMake path runs Git or accesses the network. Keep host and target build
directories separate; never pass a host artifact as `PWT_PREBUILT_LIBRARY`.
