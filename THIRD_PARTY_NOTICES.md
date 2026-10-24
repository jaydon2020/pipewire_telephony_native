# Third-party notices and redistribution

The package's own code is BSD-3-Clause, as stated in [LICENSE](LICENSE).
Bundled and derived code keeps the following licenses. The top-level license
does not replace them.

| Component | Use | License and retained text |
| --- | --- | --- |
| sdbus-c++ 2.2.1, commit `28b78822cfc5fbec4bd9906168493e9985f586ed` | Statically linked into the native library | [LGPL-2.1](native/third_party/sdbus-cpp/COPYING) with the [sdbus-c++ exception](native/third_party/sdbus-cpp/COPYING-LGPL-Exception) |
| Glaze 8.3.0 | Header-only JSON codec in the native library | [MIT](native/third_party/glaze/LICENSE) |
| Dart SDK 3.13.2 API DL source and headers | Native Dart port integration | [BSD-3-Clause](native/third_party/dart/LICENSE) |
| GoogleTest 1.17.0 | Native tests only; not linked into the released library | [BSD-3-Clause](native/third_party/googletest/LICENSE) |
| [bluez_native](https://github.com/jwinarske/bluez_native) and [appstream_dart](https://github.com/meta-flutter/appstream_dart) | Derived build-hook, library-loader, FFI lifetime, codec/type organization, and development-script patterns, identified in source comments and the README | [Apache-2.0](LICENSES/Apache-2.0.txt) |

Dependency copyright notices are retained in the linked license files and source
headers. The selected system D-Bus implementation (normally libsystemd) is a
separate runtime dependency; preserve its distribution's applicable notices too.

## Distributing a Flutter application or a prebuilt library

Include this notice and the applicable license texts and copyright notices in
the application's distributed notices. Flutter's automatic Dart license
collection is not a substitute for including nested native dependency licenses.
Preserve any additional upstream notices when updating dependencies.

The build links sdbus-c++ statically into `libpipewire_telephony_native.so`.
Its header exception expressly retains LGPL-2.1 section 6. Provide a way for
recipients to modify sdbus-c++ and rebuild/relink the native library, and allow
replacement of that library in the application. For the accompanying-source
route in section 6(a), distribute the exact corresponding sdbus-c++ sources,
this bridge's native sources and generated headers, the other required headers,
and the CMake/build instructions with the binary, including any modifications.
This package contains those sources; keep the exact package version used for
each binary release. A Git checkout must also include the pinned sdbus-c++
submodule, not just its Git reference.

The bridge can be rebuilt from that source archive with:

```sh
cmake -S native -B build/relink -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF -DPWT_BUILD_DART_INTEGRATION_TESTS=OFF
cmake --build build/relink --parallel
```

The result is `build/relink/libpipewire_telephony_native.so`. Document the
location and replacement procedure for the copy shipped in your application
bundle, including any Native Assets copy. Build for the application's target
architecture and preserve the public C ABI. AGL cross-build instructions are in
[doc/agl_build.md](doc/agl_build.md). Distribution terms must permit modification
for the recipient's own use and reverse engineering to debug those modifications.

The governing terms are [LGPL-2.1 section 6](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html#section6)
and the bundled exception. Use those terms to choose the distribution route
appropriate to your application; this note describes the accompanying-source
route rather than certifying compliance for every downstream deployment.
