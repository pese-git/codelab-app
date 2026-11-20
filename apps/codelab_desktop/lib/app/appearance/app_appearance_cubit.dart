import 'dart:async';
import 'dart:ui' show Brightness, Color;

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentThemeData, ThemeMode;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/platform/app_appearance_preferences.dart';
import '../../core/platform/system_accent_source.dart';
import 'app_appearance_start.dart';
import 'built_in_themes.dart';
import 'fluent_theme_builder.dart';

/// Состояние оформления app (design.md change `add-app-appearance-page`, D13).
///
/// Почему: `FluentApp` рисует тему из состояния, а не из виджетов; состояние
/// несёт и выбор пользователя ([settings]), и готовые темы двух режимов, чтобы
/// `BlocBuilder` над `FluentApp` ничего не вычислял (`state-management.md`
/// §63б).
///
/// Для чего: [resolvedLight] и [resolvedDark] — готовые `FluentThemeData` с
/// расширениями `CodeLabPalette` и `CodeLabCodeTheme`; [fallback] — какие
/// режимы показывают встроенную тему вместо выбранной пользовательской (файл
/// удалён или не разобран; выбор при этом в [settings] не меняется, а страница
/// показывает `settings-appearance-fallback`); [saveFailed] — последняя запись
/// выбора не удалась, оформление при этом остаётся применённым.
final class AppAppearanceState {
  const AppAppearanceState({
    required this.settings,
    required this.resolvedLight,
    required this.resolvedDark,
    this.systemAccentSupported = false,
    this.saveFailed = false,
    this.fallback = AppearanceFallback.none,
  });

  final AppAppearanceSettings settings;
  final FluentThemeData resolvedLight;
  final FluentThemeData resolvedDark;

  /// Порт системного акцента сообщил поддержку при старте: решает видимость
  /// строки «Accent color» (SETUP-17).
  final bool systemAccentSupported;
  final bool saveFailed;
  final AppearanceFallback fallback;

  AppearanceMode get mode => settings.mode;
  String get lightTheme => settings.lightTheme;
  String get darkTheme => settings.darkTheme;
  bool get systemAccent => settings.systemAccent;

  /// Режим для `FluentApp.themeMode`: `Match system` следует системе сам.
  ThemeMode get themeMode => switch (settings.mode) {
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark => ThemeMode.dark,
    AppearanceMode.system => ThemeMode.system,
  };

  AppAppearanceState copyWith({
    AppAppearanceSettings? settings,
    FluentThemeData? resolvedLight,
    FluentThemeData? resolvedDark,
    bool? saveFailed,
    AppearanceFallback? fallback,
  }) => AppAppearanceState(
    settings: settings ?? this.settings,
    resolvedLight: resolvedLight ?? this.resolvedLight,
    resolvedDark: resolvedDark ?? this.resolvedDark,
    systemAccentSupported: systemAccentSupported,
    saveFailed: saveFailed ?? this.saveFailed,
    fallback: fallback ?? this.fallback,
  );
}

