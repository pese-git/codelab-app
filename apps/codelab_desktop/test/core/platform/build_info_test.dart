// ОС и архитектура процесса для раздела «About» (задача 5.3 change
// `add-app-general-page`; design.md D1, D11; spec app-settings «Раздел
// «About» страницы «General»»: `macOS arm64`, `Linux x64`, `Windows x64`).
//
// Реализация — задача 5.4 change `add-app-general-page`.

import 'dart:ffi' show Abi;

import 'package:codelab_desktop/core/platform/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildInfo.of', () {
    test('macOS arm64', () {
      final info = BuildInfo.of(operatingSystem: 'macos', abi: Abi.macosArm64);

      expect(info.os, 'macOS');
      expect(info.arch, 'arm64');
      expect(info.label, 'macOS arm64');
    });

    test('macOS x64', () {
      final info = BuildInfo.of(operatingSystem: 'macos', abi: Abi.macosX64);

      expect(info.label, 'macOS x64');
    });

    test('Linux x64', () {
      final info = BuildInfo.of(operatingSystem: 'linux', abi: Abi.linuxX64);

      expect(info.label, 'Linux x64');
    });

    test('Linux arm64', () {
      final info = BuildInfo.of(operatingSystem: 'linux', abi: Abi.linuxArm64);

      expect(info.label, 'Linux arm64');
    });

    test('Windows x64', () {
      final info = BuildInfo.of(
        operatingSystem: 'windows',
        abi: Abi.windowsX64,
      );

      expect(info.label, 'Windows x64');
    });
  });

  test('архитектура вне перечня — имя Abi как есть, без разбора строки', () {
    final info = BuildInfo.of(operatingSystem: 'linux', abi: Abi.linuxRiscv64);

    expect(info.arch, Abi.linuxRiscv64.toString());
  });

  test('BuildInfo.current описывает процесс тестов', () {
    final info = BuildInfo.current();

    expect(info.os, isIn(['macOS', 'Linux', 'Windows']));
    expect(info.arch, isNotEmpty);
    expect(info.label, '${info.os} ${info.arch}');
  });
}
