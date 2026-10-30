// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Joel Winarske <joel.winarske@gmail.com>
// SPDX-FileCopyrightText: 2026 Jian De Seak

// Native assets build hook for pipewire_telephony_native.
//
// Builds libpipewire_telephony_native.so with CMake and exposes it as a bundled
// CodeAsset. Patterned after https://github.com/jwinarske/bluez_native,
// which is in turn patterned after
// https://github.com/meta-flutter/appstream_dart/blob/main/hook/build.dart.
// Both upstream projects are licensed under Apache-2.0; see
// LICENSES/Apache-2.0.txt.
// Keep the cross-build flow aligned with
// https://github.com/jaydon2020/bluez_obex_native/blob/main/hook/build.dart.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final skipNativeBuild = input.userDefines['skip_native_build'];
    if (skipNativeBuild is! bool?) {
      throw const FormatException(
        'hooks.user_defines.pipewire_telephony_native.skip_native_build '
        'must be a bool',
      );
    }
    if (skipNativeBuild == true ||
        Platform.environment.containsKey('SKIP_NATIVE_BUILD')) {
      stderr.writeln('Native build disabled — skipping CMake.');
      return;
    }

    final packageRoot = input.packageRoot.toFilePath();
    final nativeRoot = '${packageRoot}native';
    final buildDir = input.outputDirectory.resolve('cmake/').toFilePath();
    await Directory(buildDir).create(recursive: true);

    final sdbus = File('$nativeRoot/third_party/sdbus-cpp/CMakeLists.txt');
    if (!sdbus.existsSync()) {
      if (!Directory('$packageRoot.git').existsSync() &&
          !File('$packageRoot.git').existsSync()) {
        throw StateError(
          'native/third_party/sdbus-cpp is missing and $packageRoot has no '
          '.git to restore it from. Clone with --recurse-submodules.',
        );
      }
      stderr.writeln('sdbus-cpp submodule missing; initializing');
      await _run('git', [
        '-C',
        packageRoot,
        'submodule',
        'update',
        '--init',
        '--recursive',
      ]);
    }

    if (!File('${buildDir}CMakeCache.txt').existsSync()) {
      await _run(
        'cmake',
        cmakeConfigureArguments(
          nativeRoot: nativeRoot,
          buildDirectory: buildDir,
          hasNinja: await _which('ninja'),
        ),
      );
    }

    await _run('cmake', ['--build', buildDir, '--parallel']);

    final library = File('${buildDir}libpipewire_telephony_native.so');
    if (!library.existsSync()) {
      throw StateError(
        'libpipewire_telephony_native.so not found at ${library.path}',
      );
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/ffi/pipewire_telephony_native_asset.dart',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );

    output.dependencies
      ..addAll(nativeDependencies(Directory(nativeRoot)))
      ..add(input.packageRoot.resolve('scripts/validate_native_library.sh'));

    stderr.writeln('libpipewire_telephony_native built: ${library.path}');
  });
}

Future<void> _run(String executable, List<String> arguments) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'exit code $exitCode',
      exitCode,
    );
  }
}

Future<bool> _which(String executable) async {
  final result = await Process.run('which', [executable]);
  return result.exitCode == 0;
}

List<String> cmakeConfigureArguments({
  required String nativeRoot,
  required String buildDirectory,
  required bool hasNinja,
}) => [
  '-S',
  nativeRoot,
  '-B',
  buildDirectory,
  '-DCMAKE_BUILD_TYPE=Release',
  '-DBUILD_TESTING=OFF',
  '-DPWT_BUILD_DART_INTEGRATION_TESTS=OFF',
  '-DPWT_HOOK_BUILD=ON',
  if (hasNinja) ...['-G', 'Ninja'],
];

Iterable<Uri> nativeDependencies(Directory nativeRoot) sync* {
  yield nativeRoot.uri.resolve('CMakeLists.txt');
  yield nativeRoot.uri.resolve('exports.map');
  for (final name in [
    'src',
    'include',
    'generated',
    'third_party/glaze/include',
    'third_party/sdbus-cpp/src',
    'third_party/sdbus-cpp/include',
  ]) {
    final directory = Directory.fromUri(nativeRoot.uri.resolve('$name/'));
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          (entity.path.endsWith('/CMakeLists.txt') ||
              [
                '.cpp',
                '.cc',
                '.c',
                '.hpp',
                '.h',
                '.cmake',
                '.in',
                '.inl',
              ].any(entity.path.endsWith))) {
        yield entity.uri;
      }
    }
  }
  yield nativeRoot.uri.resolve('third_party/sdbus-cpp/CMakeLists.txt');
}
