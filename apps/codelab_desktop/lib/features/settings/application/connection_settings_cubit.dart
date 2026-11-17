import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        ConnectionProfile,
        Connected,
        ConnectionView,
        OwnSecretOutcome,
        ProfileCommitter,
        ProfileNotFound,
        ProfileRemoved,
        Reconnecting,
        ProfileSecrets,
        ProfileStore,
        RemoveFailed,
        SecretTokenRef,
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
        SecretTokenView,
        UnsupportedTokenView,
        profileOrigin;

/// Страница «Connection»: список профилей, профиль по умолчанию, «Behavior».
///
/// Почему: один владелец данных страницы — файл профилей, выбор по умолчанию
/// читается и пишется здесь, а не в виджете
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
/// журнал не попадает: из окружения читается только признак «задана», у
/// секрета хранилища — только `isSet` (design.md change
/// `add-provider-setup-ui`, D14); события журнала — по D17 и D18, без путей,
/// текстов исключений, имён переменных и секретов. [removeProfile] удаляет
/// профиль и, по флажку, его собственный секрет токена через
/// `ProfileCommitter`: сначала профиль, потом секрет (SETUP-24).
class ConnectionSettingsCubit extends Cubit<ConnectionSettingsState> {
  ConnectionSettingsCubit({
    required ProfileStore store,
    required Future<ProfileSecrets> Function() openSecrets,
    required ConnectionPreferences preferences,
    required ClientWorkspace workspace,
    required ConnectionCommands commands,
    required Map<String, String> environment,
    required String? profilesPath,
    Logger? logger,
  }) : _store = store,
       _openSecrets = openSecrets,
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

  /// Фабрика открытия хранилища секретов: оно переоткрывается при каждом
  /// открытии страницы, чтобы правка `secrets.backend` применялась без
  /// перезапуска (ревью итерации 1, design.md change `add-provider-setup-ui`,
  /// D3). Пока оно открывается, состояние — [ConnectionSettingsLoading].
  final Future<ProfileSecrets> Function() _openSecrets;

  /// Открытие хранилища этой страницы: одно на жизнь Cubit, повторные
  /// [reload] его переиспользуют.
  Future<ProfileSecrets>? _opening;
  ProfileSecrets? _secrets;
  ProfileCommitter? _committer;

  /// Есть ли секреты, на которые ссылаются профили страницы (`isSet`, без
  /// чтения значения). Заполняется в [reload].
  var _secretSet = <String, bool>{};
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
  ConnectionProfile? _seenAttempt;
  ConnectionView? _seenConnection;
  String? _seenProject;
  String? _seenAgentDirectory;

  /// Профили, о ссылке которых уже писали в журнал: событие один раз за жизнь
  /// Cubit, а не на каждое перечитывание.
  final _reportedTokenRefs = <String>{};

