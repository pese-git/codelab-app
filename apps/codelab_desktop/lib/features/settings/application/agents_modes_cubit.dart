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

import 'agents_modes_state.dart';
import 'provider_settings_session.dart';

export 'agents_modes_state.dart';

/// Привязка подтверждения `bypass` к состоянию страницы в момент открытия
/// диалога (design.md change `add-settings-agents-modes`, D5, D11).
///
/// Почему: диалог открыт долго, а за это время могли смениться доступ (другой
/// агент), загрузка снимка или цель записи; подтверждение, данное для одних
/// настроек, нельзя применять к другим (AGENTS.md §10: решение пользователя
/// не переносится на другое действие).
///
/// Как использовать: страница берёт токен у `AgentsModesCubit.beginBypass` до
/// показа диалога и передаёт его в `confirmBypass` после «Use bypass».
final class BypassToken {
  const BypassToken(this.load, this.target, this.folder);

  /// Номер загрузки, по которой построена страница.
  final int load;

  /// Цель записи на момент открытия диалога.
  final ConfigLayer target;

  /// Папка слоя `projectLocal` на момент открытия (`null` — папки нет).
  final String? folder;
}

/// Страница «Agents & modes»: режим разрешений и effort новых сессий.
///
/// Почему: единственный владелец данных страницы — снимок конфига агента
/// текущего подключения и запись двух ключей (`permissions.mode`,
/// `agent.effort`). Политику («чьи это настройки», итог режима и источник,
/// сужение проектом) решают `resolveSettingsAccess` и `sessionDefaultsOf`
/// моста `codelab_setup`; Cubit только вызывает их и превращает итог в
/// [AgentsModesState] (design.md change `add-settings-agents-modes`, D2, D4,
/// D6; AGENTS.md §7, §10).
///
/// Для чего: запись — одна `SetValue` в `AgentConfigStore.apply` сессии
/// страницы, как «Default model» (D4). Агенту Cubit ничего не отправляет:
/// режим вступает в силу после «Restart agent» (D3, Q2 (а)). `bypass` без
/// [confirmBypass] не пишется (D5), `autopilot` не пишется никогда. Для
/// WebSocket и стороннего агента локальный конфиг НЕ читается (SETUP-2).
/// События журнала — D12: только виды и значения `mode`/`effort`, без путей и
/// текстов исключений.
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// страницы, страница зовёт [reload] и закрывает Cubit вместе с собой. Поздний
/// снимок после нового [reload], смены подключения или [close] отбрасывается
/// номером загрузки (D11). Запись одна за раз: пока [AgentsModesReady.saving],
/// повторные выборы игнорируются; конфликт даёт баннер и перечитывание без
/// автоповтора (SETUP-6).
class AgentsModesCubit extends Cubit<AgentsModesState> {
  AgentsModesCubit({
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
       super(const AgentsModesLoading()) {
    _accessProfile = _connectedProfile(_workspace.current);
    _workspaceSubscription = _workspace.state.listen(_onWorkspace);
  }

  /// Режимы, которые страница может записать без подтверждения.
  static const _plainModes = {'plan', 'ask', 'standard', 'accept-edits'};
  static const _efforts = {'low', 'medium', 'high'};

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

  /// Номер загрузки и причина, по которой прежняя загрузка устарела (D11).
  var _loadAttempt = 0;
  var _supersededBy = 'reload';

  ProviderSettingsSession? _session;
  AgentConfigSnapshot? _snapshot;
  SessionDefaultsView? _defaults;
  bool _canTargetProject = false;

  /// Выбранная цель записи; пока пользователь не выбирал — предложение моста.
  ConfigLayer? _chosenTarget;

  var _saving = false;
  AgentsModesBanner? _banner;

  /// Номер загрузки, давшей текущее `Ready` (для [BypassToken]).
  var _readyAttempt = 0;

  /// Папка, для которой прочитан доступ: смена папки фокуса без смены профиля
  /// (сессия в фокусе, выбранный проект) тоже повод перечитать (D2).
  String? _loadedCwd;

  /// Итог успешной записи до перечитывания: баннер строится по действующему
  /// значению снимка, а не по записанному (оно может быть перекрыто другим
  /// слоем или сужено недоверенным проектом).
  _SavedNote? _saved;

  /// Читает доступ и снимок конфига; вызывается при открытии страницы и после
  /// каждой собственной записи.
  Future<void> reload() => _load('reload');

  Future<void> _load(String reason) async {
    _supersededBy = reason;
    final attempt = ++_loadAttempt;
    _accessProfile = _connectedProfile(_workspace.current);
    final profile = _accessProfile ?? await _defaultProfile();
    if (_stale(attempt)) {
      return;
    }
    final access = _accessOf(profile);
    switch (access) {
      case RemoteReadOnly(:final endpoint):
        _setReadOnly(
          'Read-only: this agent runs on ${profileOrigin(endpoint)}. Change '
              'its modes and agents on that host: codelab config set, '
              '.codelab/agents.',
          'remote',
        );
      case NotManaged(:final agentName):
        _setReadOnly(
          'Agent settings are managed by $agentName.',
          'not_managed',
        );
      case EditableSettings():
        await _loadEditable(attempt, access);
    }
  }

  /// Загрузка устарела: пишет `load_discarded` с причиной и возвращает `true`.
  bool _stale(int attempt) {
    if (attempt == _loadAttempt && !isClosed) {
      return false;
    }
    _logger?.debug(
      'agents_modes.load_discarded',
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

  void _setReadOnly(String notice, String access) {
    _forgetSession();
    _saved = null;
    _logger?.debug('agents_modes.loaded', context: {'access': access});
    _emit(AgentsModesReadOnly(notice: notice));
  }

  void _forgetSession() {
    _session = null;
    _snapshot = null;
    _defaults = null;
    _saved = null;
  }

  Future<void> _loadEditable(int attempt, EditableSettings access) async {
    if (access.paths.codelabHome.isEmpty) {
      _setUnreadable(const ['The CodeLab home folder is not available.']);
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
        'agents_modes.unreadable',
        context: {'error_type': error.runtimeType.toString()},
      );
      _setUnreadable(const ['Cannot read the agent settings.'], log: false);
      return;
    }
    if (_stale(attempt)) {
      return;
    }
    if (snapshot.issues.isNotEmpty || !snapshot.isReadable(ConfigLayer.user)) {
      _setUnreadable([
        for (final issue in snapshot.issues) issue.toString(),
        if (snapshot.issues.isEmpty) 'The user config.yaml cannot be read.',
      ]);
      return;
    }
    _session = session;
    _snapshot = snapshot;
    _defaults = sessionDefaultsOf(snapshot, access);
    _canTargetProject = access.cwd != null;
    _readyAttempt = attempt;
    if (_saved case final note?) {
      _saved = null;
      // Заметка принадлежит загрузке того же агента и папки: перечитывание
      // другого доступа не должно показать чужой баннер «Saved».
      if (note.load == attempt &&
          note.profile == _accessProfile &&
          note.cwd == _loadedCwd) {
        _banner = _savedBanner(note);
      }
    }
    _logger?.debug('agents_modes.loaded', context: {'access': 'editable'});
    // `_saving` здесь не трогается: перечитывание посреди записи не должно
    // разрешать вторую запись (D11); сбрасывает его только `_write`.
    _emit(_buildReady());
  }

  void _setUnreadable(List<String> problems, {bool log = true}) {
    _forgetSession();
    if (log) {
      _logger?.warning(
        'agents_modes.unreadable',
        context: {'error_type': 'ConfigIssue'},
      );
    }
    _emit(AgentsModesUnreadable(problems: problems));
  }

  ConfigLayer get _target {
    final chosen = _chosenTarget;
    if (chosen == ConfigLayer.user ||
        (chosen == ConfigLayer.projectLocal && _canTargetProject)) {
      return chosen!;
    }
    final suggested = _defaults!.suggestedTarget;
    return suggested == ConfigLayer.projectLocal && !_canTargetProject
        ? ConfigLayer.user
        : suggested;
  }

  static String _sourceLabel(ConfigSourceView? source) =>
      switch (source?.kind) {
        null => 'default',
        ConfigSourceKind.user => 'user',
        ConfigSourceKind.project => 'project',
        ConfigSourceKind.projectLocal => 'local',
        ConfigSourceKind.extraFile => 'file',
        ConfigSourceKind.environment => 'env',
      };

  AgentsModesReady _buildReady() {
    final defaults = _defaults!;
    final mode = defaults.mode;
    final label = _modeLabel(mode);
    return AgentsModesReady(
      mode: mode.id,
      modeLabel: label,
      modeSource: _sourceLabel(mode.source),
      narrowedNotice: mode.narrowedByProject
          ? 'This project is not trusted, so its config can only make the '
                'mode stricter. New sessions here use $label.'
          : null,
      effort: defaults.effort.id,
      effortSource: _sourceLabel(defaults.effort.source),
      target: _target,
      canTargetProject: _canTargetProject,
      saving: _saving,
      banner: _banner,
    );
  }

  // --- Выбор пользователя ----------------------------------------------------

  /// Переключатель цели: [layer] — `user` или `projectLocal` (D4).
  void selectTarget(ConfigLayer layer) {
    final current = state;
    if (current is! AgentsModesReady || current.saving) {
      return;
    }
    if (layer == ConfigLayer.user ||
        (layer == ConfigLayer.projectLocal && _canTargetProject)) {
      _chosenTarget = layer;
      _publishReady();
    }
  }

  /// Записывает режим [id]. `bypass` требует [confirmBypass] (D5);
  /// `autopilot` и неизвестные id игнорируются (D5).
  Future<void> selectMode(String id) async {
    if (_plainModes.contains(id)) {
      await _write('permissions.mode', id, 'mode');
    }
  }

  /// Открытие диалога подтверждения `bypass`: токен текущего состояния;
  /// `null` — страница не готова или идёт запись, диалог не нужен.
  BypassToken? beginBypass() {
    final current = state;
    if (current is! AgentsModesReady ||
        current.saving ||
        _readyAttempt != _loadAttempt) {
      return null;
    }
    return BypassToken(_readyAttempt, current.target, _loadedCwd);
  }

  /// Токен ещё действителен: страница `Ready`, запись не идёт, загрузка, цель
  /// и папка прежние (D17). Страница закрывает диалог, когда это `false`.
  bool isCurrent(BypassToken token) {
    final current = state;
    // `_readyAttempt == _loadAttempt`: пока идёт новая загрузка (другой агент),
    // состояние ещё прежний `Ready`, а сессия в нём — прежнего агента.
    return current is AgentsModesReady &&
        !current.saving &&
        _readyAttempt == _loadAttempt &&
        token.load == _readyAttempt &&
        token.target == current.target &&
        token.folder == _loadedCwd;
  }

  /// Диалог закрыт страницей без ответа пользователя (страница ушла из
  /// `Ready`): если токен устарел, пишет `agents_modes.save_failed` с
  /// `outcome: stale`, как и подтверждение устаревшим токеном (D17); записи нет.
  void dismissBypass(BypassToken token) {
    if (!isCurrent(token)) {
      _logger?.warning(
        'agents_modes.save_failed',
        context: {'key': 'mode', 'outcome': 'stale'},
      );
    }
  }

  /// «Use bypass» в диалоге подтверждения: записывает `bypass`, только если
  /// страница с момента [beginBypass] не менялась (загрузка, доступ, цель);
  /// иначе записи нет и баннер просит выбрать заново (D5, D11).
  Future<void> confirmBypass(BypassToken token) =>
      _write('permissions.mode', 'bypass', 'mode', token: token);

  /// «Cancel» или Esc: записи нет (D5).
  void cancelBypass() => _logger?.info('agents_modes.bypass_cancelled');

  /// Записывает effort [id] (`low`, `medium`, `high`).
  Future<void> selectEffort(String id) async {
    if (_efforts.contains(id)) {
      await _write('agent.effort', id, 'effort');
    }
  }

  Future<void> _write(
    String key,
    String value,
    String kind, {
    BypassToken? token,
  }) async {
    if (token != null && !isCurrent(token)) {
      // Подтверждение дано для другого состояния: записи нет (D17).
      _logger?.warning(
        'agents_modes.save_failed',
        context: {'key': kind, 'outcome': 'stale'},
      );
      if (state is AgentsModesReady) {
        _banner = const AgentsModesBanner(
          AgentsModesBannerKind.warning,
          'Settings changed while the dialog was open; bypass was not saved.',
        );
        _publishReady();
      }
      return;
    }
    final current = state;
    final snapshot = _snapshot;
    final session = _session;
    if (current is! AgentsModesReady ||
        current.saving ||
        // Идёт загрузка другого доступа: сессия и снимок ещё прежние (D11).
        _readyAttempt != _loadAttempt ||
        snapshot == null ||
        session == null) {
      return;
    }
    final layer = current.target;
    final base = snapshot.layers[layer];
    if (base == null) {
      // Слой цели не прочитан: подменять его другим нельзя, запись ушла бы не
      // туда, куда выбрал пользователь.
      _logger?.warning(
        'agents_modes.save_failed',
        context: {'key': kind, 'outcome': 'rejected'},
      );
      _banner = const AgentsModesBanner(
        AgentsModesBannerKind.error,
        'Cannot save: the target config file is not available.',
      );
      _publishReady();
      return;
    }
    final targetLabel = layer == ConfigLayer.projectLocal ? 'local' : 'user';
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
      outcome = await session.config.apply(base, [SetValue(key, value)]);
    } on Object catch (e) {
      error = e;
    }
    if (outcome is ConfigSaved) {
      _logger?.info(
        'agents_modes.${kind}_changed',
        context: {kind: value, 'target': targetLabel},
      );
    } else {
      _logger?.warning(
        'agents_modes.save_failed',
        context: {
          'key': kind,
          'outcome': switch (outcome) {
            ConfigConflict() => 'conflict',
            ConfigRejected() || ConfigInlineSecret() => 'rejected',
            _ => 'error',
          },
          if (error != null) 'error_type': error.runtimeType.toString(),
        },
      );
    }
    if (isClosed) {
      // Итог записи после закрытия страницы — только в журнал (D11).
      return;
    }
    _banner = switch (outcome) {
      // Текст баннера «Saved» строится после перечитывания (`_savedBanner`).
      ConfigSaved() => null,
      ConfigConflict() => const AgentsModesBanner(
        AgentsModesBannerKind.conflict,
        'The config changed on disk, so nothing was saved. The page was '
        'reloaded; review it and try again.',
      ),
      _ => const AgentsModesBanner(
        AgentsModesBannerKind.error,
        'The config was not saved.',
      ),
    };
    _SavedNote? note;
    if (outcome is ConfigSaved) {
      // Заметка принадлежит ровно той загрузке, которую запустит эта запись.
      note = _saved = (
        load: _loadAttempt + 1,
        key: key,
        kind: kind,
        value: value,
        layer: layer,
        restart: outcome.restartRequiredKeys,
        profile: writeProfile,
        cwd: writeCwd,
      );
    }
    _saving = false;
    await reload();
    // Перечитывание не дошло до `Ready` (конфиг стал нечитаемым): запись
    // всё равно состоялась, и пользователь должен о ней узнать (D16).
    _saved = null;
    final after = state;
    if (note != null &&
        after is AgentsModesUnreadable &&
        note.load == _loadAttempt &&
        note.profile == _accessProfile &&
        note.cwd == _loadedCwd &&
        !isClosed) {
      _emit(
        AgentsModesUnreadable(
          problems: after.problems,
          banner: AgentsModesBanner(
            AgentsModesBannerKind.saved,
            'Saved to ${_targetName(note.layer)}.',
          ),
        ),
      );
    }
  }

  static String _targetName(ConfigLayer layer) =>
      layer == ConfigLayer.projectLocal ? 'This project only' : 'All projects';

  /// Баннер «Saved» по действующему значению нового снимка: если оно не равно
  /// записанному, баннер прямо говорит, что запись перекрыта (другим слоем,
  /// окружением) или сужена недоверенным проектом (design.md D3, D4).
  AgentsModesBanner _savedBanner(_SavedNote note) {
    final defaults = _defaults!;
    final isMode = note.kind == 'mode';
    final effective = isMode ? defaults.mode.id : defaults.effort.id;
    final label = isMode ? _modeLabel(defaults.mode) : effective;
    final suffix = !note.restart.contains(note.key)
        ? '.'
        : _agentConnected()
        ? ' after Restart agent.'
        : ' when the agent starts.';
    final target = _targetName(note.layer);
    final narrowed = isMode && defaults.mode.narrowedByProject;
    if (!narrowed && effective == note.value) {
      return AgentsModesBanner(
        AgentsModesBannerKind.saved,
        'Saved. New sessions use $label$suffix',
      );
    }
    final source = narrowed
        ? 'the untrusted project'
        : _sourceLabel(isMode ? defaults.mode.source : defaults.effort.source);
    return AgentsModesBanner(
      AgentsModesBannerKind.warning,
      'Saved to $target; $source overrides it: new sessions use $label$suffix',
    );
  }

  static String _modeLabel(ModeChoiceView mode) => mode.blocksWriteAndExec
      ? '${mode.id} (edits and commands blocked by plan)'
      : mode.id;

  /// Агент подключён: `Connected` или `Reconnecting` (D3).
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
    if (isClosed || _snapshot == null || _defaults == null) {
      return;
    }
    emit(_buildReady());
  }

  void _emit(AgentsModesState next) {
    if (!isClosed) {
      emit(next);
    }
  }

  @override
  Future<void> close() async {
    // Поздний снимок и итог записи после закрытия страницы не меняют
    // состояние (D11).
    _loadAttempt++;
    await _workspaceSubscription.cancel();
    return super.close();
  }
}

/// Итог успешной записи до перечитывания (`AgentsModesCubit._saved`): ключ,
/// записанное значение, цель, ключи перезапуска и доступ (профиль и папка), в
/// котором запись сделана.
typedef _SavedNote = ({
  int load,
  String key,
  String kind,
  String value,
  ConfigLayer layer,
  List<String> restart,
  ConnectionProfile? profile,
  String? cwd,
});
