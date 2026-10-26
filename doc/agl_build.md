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

All native CMake builds validate their completed shared library against
`CMAKE_SYSTEM_PROCESSOR`, including ELF class/machine, SONAME and public ABI.
A toolchain label alone is insufficient: a host-built x86-64 library labelled
as AArch64 fails the build. Host `readelf` and `nm` (binutils) must be available;
validation never executes a target binary.

## Native Assets cross-build

An application can ask the package hook to compile directly for its Linux
target by adding the toolchain path to the application or workspace pubspec:

```yaml
hooks:
  user_defines:
    pipewire_telephony_native:
      cmake_toolchain_file: /absolute/path/to/agl-toolchain.cmake
```

Relative paths are resolved from that pubspec. The file must be a CMake
toolchain that sets `CMAKE_SYSTEM_NAME`, `CMAKE_SYSTEM_PROCESSOR`, a target
compiler and `CMAKE_SYSROOT`, and makes target `libsystemd` discoverable by
pkg-config. Native Assets hooks run in a semi-hermetic environment, so AGL/Yocto
variables such as `SDKTARGETSYSROOT` and `PKG_CONFIG_SYSROOT_DIR` are not passed
through automatically. Use a self-contained wrapper toolchain that sets the
required paths (including pkg-config environment values) before including the
SDK's `OEToolchainConfig.cmake`.

The hook registers the toolchain as a build dependency, requires CMake to
report a cross-build with a sysroot, and checks that the final ELF matches the
Native Assets target architecture. This path never executes a target binary.

The standalone `scripts/build_agl.sh` and validated prebuilt integration remain
available when the application build cannot provide a self-contained toolchain.
For that path, disable the package hook explicitly in the application pubspec:

```yaml
hooks:
  user_defines:
    pipewire_telephony_native:
      skip_native_build: true
```

Source and prebuilt deployments load from the system loader, beside a mapped
Flutter `libapp.so`, from declared assets, or from known executable-relative
application-bundle locations. Set `PWT_NATIVE_LIB` explicitly for other layouts.
