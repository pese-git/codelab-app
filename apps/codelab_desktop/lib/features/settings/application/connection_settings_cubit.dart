import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        ConnectionProfile,
        Connected,
        ConnectionView,
        Reconnecting,
        ProfileStore,
        UnsupportedTokenRef,
        ProfileTokenRef,
        WebSocketProfile,
        WorkspaceState,
        usableStoredProfiles;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/connection_preferences.dart';
import 'connection_commands.dart';
import 'connection_settings_state.dart';
import 'embedded_profile.dart';
import 'profiles_unavailable.dart';
import 'profile_view.dart';

export 'connection_settings_state.dart';
export 'profile_view.dart'
    show
        EnvTokenView,
        NoTokenView,
        ProfileTokenView,
        UnsupportedTokenView,
        profileOrigin;

/// Страница «Connection»: список профилей, профиль по умолчанию, «Behavior».
///
/// Почему: один владелец данных страницы — файл профилей, выбор по умолчанию
/// и «Connect on start» читаются и пишутся здесь, а не в виджете
/// (`state-management.md` §13, §22; design.md change `add-app-settings-shell`,
/// D4, D5, D8–D10).
///
/// Для чего: собирает [ConnectionSettingsState] из `ProfileStore`
/// (`$CODELAB_HOME/profiles.json`), `ConnectionPreferences` и `WorkspaceState`
/// (профиль и соединение окна). Подключение выполняет не он, а
/// [ConnectionCommands] (`ConnectionCubit`).
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// страницы и зовёт [reload] — файл перечитывается при открытии и после
/// каждой собственной записи; слежения за файлом нет (правка CLI видна при
/// следующем открытии). Поздний результат чтения отбрасывается номером
/// попытки (AGENTS.md §9). Битый или незнакомый файл не перезаписывается:
/// [ConnectionSettingsUnreadable], а [removeProfile] и
/// [removeIgnoredDefault] ничего не делают. Значение токена в состояние и в
/// журнал не попадает: из окружения читается только признак «задана»;
/// события журнала — по D17, без путей, текстов исключений и имён переменных.
class ConnectionSettingsCubit extends Cubit<ConnectionSettingsState> {
  ConnectionSettingsCubit({
    required ProfileStore store,
    required ConnectionPreferences preferences,
    required ClientWorkspace workspace,
    required ConnectionCommands commands,
    required Map<String, String> environment,
    required String? profilesPath,
    Logger? logger,
  }) : _store = store,
       _preferences = preferences,
       _workspace = workspace,
       _commands = commands,
       _environment = environment,
       _profilesPath = profilesPath,
       _logger = logger,
       super(const ConnectionSettingsLoading()) {
    _workspaceSubscription = _workspace.state.listen(_onWorkspace);
    _targetSubscription = _commands.restartTargets.listen(_onTarget);
  }

  final ProfileStore _store;
  final ConnectionPreferences _preferences;
  final ClientWorkspace _workspace;
  final ConnectionCommands _commands;

  /// Окружение app: читается только «задана ли переменная» (D13).
  final Map<String, String> _environment;
  final String? _profilesPath;
  final Logger? _logger;
  late final StreamSubscription<WorkspaceState> _workspaceSubscription;
  late final StreamSubscription<ConnectionProfile?> _targetSubscription;

  /// Номер чтения: результат, пришедший после более нового [reload],
  /// отбрасывается.
  var _loadAttempt = 0;

  // Загруженные данные; состояние собирается из них и из `WorkspaceState`.
  List<ConnectionProfile> _stored = const [];
  var _defaultId = embeddedProfileId;
  var _connectOnStart = false;
  var _ignoredDefault = false;
  String? _failure;
  var _readable = false;

  /// Причина и путь для [ConnectionSettingsUnreadable].
  String _unreadableReason = '';

  /// «Игнорируемая запись default» уже записана в журнал: событие один раз за
  /// жизнь страницы, а не при каждом [reload] (D17).
  var _ignoredReported = false;
  var _unreadableReported = false;