/// Единственный владелец применённого оформления app (D13;
/// `state-management.md` §63б, `concurrency.md` §47б).
///
/// Почему один владелец: режим, темы двух режимов и системный акцент должны
/// применяться ко всему app сразу и без потери состояния виджетов, иначе
/// экраны показали бы смесь тем. Источник темы — файлы каталога
/// (`ThemeLibrary`), источник акцента — порт (`SystemAccentSource`), хранение —
/// `AppAppearancePreferences`; Cubit только склеивает их и отдаёт готовые
/// `FluentThemeData`.
///
/// Для чего: переходы [setMode], [useTheme], [resetTheme], [setSystemAccent],
/// [reloadTheme], [refreshSystemAccent] сначала публикуют состояние, потом
/// пишут документ. Записи идут по очереди, побеждает последний выбор: запись,
/// которую обогнал более новый выбор, состояние не публикует. Сбой записи не
/// откатывает оформление — ставится `saveFailed`, [retrySave] повторяет запись.
/// Пользовательская тема читается из файла асинхронно, поэтому результат
/// защищён от устаревания. [useTheme] берёт номер выбора (`_choice`) в начале
/// КАЖДОГО вызова, как [resetTheme] и [setMode]: чтение применяется, только если
/// более нового выбора не было. [reloadTheme] защищён номером операции своего
/// режима: поздний результат после нового [reloadTheme], [useTheme] или
/// [resetTheme] того же режима отбрасывается. Тема, которая не загрузилась,
/// заменяется встроенной темой режима, а выбор пользователя остаётся в документе.
///
/// Как использовать: singleton root scope; начальное состояние приходит швом
/// [AppAppearanceStart] из `main` без асинхронной загрузки (первый кадр уже в
/// итоговом оформлении). Подписка на смену системного акцента (macOS, Windows)
/// живёт до [close]; на Linux уведомлений нет, и страница «Appearance» зовёт
/// [refreshSystemAccent] при открытии. События журнала — spec app-settings
/// «События журнала оформления»: пользовательская тема в них `custom`, без
/// имени, пути и текста исключений (D12).
final class AppAppearanceCubit extends Cubit<AppAppearanceState> {
  AppAppearanceCubit({
    required AppAppearancePreferences preferences,
    required ThemeLibrary library,
    required SystemAccentSource accentSource,
    required AppAppearanceStart start,
    Logger? logger,
    Duration closeWriteTimeout = const Duration(seconds: 3),
  }) : _preferences = preferences,
       _library = library,
       _accentSource = accentSource,
       _logger = logger,
       _closeWriteTimeout = closeWriteTimeout,
       _light = start.lightTheme,
       _dark = start.darkTheme,
       _accent = start.systemAccent,
       super(
         _stateOf(
           start.settings,
           light: start.lightTheme,
           dark: start.darkTheme,
           accent: start.systemAccent,
           supported: start.systemAccentSupported,
         ),
       ) {
    if (start.systemAccentSupported) {
      _accentSubscription = _accentSource.changes.listen(
        _onAccentChanged,
        onError: _onAccentFailed,
      );
    }
  }

  final AppAppearancePreferences _preferences;
  final ThemeLibrary _library;
  final SystemAccentSource _accentSource;
  final Logger? _logger;
  final Duration _closeWriteTimeout;

  /// Загруженные пользовательские темы режимов; `null` — выбрана встроенная
  /// или файл не загрузился.
  ThemeLoaded? _light;
  ThemeLoaded? _dark;

  /// ARGB системного акцента; `null` — не прочитан или недоступен.
  int? _accent;
  StreamSubscription<int?>? _accentSubscription;

  /// Номера операций над темой режима: результат чтения с устаревшим номером
  /// отбрасывается (D13).
  int _lightOp = 0;
  int _darkOp = 0;

  /// Номер последнего «Use», «Reset» или смены режима: чтение файла
  /// пользовательской темы применяется, только если с его начала не было
  /// более нового выбора.
  int _choice = 0;

  /// Номер последнего выбора: запись с меньшим номером обогнана.
  int _latest = 0;

  /// `close()` начат: новые выборы не принимаются, записи в полёте состояние не
  /// публикуют.
  bool _closing = false;
  int _inFlight = 0;
  Future<void> _tail = Future<void>.value();

  static bool _isBuiltIn(String id) => kBuiltInThemeIds.contains(id);

  static Brightness _builtInBrightness(String id) =>
      id == 'light' ? Brightness.light : Brightness.dark;

  static AppAppearanceState _stateOf(
    AppAppearanceSettings settings, {
    required ThemeLoaded? light,
    required ThemeLoaded? dark,
    required int? accent,
    required bool supported,
    bool saveFailed = false,
  }) {
    final accentColor = settings.systemAccent && accent != null
        ? Color(accent)
        : null;
    ThemeFile fileOf(String id, ThemeLoaded? loaded, String fallback) =>
        _isBuiltIn(id)
        ? builtInThemeFile(id)
        : (loaded?.theme ?? builtInThemeFile(fallback));
    final lightFailed = !_isBuiltIn(settings.lightTheme) && light == null;
    final darkFailed = !_isBuiltIn(settings.darkTheme) && dark == null;
    return AppAppearanceState(
      settings: settings,
      resolvedLight: buildFluentTheme(
        fileOf(settings.lightTheme, light, 'light'),
        systemAccent: accentColor,
      ),
      resolvedDark: buildFluentTheme(
        fileOf(settings.darkTheme, dark, 'dark'),
        systemAccent: accentColor,
      ),
      systemAccentSupported: supported,
      saveFailed: saveFailed,
      fallback: switch ((lightFailed, darkFailed)) {
        (true, true) => AppearanceFallback.both,
        (true, false) => AppearanceFallback.light,
        (false, true) => AppearanceFallback.dark,
        _ => AppearanceFallback.none,
      },
    );
  }

