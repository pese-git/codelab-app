import 'package:flutter/foundation.dart' show TargetPlatform;

/// Порт системного акцента (`add-app-appearance-page`, D7).
///
/// ЗАГЛУШКА для красных тестов 4.9: интерфейс по design.md D7; адаптер
/// `system_theme` — задача 4.10.
abstract interface class SystemAccentSource {
  /// Известно синхронно после старта: решает видимость строки «Accent color».
  bool get supported;

  /// ARGB или `null`, если акцент недоступен; ошибка канала — исключение.
  Future<int?> read();

  /// Смены акцента; на платформе без уведомлений — пустой поток.
  Stream<int?> get changes;
}

/// Платформа без системного акцента: [supported] ложно.
final class UnsupportedSystemAccentSource implements SystemAccentSource {
  const UnsupportedSystemAccentSource();

  @override
  bool get supported => false;

  @override
  Future<int?> read() async => null;

  @override
  Stream<int?> get changes => const Stream.empty();
}

/// Адаптер пакета `system_theme` (единственное место импорта пакета, D1).
///
/// ЗАГЛУШКА: ведёт себя как платформа без акцента, канал не читает.
final class SystemThemeAccentSource implements SystemAccentSource {
  SystemThemeAccentSource._();

  /// Первое чтение при старте (`main`, до `runApp`, не дольше [timeout]);
  /// [platform] — шов тестов, по умолчанию `defaultTargetPlatform`.
  static Future<SystemThemeAccentSource> start({
    Duration timeout = const Duration(seconds: 1),
    TargetPlatform? platform,
  }) async => SystemThemeAccentSource._();

  @override
  bool get supported => false;

  @override
  Future<int?> read() async => null;

  @override
  Stream<int?> get changes => const Stream.empty();
}
