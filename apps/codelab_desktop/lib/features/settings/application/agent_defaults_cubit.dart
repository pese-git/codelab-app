import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        Connected,
        ConnectionProfile,
        EmbeddedProfile,
        Reconnecting,
        StdioProfile,
        WebSocketProfile,
        WorkspaceState,
        profileOrigin;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/home_path_label.dart';
import 'agent_defaults_rows.dart';
import 'agent_defaults_state.dart';
import 'provider_settings_session.dart';

export 'agent_defaults_state.dart';

/// Блок «Agent defaults» страницы «General»: общие умолчания агента из
/// `config.yaml`, те же строки реестра, что у `/settings` CLI.
///
/// Почему: единственный владелец данных блока — снимок конфига агента
/// текущего подключения и запись одного ключа за раз. Политику («чьи это
/// настройки» — `resolveSettingsAccess`; «можно ли править строку» —
/// `settingEditRefusalOf`; разбор значения — `SettingsRegistry.parseCliValue`;
/// перезапуск — `restartRequiredKeys` писателя) решают мост `codelab_setup` и
/// реестр, Cubit только вызывает их и превращает итог в [AgentDefaultsState]
/// (design.md change `add-app-general-page`, D2, D4–D7; AGENTS.md §7, §10).
///
/// Для чего: запись — один `AgentConfigStore.apply` с одной правкой в слой
/// `user` (цель всегда `user`, D4; слои `project` и `projectLocal` не
/// пишутся). Агенту Cubit ничего не отправляет. Для WebSocket и стороннего
/// агента локальный конфиг НЕ читается (SETUP-2). Текста в состоянии нет:
/// баннер и ошибки — типизированные данные, текст строит страница из ARB
/// (D7, D15). События журнала — D16: ключ и признаки, без значений, путей и
/// текстов исключений (CFG-10).
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// страницы (`CodeLabDependencies.createAgentDefaultsCubit`), страница зовёт
/// [reload] и закрывает Cubit вместе с собой. Поздний снимок после нового
/// [reload], смены подключения или папки либо [close] отбрасывается номером
/// загрузки (`agent_defaults.load_discarded`). Запись одна за раз: пока
/// [AgentDefaultsReady.saving], повторные правки игнорируются; правка во время
/// новой загрузки не пишется (`save_failed`, `stale`); конфликт даёт баннер и
/// перечитывание без автоповтора (SETUP-6).
class AgentDefaultsCubit extends Cubit<AgentDefaultsState> {
  AgentDefaultsCubit({
    required ClientWorkspace workspace,
    required Future<ConnectionProfile> Function() defaultProfile,
    required ProviderSettingsOpener open,
    required Map<String, String> environment,
    required String? codelabHome,
    required String? Function() projectDirectory,
    Logger? logger,
  }) : _workspace = workspace,
       _defaultProfile = defaultProfile,
       _open = open,
       _environment = environment,
       _codelabHome = codelabHome,
       _projectDirectory = projectDirectory,
       _logger = logger,
       super(const AgentDefaultsLoading()) {
    _accessProfile = _connectedProfile(_workspace.current);
    _workspaceSubscription = _workspace.state.listen(_onWorkspace);
  }

  final ClientWorkspace _workspace;
  final Future<ConnectionProfile> Function() _defaultProfile;
  final ProviderSettingsOpener _open;
  final Map<String, String> _environment;
  final String? _codelabHome;
  final String? Function() _projectDirectory;
  final Logger? _logger;

  late final StreamSubscription<WorkspaceState> _workspaceSubscription;

  /// Профиль, для которого прочитан доступ; смена — повод перечитать.
  ConnectionProfile? _accessProfile;

  /// Папка, для которой прочитан доступ (сессия в фокусе, выбранный проект).
  String? _loadedCwd;

  /// Номер загрузки и причина, по которой прежняя загрузка устарела (D7).
  var _loadAttempt = 0;
  var _supersededBy = 'reload';

  /// Номер загрузки, давшей текущее `Ready`.
  var _readyAttempt = 0;

