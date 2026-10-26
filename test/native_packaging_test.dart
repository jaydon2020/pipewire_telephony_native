/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory.current.path;
  late Directory scratch;
  late String executable;
  late String ambient;
  final environment = {...Platform.environment}
    ..remove('PWT_NATIVE_LIB')
    ..remove('LD_LIBRARY_PATH')
    ..remove('SKIP_NATIVE_BUILD');

  Future<ProcessResult> run(
    String command,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.run(
    command,
    arguments,
    workingDirectory: workingDirectory ?? root,
    environment: environment,
    includeParentEnvironment: false,
  );

  Future<void> mustRun(
    String command,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final result = await run(
      command,
      arguments,
      workingDirectory: workingDirectory,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  setUpAll(() async {
    scratch = await Directory.systemTemp.createTemp('pwt-packaging-test.');
    addTearDown(() => scratch.delete(recursive: true));
    ambient = '${scratch.path}/ambient';
    await Directory(ambient).create();
    for (final marker in [false, true]) {
      await mustRun('cc', [
        '-shared',
        '-fPIC',
        if (marker) '-DPWT_LOADER_MARKER',
        '$root/test/fixtures/loader_fixture.c',
        '-o',
        '$ambient/${marker ? 'libpipewire_telephony_native.so' : 'libfixture.so'}',
      ]);
    }
    await mustRun('dart', [
      'build',
      'cli',
      '--target',
      'test/support/load_bundled_library.dart',
      '--output',
      '${scratch.path}/cli',
    ]);
    executable = '${scratch.path}/cli/bundle/bin/load_bundled_library';
    environment['PWT_TEST_WORKING_DIRECTORY'] = ambient;
  });

  test(
    'bundled asset wins over a library beside an unrelated loaded DLL',
    () async {
      final result = await run(executable, ['$ambient/libfixture.so']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('bundled telephony library loaded'));
      expect(result.stdout, isNot(contains('AUDIT_UNTRUSTED_LIBRARY_LOADED')));
    },
  );

  test('library beside a loaded libapp.so supports AGL homescreen', () async {
    final binary = await Directory(
      '${scratch.path}/homescreen/bin',
    ).create(recursive: true);
    final libraries = await Directory(
      '${scratch.path}/homescreen/release/lib',
    ).create(recursive: true);
    final probe = await File(executable).copy('${binary.path}/flutter-auto');
    final libapp = await File(
      '$ambient/libfixture.so',
    ).copy('${libraries.path}/libapp.so');
    await File(
      '$ambient/libpipewire_telephony_native.so',
    ).copy('${libraries.path}/libpipewire_telephony_native.so');

    final result = await run(probe.path, [libapp.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('AUDIT_UNTRUSTED_LIBRARY_LOADED'));
    expect(result.stdout, contains('bundled telephony library loaded'));
  });

  test('missing asset never falls back to the working directory', () async {
    final isolated = await Directory(
      '${scratch.path}/missing/bin',
    ).create(recursive: true);
    final copy = await File(executable).copy('${isolated.path}/probe');
    final cwd = await Directory(
      '${scratch.path}/cwd/build/native',
    ).create(recursive: true);
    await File(
      '$ambient/libpipewire_telephony_native.so',
    ).copy('${cwd.path}/libpipewire_telephony_native.so');
    environment['PWT_TEST_WORKING_DIRECTORY'] = '${scratch.path}/cwd';
    final result = await run(copy.path, const []);
    environment['PWT_TEST_WORKING_DIRECTORY'] = ambient;
    expect(result.exitCode, isNot(0));
    expect(result.stdout, isNot(contains('AUDIT_UNTRUSTED_LIBRARY_LOADED')));
  });

  test('an explicit native library override remains available', () async {
    environment['PWT_NATIVE_LIB'] = '$ambient/libpipewire_telephony_native.so';
    final result = await run(executable, const []);
    environment.remove('PWT_NATIVE_LIB');
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('AUDIT_UNTRUSTED_LIBRARY_LOADED'));
  });

  test('legacy executable-relative libraries still load', () async {
    final binary = await Directory(
      '${scratch.path}/legacy/bin',
    ).create(recursive: true);
    final library = await Directory('${binary.path}/lib').create();
    await File(executable).copy('${binary.path}/probe');
    await File(
      '${scratch.path}/cli/bundle/lib/libpipewire_telephony_native.so',
    ).copy('${library.path}/libpipewire_telephony_native.so');
    final result = await run('${binary.path}/probe', const []);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('bundled telephony library loaded'));
    expect(result.stdout, isNot(contains('AUDIT_UNTRUSTED_LIBRARY_LOADED')));
  });

  test('ELF class must also match the expected architecture', () async {
    final directory = await Directory('${scratch.path}/wrong-class').create();
    final header = ByteData(52);
    header.buffer.asUint8List().setAll(0, [0x7f, 0x45, 0x4c, 0x46, 1, 1, 1]);
    header.setUint16(16, 3, Endian.little); // ET_DYN
    header.setUint16(18, 62, Endian.little); // EM_X86_64 with ELFCLASS32
    header.setUint32(20, 1, Endian.little);
    header.setUint16(40, 52, Endian.little);
    final file = File('${directory.path}/libpipewire_telephony_native.so');
    await file.writeAsBytes(header.buffer.asUint8List());
    final result = await run('$root/scripts/validate_native_library.sh', [
      file.path,
      'Advanced Micro Devices X86-64',
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains("ELF class is 'ELF32', expected 'ELF64'"));
  });

  test(
    'AGL LLVM runtimes are accepted but unknown dependencies are not',
    () async {
      final tools = await Directory('${scratch.path}/validator-tools').create();
      final library = await File(
        '${scratch.path}/libpipewire_telephony_native.so',
      ).create();
      final readelf = File('${tools.path}/readelf');
      await readelf.writeAsString(r'''#!/bin/bash
if [[ "$1" == "-h" ]]; then
  printf '  Class:                             ELF64\n'
  printf '  Machine:                           Advanced Micro Devices X86-64\n'
else
  printf ' 0x000000000000000e (SONAME)             Library soname: [libpipewire_telephony_native.so]\n'
  printf ' 0x0000000000000001 (NEEDED)             Shared library: [libc++.so.1]\n'
  printf ' 0x0000000000000001 (NEEDED)             Shared library: [libc++abi.so.1]\n'
  if [[ -n "${PWT_TEST_EXTRA_DEPENDENCY:-}" ]]; then
    printf ' 0x0000000000000001 (NEEDED)             Shared library: [%s]\n' "$PWT_TEST_EXTRA_DEPENDENCY"
  fi
fi
''');
      final nm = File('${tools.path}/nm');
      await nm.writeAsString('''#!/bin/bash
printf '%s\\n' \\
  'pwt_abi_version T 0 0' \\
  'pwt_client_create T 0 0' \\
  'pwt_client_destroy T 0 0' \\
  'pwt_client_start T 0 0' \\
  'pwt_client_stop T 0 0' \\
  'pwt_client_submit T 0 0' \\
  'pwt_free T 0 0' \\
  'pwt_initialize_dart_api_dl T 0 0' \\
  'pwt_library_path T 0 0'
''');
      await mustRun('chmod', ['+x', readelf.path, nm.path]);

      final originalPath = environment['PATH']!;
      environment['PATH'] = '${tools.path}:$originalPath';
      try {
        final accepted = await run('$root/scripts/validate_native_library.sh', [
          library.path,
          'Advanced Micro Devices X86-64',
        ]);
        expect(accepted.exitCode, 0, reason: '${accepted.stderr}');

        environment['PWT_TEST_EXTRA_DEPENDENCY'] = 'libunexpected.so.1';
        final rejected = await run('$root/scripts/validate_native_library.sh', [
          library.path,
          'Advanced Micro Devices X86-64',
        ]);
        expect(rejected.exitCode, isNot(0));
        expect(
          rejected.stderr,
          contains('unexpected direct runtime dependency: libunexpected.so.1'),
        );
      } finally {
        environment['PATH'] = originalPath;
        environment.remove('PWT_TEST_EXTRA_DEPENDENCY');
      }
    },
  );

  test('a foreign processor label cannot hide a host-built ELF', () async {
    final processor = Architecture.current == Architecture.arm64
        ? 'x86_64'
        : 'aarch64';
    final toolchain = File('${scratch.path}/toolchain.cmake');
    await toolchain.writeAsString('''
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $processor)
set(CMAKE_SYSROOT /)
set(CMAKE_C_COMPILER cc)
set(CMAKE_CXX_COMPILER c++)
''');
    final build = '${scratch.path}/cross';
    await mustRun('cmake', [
      '-S',
      '$root/native',
      '-B',
      build,
      '-DCMAKE_TOOLCHAIN_FILE=${toolchain.path}',
      '-DPWT_REQUIRE_CROSS_COMPILE=ON',
      '-DPWT_BUILD_DART_INTEGRATION_TESTS=OFF',
      '-DBUILD_TESTING=OFF',
    ]);
    final result = await run('cmake', ['--build', build, '--parallel']);
    expect(result.exitCode, isNot(0));
    expect('${result.stdout}\n${result.stderr}', contains('ELF machine'));
  });

  test('the Native Assets hook rejects a foreign CLI target', () async {
    final help = await run('dart', ['build', 'cli', '--help']);
    if (!help.stdout.toString().contains('--target-arch')) {
      markTestSkipped('This Dart CLI cannot request a foreign target.');
      return;
    }
    final target = Architecture.current == Architecture.arm64 ? 'x64' : 'arm64';
    final result = await run('dart', [
      'build',
      'cli',
      '--target',
      'test/support/load_bundled_library.dart',
      '--target-arch',
      target,
      '--output',
      '${scratch.path}/foreign-cli',
    ]);
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}\n${result.stderr}',
      contains('requires hooks.user_defines.pipewire_telephony_native.'),
    );
  });

  test('the Native Assets hook forwards a cross toolchain', () async {
    final help = await run('dart', ['build', 'cli', '--help']);
    if (!help.stdout.toString().contains('--target-arch')) {
      markTestSkipped('This Dart CLI cannot request a foreign target.');
      return;
    }
    final target = Architecture.current == Architecture.arm64 ? 'x64' : 'arm64';
    final processor = target == 'arm64' ? 'aarch64' : 'x86_64';
    final workspace = await Directory('${scratch.path}/cross-hook').create();
    await Directory('${workspace.path}/bin').create();
    await File('${workspace.path}/toolchain.cmake').writeAsString('''
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $processor)
set(CMAKE_SYSROOT /)
set(CMAKE_C_COMPILER cc)
set(CMAKE_CXX_COMPILER c++)
''');
    await File('${workspace.path}/pubspec.yaml').writeAsString('''
name: pwt_cross_hook_test
environment:
  sdk: '>=3.10.1 <4.0.0'
dependencies:
  pipewire_telephony_native:
    path: $root
hooks:
  user_defines:
    pipewire_telephony_native:
      cmake_toolchain_file: toolchain.cmake
''');
    await File('${workspace.path}/bin/main.dart').writeAsString('''
import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';

void main() => print(PipeWireBus.system);
''');
    await mustRun('dart', ['pub', 'get'], workingDirectory: workspace.path);
    final result = await run('dart', [
      'build',
      'cli',
      '--target',
      'bin/main.dart',
      '--target-arch',
      target,
      '--output',
      '${workspace.path}/output',
    ], workingDirectory: workspace.path);
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0));
    expect(output, isNot(contains('requires hooks.user_defines')));
    expect(output, contains('ELF machine'));
  });

  test('the Native Assets hook accepts an explicit skip user define', () async {
    final workspace = await Directory('${scratch.path}/skip-hook').create();
    await Directory('${workspace.path}/bin').create();
    await File('${workspace.path}/pubspec.yaml').writeAsString('''
name: pwt_skip_hook_test
environment:
  sdk: '>=3.10.1 <4.0.0'
dependencies:
  pipewire_telephony_native:
    path: $root
hooks:
  user_defines:
    pipewire_telephony_native:
      skip_native_build: true
''');
    await File('${workspace.path}/bin/main.dart').writeAsString('''
import 'package:pipewire_telephony_native/pipewire_telephony_native.dart';

void main() => print(PipeWireBus.system);
''');
    await mustRun('dart', ['pub', 'get'], workingDirectory: workspace.path);
    await mustRun('dart', [
      'build',
      'cli',
      '--target',
      'bin/main.dart',
      '--output',
      '${workspace.path}/output',
    ], workingDirectory: workspace.path);
  });
}