  /// Пересобирает темы из текущих данных и публикует состояние.
  void _publish(AppAppearanceSettings settings, {bool? saveFailed}) {
    if (isClosed) return;
    emit(
      _stateOf(
        settings,
        light: _light,
        dark: _dark,
        accent: _accent,
        supported: state.systemAccentSupported,
        saveFailed: saveFailed ?? state.saveFailed,
      ),
    );
  }

  String _logName(String id) => _isBuiltIn(id) ? id : 'custom';

  void _logChanged(String field, Object value) => _logger?.info(
    'settings.appearance_changed',
    context: {'field': field, 'value': value},
  );

  /// Выбирает режим оформления.
  ///
  /// Повторный выбор того же режима ничего не делает, кроме повторной записи
  /// после сбоя. Завершается, когда запись этого выбора закончена.
  Future<void> setMode(AppearanceMode mode) {
    if (isClosed || _closing) return Future<void>.value();
    if (mode == state.mode && !state.saveFailed) return _tail;
    // Новый выбор режима тоже отменяет ещё читающийся «Use»: иначе тот позже
    // переписал бы режим и тему поверх выбора пользователя.
    _choice++;
    final settings = state.settings.copyWith(mode: mode);
    _publish(settings, saveFailed: false);
    _logChanged('mode', mode.name);
    return _enqueue(settings, ++_latest);
  }

  /// Назначает тему [id] её режиму («Use»).
  ///
  /// Встроенную применяет сразу; пользовательскую читает из каталога и
  /// разбирает: тема, которая не загрузилась, не назначается. Если «Mode»
  /// зафиксирован на другом режиме, он переключается на режим темы, чтобы
  /// выбор был виден сразу; при `Match system` не меняется.
  Future<void> useTheme(String id) async {
    if (isClosed || _closing) return;
    // Номер выбора берётся в начале КАЖДОГО вызова: пользовательская тема
    // дочитывается из файла, и «Use A», «Use B» с первым дочитанным A иначе
    // оставили бы A. Побеждает последний выбор (D13).
    final choice = ++_choice;
    if (_isBuiltIn(id)) {
      _bumpOp(_builtInBrightness(id));
      return _assign(id, null);
    }
    final loaded = await _readLoaded(id);
    if (isClosed || _closing) return;
    if (loaded == null) return;
    // Более новый выбор (или «Reset») начался, пока файл читался: результат
    // устарел.
    if (choice != _choice) return;
    final brightness = loaded.theme.base == ThemeBase.light
        ? Brightness.light
        : Brightness.dark;
    _bumpOp(brightness);
    return _assign(id, loaded, brightness: brightness);
  }

  /// Возвращает режиму [brightness] встроенную тему по умолчанию («Reset»).
  Future<void> resetTheme(Brightness brightness) async {
    if (isClosed || _closing) return;
    _choice++;
    _bumpOp(brightness);
    return _assign(brightness == Brightness.light ? 'light' : 'dark', null);
  }

  void _bumpOp(Brightness brightness) =>
      brightness == Brightness.light ? _lightOp++ : _darkOp++;