  ProviderSettingsSession? _session;
  AgentConfigSnapshot? _snapshot;
  List<AgentDefaultsGroup> _groups = const [];

  var _saving = false;
  AgentDefaultsBanner? _banner;
  final _fieldErrors = <String>{};

  /// Итог успешной записи до перечитывания: баннер строится по действующему
  /// значению нового снимка, а не по записанному (его мог перекрыть другой
  /// слой).
  _SavedNote? _saved;

  /// Номер загрузки последней записи, о которой уже есть
  /// `agent_defaults.saved`: запись не должна пропасть из журнала, если
  /// перечитывание обогнали.
  var _savedLoggedFor = -1;

  /// Читает доступ и снимок конфига; вызывается при открытии страницы и после
  /// каждой собственной записи.
  Future<void> reload() => _load('reload');

  Future<void> _load(String reason, {bool keepBanner = false}) async {
    _supersededBy = reason;
    final attempt = ++_loadAttempt;
    if (!keepBanner) {
      _banner = null;
    }
    _fieldErrors.clear();
    _accessProfile = _connectedProfile(_workspace.current);
    final profile = _accessProfile ?? await _defaultProfile();
    if (_stale(attempt)) {
      return;
    }
    switch (_accessOf(profile)) {
      case RemoteReadOnly(:final endpoint):
        _setReadOnly(
          AgentDefaultsReadOnlyKind.remote,
          profileOrigin(endpoint),
          'remote',
        );
      case NotManaged(:final agentName):
        _setReadOnly(
          AgentDefaultsReadOnlyKind.notManaged,
          agentName,
          'not_managed',
        );
      case final EditableSettings access:
        await _loadEditable(attempt, access);
    }
  }

  /// Загрузка устарела: пишет `load_discarded` с причиной и возвращает `true`.
  bool _stale(int attempt) {
    if (attempt == _loadAttempt && !isClosed) {
      return false;
    }
    _logger?.debug(
      'agent_defaults.load_discarded',
      context: {'reason': isClosed ? 'closed' : _supersededBy},
    );
    return true;
  }

  String? _focusCwd() {
    final dir = _projectDirectory();
    return dir == null || dir.isEmpty ? null : dir;
  }

  SettingsAccess _accessOf(ConnectionProfile profile) {
    final cwd = _focusCwd();
    _loadedCwd = cwd;
    final home = _codelabHome ?? '';
    return switch (profile) {
      EmbeddedProfile() => resolveSettingsAccess(
        kind: AgentLaunchKind.embedded,
        cwd: cwd,
        defaultCodelabHome: home,
      ),
      StdioProfile(:final command, :final args, :final env) =>
        resolveSettingsAccess(
          kind: AgentLaunchKind.stdio,
          command: command,
          args: args,
          env: env,
          cwd: profile.runInProjectDirectory ? cwd : null,
          defaultCodelabHome: home,
        ),
      WebSocketProfile(:final uri) => resolveSettingsAccess(
        kind: AgentLaunchKind.webSocket,
        endpoint: uri,
        defaultCodelabHome: home,
      ),
    };
  }

  void _setReadOnly(
    AgentDefaultsReadOnlyKind kind,
    String subject,
    String log,
  ) {
    _forgetSession();
    _logger?.debug('agent_defaults.loaded', context: {'access': log});
    _emit(AgentDefaultsReadOnly(kind: kind, subject: subject));
  }

  void _forgetSession() {
    _session = null;
    _snapshot = null;
    _groups = const [];
    _saved = null;
  }