  /// Читает файл и настройки; вызывается при открытии страницы и после
  /// каждой собственной записи.
  Future<void> reload() async {
    final attempt = ++_loadAttempt;
    final secrets = _secrets ?? await (_opening ??= _openSecrets());
    if (isClosed) {
      // Поздний результат открытия после закрытия страницы отбрасывается.
      return;
    }
    if (_secrets == null) {
      _secrets = secrets;
      _committer = ProfileCommitter(store: _store, secrets: secrets);
    }
    List<ConnectionProfile>? loaded;
    Object? loadError;
    try {
      loaded = await _store.load();
    } on Object catch (error) {
      loadError = error;
    }
    var savedDefault = await _readOrNull(_preferences.loadDefaultProfileId);
    if (isClosed || attempt != _loadAttempt) {
      return;
    }

    if (loaded == null) {
      _readable = false;
      _stored = const [];
      _ignoredDefault = false;
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
    final secretStatus = await _loadSecretStatus(usable);
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
    _secretSet = secretStatus;
    _defaultId = savedDefault ?? embeddedProfileId;
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
      _fail(id, error.runtimeType.toString(), stage: 'default');
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

  /// «Use» (D18): делает профиль [id] профилем следующего старта агента.
  /// Работающий агент и профиль по умолчанию не меняются (D5).
  Future<void> use(String id) async {
    final rows = switch (state) {
      ConnectionSettingsReady(:final rows) ||
      ConnectionSettingsUnreadable(:final rows) => rows,
      ConnectionSettingsLoading() => const <ConnectionProfileRow>[],
    };
    for (final row in rows) {
      if (row.id == id) {
        await _commands.use(row.profile);
        return;
      }
    }
  }

  /// «Restart agent» (D9, D22): перезапуск выбранным профилем. Недоступна без
  /// корня процесса — и при прямом вызове. Подтверждение при работе — у
  /// `ConnectionCubit`.
  Future<void> restartAgent() async {
    final current = state;
    if (current is! ConnectionSettingsLoaded || !current.canRestart) {
      return;
    }
    await _commands.restart();
  }

  /// Удаляет профиль [id] из файла; `true` — запись удалена.
  ///
  /// Встроенный агент и профиль текущего подключения отклоняются здесь, до
  /// `ProfileStore.remove`, а не только недоступностью кнопки; битый файл
  /// не трогается (spec app-settings «Rename» и «Remove» профиля).
  ///
  /// [deleteOwnSecret] — флажок «Also delete the stored token»: секрет
  /// `codelab/profiles/<id>/token` удаляется только после успешной записи
  /// файла, только если профиль ссылается именно на него и больше никто на
  /// него не ссылается (SETUP-24; решает `ProfileCommitter`). Отказ удаления
  /// секрета профиль не возвращает: страница называет команду
  /// `codelab secret delete` (D13, D18).
  Future<bool> removeProfile(String id, {bool deleteOwnSecret = false}) async {
    final current = state;
    if (current is! ConnectionSettingsReady) {
      return false;
    }
    final row = current.rows.where((r) => r.id == id).firstOrNull;
    if (row == null || !row.canRemove) {
      return false;
    }
    final result = await _committer!.remove(
      id,
      deleteOwnSecret: deleteOwnSecret,
    );
    if (isClosed) {
      return result is ProfileRemoved;
    }
    switch (result) {
      case RemoveFailed():
        _fail(id, result.errorType ?? 'RemoveFailed', stage: 'profile');
        return false;
      case ProfileNotFound():
        await reload();
        return false;
      case ProfileRemoved(:final secret, :final secretName):
        _logger?.info(
          'connection_profile.removed',
          context: {'profile_id': id},
        );
        if (secret == OwnSecretOutcome.deleted) {
          _logger?.info(
            'connection_profile.token_deleted',
            context: {'profile_id': id, 'backend': _secrets!.backend.id},
          );
        } else if (secret == OwnSecretOutcome.deleteFailed) {
          _logger?.warning(
            'connection_profile.token_delete_failed',
            context: {
              'profile_id': id,
              'backend': _secrets!.backend.id,
              'error_type': 'SecretDeleteFailed',
            },
          );
        }
        if (_defaultId == id) {
          await _tryDropDefault();
        }
        await reload();
        if (secret == OwnSecretOutcome.deleteFailed && !isClosed) {
          // После `reload`: он сбрасывает прежнюю ошибку страницы.
          _failure =
              'The profile was removed, but the stored token $secretName was '
              'not deleted. Remove it with codelab secret delete $secretName.';
          _publish();
        }
        return true;
    }
  }

  /// «Rename»: меняет только `label` профиля [id]; `true` — запись изменена.
  ///
  /// Профиль берётся из файла как он есть сейчас, а не из копии страницы:
  /// поле, которое успел поменять CLI, не теряется. Встроенный агент, неизвестный
  /// id, пустое имя и нечитаемый файл отклоняются здесь, а не только
  /// недоступной кнопкой (spec app-settings «Rename» и «Remove» профиля).
  Future<bool> renameProfile(String id, String label) async {
    final current = state;
    final text = label.trim();
    if (current is! ConnectionSettingsReady || text.isEmpty) {
      return false;
    }
    final row = current.rows.where((r) => r.id == id).firstOrNull;
    if (row == null || !row.hasFileActions) {
      return false;
    }
    try {
      final stored = await _store.load();
      final profile = stored.where((p) => p.id == id).firstOrNull;
      if (profile == null) {
        await reload();
        return false;
      }
      await _store.save(profile.copyWith(label: text));
    } on Object catch (error) {
      _fail(id, error.runtimeType.toString(), stage: 'profile');
      return false;
    }
    if (isClosed) {
      return true;
    }
    // Имя в журнал не пишется: оно может оказаться чем угодно (D17).
    _logger?.info('connection_profile.renamed', context: {'profile_id': id});
    await reload();
    return true;
  }

  /// Диалог «Add connection profile» записал профили: перечитывает файл,
  /// чтобы страница показала все строки.
  ///
  /// Диалог мог записать несколько профилей за одно открытие («Add
  /// another»), поэтому страница зовёт метод один раз после закрытия
  /// (`remove-test-connection`, D1).
  Future<void> profilesChanged() => reload();

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
      _fail('default', error.runtimeType.toString(), stage: 'profile');
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
            workspace.profile == _seenAttempt &&
            workspace.projectDirectory == _seenProject &&
            workspace.agentDirectory == _seenAgentDirectory)) {
      return;
    }
    _publish();
  }

  /// Выбранный или работающий профиль сменился: «Selected», «Current» и
  /// подпись Restart/Reconnect. Сигнал приходит и при смене только работающего
  /// профиля (выбранный тот же), поэтому публикуем всегда.
  void _onTarget(ConnectionProfile? target) {
    if (state is ConnectionSettingsLoaded) {
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
    // «Current» — профиль работающего агента при живом соединении (решение
    // пользователя 2026-11-05); «Selected» — выбранный для следующего старта
    // (D18). Это разные профили, пока пользователь не нажал «Restart agent».
    final running = _commands.runningProfile;
    final attempt = workspace.profile;
    final live =
        workspace.connection is Connected ||
        workspace.connection is Reconnecting;
    final current = live && running != null && attempt?.id == running.id
        ? running
        : null;
    bool selected(String id) => target?.id == id;
    _seenAttempt = attempt;
    _seenConnection = workspace.connection;
    _seenProject = workspace.projectDirectory;
    _seenAgentDirectory = workspace.agentDirectory;
    // Бейдж — у строки профиля последней попытки (`WorkspaceState.profile`):
    // он показывает исход попытки, в том числе неудачной, где «Current» нет.
    final connectionStatus = ConnectionRowStatus.of(workspace.connection);
    ConnectionRowStatus? statusOf(String id) =>
        attempt?.id == id ? connectionStatus : null;
    final embedded = ConnectionProfileRow.embedded(
      profile: embeddedConnectionProfile,
      isDefault: _defaultId == embeddedProfileId,
      isCurrent: current?.id == embeddedProfileId,
      isSelected: selected(embeddedProfileId),
      status: statusOf(embeddedProfileId),
    );
    if (!_readable) {
      emit(
        ConnectionSettingsUnreadable(
          rows: [embedded],
          restartTarget: target,
          currentProfile: current,
          connection: workspace.connection,
          restartAvailable: _commands.restartDirectory != null,
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
          token: profile is WebSocketProfile ? _tokenView(profile) : null,
          isDefault: _defaultId == profile.id,
          isCurrent: current?.id == profile.id,
          isSelected: selected(profile.id),
          status: statusOf(profile.id),
        ),
    ];
    if (current != null &&
        current.id != embeddedProfileId &&
        !_stored.any((profile) => profile.id == current.id)) {
      rows.add(
        ConnectionProfileRow.unsaved(
          profile: current,
          token: current is WebSocketProfile ? _tokenView(current) : null,
          isSelected: selected(current.id),
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
        restartAvailable: _commands.restartDirectory != null,
        ignoredDefaultEntry: _ignoredDefault,
        failure: _failure,
      ),
    );
  }

  /// Сбой записи: на экране — общий текст, в журнале — только имя типа
  /// (`error.toString()` может нести секрет, D17).
  ///
  /// [stage] — что не записалось: `profile` (файл профилей: «Rename»,
  /// «Remove») или `default` (ключ профиля по умолчанию); без значения — для
  /// прочих настроек страницы (D17).
  void _fail(String profileId, String errorType, {String? stage}) {
    _logger?.warning(
      'connection_profile.save_failed',
      context: {
        if (profileId.isNotEmpty) 'profile_id': profileId,
        'error_type': errorType,
        'stage': ?stage,
      },
    );
    _failure = 'Could not save the change. Try again.';
    _publish();
  }

  /// Вид токена для строки: наличие секрета известно из последнего
  /// [reload], значение не читается.
  ProfileTokenView _tokenView(WebSocketProfile profile) => tokenViewOf(
    profile,
    _environment,
    secretBackend: _secrets!.backend.id,
    secretIsSet: (name) => _secretSet[name] ?? false,
  );

  /// `isSet` для каждого секрета, на который ссылаются профили страницы и
  /// цель перезапуска. Нечитаемое хранилище даёт «нет»: страница не падает,
  /// строка честно говорит `missing`; текст ошибки не пишется (D17).
  Future<Map<String, bool>> _loadSecretStatus(
    List<ConnectionProfile> profiles,
  ) async {
    final names = <String>{
      for (final profile in [...profiles, ?_commands.restartTarget])
        if (profile is WebSocketProfile && profile.tokenRef != null)
          if (ProfileTokenRef.parse(profile.tokenRef!) case SecretTokenRef(
            :final name,
          ))
            name,
    };
    final status = <String, bool>{};
    for (final name in names) {
      try {
        status[name] = await _secrets!.isSet(name);
      } on Object {
        status[name] = false;
      }
    }
    return status;
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
