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

  Future<ProcessResult> run(String command, List<String> arguments) =>
      Process.run(
        command,
        arguments,
        workingDirectory: root,
        environment: environment,
        includeParentEnvironment: false,
      );

  Future<void> mustRun(String command, List<String> arguments) async {
    final result = await run(command, arguments);
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
      contains('The Native Assets hook supports native compilation only'),
    );
  });
}