  Future<void> _loadEditable(int attempt, EditableSettings access) async {
    if (access.paths.codelabHome.isEmpty) {
      _setUnreadable(AgentDefaultsUnreadableReason.homeUnavailable);
      return;
    }
    final profile = _accessProfile;
    final environment = {
      ..._environment,
      if (profile is StdioProfile) ...profile.env,
    };
    final ProviderSettingsSession session;
    final AgentConfigSnapshot snapshot;
    try {
      session = await _open(access, environment);
      snapshot = await session.config.snapshot(
        cwd: access.cwd ?? access.paths.codelabHome,
      );
    } on Object catch (error) {
      if (_stale(attempt)) {
        return;
      }
      _logger?.warning(
        'agent_defaults.unreadable',
        context: {'error_type': error.runtimeType.toString()},
      );
      _setUnreadable(AgentDefaultsUnreadableReason.cannotRead, log: false);
      return;
    }
    if (_stale(attempt)) {
      return;
    }
    if (snapshot.issues.isNotEmpty || !snapshot.isReadable(ConfigLayer.user)) {
      // Проблемы загрузчика ядра — как есть; своих строк у app нет (D7).
      _setUnreadable(
        snapshot.issues.isEmpty
            ? AgentDefaultsUnreadableReason.userLayerUnreadable
            : AgentDefaultsUnreadableReason.loader,
        problems: [for (final issue in snapshot.issues) issue.toString()],
      );
      return;
    }
    _session = session;
    _snapshot = snapshot;
    _groups = agentDefaultsGroupsOf(settingFieldsOf(snapshot));
    _readyAttempt = attempt;
    if (_saved case final note?) {
      _saved = null;
      // Заметка принадлежит загрузке той же записи, того же агента и папки:
      // перечитывание другого доступа не должно показать чужой баннер.
      if (note.load == attempt &&
          note.profile == _accessProfile &&
          note.cwd == _loadedCwd) {
        _banner = _savedBanner(note);
        _logSaved(
          note,
          overridden: _banner!.kind != AgentDefaultsBannerKind.saved,
        );
      }
    }
    _logger?.debug(
      'agent_defaults.loaded',
      context: {
        'access': 'editable',
        'rows': [for (final g in _groups) ...g.rows].length,
      },
    );
    // `_saving` здесь не трогается: перечитывание посреди записи не должно
    // разрешать вторую запись; сбрасывает его только `_write`.
    _emit(_buildReady());
  }

  /// Переводит блок в `Unreadable`: [reason] — тип причины, текст строит
  /// страница из ARB; [problems] — только проблемы загрузчика ядра.
  void _setUnreadable(
    AgentDefaultsUnreadableReason reason, {
    List<String> problems = const [],
    bool log = true,
  }) {
    _forgetSession();
    if (log) {
      _logger?.warning(
        'agent_defaults.unreadable',
        context: {'error_type': 'ConfigIssue'},
      );
    }
    _emit(
      AgentDefaultsUnreadable(
        reason: reason,
        problems: problems,
        configHome: _homeLabel,
      ),
    );
  }

  /// Метка `$CODELAB_HOME` для текстов страницы: `~` вместо домашнего
  /// каталога, те же правила, что у диалога «Add connection profile»
  /// (`homePathLabel`); без известной папки — `~/.codelab`.
  String get _homeLabel {
    final home = _codelabHome;
    return home == null || home.isEmpty
        ? '~/.codelab'
        : homePathLabel(home, _environment);
  }

  AgentDefaultsReady _buildReady() => AgentDefaultsReady(
    groups: _groups,
    banner: _banner,
    saving: _saving,
    fieldErrors: Set.unmodifiable(_fieldErrors),
    configHome: _homeLabel,
  );

  // --- Правка ----------------------------------------------------------------

