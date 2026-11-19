import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

/// Операционная система и архитектура процесса для раздела «About»
/// (design.md change `add-app-general-page`, D1, D11).
///
/// Почему отдельный файл: архитектуру процесса даёт `Abi.current()` из
/// `dart:ffi`, а платформенный код app изолирован (AGENTS.md §11). Правило
/// сторожа разрешает `dart:ffi` в `apps/codelab_desktop/lib` только здесь.
/// Разбор хвоста `Platform.version` отклонён: формат строки не контракт SDK.
///
/// Как использовать: composition root зовёт [BuildInfo.current] один раз;
/// [BuildInfo.of] — чистое отображение значений платформы для тестов.
final class BuildInfo {
  const BuildInfo({required this.os, required this.arch});

  /// ОС и архитектура по значениям платформы.
  ///
  /// [operatingSystem] — `Platform.operatingSystem` (`macos`, `linux`,
  /// `windows`), [abi] — `Abi.current()`. Незнакомая ОС остаётся как есть.
  factory BuildInfo.of({required String operatingSystem, required Abi abi}) =>
      BuildInfo(os: _osName(operatingSystem), arch: _archName(abi));

  /// ОС и архитектура текущего процесса.
  factory BuildInfo.current() => BuildInfo.of(
    operatingSystem: Platform.operatingSystem,
    abi: Abi.current(),
  );

  /// `macOS`, `Linux`, `Windows`.
  final String os;

  /// `arm64`, `x64`.
  final String arch;

  /// `macOS arm64`.
  String get label => '$os $arch';

  static String _osName(String operatingSystem) => switch (operatingSystem) {
    'macos' => 'macOS',
    'linux' => 'Linux',
    'windows' => 'Windows',
    final other => other,
  };

  /// Архитектура по константам `Abi`, а не по разбору `abi.toString()`:
  /// формат строки не контракт SDK (D1). Вне перечня — имя `Abi` как есть.
  static String _archName(Abi abi) => switch (abi) {
    Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
    Abi.macosX64 || Abi.linuxX64 || Abi.windowsX64 => 'x64',
    _ => abi.toString(),
  };
}
