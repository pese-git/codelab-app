import 'dart:async';

import 'package:codelab_desktop/app/language/app_language_cubit.dart'
    show AppStrings;
import 'package:codelab_desktop/l10n/app_localizations.dart';

/// Порт языка с неизменным каталогом: язык не меняется.
///
/// Почему: Cubit-тесты с текстом проверяют строки на английском, и смена
/// языка им не нужна (`add-desktop-localization`, D9; `testing.md` §30а).
///
/// Как использовать: `FixedAppStrings(AppLocalizationsEn())`.
final class FixedAppStrings implements AppStrings {
  const FixedAppStrings(this.current);

  @override
  final AppLocalizations current;

  @override
  Stream<AppLocalizations> get changes => const Stream.empty();
}

/// Управляемый порт языка для тестов смены языка Cubit-ов с текстом.
///
/// Почему: нужно вызвать смену языка в нужный момент и проверить, что Cubit
/// подписался один раз и отписался в `close()` (D5, правило 3; R3).
///
/// Как использовать: `final strings = TestAppStrings(AppLocalizationsEn());`
/// передать Cubit-у; `strings.emit(AppLocalizationsRu())` меняет [current] и
/// шлёт событие; после `cubit.close()` `strings.hasListener` — `false`.
final class TestAppStrings implements AppStrings {
  TestAppStrings(this._current);

  AppLocalizations _current;
  final _controller = StreamController<AppLocalizations>.broadcast();

  @override
  AppLocalizations get current => _current;

  @override
  Stream<AppLocalizations> get changes => _controller.stream;

  /// Есть ли подписчик на [changes] (утёкшая подписка видна здесь).
  bool get hasListener => _controller.hasListener;

  /// Меняет язык и сообщает подписчикам.
  void emit(AppLocalizations strings) {
    _current = strings;
    _controller.add(strings);
  }

  Future<void> close() => _controller.close();
}
