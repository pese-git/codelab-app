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
/// шлёт событие; после `cubit.close()` `strings.hasListener` — `false`, а
/// [subscriberCount] показывает, не выросло ли число подписок после
/// переподключения и смены сессии (R3).
final class TestAppStrings implements AppStrings {
  TestAppStrings(this._current);

  AppLocalizations _current;
  final _controller = StreamController<AppLocalizations>.broadcast();
  var _subscribers = 0;

  @override
  AppLocalizations get current => _current;

  // Свой счётчик, а не `_controller.hasListener`: широковещательный
  // контроллер знает только «есть ли хоть один», а утечку второй подписки
  // можно увидеть лишь по числу.
  @override
  Stream<AppLocalizations> get changes =>
      Stream<AppLocalizations>.multi((subscriber) {
        _subscribers++;
        final inner = _controller.stream.listen(
          subscriber.add,
          onDone: subscriber.close,
        );
        subscriber.onCancel = () {
          _subscribers--;
          return inner.cancel();
        };
      }, isBroadcast: true);

  /// Есть ли подписчик на [changes] (утёкшая подписка видна здесь).
  bool get hasListener => _subscribers > 0;

  /// Сколько подписок на [changes] живо сейчас.
  int get subscriberCount => _subscribers;

  /// Меняет язык и сообщает подписчикам.
  void emit(AppLocalizations strings) {
    _current = strings;
    _controller.add(strings);
  }

  Future<void> close() => _controller.close();
}
