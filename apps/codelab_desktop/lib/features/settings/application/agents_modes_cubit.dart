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
import 'package:path/path.dart' as p;

import '../../../core/platform/home_path_label.dart';
import '../../../core/platform/local_folder_opener.dart';
import 'agent_definitions_port.dart';
import 'agents_modes_state.dart';
import 'provider_settings_session.dart';

export 'agent_definitions_port.dart';
export 'agents_modes_state.dart';

/// Каталог определений агентов для меню «Open folder» (D8).
enum AgentsFolder { user, project }

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
    AgentDefinitionsLoader? loadDefinitions,
    LocalFolderOpener? folderOpener,
  }) : _workspace = workspace,
       _loadDefinitions = loadDefinitions,
       _folderOpener = folderOpener,
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
  final AgentDefinitionsLoader? _loadDefinitions;
  final LocalFolderOpener? _folderOpener;
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

  /// Определения агентов последней успешной загрузки; `null` — загрузчика нет,
  /// загрузка не удалась или страница не `Ready`.
  AgentDefinitionsLoad? _definitions;

  /// Загрузка определений упала непредвиденным исключением.
  var _definitionsFailed = false;

  /// Подпись того, что не удалось открыть (`Could not open <label>.`).
  String? _openFailure;

  /// Отмена идущей загрузки определений: новая загрузка и [close] обрывают её
  /// (D11).
  CancelTokenSource? _definitionsCancel;
  AgentsModesBanner? _banner;

  /// Номер загрузки, давшей текущее `Ready` (для [BypassToken]).
  var _readyAttempt = 0;

  /// Папка проекта, которую читает агент профиля (`access.cwd`): `null` у
  /// stdio-профиля без `runInProjectDirectory` — проектных слоёв и определений
  /// проекта нет, и «недоверенного проекта» тоже.
  String? _accessCwd;

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
    _definitionsCancel?.cancel('superseded');
    _definitionsCancel = null;
    _accessProfile = _connectedProfile(_workspace.current);
    final profile = _accessProfile ?? await _defaultProfile();
    if (_stale(attempt)) {
      return;
    }
    final access = _accessOf(profile);
    switch (access) {
      case RemoteReadOnly(:final endpoint):
        _setReadOnly(RemoteAgentReadOnly(profileOrigin(endpoint)), 'remote');
      case NotManaged(:final agentName):
        _setReadOnly(ForeignAgentReadOnly(agentName), 'not_managed');
      case EditableSettings():
        await _loadEditable(attempt, profile, access);
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

  void _setReadOnly(ReadOnlyReason reason, String access) {
    _forgetSession();
    _saved = null;
    _logger?.debug('agents_modes.loaded', context: {'access': access});
    _emit(AgentsModesReadOnly(reason: reason));
  }

  void _forgetSession() {
    _session = null;
    _snapshot = null;
    _defaults = null;
    _saved = null;
    _definitions = null;
    _definitionsFailed = false;
    _openFailure = null;
  }

  /// [profile] — профиль, по которому решён доступ: подключённый или профиль
  /// по умолчанию. `env` stdio-профиля входит в окружение сессии и без
  /// подключения: из него строится слой `environment` снимка (doc
  /// `ProviderSettingsOpener`), иначе ключ, заданный переменной профиля,
  /// выглядел бы редактируемым.
  Future<void> _loadEditable(
    int attempt,
    ConnectionProfile profile,
    EditableSettings access,
  ) async {
    if (access.paths.codelabHome.isEmpty) {
      _setUnreadable(const [
        AppSettingsProblem(AppSettingsProblemKind.homeUnavailable),
      ]);
      return;
    }
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
      _setUnreadable(const [
        AppSettingsProblem(AppSettingsProblemKind.cannotReadSettings),
      ], log: false);
      return;
    }
    if (_stale(attempt)) {
      return;
    }
    if (snapshot.issues.isNotEmpty || !snapshot.isReadable(ConfigLayer.user)) {
      _setUnreadable([
        for (final issue in snapshot.issues)
          LoaderSettingsProblem(issue.toString()),
        if (snapshot.issues.isEmpty)
          const AppSettingsProblem(AppSettingsProblemKind.userConfigUnreadable),
      ]);
      return;
    }
    // Определения читаются тем же номером загрузки, что и снимок (D11): ошибка
    // таблицы не делает страницу нечитаемой, режим и effort остаются.
    AgentDefinitionsLoad? definitions;
    var definitionsFailed = false;
    final loader = _loadDefinitions;
    if (loader != null) {
      final cancel = CancelTokenSource();
      _definitionsCancel = cancel;
      try {
        definitions = await loader(
          snapshot: snapshot,
          access: access,
          environment: environment,
          cancel: cancel.token,
        );
      } on Object catch (error) {
        if (_stale(attempt)) {
          cancel.dispose();
          return;
        }
        definitionsFailed = true;
        _logger?.warning(
          'agents_modes.definitions_failed',
          context: {
            'reason': 'error',
            'error_type': error.runtimeType.toString(),
          },
        );
      }
      // Чтение закончено: источник отмены освобождается (D11).
      cancel.dispose();
      if (identical(_definitionsCancel, cancel)) {
        _definitionsCancel = null;
      }
      if (_stale(attempt)) {
        return;
      }
      if (definitions != null && definitions.timedOut) {
        _logger?.warning(
          'agents_modes.definitions_failed',
          context: {'reason': 'timeout'},
        );
      }
    }
    _definitions = definitions;
    _accessCwd = access.cwd;
    _definitionsFailed = definitionsFailed;
    _openFailure = null;
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
    _logger?.debug(
      'agents_modes.loaded',
      context: {
        'access': 'editable',
        if (definitions != null) ...{
          'definitions': definitions.rows.where((r) => r.path != null).length,
          // Столько же, сколько InfoBar ошибок файлов (D7, D19).
          'errors': definitions.rows.where(_hasErrorInfoBar).length,
        },
      },
    );
    // `_saving` здесь не трогается: перечитывание посреди записи не должно
    // разрешать вторую запись (D11); сбрасывает его только `_write`.
    _emit(_buildReady());
  }

  void _setUnreadable(List<SettingsProblem> problems, {bool log = true}) {
    _forgetSession();
    if (log) {
      _logger?.warning(
        'agents_modes.unreadable',
        context: {'error_type': 'ConfigIssue'},
      );
    }
    _emit(AgentsModesUnreadable(issues: problems));
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

  AgentsModesReady _buildReady() {
    final defaults = _defaults!;
    final mode = defaults.mode;
    return AgentsModesReady(
      mode: mode.id,
      blocksWriteAndExec: mode.blocksWriteAndExec,
      narrowedByProject: mode.narrowedByProject,
      modeSourceKind: mode.source?.kind,
      effort: defaults.effort.id,
      effortSourceKind: defaults.effort.source?.kind,
      target: _target,
      canTargetProject: _canTargetProject,
      saving: _saving,
      banner: _banner,
      definitions: _definitionsView(),
    );
  }

  // --- Блок «Agent definitions» ------------------------------------------------

  AgentsDefinitionsView? _definitionsView() {
    if (_loadDefinitions == null) {
      return null;
    }
    final loaded = _definitions;
    if (loaded == null) {
      return AgentsDefinitionsView(
        rows: const [],
        failed: _definitionsFailed,
        openFailure: _openFailure,
      );
    }
    final rows = <AgentsDefinitionRow>[];
    final errors = <AgentsDefinitionError>[];
    for (final row in loaded.rows) {
      final path = row.path;
      // Отклонённый файл не загружен: «Available in», «Tools» и «Model» у него
      // прочерк (D7).
      final failed = switch (row.status) {
        AgentRowStatus.error ||
        AgentRowStatus.modelNotConfigured ||
        AgentRowStatus.duplicate ||
        AgentRowStatus.shadowed => true,
        _ => false,
      };
      rows.add(
        AgentsDefinitionRow(
          name: row.name,
          descriptionText: row.description,
          sourcePath: path == null ? null : homePathLabel(path, _environment),
          scope: failed ? null : row.availableIn,
          // `null` у рабочей строки — «все инструменты» и модель сессии (D7).
          toolNames: failed ? null : row.tools,
          modelId: failed ? null : row.model,
          loaded: !failed,
          rowStatus: row.status,
          errorLine: row.errorLine,
          overriddenBy: row.overriddenBy == null
              ? null
              : homePathLabel(row.overriddenBy!, _environment),
          tone: _statusTone(row.status),
        ),
      );
      // InfoBar с «Open folder» — каждому файлу с диагностикой уровня `error`:
      // разбор (`error`), модель вне каталога (диагностика `invalid_value` с
      // текстом константы ядра, D18) и дубликат имени. Перекрытый файл
      // (`shadowed`, уровень info) — не ошибка.
      if (_hasErrorInfoBar(row)) {
        errors.add(
          AgentsDefinitionError(
            index: errors.length,
            path: path!,
            pathLabel: homePathLabel(path, _environment),
            line: row.errorLine,
            // Текст ядра — как есть; без него причина типом (D5, D6).
            message: row.errorMessage,
            reason: switch (row.status) {
              AgentRowStatus.modelNotConfigured =>
                AgentsDefinitionErrorKind.modelNotConfigured,
              AgentRowStatus.duplicate => AgentsDefinitionErrorKind.duplicate,
              _ => AgentsDefinitionErrorKind.other,
            },
          ),
        );
      }
    }
    // Папка проекта известна, а доверия нет: проект недоверенный (fail-closed).
    final untrusted = _accessCwd != null && !loaded.projectTrusted;
    final cwd = _accessCwd;
    return AgentsDefinitionsView(
      rows: rows,
      errors: errors,
      untrustedProject: untrusted,
      projectLabel: untrusted && cwd != null
          ? homePathLabel(cwd, _environment)
          : null,
      timedOut: loaded.timedOut,
      // Проект читается, только если агент работает в его папке.
      projectFolderAvailable:
          _accessCwd != null && !untrusted && loaded.projectDirectory != null,
      projectFolderExists: loaded.projectDirectoryExists,
      openFailure: _openFailure,
      userFolderLabel: homePathLabel(loaded.userDirectory, _environment),
    );
  }

  /// Файл с диагностикой уровня `error` и известным путём: ему положен InfoBar
  /// «Open folder» (`shadowed` — уровень info, без InfoBar).
  static bool _hasErrorInfoBar(AgentDefinitionRowView row) =>
      row.path != null &&
      (row.status == AgentRowStatus.error ||
          row.status == AgentRowStatus.modelNotConfigured ||
          row.status == AgentRowStatus.duplicate);

  static AgentsStatusTone _statusTone(AgentRowStatus status) =>
      switch (status) {
        AgentRowStatus.available => AgentsStatusTone.success,
        AgentRowStatus.overridden ||
        AgentRowStatus.modelNotConfigured ||
        AgentRowStatus.shadowed ||
        AgentRowStatus.subagentsOff => AgentsStatusTone.warning,
        AgentRowStatus.error ||
        AgentRowStatus.duplicate => AgentsStatusTone.danger,
      };

  // --- Выбор пользователя ----------------------------------------------------

  /// «Open folder» у InfoBar ошибки определения: открывает каталог, где лежит
  /// файл [filePath] (`dirname`), а сам файл не открывается никогда (Q14 (б),
  /// D21). Каталог должен быть одним из каталогов определений состояния
  /// (`$CODELAB_HOME/agents`, `<project>/.codelab/agents` доверенного
  /// проекта); иначе `not_allowed` без вызова порта (D8).
  Future<void> openDefinitionFolder(String filePath) async {
    final directory = p.dirname(filePath);
    final loaded = _definitions;
    if (_folderOpener == null ||
        loaded == null ||
        !_isDefinitionsFolder(loaded, directory)) {
      _logOpen('file_dir', 'not_allowed');
      return;
    }
    await _openFolderIn('file_dir', directory, create: false);
  }

  bool _isDefinitionsFolder(AgentDefinitionsLoad loaded, String directory) {
    if (p.equals(directory, loaded.userDirectory)) {
      return true;
    }
    final project = loaded.projectDirectory;
    return project != null &&
        _accessCwd != null &&
        loaded.projectTrusted &&
        p.equals(directory, project);
  }

  /// Меню «Open folder»: [folder] — `$CODELAB_HOME/agents` (с `create: true`)
  /// или `<project>/.codelab/agents` доверенного проекта (без создания,
  /// Q11). Путь берётся из состояния, а не от вызывающего (D8).
  Future<void> openFolder(AgentsFolder folder) async {
    final loaded = _definitions;
    if (_folderOpener == null || loaded == null) {
      _logOpen(_folderKind(folder), 'not_allowed');
      return;
    }
    switch (folder) {
      case AgentsFolder.user:
        // Каталог в доме создаётся: в него кладут первое определение (Q11 (а));
        // поверх битой ссылки порт его не создаёт (D21).
        await _openFolderIn('user_dir', loaded.userDirectory, create: true);
      case AgentsFolder.project:
        final projectPath = loaded.projectDirectory;
        if (_accessCwd == null ||
            !loaded.projectTrusted ||
            projectPath == null ||
            !loaded.projectDirectoryExists) {
          // В папке проекта app ничего не создаёт без явной просьбы (Q11 (б)).
          _logOpen('project_dir', 'not_allowed');
          return;
        }
        await _openFolderIn('project_dir', projectPath, create: false);
    }
  }

  static String _folderKind(AgentsFolder folder) =>
      folder == AgentsFolder.user ? 'user_dir' : 'project_dir';

  Future<void> _openFolderIn(
    String kind,
    String directory, {
    required bool create,
  }) async {
    final outcome = await _folderOpener!.open(directory, create: create);
    _logOpen(kind, switch (outcome) {
      FolderOpenOutcome.opened => 'opened',
      FolderOpenOutcome.created => 'created',
      FolderOpenOutcome.failed => 'failed',
      FolderOpenOutcome.missing => 'missing',
    });
    if (isClosed) {
      return;
    }
    // Сбой и отсутствие каталога пользователю видны одним InfoBar; причину
    // (и путь) в состояние и журнал не кладём.
    _openFailure =
        outcome == FolderOpenOutcome.failed ||
            outcome == FolderOpenOutcome.missing
        ? homePathLabel(directory, _environment)
        : null;
    _publishReady();
  }

  /// Событие без пути и имени файла (D12).
  void _logOpen(String kind, String outcome) => _logger?.info(
    'agents_modes.open_path',
    context: {'kind': kind, 'outcome': outcome},
  );

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
          message: AgentsBypassStaleMessage(),
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
        message: AgentsTargetUnavailableMessage(),
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
        message: AgentsConflictMessage(),
      ),
      _ => const AgentsModesBanner(
        AgentsModesBannerKind.error,
        message: AgentsNotSavedMessage(),
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
          issues: after.issues,
          banner: AgentsModesBanner(
            AgentsModesBannerKind.saved,
            message: AgentsSavedOnlyMessage(note.layer),
          ),
        ),
      );
    }
  }

  /// Баннер «Saved» по действующему значению нового снимка: если оно не равно
  /// записанному, баннер прямо говорит, что запись перекрыта (другим слоем,
  /// окружением) или сужена недоверенным проектом (design.md D3, D4). Это три
  /// целых сообщения, а не основа с хвостом (D5, правило 7).
  AgentsModesBanner _savedBanner(_SavedNote note) {
    final defaults = _defaults!;
    final isMode = note.kind == 'mode';
    final setting = isMode
        ? AgentsModesSetting.mode
        : AgentsModesSetting.effort;
    final effective = isMode ? defaults.mode.id : defaults.effort.id;
    final blocks = isMode && defaults.mode.blocksWriteAndExec;
    final when = !note.restart.contains(note.key)
        ? AgentsApplyWhen.now
        : _agentConnected()
        ? AgentsApplyWhen.afterRestart
        : AgentsApplyWhen.whenAgentStarts;
    final narrowed = isMode && defaults.mode.narrowedByProject;
    if (!narrowed && effective == note.value) {
      return AgentsModesBanner(
        AgentsModesBannerKind.saved,
        message: AgentsSavedMessage(
          setting: setting,
          value: effective,
          when: when,
          blocksWriteAndExec: blocks,
        ),
      );
    }
    if (narrowed) {
      return AgentsModesBanner(
        AgentsModesBannerKind.warning,
        message: AgentsSavedNarrowedMessage(
          target: note.layer,
          value: effective,
          when: when,
          blocksWriteAndExec: blocks,
        ),
      );
    }
    return AgentsModesBanner(
      AgentsModesBannerKind.warning,
      message: AgentsSavedOverriddenMessage(
        setting: setting,
        target: note.layer,
        source: (isMode ? defaults.mode.source : defaults.effort.source)?.kind,
        value: effective,
        when: when,
        blocksWriteAndExec: blocks,
      ),
    );
  }

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
    _definitionsCancel?.cancel('closed');
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