  // Последние учтённые цель перезапуска, профиль попытки и соединение
  // workspace: `_publish` нужен только при их смене, а не при каждом
  // изменении списка сессий.
  ConnectionProfile? _seenTarget;
  ConnectionProfile? _seenAttempt;
  ConnectionView? _seenConnection;

  /// Профили, о ссылке которых уже писали в журнал: событие один раз за жизнь
  /// Cubit, а не на каждое перечитывание.
  final _reportedTokenRefs = <String>{};

  /// Читает файл и настройки; вызывается при открытии страницы и после
  /// каждой собственной записи.
  Future<void> reload() async {
    final attempt = ++_loadAttempt;
    List<ConnectionProfile>? loaded;
    Object? loadError;
    try {
      loaded = await _store.load();
    } on Object catch (error) {
      loadError = error;
    }
    var savedDefault = await _readOrNull(_preferences.loadDefaultProfileId);
    final connectOnStart =
        await _readOrNull(_preferences.loadConnectOnStart) ?? false;
    if (isClosed || attempt != _loadAttempt) {
      return;
    }

    if (loaded == null) {
      _readable = false;
      _stored = const [];
      _ignoredDefault = false;
      _connectOnStart = connectOnStart;
      _defaultId = embeddedProfileId;
      _unreadableReason = _reasonOf(loadError!);
      // Один раз за жизнь страницы: после каждой собственной записи файл
      // перечитывается, и событие повторялось бы.
      if (!_unreadableReported) {
        _unreadableReported = true;
        _logger?.warning(
          'connection_profile.unreadable',
          context: {'error_type': loadError.runtimeType.toString()},
        );
      }
      _publish();
      return;
    }

    final (:usable, :ignoredDefault) = usableStoredProfiles(loaded);
    if (savedDefault != null &&
        savedDefault != embeddedProfileId &&
        !usable.any((profile) => profile.id == savedDefault)) {
      // Профиль удалили (например, из CLI): выбор без профиля сбрасывается.
      await _tryDropDefault();
      _logger?.info('connection_profile.default_reset');
      savedDefault = null;
    }
    if (isClosed || attempt != _loadAttempt) {
      return;
    }
    _readable = true;
    _stored = usable;
    _defaultId = savedDefault ?? embeddedProfileId;
    _connectOnStart = connectOnStart;
    _ignoredDefault = ignoredDefault;
    _failure = null;
    if (ignoredDefault && !_ignoredReported) {
      _ignoredReported = true;
      // Только факт: поля записи (команда, аргументы, env) не пишутся.
      _logger?.warning('connection_profile.default_ignored');
    }
    for (final profile in usable) {
      if (profile is WebSocketProfile &&
          profile.tokenRef != null &&
          ProfileTokenRef.parse(profile.tokenRef!) is UnsupportedTokenRef &&
          _reportedTokenRefs.add(profile.id)) {
        _logger?.warning(
          'connection_profile.token_ref_unsupported',
          context: {'profile_id': profile.id},
        );
      }
    }
    _publish();
  }

  /// Делает [id] профилем по умолчанию; `embedded` удаляет ключ. Неизвестный
  /// id игнорируется.
  Future<void> selectDefault(String id) async {
    final known = id == embeddedProfileId || _stored.any((p) => p.id == id);
    if (!known || state is ConnectionSettingsLoading) {
      return;
    }
    try {
      await _preferences.saveDefaultProfileId(
        id == embeddedProfileId ? null : id,
      );
    } on Object catch (error) {
      _fail(id, error);
      return;
    }
    if (isClosed) {
      return;
    }
    _defaultId = id;
    _failure = null;
    _logger?.info(
      'connection_profile.default_changed',
      context: {'profile_id': id},
    );
    _publish();
    // Перечитываем после записи: чтение в полёте могло взять старый выбор, и
    // более новое чтение вытесняет его номером попытки.
    await reload();
  }

