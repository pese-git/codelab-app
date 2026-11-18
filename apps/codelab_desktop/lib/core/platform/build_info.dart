import 'dart:ffi' show Abi;

/// Операционная система и архитектура процесса для раздела «About»
/// (design.md change `add-app-general-page`, D1, D11).
///
/// Заглушка итерации 5 (красные тесты 5.3): значения пустые, реализация —
/// задача 5.4. `dart:ffi` разрешён только в этом файле (правило сторожа 5.6).
final class BuildInfo {
  const BuildInfo({required this.os, required this.arch});

  /// ОС и архитектура по значениям платформы; чистая функция для тестов.
  factory BuildInfo.of({required String operatingSystem, required Abi abi}) =>
      const BuildInfo(os: '', arch: '');

  /// ОС и архитектура текущего процесса.
  factory BuildInfo.current() => const BuildInfo(os: '', arch: '');

  /// `macOS`, `Linux`, `Windows`.
  final String os;

  /// `arm64`, `x64`.
  final String arch;

  /// `macOS arm64`.
  String get label => '$os $arch';
}
