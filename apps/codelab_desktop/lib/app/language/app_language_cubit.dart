import 'dart:async';
import 'dart:ui';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/platform/app_language_preferences.dart';
import '../../l10n/app_localizations.dart';
import 'app_locale.dart';

/// Узкий порт языка для Cubit-ов, которые хранят текст в состоянии.
///
/// Почему порт, а не весь [AppLanguageCubit]: Cubit-ам с текстом нужны только
/// текущий каталог и событие смены; узкий порт даёт независимое тестирование
/// (`FixedAppStrings`, `TestAppStrings`; AGENTS.md §13) —
/// `add-desktop-localization`, D2, D5.
///
/// Как использовать: Cubit читает [current] только внутри проекции, подписывается
/// на [changes] один раз в конструкторе и отменяет подписку в `close()`.
abstract interface class AppStrings {
  /// Каталог текущего языка.
  AppLocalizations get current;

  /// Новый каталог ровно один раз на смену языка (повторный выбор того же
  /// языка события не даёт). Поток закрывается вместе с владельцем.
  Stream<AppLocalizations> get changes;
}

/// Состояние языка интерфейса.
///
/// [preference] — выбор пользователя, [locale] — применённый язык
/// (`resolveAppLocale`), [strings] — каталог этого языка, [saveFailed] —
/// последняя запись выбора не удалась (язык при этом остаётся применённым;
/// `state-management.md` §63а).
final class AppLanguageState {
  const AppLanguageState({
    required this.preference,
    required this.locale,
    required this.strings,
    this.saveFailed = false,
  });

  final AppLanguagePreference preference;
  final Locale locale;
  final AppLocalizations strings;
  final bool saveFailed;

  AppLanguageState copyWith({
    AppLanguagePreference? preference,
    Locale? locale,
    AppLocalizations? strings,
    bool? saveFailed,
  }) => AppLanguageState(
    preference: preference ?? this.preference,
    locale: locale ?? this.locale,
    strings: strings ?? this.strings,
    saveFailed: saveFailed ?? this.saveFailed,
  );
}

/// Единственный владелец языка интерфейса.
///
/// Почему: язык должен иметь одного владельца, иначе экраны и Cubit-ы
/// показали бы смесь языков (D2, D5; `state-management.md` §63а).
///
/// Для чего: `select` синхронно применяет язык (`emit`), затем пишет ключ.
/// Записи идут по очереди, побеждает последний выбор: запись, которую
/// обогнал более новый выбор, состояние не публикует (`concurrency.md` §47а,
/// R4). Сбой записи не откатывает язык: ставится `saveFailed`.
///
/// Как использовать: singleton root scope; начальные [preference] и [locale]
/// приходят швом из `main` без асинхронной загрузки. Потребители — `BlocBuilder`
/// над `FluentApp` и Cubit-ы с текстом через порт [AppStrings]. Закрывается
/// вместе со scope.
final class AppLanguageCubit extends Cubit<AppLanguageState>
    implements AppStrings {
  AppLanguageCubit({
    required AppLanguagePreferences preferences,
    required AppLanguagePreference preference,
    required Locale locale,
    List<Locale> Function()? systemLocales,
    Logger? logger,
  }) : _preferences = preferences,
       _systemLocales =
           systemLocales ?? (() => PlatformDispatcher.instance.locales),
       _logger = logger,
       super(
         AppLanguageState(
           preference: preference,
           locale: locale,
           strings: lookupAppLocalizations(locale),
         ),
       );

  final AppLanguagePreferences _preferences;
  final List<Locale> Function() _systemLocales;
  final Logger? _logger;

  /// Подписчики [changes]; считаются для события `app.locale_applied`.
  final _listeners = <MultiStreamController<AppLocalizations>>[];

  /// Номер последнего выбора: запись с меньшим номером обогнана.
  int _latest = 0;
  int _inFlight = 0;
  Future<void> _tail = Future<void>.value();

  @override
  AppLocalizations get current => state.strings;

  @override
  late final Stream<AppLocalizations> changes = Stream.multi((controller) {
    if (isClosed) {
      controller.close();
      return;
    }
    _listeners.add(controller);
    controller.onCancel = () => _listeners.remove(controller);
  }, isBroadcast: true);

  /// Применяет язык синхронно и затем сохраняет его.
  ///
  /// Повторный выбор того же значения ничего не делает, кроме повторной записи
  /// после сбоя. Завершается, когда запись этого выбора закончена.
  Future<void> select(AppLanguagePreference preference) {
    if (isClosed) return Future<void>.value();
    if (preference == state.preference && !state.saveFailed) {
      return Future<void>.value();
    }
    final token = ++_latest;
    final locale = resolveAppLocale(preference, _systemLocales());
    final localeChanged = locale != state.locale;

    emit(
      state.copyWith(
        preference: preference,
        locale: locale,
        strings: localeChanged ? lookupAppLocalizations(locale) : null,
        saveFailed: false,
      ),
    );
    _logger?.info(
      'settings.language_changed',
      context: {'language': preference.name, 'locale': locale.toLanguageTag()},
    );
    if (localeChanged) {
      for (final controller in List.of(_listeners)) {
        controller.add(state.strings);
      }
      _logger?.debug(
        'app.locale_applied',
        context: {
          'locale': locale.toLanguageTag(),
          'subscribers': _listeners.length,
        },
      );
    }
    return _enqueue(preference, token);
  }

  /// Ставит запись в очередь; при пустой очереди начинает её сразу.
  Future<void> _enqueue(AppLanguagePreference preference, int token) {
    final Future<void> run = _inFlight == 0
        ? _write(preference, token)
        : _tail.then((_) => _write(preference, token));
    _inFlight++;
    _tail = run.whenComplete(() => _inFlight--);
    return run;
  }

  Future<void> _write(AppLanguagePreference preference, int token) async {
    try {
      await _preferences.save(preference);
    } on Object catch (error) {
      // Только класс ошибки: текст исключения может содержать пути.
      _logger?.warning(
        'settings.language_save_failed',
        context: {'error_class': error.runtimeType.toString()},
      );
      if (!isClosed && token == _latest) {
        emit(state.copyWith(saveFailed: true));
      }
    }
  }

  @override
  Future<void> close() async {
    for (final controller in List.of(_listeners)) {
      await controller.close();
    }
    _listeners.clear();
    return super.close();
  }
}