  Future<void> _assign(
    String id,
    ThemeLoaded? loaded, {
    Brightness? brightness,
  }) {
    final target = brightness ?? _builtInBrightness(id);
    var settings = state.settings;
    var modeChanged = false;
    if (target == Brightness.light) {
      _light = loaded;
      settings = settings.copyWith(lightTheme: id);
    } else {
      _dark = loaded;
      settings = settings.copyWith(darkTheme: id);
    }
    final fixed = switch (settings.mode) {
      AppearanceMode.light => Brightness.light,
      AppearanceMode.dark => Brightness.dark,
      AppearanceMode.system => null,
    };
    if (fixed != null && fixed != target) {
      settings = settings.copyWith(
        mode: target == Brightness.light
            ? AppearanceMode.light
            : AppearanceMode.dark,
      );
      modeChanged = true;
    }
    _publish(settings, saveFailed: false);
    _logChanged(
      target == Brightness.light ? 'light_theme' : 'dark_theme',
      _logName(id),
    );
    if (modeChanged) _logChanged('mode', settings.mode.name);
    return _enqueue(settings, ++_latest);
  }

  /// Включает или выключает системный акцент.
  ///
  /// Включённый акцент заменяет `accent` любой темы (Q4). Ошибка чтения не
  /// отменяет выбор пользователя: применяется `accent` темы, пишется событие
  /// `appearance.system_accent_failed`.
  Future<void> setSystemAccent(bool enabled) async {
    if (isClosed || _closing) return;
    if (enabled == state.systemAccent && !state.saveFailed) {
      await _tail;
      return;
    }
    final settings = state.settings.copyWith(systemAccent: enabled);
    _publish(settings, saveFailed: false);
    _logChanged('system_accent', enabled);
    final write = _enqueue(settings, ++_latest);
    if (enabled && state.systemAccentSupported) await _readAccent();
    await write;
  }

  /// Перечитывает файл темы [id], если она назначена режиму («Reload»).
  ///
  /// Файл не загрузился — режим показывает встроенную тему, выбор остаётся.
  /// Поздний результат после более нового чтения или выбора того же режима
  /// отбрасывается.
  Future<void> reloadTheme(String id) async {
    if (isClosed || _closing || _isBuiltIn(id)) return;
    final inLight = state.lightTheme == id;
    final inDark = state.darkTheme == id;
    if (!inLight && !inDark) return;
    final brightness = inLight ? Brightness.light : Brightness.dark;
    _bumpOp(brightness);
    final token = brightness == Brightness.light ? _lightOp : _darkOp;
    final loaded = await _readLoaded(id, expected: brightness);
    if (isClosed || _closing) return;
    if (token != (brightness == Brightness.light ? _lightOp : _darkOp)) {
      return;
    }
    if (brightness == Brightness.light) {
      _light = loaded;
    } else {
      _dark = loaded;
    }
    _publish(state.settings);
  }

  /// Перечитывает системный акцент (открытие страницы «Appearance»; Linux не
  /// сообщает о смене, D7). Одно чтение, без опроса.
  Future<void> refreshSystemAccent() async {
    if (isClosed || _closing || !state.systemAccentSupported) return;
    await _readAccent();
  }

  /// Повторяет запись текущего выбора после сбоя (`Retry`).
  Future<void> retrySave() {
    if (isClosed || _closing) return Future<void>.value();
    _publish(state.settings, saveFailed: false);
    return _enqueue(state.settings, ++_latest);
  }

  /// Читает порт акцента и применяет результат; ошибка — `accent` темы.
  Future<void> _readAccent() async {
    int? value;
    try {
      value = await _accentSource.read();
    } on Object catch (error) {
      _onAccentFailed(error);
      return;
    }
    _applyAccent(value);
  }

  void _onAccentChanged(int? value) => _applyAccent(value);

  void _applyAccent(int? value) {
    if (isClosed || _closing || value == _accent) return;
    _accent = value;
    _publish(state.settings);
  }

  void _onAccentFailed(Object error) {
    // Только класс ошибки: в тексте исключения плагина бывают пути (AGENTS.md
    // §16).
    _logger?.warning(
      'appearance.system_accent_failed',
      context: {'error_class': error.runtimeType.toString()},
    );
    if (isClosed || _closing || _accent == null) return;
    _accent = null;
    _publish(state.settings);
  }

