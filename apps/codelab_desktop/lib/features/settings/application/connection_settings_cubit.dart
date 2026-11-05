import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        ConnectionProfile,
        Connected,
        ConnectionView,
        OwnSecretOutcome,
        ProbeCancellation,
        ProfileCommitter,
        ProfileNotFound,
        ProfileProbe,
        ProfileProbeOutcome,
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
import 'probe_outcome_view.dart';
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
    required ProfileProbe probe,
    required String Function() projectDirectory,
    Logger? logger,
  }) : _store = store,
       _openSecrets = openSecrets,
       _probe = probe,
       _projectDirectory = projectDirectory,
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

  /// Проверка профиля строки «Test connection» (D12); та же, что у диалога.
  final ProfileProbe _probe;

  /// Папка проекта для stdio-профилей с «Run in the project folder».
  final String Function() _projectDirectory;
  late final StreamSubscription<WorkspaceState> _workspaceSubscription;
  late final StreamSubscription<ConnectionProfile?> _targetSubscription;

  /// Номер чтения: результат, пришедший после более нового [reload],
  /// отбрасывается.
  var _loadAttempt = 0;

  /// Исходы проверок за жизнь страницы (D14).
  final _probes = <String, ProfileProbeOutcome>{};

  /// Профиль, для которого получен исход в [_probes]: после перечитывания
  /// исход остаётся, только если профиль с тем же id не изменился (другой
  /// URL, команда или ссылка на токен) — иначе метка «проверен» относилась бы
  /// к чужой конфигурации (целостность данных, корневой `AGENTS.md` §2).
  final _probedProfiles = <String, ConnectionProfile>{};

  /// Успешные проверки диалога, ещё не привязанные к прочитанному профилю.
  final _pendingTested = <String, ProfileProbeOutcome>{};

  /// Идущие проверки строк: id → (номер, отмена). Новая проверка той же
  /// строки и `close()` отменяют прежнюю (AGENTS.md §9).
  final _probing = <String, ({int operation, ProbeCancellation cancel})>{};
  var _probeSeq = 0;

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
    // Исход удалённого (например, из CLI) профиля не переживает перечитывание.
    // Исход изменённого профиля тоже сбрасывается: сравнение целиком.
    _probes.removeWhere((id, _) {
      final stored = usable.where((p) => p.id == id).firstOrNull;
      final probed = _probedProfiles[id];
      return stored == null ||
          probed == null ||
          !_sameConnection(stored, probed);
    });
    _probedProfiles.removeWhere((id, _) => !_probes.containsKey(id));
    // Исходы диалога привязываются к только что прочитанному профилю; чтение,
    // вытесненное более новым, их не теряет — они ждут в `_pendingTested`.
    for (final MapEntry(:key, :value) in _pendingTested.entries) {
      final added = usable.where((p) => p.id == key).firstOrNull;
      if (added != null) {
        _probes[key] = value;
        _probedProfiles[key] = added;
      }
    }
    _pendingTested.clear();
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
      _fail('', error.runtimeType.toString());
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

  /// «Test connection» строки [id]: один `initialize` без сессии (D12).
  ///
  /// Исход остаётся за страницей до закрытия ([ConnectionSettingsLoaded.lastProbes])
  /// и снимает метку «Not tested». Недоступна для встроенного агента (Q4) и
  /// неизвестных id. Повторный вызов и `close()` отменяют идущую проверку.
  Future<void> testProfile(String id) async {
    final current = state;
    if (current is! ConnectionSettingsReady) {
      return;
    }
    final row = current.rows.where((r) => r.id == id).firstOrNull;
    if (row == null || !row.hasFileActions) {
      return;
    }
    _probing[id]?.cancel.cancel();
    final operation = ++_probeSeq;
    final cancellation = ProbeCancellation();
    _probing[id] = (operation: operation, cancel: cancellation);
    _logger?.info(
      'connection_profile.probe_started',
      context: {
        'operation_id': operation,
        'profile_id': id,
        'type': row.profile is WebSocketProfile ? 'websocket' : 'stdio',
      },
    );
    _publish();
    final stopwatch = Stopwatch()..start();
    final outcome = await _probe.probe(
      row.profile,
      projectDirectory: _projectDirectory(),
      cancellation: cancellation,
    );
    // Файл могли перечитать за время проверки: исход профиля, который
    // изменился по значимым полям (или исчез), относится к чужой конфигурации.
    final storedNow = _stored.where((p) => p.id == id).firstOrNull;
    final changed =
        storedNow == null || !_sameConnection(storedNow, row.profile);
    if (isClosed ||
        _probing[id]?.operation != operation ||
        outcome == null ||
        changed) {
      _logger?.debug(
        'connection_profile.probe_discarded',
        context: {'operation_id': operation, 'profile_id': id},
      );
      return;
    }
    _probing.remove(id);
    _probes[id] = outcome;
    _probedProfiles[id] = row.profile;
    _logger?.info(
      'connection_profile.probe_finished',
      context: {
        'operation_id': operation,
        'profile_id': id,
        'outcome': probeOutcomeName(outcome),
        'duration_ms': stopwatch.elapsedMilliseconds,
      },
    );
    _publish();
  }

  /// Профиль [id] записан диалогом «Add connection profile»: запоминает
  /// успешную проверку диалога ([tested]) и перечитывает файл.
  ///
  /// Без успешной проверки строка остаётся с меткой «Not tested» (D14).
  Future<void> profileAdded(String id, ProfileProbeOutcome? tested) async {
    if (tested != null) {
      _pendingTested[id] = tested;
    }
    await reload();
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
    // Закрытие страницы отменяет идущие проверки строк: транспорты
    // закрываются, исходы отбрасываются.
    for (final probing in _probing.values) {
      probing.cancel.cancel();
    }
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
          lastProbes: Map.unmodifiable(_probes),
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
          status: statusOf(profile.id),
          probe: _probes[profile.id],
          isProbing: _probing.containsKey(profile.id),
        ),
    ];
    if (current != null &&
        current.id != embeddedProfileId &&
        !_stored.any((profile) => profile.id == current.id)) {
      rows.add(
        ConnectionProfileRow.unsaved(
          profile: current,
          token: current is WebSocketProfile ? _tokenView(current) : null,
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
        lastProbes: Map.unmodifiable(_probes),
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

/// Совпадают ли профили по тому, что определяет подключение: имя (`label`)
/// не в счёт, поэтому «Rename» не сбрасывает метку «проверен».
bool _sameConnection(ConnectionProfile a, ConnectionProfile b) =>
    a.copyWith(label: '') == b.copyWith(label: '');