  /// Подключает окно к профилю [id]; профиль по умолчанию не меняется (D5).
  Future<void> connect(String id) async {
    final rows = switch (state) {
      ConnectionSettingsReady(:final rows) ||
      ConnectionSettingsUnreadable(:final rows) => rows,
      ConnectionSettingsLoading() => const <ConnectionProfileRow>[],
    };
    for (final row in rows) {
      if (row.id == id) {
        await _commands.connect(row.profile);
        return;
      }
    }
  }

  /// «Connect on start» (D8): сохраняется сразу, действует со следующего
  /// запуска.
  Future<void> setConnectOnStart(bool value) async {
    try {
      await _preferences.saveConnectOnStart(value);
    } on Object catch (error) {
      _fail('', error);
      return;
    }
    if (isClosed) {
      return;
    }
    _connectOnStart = value;
    _failure = null;
    _publish();
    await reload();
  }

  /// «Restart agent» (D9): переподключение текущим профилем. Недоступна без
  /// профиля и во время подключения — и при прямом вызове.
  Future<void> restartAgent() async {
    final current = state;
    if (current is! ConnectionSettingsLoaded || !current.canRestart) {
      return;
    }
    await _commands.reconnect();
  }

  /// Удаляет профиль [id] из файла; `true` — запись удалена.
  ///
  /// Встроенный агент и профиль текущего подключения отклоняются здесь, до
  /// `ProfileStore.remove`, а не только недоступностью кнопки; битый файл
  /// не трогается (spec app-settings «Rename» и «Remove» профиля).
  Future<bool> removeProfile(String id) async {
    final current = state;
    if (current is! ConnectionSettingsReady) {
      return false;
    }
    final row = current.rows.where((r) => r.id == id).firstOrNull;
    if (row == null || !row.canRemove) {
      return false;
    }
    final bool removed;
    try {
      removed = await _store.remove(id);
    } on Object catch (error) {
      _fail(id, error);
      return false;
    }
    if (isClosed) {
      return removed;
    }
    if (removed) {
      _logger?.info('connection_profile.removed', context: {'profile_id': id});
      if (_defaultId == id) {
        await _tryDropDefault();
      }
    }
    await reload();
    return removed;
  }

  /// Удаляет из файла прежнюю запись `default` после подтверждения на
  /// странице (D5, D21); остальные записи не трогает.
  Future<bool> removeIgnoredDefault() async {
    final current = state;
    if (current is! ConnectionSettingsReady || !current.ignoredDefaultEntry) {
      return false;
    }
    final bool removed;
    try {
      removed = await _store.remove('default');
    } on Object catch (error) {
      _fail('default', error);
      return false;
    }
    if (isClosed) {
      return removed;
    }
    if (removed) {
      _logger?.info('connection_profile.default_removed');
    }
    await reload();
    return removed;
  }

  @override
  Future<void> close() async {
    await _workspaceSubscription.cancel();
    await _targetSubscription.cancel();
    return super.close();
  }

  /// Страницу интересуют профиль и соединение; смена списка сессий её не
  /// перерисовывает.
  void _onWorkspace(WorkspaceState workspace) {
    if (state is! ConnectionSettingsLoaded ||
        (workspace.connection == _seenConnection &&
            workspace.profile == _seenAttempt)) {
      return;
    }
    _publish();
  }

  /// Цель перезапуска сменилась: «Current» и подпись Restart/Reconnect.
  void _onTarget(ConnectionProfile? target) {
    if (state is ConnectionSettingsLoaded && target != _seenTarget) {
      _publish();
    }
  }