  /// Применяет введённый текст [raw] к ключу [key]: разбор
  /// `SettingsRegistry.parseCliValue`, затем одна запись в слой `user`.
  ///
  /// Переключатель и список передают `true`/`false` и значение из
  /// `enumValues`. Пустая строка у ключа, заданного в `user`, сбрасывает его
  /// (`UnsetValue`, как `/settings <key> --reset`); у остальных — ничего не
  /// пишет. Ключ вне блока, строка с отказом моста, состояние не `Ready` и
  /// идущая запись — пустая операция. Введённое значение в состояние и журнал
  /// не попадает (CFG-10).
  Future<void> submit(String key, String raw) async {
    final current = state;
    final snapshot = _snapshot;
    final session = _session;
    if (current is! AgentDefaultsReady ||
        current.saving ||
        snapshot == null ||
        session == null) {
      return;
    }
    final row = _rowOf(key);
    if (row == null || row.refusal != null) {
      return;
    }
    if (_readyAttempt != _loadAttempt) {
      // Идёт загрузка другого доступа или перечитывание: сессия и снимок ещё
      // прежние, писать по ним нельзя (D7).
      _logger?.warning(
        'agent_defaults.save_failed',
        context: {'key': key, 'outcome': 'stale'},
      );
      return;
    }
    final ConfigEdit edit;
    if (raw.trim().isEmpty) {
      _fieldErrors.remove(key);
      if (snapshot.layers[ConfigLayer.user]?.get(key) == null) {
        _publishReady();
        return;
      }
      edit = UnsetValue(key);
    } else {
      try {
        edit = SetValue(
          key,
          SettingsRegistry.parseCliValue(row.field.descriptor, raw),
        );
      } on ConfigValueException {
        _fieldErrors.add(key);
        _publishReady();
        return;
      }
      _fieldErrors.remove(key);
    }
    await _write(snapshot, session, row, edit);
  }

  AgentDefaultsRow? _rowOf(String key) {
    for (final group in _groups) {
      for (final row in group.rows) {
        if (row.field.key == key) {
          return row;
        }
      }
    }
    return null;
  }

  Future<void> _write(
    AgentConfigSnapshot snapshot,
    ProviderSettingsSession session,
    AgentDefaultsRow row,
    ConfigEdit edit,
  ) async {
    final key = row.field.key;
    final base = snapshot.layers[ConfigLayer.user];
    if (base == null) {
      _logger?.warning(
        'agent_defaults.save_failed',
        context: {'key': key, 'outcome': 'rejected'},
      );
      _banner = AgentDefaultsBanner(AgentDefaultsBannerKind.rejected, key: key);
      _publishReady();
      return;
    }
    // Доступ записи фиксируется до `await`: смена папки или профиля во время
    // записи не должна дать баннер «Saved» для другого доступа.
    final writeProfile = _accessProfile;
    final writeCwd = _loadedCwd;
    _saving = true;
    _banner = null;
    _saved = null;
    _publishReady();
    ConfigSaveOutcome? outcome;
    Object? error;
    try {
      outcome = await session.config.apply(base, [edit]);
    } on Object catch (e) {
      error = e;
    }
    if (outcome is! ConfigSaved) {
      _logger?.warning(
        'agent_defaults.save_failed',
        context: {
          'key': key,
          'outcome': switch (outcome) {
            ConfigConflict() => 'conflict',
            ConfigRejected() => 'rejected',
            ConfigInlineSecret() => 'inline_secret',
            _ => 'error',
          },
          if (error != null) 'error_type': error.runtimeType.toString(),
        },
      );
    }
    if (isClosed) {
      // Итог записи после закрытия страницы — только в журнал (D7); признак
      // перекрытия без перечитывания неизвестен.
      if (outcome is ConfigSaved) {
        _logger?.info(
          'agent_defaults.saved',
          context: {
            'key': key,
            'restart_required': outcome.restartRequiredKeys.contains(key),
            'overridden': false,
          },
        );
      }
      return;
    }
    _banner = switch (outcome) {
      // Текст «Saved» строится после перечитывания (`_savedBanner`).
      ConfigSaved() => null,
      ConfigConflict() => AgentDefaultsBanner(
        AgentDefaultsBannerKind.conflict,
        key: key,
      ),
      ConfigInlineSecret() => AgentDefaultsBanner(
        AgentDefaultsBannerKind.inlineSecret,
        key: key,
      ),
      ConfigRejected(:final issues) => AgentDefaultsBanner(
        AgentDefaultsBannerKind.rejected,
        key: key,
        problems: [for (final issue in issues) issue.toString()],
      ),
      _ => AgentDefaultsBanner(AgentDefaultsBannerKind.rejected, key: key),
    };
    _SavedNote? note;
    if (outcome is ConfigSaved) {
      // Заметка принадлежит ровно той загрузке, которую запустит эта запись.
      note = _saved = (
        load: _loadAttempt + 1,
        key: key,
        written: edit is SetValue ? edit.value : null,
        restart: outcome.restartRequiredKeys.contains(key),
        profile: writeProfile,
        cwd: writeCwd,
      );
    }
    _saving = false;
    await _load('reload', keepBanner: true);
    _saved = null;
    if (note != null && _savedLoggedFor != note.load) {
      _logSaved(note, overridden: false);
    }
    // Перечитывание не дошло до `Ready` (конфиг стал нечитаемым): запись
    // всё равно состоялась, и пользователь должен о ней узнать.
    final after = state;
    if (note != null &&
        after is AgentDefaultsUnreadable &&
        note.load == _loadAttempt &&
        note.profile == _accessProfile &&
        note.cwd == _loadedCwd &&
        !isClosed) {
      _emit(
        AgentDefaultsUnreadable(
          reason: after.reason,
          problems: after.problems,
          banner: AgentDefaultsBanner(
            AgentDefaultsBannerKind.savedUnverified,
            key: key,
          ),
          configHome: _homeLabel,
        ),
      );
    }
  }

