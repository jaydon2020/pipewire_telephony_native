// Native Assets build hook for pipewire_telephony_native.
//
// Builds libpipewire_telephony_native.so with CMake and exposes it as a bundled
// CodeAsset. Patterned after https://github.com/jwinarske/bluez_native, which
// is in turn patterned after
// https://github.com/meta-flutter/appstream_dart/blob/main/hook/build.dart.
// Both upstream projects are licensed under Apache-2.0; see
// LICENSES/Apache-2.0.txt.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    if (Platform.environment.containsKey('SKIP_NATIVE_BUILD')) {
      stderr.writeln('SKIP_NATIVE_BUILD set - skipping native build.');
      return;
    }

    validateOperatingSystems(OS.current, input.config.code.targetOS);

    final packageRoot = input.packageRoot.toFilePath();
    final nativeRoot = '${packageRoot}native';
    final buildDirectory = input.outputDirectory.resolve('cmake/').toFilePath();
    await Directory(buildDirectory).create(recursive: true);

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

    final hasNinja = await _which('ninja');
    if (!File('${buildDirectory}CMakeCache.txt').existsSync()) {
      await _run('cmake', [
        '-S',
        nativeRoot,
        '-B',
        buildDirectory,
        '-DCMAKE_BUILD_TYPE=Release',
        '-DBUILD_TESTING=OFF',
        '-DPWT_BUILD_DART_INTEGRATION_TESTS=OFF',
        '-DPWT_HOOK_BUILD=ON',
        if (hasNinja) ...['-G', 'Ninja'],
      ]);
    }

    await _run('cmake', ['--build', buildDirectory, '--parallel']);

    final library = File('${buildDirectory}libpipewire_telephony_native.so');
    if (!library.existsSync()) {
      throw StateError('Native library not found at ${library.path}');
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/ffi/pipewire_telephony_native_asset.dart',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );

    for (final entity in Directory(nativeRoot).listSync(recursive: true)) {
      if (entity is! File) continue;
      if (const [
        '.c',
        '.cc',
        '.cpp',
        '.h',
        '.hpp',
        '.cmake',
        '.txt',
        '.in',
      ].any(entity.path.endsWith)) {
        output.dependencies.add(entity.uri);
      }
    }

    stderr.writeln('libpipewire_telephony_native built: ${library.path}');
  });
}

Future<void> _run(String executable, List<String> arguments) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'exit code $code', code);
  }
}

Future<bool> _which(String executable) async {
  final result = await Process.run('which', [executable]);
  return result.exitCode == 0;
}

void validateOperatingSystems(OS hostOS, OS targetOS) {
  if (hostOS != OS.linux || targetOS != OS.linux) {
    throw UnsupportedError(
      'pipewire_telephony_native requires a Linux host and target.',
    );
  }
}