  /// Читает и разбирает файл темы [name]; `null` — темы нет или она не
  /// загрузилась (причина пишется событием без имени и текста файла).
  ///
  /// [expected] — режим, которому назначается тема при перечитывании: база,
  /// относящаяся к другому режиму, даёт `wrongMode` (spec app-settings «База
  /// пользовательской темы сменила режим»). Без [expected] режим берётся из
  /// базы самой темы (`useTheme`).
  Future<ThemeLoaded?> _readLoaded(String name, {Brightness? expected}) async {
    final ThemeEntry? entry;
    try {
      entry = await _library.read(name);
    } on Object catch (error) {
      // Код общий, класс ошибки — отдельным полем: текст исключения порта
      // может содержать пути (AGENTS.md §16).
      _logInvalid('unreadable', 0, 0, errorClass: error.runtimeType.toString());
      return null;
    }
    if (entry == null) {
      _logInvalid('missing', 0, 0);
      return null;
    }
    final text = entry.text;
    if (text == null) {
      _logInvalid(entry.error?.name ?? 'unreadable', 0, 0);
      return null;
    }
    final parsed = ThemeFile.parse('$name.json', text);
    switch (parsed) {
      case ThemeRejected(:final issue):
        _logInvalid(issue.code.name, issue.line, issue.column);
        return null;
      case ThemeLoaded loaded:
        final brightness = loaded.theme.base == ThemeBase.light
            ? Brightness.light
            : Brightness.dark;
        if (expected != null && expected != brightness) {
          _logInvalid('wrongMode', 0, 0);
          return null;
        }
        _logger?.info(
          'appearance.theme_loaded',
          context: {
            'theme': 'custom',
            'extends': loaded.theme.base.jsonName,
            'warnings': loaded.warnings.length,
            // Счётчики по кодам, а не массив: число предупреждений в файле
            // не ограничено, а журнал — да (spec «События журнала»).
            'code_counts': _codeCounts(loaded.warnings),
          },
        );
        return loaded;
    }
  }

  /// Счётчики предупреждений по кодам за один проход: файл до 64 КиБ даёт до
  /// десятков тысяч предупреждений, квадратичный подсчёт повесил бы UI isolate.
  static Map<String, int> _codeCounts(List<ThemeIssue> warnings) {
    final counts = <String, int>{};
    for (final warning in warnings) {
      counts.update(warning.code.name, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  void _logInvalid(String code, int line, int column, {String? errorClass}) =>
      _logger?.warning(
        'appearance.theme_invalid',
        context: {
          'theme': 'custom',
          'code': code,
          'line': line,
          'column': column,
          'error_class': ?errorClass,
        },
      );

  /// Ставит запись в очередь; при пустой очереди начинает её сразу.
  Future<void> _enqueue(AppAppearanceSettings settings, int token) {
    final Future<void> run = _inFlight == 0
        ? _write(settings, token)
        : _tail.then((_) => _write(settings, token));
    _inFlight++;
    _tail = run.whenComplete(() => _inFlight--);
    return run;
  }

  Future<void> _write(AppAppearanceSettings settings, int token) async {
    try {
      await _preferences.save(settings);
    } on Object catch (error) {
      _logger?.warning(
        'appearance.save_failed',
        context: {'error_class': error.runtimeType.toString()},
      );
      if (!isClosed && !_closing && token == _latest) {
        emit(state.copyWith(saveFailed: true));
      }
    }
  }

  /// Закрывает владельца: отменяет подписку на акцент, ждёт идущую запись не
  /// дольше срока и только потом закрывает Cubit.
  ///
  /// Запись ждём, чтобы последний выбор пользователя дошёл до хранилища до
  /// выхода из app; состояние после этого не публикуется (`concurrency.md`
  /// §47б).
  @override
  Future<void> close() async {
    _closing = true;
    final subscription = _accentSubscription;
    _accentSubscription = null;
    if (subscription != null) await subscription.cancel();
    await _tail.timeout(
      _closeWriteTimeout,
      // Запись не успела: выбор мог не дойти до хранилища. Только срок — без
      // выбора и текста ошибки.
      onTimeout: () => _logger?.warning(
        'appearance.save_timeout',
        context: {'timeout_ms': _closeWriteTimeout.inMilliseconds},
      ),
    );
    return super.close();
  }
}