  /// Баннер «Saved» по действующему значению нового снимка: если оно не равно
  /// записанному, баннер прямо говорит, что запись перекрыта другим слоем
  /// (D4; образец — D16 change `add-settings-agents-modes`).
  AgentDefaultsBanner _savedBanner(_SavedNote note) {
    final field = _rowOf(note.key)?.field;
    final restart = !note.restart
        ? AgentDefaultsRestart.none
        : _agentConnected()
        ? AgentDefaultsRestart.afterRestart
        : AgentDefaultsRestart.whenStarts;
    if (field == null) {
      return AgentDefaultsBanner(
        AgentDefaultsBannerKind.saved,
        key: note.key,
        restart: restart,
      );
    }
    // Сброс: ключ нигде не должен остаться; запись: итог равен записанному.
    final overridden = note.written == null
        ? field.source != null
        : '${field.value}' != '${note.written}';
    if (!overridden) {
      return AgentDefaultsBanner(
        AgentDefaultsBannerKind.saved,
        key: note.key,
        restart: restart,
      );
    }
    return AgentDefaultsBanner(
      AgentDefaultsBannerKind.overridden,
      key: note.key,
      restart: restart,
      overriddenBy: field.sourceName,
      effective: field.displayValue,
    );
  }

  void _logSaved(_SavedNote note, {required bool overridden}) {
    _savedLoggedFor = note.load;
    _logger?.info(
      'agent_defaults.saved',
      context: {
        'key': note.key,
        'restart_required': note.restart,
        'overridden': overridden,
      },
    );
  }

  /// Агент подключён: `Connected` или `Reconnecting`.
  bool _agentConnected() => _connectedProfile(_workspace.current) != null;

  static ConnectionProfile? _connectedProfile(WorkspaceState state) =>
      state.connection is Connected || state.connection is Reconnecting
      ? state.profile
      : null;

  void _onWorkspace(WorkspaceState next) {
    if (_connectedProfile(next) != _accessProfile ||
        _focusCwd() != _loadedCwd) {
      unawaited(_load('access_changed'));
    }
  }

  void _publishReady() {
    if (isClosed || _snapshot == null) {
      return;
    }
    emit(_buildReady());
  }

  void _emit(AgentDefaultsState next) {
    if (!isClosed) {
      emit(next);
    }
  }

  @override
  Future<void> close() async {
    // Поздний снимок и итог записи после закрытия страницы не меняют
    // состояние (D7); подписка на рабочее пространство отменяется (§9).
    _loadAttempt++;
    await _workspaceSubscription.cancel();
    return super.close();
  }
}

/// Итог успешной записи до перечитывания: ключ, записанное значение (`null` —
/// сброс), признак перезапуска и доступ (профиль и папка), в котором запись
/// сделана.
typedef _SavedNote = ({
  int load,
  String key,
  Object? written,
  bool restart,
  ConnectionProfile? profile,
  String? cwd,
});
