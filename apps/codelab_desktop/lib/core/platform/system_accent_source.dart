import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
// Единственный импорт пакета в app (правило сторожа, design.md change
// `add-app-appearance-page`, D1): остальной код видит порт `SystemAccentSource`.
import 'package:system_theme/system_theme.dart';

/// Порт системного акцента (`add-app-appearance-page`, D7).
///
/// Почему порт: Flutter на десктопе системный акцент не отдаёт, цвет читает
/// нативный плагин (`platform-integration.md` §4, §8); `AppAppearanceCubit` и
/// страница знают только этот узкий интерфейс и тестируются на двойнике.
///
/// Как использовать: реализацию выбирает composition root по платформе
/// (`main`); `supported` известно синхронно после первого чтения при старте,
/// поэтому строка «Accent color» не появляется и не исчезает после первого
/// кадра (spec app-settings «Системный акцент»).
abstract interface class SystemAccentSource {
  /// Платформа поддерживается и первое чтение дало цвет.
  bool get supported;

  /// ARGB текущего акцента или `null`, если акцент недоступен. Ошибка канала
  /// приходит исключением: вызывающий (`AppAppearanceCubit`) пишет событие и
  /// применяет `accent` темы.
  Future<int?> read();

  /// Смены акцента в ARGB; на платформе без уведомлений — пустой поток.
  Stream<int?> get changes;
}

/// Платформа без системного акцента: [supported] ложно.
///
/// Для чего: порт по умолчанию composition root и тестов; ни канала, ни
/// подписок.
final class UnsupportedSystemAccentSource implements SystemAccentSource {
  const UnsupportedSystemAccentSource();

  @override
  bool get supported => false;

  @override
  Future<int?> read() async => null;

  @override
  Stream<int?> get changes => const Stream.empty();
}

/// Адаптер пакета `system_theme` 3.3.0 (D7).
///
/// Почему адаптер, а не прямые вызовы пакета: у API три особенности, которые
/// без обёртки теряют данные или ошибки (design.md D7).
///  - При отсутствии плагина `SystemAccentColor.load()` молча оставляет
///    запасной цвет `#00b7c3`. Адаптер заводит объект с маркером
///    `Color(0x00000000)` и считает акцент недоступным, если после `load()`
///    остался маркер; запасной цвет пакета в app не попадает.
///  - Статический `SystemTheme.accentColor` грузится без `await`, его
///    исключение потерялось бы (`AGENTS.md` §12); адаптер его не использует и
///    сам ждёт `load()` внутри `try`.
///  - `load()` подписывается на `onChange` и не отписывается: адаптер создаёт
///    объект один раз за процесс, поэтому такая подписка одна.
///
/// Как использовать: `await SystemThemeAccentSource.start()` в `main` до
/// `runApp`; чтение ограничено временем, как файлы тем. Поддержка платформ —
/// `supportsAccentColor` пакета (macOS, Windows, Linux, а также мобильные и
/// web, которых в app нет); уведомления о смене — macOS и Windows, на Linux
/// цвет перечитывается по `read()` (spec app-settings «Linux без
/// уведомлений»).
final class SystemThemeAccentSource implements SystemAccentSource {
  SystemThemeAccentSource._({
    required this.supported,
    required SystemAccentColor color,
    required bool listens,
  }) : _color = color,
       _listens = listens;

  /// Маркер «плагин не ответил»: у реального цвета акцента альфа не нулевая.
  static const _marker = Color(0x00000000);

  /// Первое чтение при старте (`main`, до `runApp`, не дольше [timeout]);
  /// [platform] — шов тестов, по умолчанию `defaultTargetPlatform`.
  ///
  /// Не бросает: ошибка, таймаут и ответ без цвета дают `supported == false`.
  static Future<SystemThemeAccentSource> start({
    Duration timeout = const Duration(seconds: 1),
    TargetPlatform? platform,
  }) async {
    final target = platform ?? defaultTargetPlatform;
    final color = SystemAccentColor(_marker);
    var supported = false;
    if (target.supportsAccentColor) {
      try {
        await color.load().timeout(timeout);
        supported = color.accent != _marker;
      } on Object {
        // Причина не нужна: «нет акцента» одинаково для таймаута, ошибки
        // канала и отсутствия плагина; строка на странице просто скрыта.
        supported = false;
      }
    }
    return SystemThemeAccentSource._(
      supported: supported,
      color: color,
      listens: supported && target.supportsListeningToAccentColorChanges,
    );
  }

  @override
  final bool supported;

  final SystemAccentColor _color;
  final bool _listens;

  @override
  Future<int?> read() async {
    if (!supported) return null;
    await _color.load();
    return _color.accent == _marker ? null : _color.accent.toARGB32();
  }

  @override
  Stream<int?> get changes => _listens
      ? SystemTheme.onChange.map<int?>((color) => color.accent.toARGB32())
      : const Stream.empty();
}