  /// Собирает состояние страницы из загруженных данных и `WorkspaceState`
  /// (профиль и соединение окна): [ConnectionSettingsReady] или, если
  /// профили недоступны, [ConnectionSettingsUnreadable] с теми же строкой
  /// встроенного агента и блоком «Behavior».
  void _publish() {
    if (isClosed) {
      return;
    }
    final workspace = _workspace.current;
    // Цель перезапуска — не `WorkspaceState.profile`: workspace публикует
    // профиль в начале попытки, и после неудачи он указывал бы на профиль,
    // который не подключился (MEDIUM-A).
    final target = _commands.restartTarget;
    // «Current» — только цель с живым соединением: workspace подключён или
    // переподключается именно к ней (решение пользователя 2026-11-05).
    final attempt = workspace.profile;
    final live =
        workspace.connection is Connected ||
        workspace.connection is Reconnecting;
    final current = live && target != null && attempt?.id == target.id
        ? target
        : null;
    _seenTarget = target;
    _seenAttempt = attempt;
    _seenConnection = workspace.connection;
    // Бейдж — у строки профиля последней попытки (`WorkspaceState.profile`):
    // он показывает исход попытки, в том числе неудачной, где «Current» нет.
    final connectionStatus = ConnectionRowStatus.of(workspace.connection);
    ConnectionRowStatus? statusOf(String id) =>
        attempt?.id == id ? connectionStatus : null;
    final embedded = ConnectionProfileRow.embedded(
      profile: embeddedConnectionProfile,
      isDefault: _defaultId == embeddedProfileId,
      isCurrent: current?.id == embeddedProfileId,
      status: statusOf(embeddedProfileId),
    );
    if (!_readable) {
      emit(
        ConnectionSettingsUnreadable(
          rows: [embedded],
          restartTarget: target,
          currentProfile: current,
          connection: workspace.connection,
          connectOnStart: _connectOnStart,
          path: _profilesPath,
          reason: _unreadableReason,
          failure: _failure,
        ),
      );
      return;
    }
    final rows = <ConnectionProfileRow>[
      embedded,
      for (final profile in _stored)
        ConnectionProfileRow.stored(
          profile: profile,
          token: profile is WebSocketProfile
              ? tokenViewOf(profile, _environment)
              : null,
          isDefault: _defaultId == profile.id,
          isCurrent: current?.id == profile.id,
          status: statusOf(profile.id),
        ),
    ];
    if (current != null &&
        current.id != embeddedProfileId &&
        !_stored.any((profile) => profile.id == current.id)) {
      rows.add(
        ConnectionProfileRow.unsaved(
          profile: current,
          token: current is WebSocketProfile
              ? tokenViewOf(current, _environment)
              : null,
          status: statusOf(current.id),
        ),
      );
    }
    emit(
      ConnectionSettingsReady(
        rows: rows,
        defaultProfileId: _defaultId,
        restartTarget: target,
        currentProfile: current,
        connection: workspace.connection,
        connectOnStart: _connectOnStart,
        ignoredDefaultEntry: _ignoredDefault,
        failure: _failure,
      ),
    );
  }

  /// Сбой записи: на экране — общий текст, в журнале — только имя типа
  /// (`error.toString()` может нести секрет, D17).
  void _fail(String profileId, Object error) {
    _logger?.warning(
      'connection_profile.save_failed',
      context: {
        if (profileId.isNotEmpty) 'profile_id': profileId,
        'error_type': error.runtimeType.toString(),
      },
    );
    _failure = 'Could not save the change. Try again.';
    _publish();
  }

  Future<void> _tryDropDefault() async {
    try {
      await _preferences.saveDefaultProfileId(null);
    } on Object {
      // Ключ с id, которого нет, при следующем чтении будет сброшен снова.
    }
  }

  Future<T?> _readOrNull<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  /// Причина для экрана без текста исключения: оно может нести содержимое
  /// файла.
  static String _reasonOf(Object error) => switch (error) {
    ProfilesUnavailableException(:final message) => message,
    FormatException() =>
      'the file has an unsupported version or an invalid structure',
    _ => 'the file cannot be read (${error.runtimeType})',
  };
}
