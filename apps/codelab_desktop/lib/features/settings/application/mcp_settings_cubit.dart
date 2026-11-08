import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show AgentMessageChunk, SessionId, TextContent;
import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        Connected,
        ConnectionProfile,
        EmbeddedProfile,
        PromptCompleted,
        PromptFailed,
        PromptOutcome,
        PromptQueued,
        Reconnecting,
        SessionStatusView,
        StdioProfile,
        WebSocketProfile,
        WorkspaceState,
        profileOrigin;
import 'package:codelab_embedded/codelab_embedded.dart'
    show McpServerState, McpServerSummary, McpStatusPort;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/home_path_label.dart';
import 'embedded_mcp_status_source.dart';
import 'mcp_settings_state.dart';
import 'provider_settings_session.dart';

export 'embedded_mcp_status_source.dart';
export 'mcp_settings_state.dart';
export 'provider_settings_session.dart';

/// Страница «MCP servers»: серверы `mcp.servers` агента текущего подключения и
/// панель «Agent status».
///
/// Почему: один владелец данных страницы — снимок конфига агента, запись
/// серверов и подписка на состояние MCP встроенного агента (design.md change
/// `add-provider-setup-ui`, D11, D12, D21). Политику («чьи это настройки»,
/// порядок «секрет → конфиг → откат», что можно удалить) решают
/// `resolveSettingsAccess`, `McpServerCommitter` и `McpServerRemover` моста
/// `codelab_setup`; Cubit только вызывает их и превращает итог в состояние
/// (AGENTS.md §7, §10).
///
/// Для чего: собирает состояние из [ProviderSettingsSession] (конфиг, секреты,
/// порты записи) и `WorkspaceState` (профиль, соединение, активная сессия).
/// Для WebSocket и стороннего агента локальный конфиг НЕ читается (SETUP-2):
/// [McpSettingsReadOnly] только с панелью. Нечитаемый слой и проблемы видов
/// `syntax`, `profile`, `unknownKey`, `type` дают [McpSettingsUnreadable];
/// проблемы `rejections` снимка (незаданная `${VAR}` и т. п.) оставляют
/// страницу [McpSettingsReady] с InfoBar `mcp-rejected` (Q26). Значения
/// секретов, `env`, `headers`, URL-пути и тексты ответов `/mcp` в журнал не
/// идут (D18).
///
/// Панель: у встроенного агента — живая таблица по порту
/// [EmbeddedMcpStatusSource]; подписка одна, владелец — этот Cubit (AGENTS.md
/// §9), она отменяется при смене сессии, профиля, переподключении и [close].
/// У агента вне процесса — текст ответа `/mcp …`, отправленного обычным
/// промптом только по кнопке; поздний ответ отбрасывается по номеру запроса.
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// страницы, страница зовёт [reload] и закрывает Cubit вместе с собой.
class McpSettingsCubit extends Cubit<McpSettingsState> {
  McpSettingsCubit({
    required ClientWorkspace workspace,
    required Future<ConnectionProfile> Function() defaultProfile,
    required ProviderSettingsOpener open,
    required Map<String, String> environment,
    required String? codelabHome,
    required String Function() projectDirectory,
    required EmbeddedMcpStatusSource statusSource,
    Logger? logger,
    DateTime Function()? now,
  }) : _workspace = workspace,
       _defaultProfile = defaultProfile,
       _open = open,
       _environment = environment,
       _codelabHome = codelabHome,
       _projectDirectory = projectDirectory,
       _statusSource = statusSource,
       _logger = logger,
       _now = now ?? DateTime.now,
       super(const McpSettingsLoading()) {
    _accessProfile = _connectedProfile(_workspace.current);
    _workspaceSubscription = _workspace.state.listen(_onWorkspace);
    _bindStatus(_workspace.current);
  }

  final ClientWorkspace _workspace;
  final Future<ConnectionProfile> Function() _defaultProfile;
  final ProviderSettingsOpener _open;
  final Map<String, String> _environment;
  final String? _codelabHome;
  final String Function() _projectDirectory;
  final EmbeddedMcpStatusSource _statusSource;
  final Logger? _logger;
  final DateTime Function() _now;

  late final StreamSubscription<WorkspaceState> _workspaceSubscription;

  /// Профиль, для которого прочитан доступ; смена — повод перечитать (D5).
  ConnectionProfile? _accessProfile;

  /// Номер загрузки: поздний снимок после новой загрузки или [close]
  /// отбрасывается (D21).
  var _loadAttempt = 0;

  ProviderSettingsSession? _session;
  EditableSettings? _access;
  AgentConfigSnapshot? _snapshot;

  var _saving = false;

  /// Охрана от второй записи, пока первая ещё не дошла до `_saving` (вопрос
  /// «Replace it» тоже асинхронный): D21, SETUP-6.
  var _writing = false;
  McpBanner? _banner;
  var _newServerOpen = false;
  McpReplaceQuestion? _replaceQuestion;
  McpDraftIssues? _draftIssues;

  /// Читаемая загрузка идёт после своей записи: заголовок `mcp-rejected` и
  /// событие `rejected_after_save`.
  var _afterWrite = false;
  String? _writtenServer;

  // --- Панель «Agent status» --------------------------------------------------

  McpAgentStatus _agentStatus = const McpAgentStatusUnavailable();

  /// Ключ привязки: активная сессия и профиль. Смена пересоздаёт подписки.
  (SessionId?, ConnectionProfile?)? _boundKey;
  var _boundConnected = false;
  SessionId? _boundSession;
  McpStatusPort? _port;
  StreamSubscription<List<McpServerSummary>>? _portSubscription;
  StreamSubscription<Object?>? _viewSubscription;

  /// Номер запроса `/mcp …`: растёт на каждую отправку, смену сессии и
  /// [close]; ответ с устаревшим номером отбрасывается (D12, D21).
  var _commandSeq = 0;
  String? _replyText;
  String? _replyNotice;
  var _sending = false;

  /// Контекст событий панели: корреляция по сессии (AGENTS.md §16).
  Map<String, Object?> _ctx([Map<String, Object?> extra = const {}]) => {
    ...extra,
    'session_id': ?_boundSession?.value,
  };

  static const _listFailed = '/mcp list did not complete. Try Refresh again.';

  // --- Загрузка ---------------------------------------------------------------

  /// Читает доступ и конфиг; вызывается при открытии страницы и при смене
  /// подключения. Своя запись перечитывает снимок сама.
  Future<void> reload() => _reload(afterWrite: false);

  Future<void> _reload({required bool afterWrite}) async {
    final attempt = ++_loadAttempt;
    _afterWrite = afterWrite;
    _accessProfile = _connectedProfile(_workspace.current);
    final ConnectionProfile profile;
    try {
      profile = _accessProfile ?? await _defaultProfile();
    } on Object catch (error) {
      // Ошибка чтения профиля по умолчанию не теряется: страница не
      // остаётся в `Loading` (AGENTS.md §12).
      if (isClosed || attempt != _loadAttempt) {
        return;
      }
      _logger?.warning(
        'mcp_settings.unreadable',
        context: {'error_type': error.runtimeType.toString()},
      );
      _setUnreadable(const ['Cannot read the agent settings.'], log: false);
      return;
    }
    if (isClosed || attempt != _loadAttempt) {
      return;
    }
    switch (_accessOf(profile)) {
      case RemoteReadOnly(:final endpoint):
        _setReadOnly(
          'Read-only: this agent runs on ${profileOrigin(endpoint)}.',
          hint:
              'Change providers and MCP on that host: codelab provider add, '
              'codelab mcp add, codelab config set.',
          access: 'remote',
        );
      case NotManaged(:final agentName):
        _setReadOnly(
          'Provider settings are managed by $agentName.',
          access: 'not_managed',
        );
      case final EditableSettings access:
        await _loadEditable(attempt, profile, access);
    }
  }

  SettingsAccess _accessOf(ConnectionProfile profile) {
    final dir = _projectDirectory();
    final cwd = dir.isEmpty ? null : dir;
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

  void _setReadOnly(String notice, {String? hint, required String access}) {
    _clearSnapshot();
    _logger?.debug(
      'mcp_settings.loaded',
      context: {'servers': 0, 'access': access},
    );
    _emit(
      McpSettingsReadOnly(
        notice: notice,
        hint: hint,
        agentStatus: _agentStatus,
      ),
    );
  }

  void _clearSnapshot() {
    _session = null;
    _access = null;
    _snapshot = null;
  }

  Future<void> _loadEditable(
    int attempt,
    ConnectionProfile profile,
    EditableSettings access,
  ) async {
    if (access.paths.codelabHome.isEmpty) {
      _setUnreadable(const ['The CodeLab home folder is not available.']);
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
      if (isClosed || attempt != _loadAttempt) {
        return;
      }
      _logger?.warning(
        'mcp_settings.unreadable',
        context: {'error_type': error.runtimeType.toString()},
      );
      _setUnreadable(const ['Cannot read the agent settings.'], log: false);
      return;
    }
    if (isClosed || attempt != _loadAttempt) {
      return;
    }
    // Нечитаемый слой и проблемы схемы блокируют запись: файл пользователя не
    // перезаписывается. Проблемы значений (`rejections`) страницу не
    // блокируют (Q26).
    final blocking = [
      for (final issue in snapshot.issues)
        if (_blockingKinds.contains(issue.kind)) issue,
    ];
    if (blocking.isNotEmpty || !snapshot.isReadable(ConfigLayer.user)) {
      _setUnreadable([
        for (final issue in blocking) issue.toString(),
        if (blocking.isEmpty) 'The user config.yaml cannot be read.',
      ]);
      return;
    }
    _session = session;
    _access = access;
    _snapshot = snapshot;
    final rows = mcpServerEntriesOf(snapshot);
    _logger?.debug(
      'mcp_settings.loaded',
      context: {'servers': rows.length, 'access': 'editable'},
    );
    if (_afterWrite && snapshot.rejections.isNotEmpty) {
      _logger?.warning(
        'mcp_settings.rejected_after_save',
        context: {
          'server': ?_writtenServer,
          'issues': snapshot.rejections.length,
        },
      );
    }
    // `_saving` здесь не трогается: перечитывание посреди записи не должно
    // разрешать вторую запись (D21); сбрасывает его только `_finishWrite`.
    _emit(_buildReady());
  }

  static const _blockingKinds = {
    ConfigIssueKind.syntax,
    ConfigIssueKind.profile,
    ConfigIssueKind.unknownKey,
    ConfigIssueKind.type,
  };

  void _setUnreadable(List<String> problems, {bool log = true}) {
    _clearSnapshot();
    if (log) {
      _logger?.warning(
        'mcp_settings.unreadable',
        context: {'error_type': 'ConfigIssue'},
      );
    }
    _emit(McpSettingsUnreadable(problems: problems, agentStatus: _agentStatus));
  }

  McpSettingsReady _buildReady() {
    final snapshot = _snapshot!;
    final backend = _session!.backend;
    return McpSettingsReady(
      rows: [for (final entry in mcpServerEntriesOf(snapshot)) _rowOf(entry)],
      secretStorage: McpSecretStorage(
        backendId: backend.id,
        writable: backend.writable,
        unavailableReason: backend.unavailableReason,
      ),
      canSaveToProject: _canSaveToProject,
      banner: _banner,
      rejected: _rejectedOf(snapshot),
      newServerOpen: _newServerOpen,
      replaceQuestion: _replaceQuestion,
      draftIssues: _draftIssues,
      saving: _saving,
      agentStatus: _agentStatus,
    );
  }

  bool get _canSaveToProject =>
      _access?.targets.any((t) => t.layer == ConfigLayer.projectLocal) ?? false;

  McpServerRow _rowOf(McpServerEntryView entry) {
    final source = entry.source;
    final sourceLabel = switch (source.kind) {
      ConfigSourceKind.user => 'user',
      ConfigSourceKind.projectLocal => 'this project',
      _ => 'defined in ${homePathLabel(source.label, _environment)}',
    };
    final layer = switch (source.kind) {
      ConfigSourceKind.user => ConfigLayer.user,
      ConfigSourceKind.projectLocal => ConfigLayer.projectLocal,
      _ => ConfigLayer.project,
    };
    final fromProjectFile = !entry.editable && !entry.disabledHere;
    final element = entry.editable
        ? mcpServerElementOf(_snapshot!, entry.name)
        : null;
    return McpServerRow(
      draft: element == null
          ? null
          : McpServerDraft.fromElement(element.element),
      name: entry.name,
      entry: entry,
      sourceLabel: sourceLabel,
      layer: layer,
      enabled: entry.enabled,
      canToggle: entry.editable,
      canEdit: entry.editable,
      canRemove: entry.editable,
      canDisableHere: fromProjectFile && _canSaveToProject,
      canEnableHere: entry.disabledHere,
      note: entry.disabledHere
          ? '${entry.name} is disabled in .codelab/config.local.yaml. '
                '"Enable here" removes this override.'
          : fromProjectFile
          ? '${entry.name} comes from the project file: it can\'t be edited '
                'or removed here; "Disable here" writes enabled: false to '
                '.codelab/config.local.yaml.'
          : null,
    );
  }

  McpRejectedConfig? _rejectedOf(AgentConfigSnapshot snapshot) {
    final issues = snapshot.rejections;
    if (issues.isEmpty) {
      return null;
    }
    final server = RegExp(
      r'^mcp\.servers\[([^\]]+)\]',
    ).firstMatch(issues.first.key)?.group(1);
    return McpRejectedConfig(
      title: _afterWrite
          ? 'Saved, but the agent rejected the new config'
          : 'The agent rejects the current config',
      problems: [
        for (final issue in issues)
          issue.key.isEmpty ? issue.message : '${issue.key}: ${issue.message}',
      ],
      editServer: server,
    );
  }

  /// Имя секрета для значения [key] сервера [server] (`codelab/mcp/…`):
  /// правило моста, по которому подпись «Secret — stored in … as …» совпадает
  /// с тем, что будет записано (D11).
  static String secretNameFor(String server, String key) =>
      SecretNames.forMcp(server, key);

  // --- Карточка нового сервера -------------------------------------------------

  /// «Add server»: открывает карточку `New server`; вторая «Add server», пока
  /// карточка открыта, ничего не меняет (Q25 (1)).
  void openNewServer() {
    if (_newServerOpen || state is! McpSettingsReady) {
      return;
    }
    _newServerOpen = true;
    _publishReady();
  }

  /// «Cancel» карточки: убирает её без записи; во время записи не работает.
  void cancelNewServer() {
    if (!_newServerOpen || _saving || _writing) {
      return;
    }
    _newServerOpen = false;
    _draftIssues = _draftIssues?.server == null ? null : _draftIssues;
    _replaceQuestion = _replaceQuestion?.server == null
        ? null
        : _replaceQuestion;
    _publishReady();
  }

  /// Черновик правки сервера [name] из СЫРОГО элемента его слоя; `null` —
  /// сервера нет или его нельзя править (слой 3, «disabled here»).
  McpServerDraft? draftFor(String name) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return null;
    }
    final editable = mcpServerEntriesOf(
      snapshot,
    ).where((e) => e.name == name && e.editable).firstOrNull;
    final element = mcpServerElementOf(snapshot, name);
    if (editable == null || element == null) {
      return null;
    }
    return McpServerDraft.fromElement(element.element);
  }

  /// Снимает вопрос «Replace it» без записи.
  void dismissReplaceQuestion() {
    if (_replaceQuestion == null) {
      return;
    }
    _replaceQuestion = null;
    _publishReady();
  }

  /// Редактор отклонил черновик до отправки (например, два одинаковых ключа
  /// в карте не различить): проблема публикуется в состоянии, как проблемы
  /// `validate`, и пишется `mcp_settings.save_failed` (`invalid`). Текст
  /// проблемы принадлежит состоянию, а не полю виджета (ревью 5b).
  void rejectDraft({
    required String? server,
    required String name,
    required List<McpDraftProblem> problems,
  }) {
    if (state is! McpSettingsReady) {
      return;
    }
    _draftIssues = McpDraftIssues(server: server, problems: problems);
    _replaceQuestion = null;
    _logSaveFailed(server: name, operation: 'save', outcome: 'invalid');
    _publishReady();
  }

  // --- Запись ------------------------------------------------------------------

  /// Сохраняет [draft]: новый сервер — в слой [target], правка — в слой самого
  /// сервера ([target] игнорируется, Q27). `true` — записано.
  ///
  /// До `commit` проверяет черновик вместе с занятыми именами
  /// (`validate(existingNames:)`: мост уникальность не проверяет) и спрашивает
  /// `McpServerCommitter.occupiedSecrets` (то же правило, что в `commit`);
  /// занятые имена, не выбранные в [replaceSecrets], дают вопрос «Replace it»
  /// без записи (SETUP-5).
  Future<bool> save(
    McpServerDraft draft, {
    ConfigLayer target = ConfigLayer.user,
    Set<String> replaceSecrets = const {},
  }) => _exclusive(
    () => _save(draft, target, replaceSecrets),
    server: draft.name,
    operation: 'save',
  );

  Future<bool> _save(
    McpServerDraft draft,
    ConfigLayer target,
    Set<String> replaceSecrets,
  ) async {
    final snapshot = _snapshot;
    final session = _session;
    if (state is! McpSettingsReady || snapshot == null || session == null) {
      return false;
    }
    final original = draft.originalName;
    final problems = draft.validate(
      existingNames: {for (final e in mcpServerEntriesOf(snapshot)) e.name},
    );
    if (problems.isNotEmpty) {
      _draftIssues = McpDraftIssues(server: original, problems: problems);
      _replaceQuestion = null;
      _logSaveFailed(server: draft.name, operation: 'save', outcome: 'invalid');
      _publishReady();
      return false;
    }
    final ConfigLayer layer;
    if (original != null) {
      final editable = mcpServerEntriesOf(
        snapshot,
      ).where((e) => e.name == original && e.editable).firstOrNull;
      final element = mcpServerElementOf(snapshot, original);
      if (editable == null || element == null) {
        _failRefused(original, 'save', McpServerRefusal.notEditable);
        return false;
      }
      layer = element.layer;
    } else {
      layer = target;
      if (layer == ConfigLayer.project ||
          (layer == ConfigLayer.projectLocal && !_canSaveToProject)) {
        _failRefused(draft.name, 'save', McpServerRefusal.noProjectTarget);
        return false;
      }
    }
    final base = snapshot.layers[layer];
    if (base == null) {
      _failRefused(draft.name, 'save', McpServerRefusal.layerUnreadable);
      return false;
    }
    // Подключение или конфиг могли смениться, пока шёл ответ хранилища:
    // запись по прежнему снимку не выполняется (ревью 5b, LOW-4).
    final attempt = _loadAttempt;
    final committer = session.mcpCommitter();
    final check = await committer.occupiedSecrets(
      draft,
      replaceSecrets: replaceSecrets,
    );
    if (isClosed) {
      return false;
    }
    if (attempt != _loadAttempt || !identical(session, _session)) {
      _banner = const McpBanner(McpBannerKind.error, [
        'The MCP server settings changed. Review the page and try again.',
      ]);
      _logSaveFailed(server: draft.name, operation: 'save', outcome: 'stale');
      _publishReady();
      return false;
    }
    if (check.errorType case final type?) {
      _banner = const McpBanner(McpBannerKind.error, [
        'The secret store could not be read, so nothing was saved.',
      ]);
      _logSaveFailed(
        server: draft.name,
        operation: 'save',
        outcome: 'error',
        errorType: type,
      );
      _publishReady();
      return false;
    }
    if (check.names.isNotEmpty) {
      _draftIssues = null;
      _replaceQuestion = McpReplaceQuestion(
        server: original,
        names: check.names,
      );
      _publishReady();
      return false;
    }
    _draftIssues = null;
    _replaceQuestion = null;
    _beginWrite();
    final outcome = await committer.commit(
      draft,
      base,
      replaceSecrets: replaceSecrets,
      cwd: snapshot.cwd,
    );
    if (isClosed) {
      return outcome is McpServerCommitted;
    }
    final name = draft.name;
    switch (outcome) {
      case McpServerCommitted(
        :final saved,
        :final replacedSecrets,
        :final secrets,
      ):
        final cleanup = _cleanupSummary(secrets);
        _logger?.info(
          'mcp_settings.saved',
          context: {
            'server': name,
            'type': draft.kind.name,
            'target': _targetName(layer),
            'secret_refs': _secretRefs(draft),
            'replaced': replacedSecrets.length,
            'secrets_deleted': cleanup.deleted,
            'secrets_kept': cleanup.kept,
            'secrets_failed': cleanup.failed,
          },
        );
        if (original == null) {
          _newServerOpen = false;
        }
        await _finishWrite(
          server: name,
          wrote: true,
          banner: McpBanner(
            cleanup.failed > 0 ? McpBannerKind.error : McpBannerKind.saved,
            [
              'Server $name saved.',
              for (final warning in saved.warnings)
                warning.key.isEmpty
                    ? warning.message
                    : '${warning.key}: ${warning.message}',
              ...cleanup.lines,
            ],
          ),
        );
        return true;
      case McpServerInvalid(:final problems):
        _draftIssues = McpDraftIssues(server: original, problems: problems);
        _logSaveFailed(server: name, operation: 'save', outcome: 'invalid');
        await _finishWrite(server: name);
        return false;
      case McpSecretAppeared(:final names):
        _replaceQuestion = McpReplaceQuestion(server: original, names: names);
        _logSaveFailed(
          server: name,
          operation: 'save',
          outcome: 'secret_appeared',
        );
        await _finishWrite(server: name);
        return false;
      case McpSecretNotStored(
        :final reason,
        :final rollback,
        :final notRolledBack,
      ):
        await _finishWrite(
          server: name,
          failedOutcome: 'secret_failed',
          operation: 'save',
          rollback: rollback,
          banner: McpBanner(McpBannerKind.error, [
            'The secret was not stored, so nothing was saved: $reason',
            // Записанные до отказа секреты, которые откат не удалил, остались
            // в хранилище: имя и команда для ручного удаления (D9).
            for (final secret in notRolledBack)
              '$secret could not be deleted. Delete it with: '
                  'codelab secret delete $secret',
          ]),
        );
        return false;
      case McpServerNotSaved(
        :final outcome,
        :final errorType,
        :final rollback,
        :final replacedSecrets,
        :final notRolledBack,
      ):
        await _finishWrite(
          server: name,
          failed: outcome,
          errorType: errorType,
          operation: 'save',
          rollback: rollback,
          extraLines: [
            // Созданный секрет, который откат не смог удалить, остаётся в
            // хранилище: имя и команда нужны для ручного удаления (D9).
            for (final secret in notRolledBack)
              '$secret could not be deleted. Delete it with: '
                  'codelab secret delete $secret',
            for (final secret in replacedSecrets)
              'The stored value of $secret was already replaced and could '
                  'not be restored.',
          ],
        );
        return false;
    }
  }

  /// Итог очистки секретов страницы: строки баннера (как у «Remove», Q25 (4))
  /// и числа для журнала; имена секретов в журнал не идут (D18).
  ({List<String> lines, int deleted, int kept, int failed}) _cleanupSummary(
    Map<String, SecretCleanup> secrets,
  ) {
    var deleted = 0, kept = 0, failed = 0;
    final lines = <String>[];
    for (final MapEntry(:key, :value) in secrets.entries) {
      switch (value) {
        case SecretCleanup.deleted:
          deleted++;
        case SecretCleanup.kept:
          kept++;
          lines.add('$key is kept: it was not created by this page.');
        case SecretCleanup.stillReferenced:
          kept++;
          lines.add('$key is kept because other settings still use it.');
        case SecretCleanup.failed:
          failed++;
          lines.add(
            '$key could not be deleted. Delete it with: '
            'codelab secret delete $key',
          );
        case SecretCleanup.alreadyAbsent || SecretCleanup.notRequested:
          break;
      }
    }
    return (lines: lines, deleted: deleted, kept: kept, failed: failed);
  }

  static int _secretRefs(McpServerDraft draft) {
    final table = draft.kind == McpTransportKind.stdio
        ? draft.env
        : draft.headers;
    return table.values
        .where(
          (v) => switch (v) {
            McpTextValue(:final value) => value.contains(r'${secret:'),
            _ => true,
          },
        )
        .length;
  }

  static String _targetName(ConfigLayer layer) =>
      layer == ConfigLayer.user ? 'user' : 'local';

  /// Переключатель `enabled`: пишет сырой элемент слоя сервера с новым
  /// `enabled` (D11). У слоя 3 и «disabled here» запись не идёт.
  Future<bool> setEnabled(String name, {required bool enabled}) =>
      _exclusive(server: name, operation: 'toggle', () async {
        final snapshot = _snapshot;
        final session = _session;
        final row = _rowNamed(name);
        if (snapshot == null || session == null || row == null) {
          return false;
        }
        if (!row.canToggle) {
          return false;
        }
        _beginWrite();
        final outcome = await session.mcpCommitter().setEnabled(
          snapshot,
          name,
          enabled: enabled,
        );
        return _finishToggle(
          name,
          outcome,
          action: enabled ? 'enable' : 'disable',
          target: _targetName(row.layer),
        );
      });

  /// «Disable here» сервера слоя 3: `{name, enabled: false}` в `projectLocal`
  /// (Q21). Отказ моста (`noProjectTarget`, `layerUnreadable`) — баннер без
  /// записи.
  Future<bool> disableHere(String name) =>
      _exclusive(server: name, operation: 'toggle', () async {
        final snapshot = _snapshot;
        final session = _session;
        final access = _access;
        if (snapshot == null || session == null || access == null) {
          return false;
        }
        _beginWrite();
        final outcome = await session.mcpCommitter().disableHere(
          snapshot,
          name,
          access: access,
        );
        return _finishToggle(
          name,
          outcome,
          action: 'disable_here',
          target: 'local',
        );
      });

  /// «Enable here»: убирает переопределение из `projectLocal` (Q21).
  Future<bool> enableHere(
    String name,
  ) => _exclusive(server: name, operation: 'toggle', () async {
    final snapshot = _snapshot;
    final session = _session;
    if (snapshot == null || session == null) {
      return false;
    }
    _beginWrite();
    final outcome = await session.mcpRemover().enableHere(snapshot, name: name);
    return _finishToggle(name, outcome, action: 'enable_here', target: 'local');
  });

  Future<bool> _finishToggle(
    String name,
    McpServerWriteOutcome outcome, {
    required String action,
    required String target,
  }) async {
    if (isClosed) {
      return outcome is McpServerWritten;
    }
    switch (outcome) {
      case McpServerWritten():
        _logger?.info(
          'mcp_settings.toggled',
          context: {'server': name, 'action': action, 'target': target},
        );
        await _finishWrite(server: name, wrote: true);
        return true;
      case McpServerNotWritten(:final outcome, :final errorType):
        await _finishWrite(
          server: name,
          failed: outcome,
          errorType: errorType,
          operation: 'toggle',
        );
        return false;
      case McpServerRefused(:final reason):
        await _finishWrite(
          server: name,
          operation: 'toggle',
          refusal: reason,
          banner: McpBanner(McpBannerKind.error, [_refusalText(reason)]),
        );
        return false;
    }
  }

  // --- Remove ------------------------------------------------------------------

  /// Данные диалога `Remove <name>?`: секреты страницы, которые будут
  /// удалены, если ими никто не пользуется (Q25 (3)). Список даёт мост
  /// (`McpServerRemover.secretCandidatesOf`). `null` — сервера нет или его
  /// нельзя удалить. Ничего не пишет.
  McpRemovalPlan? removalPlan(String name) {
    final snapshot = _snapshot;
    final row = _rowNamed(name);
    if (snapshot == null || row == null || !row.canRemove) {
      return null;
    }
    return McpRemovalPlan(
      server: name,
      secrets: McpServerRemover.secretCandidatesOf(snapshot, name),
    );
  }

  /// Удаляет сервер [name] одной записью; секреты — после `ConfigSaved` и
  /// только без оставшихся ссылок (SETUP-24). Вызывается после подтверждения.
  Future<bool> remove(String name) =>
      _exclusive(server: name, operation: 'remove', () async {
        final snapshot = _snapshot;
        final session = _session;
        final row = _rowNamed(name);
        if (snapshot == null ||
            session == null ||
            row == null ||
            !row.canRemove) {
          return false;
        }
        _beginWrite();
        final outcome = await session.mcpRemover().remove(snapshot, name: name);
        if (isClosed) {
          return outcome is McpServerRemoved;
        }
        switch (outcome) {
          case McpServerRemoved(:final secrets):
            final cleanup = _cleanupSummary(secrets);
            _logger?.info(
              'mcp_settings.removed',
              context: {
                'server': name,
                'secrets_deleted': cleanup.deleted,
                'secrets_kept': cleanup.kept,
                'secrets_failed': cleanup.failed,
              },
            );
            await _finishWrite(
              server: name,
              wrote: true,
              banner: McpBanner(
                cleanup.failed > 0 ? McpBannerKind.error : McpBannerKind.saved,
                ['Server $name removed.', ...cleanup.lines],
              ),
            );
            return true;
          case McpServerRemovalNotSaved(:final outcome, :final errorType):
            await _finishWrite(
              server: name,
              failed: outcome,
              errorType: errorType,
              operation: 'remove',
            );
            return false;
          case McpServerRemovalRefused(:final reason):
            await _finishWrite(
              server: name,
              operation: 'remove',
              refusal: reason,
              banner: McpBanner(McpBannerKind.error, [_refusalText(reason)]),
            );
            return false;
        }
      });

  static String _refusalText(McpServerRefusal reason) => switch (reason) {
    McpServerRefusal.unknownServer ||
    McpServerRefusal.layerUnreadable ||
    McpServerRefusal.notDisabledHere =>
      'The MCP settings changed. Review the page and try again.',
    McpServerRefusal.notEditable =>
      'This server is defined in a read-only file. Change it there.',
    McpServerRefusal.notProject =>
      'Only a server from the project file can be disabled here.',
    McpServerRefusal.noProjectTarget =>
      'The project folder is not known, so nothing can be written to '
          '.codelab/config.local.yaml.',
  };

  McpServerRow? _rowNamed(String name) {
    final current = state;
    return current is McpSettingsReady
        ? current.rows.where((r) => r.name == name).firstOrNull
        : null;
  }

  // --- Общая часть записи -------------------------------------------------------

  /// Выполняет запись по одной за раз и при ЛЮБОМ исходе сбрасывает признак
  /// записи: исключение хранилища или писателя не оставляет страницу в
  /// `saving` и не теряется — баннер `error` и `save_failed` с типом
  /// исключения (D18, ревью 5b).
  Future<bool> _exclusive(
    Future<bool> Function() action, {
    required String server,
    required String operation,
  }) async {
    if (_writing || _saving || state is! McpSettingsReady) {
      return false;
    }
    _writing = true;
    try {
      return await action();
    } on Object catch (error) {
      if (!isClosed) {
        _saving = false;
        _banner = const McpBanner(McpBannerKind.error, [
          'The change was not saved because of an error.',
        ]);
        _logSaveFailed(
          server: server,
          operation: operation,
          outcome: 'error',
          errorType: error.runtimeType.toString(),
        );
        _publishReady();
      }
      return false;
    } finally {
      _writing = false;
    }
  }

  void _beginWrite() {
    _saving = true;
    _banner = null;
    _publishReady();
  }

  /// Отказ до записи: баннер и событие, файл и хранилище не тронуты.
  void _failRefused(String server, String operation, McpServerRefusal reason) {
    _banner = McpBanner(McpBannerKind.error, [_refusalText(reason)]);
    _logSaveFailed(
      server: server,
      operation: operation,
      outcome: 'refused',
      refusal: reason,
    );
    _publishReady();
  }

  /// Итог записи в баннер и перечитывание снимка (после любого исхода: файл
  /// мог измениться, а отказ оставляет страницу прежней).
  ///
  /// [failed] — неуспешный исход записи (баннер по его виду); `null` с
  /// [errorType] — исключение писателя. Событие `save_failed` несёт только вид
  /// исхода, без текстов проблем (D18).
  Future<void> _finishWrite({
    required String server,
    ConfigSaveOutcome? failed,
    String? errorType,
    String operation = 'save',
    KeyRollback? rollback,
    String? failedOutcome,
    McpServerRefusal? refusal,
    McpBanner? banner,
    bool wrote = false,
    List<String> extraLines = const [],
  }) async {
    final isFailure =
        failed != null ||
        errorType != null ||
        failedOutcome != null ||
        refusal != null;
    if (failed != null || errorType != null) {
      switch (failed) {
        case ConfigConflict():
          _banner = const McpBanner(McpBannerKind.conflict, [
            'The config changed on disk, so nothing was saved. The page was '
                'reloaded; review it and try again.',
          ]);
          failedOutcome = 'conflict';
        case ConfigRejected(:final issues):
          _banner = McpBanner(McpBannerKind.error, [
            'The config was not saved: ${[for (final i in issues) i.key.isEmpty ? i.message : '${i.key}: ${i.message}'].join('; ')}',
          ]);
          failedOutcome = 'rejected';
        case ConfigInlineSecret(:final key):
          _banner = McpBanner(McpBannerKind.error, [
            'The config was not saved: $key must not hold a literal secret.',
          ]);
          failedOutcome = 'inline_secret';
        case ConfigSaved():
        case null:
          _banner = const McpBanner(McpBannerKind.error, [
            'The config was not saved because of an error.',
          ]);
          failedOutcome = 'error';
      }
    } else {
      _banner = banner;
      if (refusal != null) {
        failedOutcome = 'refused';
      }
    }
    if (extraLines.isNotEmpty && _banner != null) {
      _banner = McpBanner(_banner!.kind, [..._banner!.lines, ...extraLines]);
    }
    if (isFailure) {
      _logSaveFailed(
        server: server,
        operation: operation,
        outcome: failedOutcome!,
        refusal: refusal,
        rollback: operation == 'save' ? rollback : null,
        errorType: failedOutcome == 'error' ? errorType : null,
      );
    } else if (wrote) {
      _writtenServer = server;
    }
    _saving = false;
    await _reload(afterWrite: wrote);
  }

  void _logSaveFailed({
    required String server,
    required String operation,
    required String outcome,
    McpServerRefusal? refusal,
    KeyRollback? rollback,
    String? errorType,
  }) => _logger?.warning(
    'mcp_settings.save_failed',
    context: {
      'server': server,
      'operation': operation,
      'outcome': outcome,
      'refusal': ?refusal?.name,
      'rollback': ?rollback?.name,
      'error_type': ?errorType,
    },
  );

  // --- Панель «Agent status» -----------------------------------------------------

  static ConnectionProfile? _connectedProfile(WorkspaceState state) =>
      state.connection is Connected || state.connection is Reconnecting
      ? state.profile
      : null;

  void _onWorkspace(WorkspaceState next) {
    _bindStatus(next);
    final profile = _connectedProfile(next);
    if (profile != _accessProfile) {
      // Смена подключения перечитывает доступ (D5).
      unawaited(reload());
    }
  }

  /// Привязывает панель к активной сессии (D12). Подписка на `changes` одна:
  /// прежняя отменяется до новой при смене сессии, профиля и при каждом
  /// переходе встроенного агента в `Connected` и обратно (новое соединение —
  /// новый агент и новый порт даже при том же id сессии).
  void _bindStatus(WorkspaceState ws) {
    final connected = ws.connection is Connected;
    final embedded = ws.profile is EmbeddedProfile;
    final key = (ws.activeSessionId, ws.profile);
    final structural = key != _boundKey;
    final reconnected = embedded && connected != _boundConnected;
    _boundConnected = connected;
    if (!structural && !reconnected) {
      if (!embedded) {
        _setStatus(_textStatus());
      }
      return;
    }
    _boundKey = key;
    _unbindStatus();
    if (structural) {
      // Ответ `/mcp …` прежней сессии больше не нужен (D21).
      _commandSeq++;
      _replyText = null;
      _replyNotice = null;
      _sending = false;
    }
    final id = ws.activeSessionId;
    _boundSession = id;
    if (id == null || ws.profile == null) {
      _setStatus(const McpAgentStatusUnavailable());
      return;
    }
    if (embedded) {
      final port = connected ? _statusSource.statusOf(id) : null;
      if (port == null) {
        _setStatus(const McpAgentStatusUnavailable());
        return;
      }
      _port = port;
      _portSubscription = port.changes.listen(
        (servers) => _setStatus(_liveStatus(servers)),
        onDone: () {
          // Сессия или агент закрыты: панель недоступна до следующего
          // `Connected`.
          if (identical(_port, port)) {
            _portSubscription = null;
            _port = null;
            _setStatus(const McpAgentStatusUnavailable());
          }
        },
      );
      _logger?.debug('mcp_settings.status_subscribed', context: _ctx());
      _setStatus(_liveStatus(port.servers));
      return;
    }
    final handle = _workspace.session(id);
    if (handle != null) {
      _viewSubscription = handle.view.listen((_) {
        _setStatus(_textStatus());
      });
    }
    _setStatus(_textStatus());
  }

  void _unbindStatus() {
    if (_portSubscription != null) {
      unawaited(_portSubscription!.cancel());
      _logger?.debug('mcp_settings.status_unsubscribed', context: _ctx());
    }
    _portSubscription = null;
    _port = null;
    unawaited(_viewSubscription?.cancel());
    _viewSubscription = null;
  }

  McpAgentStatus _liveStatus(List<McpServerSummary> servers) =>
      McpAgentStatusLive(
        rows: [
          for (final s in servers)
            McpStatusRow(
              name: s.name,
              state: s.state,
              stateLabel: switch (s.state) {
                McpServerState.connecting => 'connecting',
                McpServerState.connected => 'connected',
                McpServerState.disabled => 'disabled',
                McpServerState.failed =>
                  s.retryIn == null
                      ? 'failed'
                      : 'failed · retry in ${s.retryIn!.inSeconds} s',
              },
              tools: s.state == McpServerState.disabled
                  ? '—'
                  : '${s.toolCount}',
              lastError: s.lastError ?? '—',
              canReconnect: s.state != McpServerState.disabled,
            ),
        ],
        updatedAt: _now(),
      );

  /// Панель агента вне процесса: `Unavailable` без сессии и без команды
  /// `mcp`; иначе текст с признаком `canSend` (D12).
  McpAgentStatus _textStatus() {
    final id = _boundSession;
    final handle = id == null ? null : _workspace.session(id);
    if (handle == null ||
        !handle.current.agentCommands.any((c) => c.name == 'mcp')) {
      return const McpAgentStatusUnavailable();
    }
    final view = handle.current;
    final canSend =
        _workspace.current.connection is Connected &&
        !_sending &&
        view.status == SessionStatusView.idle &&
        view.queue.isEmpty;
    return McpAgentStatusText(
      text: _replyText,
      sending: _sending,
      canSend: canSend,
      notice: _replyNotice,
    );
  }

  void _setStatus(McpAgentStatus status) {
    _agentStatus = status;
    final current = state;
    if (!isClosed && current is McpSettingsLoaded) {
      emit(current.withAgentStatus(status));
    }
  }

  /// «Refresh»: `/mcp list` агенту вне процесса. Встроенному агенту не нужен:
  /// его таблица живая.
  Future<void> refresh() => _send('/mcp list', command: 'list');

  /// «Reconnect» строки: порт встроенного агента или `/mcp reload <name>`.
  Future<void> reconnectServer(String name) async {
    final port = _port;
    if (port != null) {
      _logger?.info(
        'mcp_settings.status_reconnect',
        context: _ctx({'server': name, 'scope': 'one'}),
      );
      await port.reconnect(name);
      return;
    }
    await _send('/mcp reload $name', command: 'reload', server: name);
  }

  /// «Reload all»: у встроенного агента — `reconnect` по очереди без
  /// `disabled`, у остальных — `/mcp reload`.
  Future<void> reloadAll() async {
    final port = _port;
    if (port != null) {
      _logger?.info(
        'mcp_settings.status_reconnect',
        context: _ctx({'server': '*', 'scope': 'all'}),
      );
      for (final server in [...port.servers]) {
        if (server.state == McpServerState.disabled || isClosed) {
          continue;
        }
        await port.reconnect(server.name);
      }
      return;
    }
    await _send('/mcp reload', command: 'reload');
  }

  /// Отправляет команду обычным промптом активной сессии по явному действию
  /// пользователя (SETUP-14). Текст ответа этого хода — склейка
  /// `AgentMessageChunk` из `PromptCompleted.turn.updates` без разбора.
  Future<void> _send(
    String text, {
    required String command,
    String? server,
  }) async {
    final id = _boundSession;
    final handle = id == null ? null : _workspace.session(id);
    // Признак пересчитывается по текущему виду сессии и соединению: событие
    // `view` могло ещё не прийти, а ход — уже начаться (ревью 5b).
    if (_agentStatus is! McpAgentStatusText || handle == null) {
      return;
    }
    final status = _textStatus();
    if (status is! McpAgentStatusText || !status.canSend) {
      _setStatus(status);
      return;
    }
    final seq = ++_commandSeq;
    _sending = true;
    _setStatus(_textStatus());
    _logger?.info(
      'mcp_settings.command_sent',
      context: _ctx({'command': command, 'server': ?server}),
    );
    PromptOutcome? outcome;
    try {
      outcome = await handle.send(text);
    } on Object {
      // Текст исключения не показывается и не пишется (Q25 (6), D18).
      outcome = null;
    }
    // Встав в очередь, команда ушла бы позже сама, без действия
    // пользователя: элемент убирается всегда, даже если страницу закрыли или
    // сессия сменилась (SETUP-14, ревью 5b).
    var alreadySent = false;
    if (outcome case PromptQueued(:final item)) {
      // `null` — элемент уже ушёл к агенту: гонку видно в журнале.
      alreadySent = handle.queue.remove(item.id) == null;
    }
    if (isClosed) {
      _discarded(command, 'closed', id);
      return;
    }
    if (seq != _commandSeq) {
      _discarded(command, 'session_changed', id);
      return;
    }
    _sending = false;
    switch (outcome) {
      case PromptCompleted(:final turn):
        _replyText = [
          for (final update in turn.updates)
            if (update is AgentMessageChunk && update.content is TextContent)
              (update.content as TextContent).text,
        ].join();
        _replyNotice = null;
      case PromptQueued():
        _replyNotice = _listFailed;
        _discarded(command, alreadySent ? 'already_sent' : 'queued', id);
      case PromptFailed() || null:
        _replyNotice = _listFailed;
        _discarded(command, 'failed', id);
    }
    _setStatus(_textStatus());
  }

  void _discarded(String command, String reason, SessionId? session) =>
      _logger?.debug(
        'mcp_settings.command_discarded',
        context: {
          'command': command,
          'reason': reason,
          'session_id': ?session?.value,
        },
      );

  // --- Служебное -----------------------------------------------------------------

  void _publishReady() {
    if (isClosed || _snapshot == null || _session == null) {
      return;
    }
    emit(_buildReady());
  }

  void _emit(McpSettingsState next) {
    if (!isClosed) {
      emit(next);
    }
  }

  @override
  Future<void> close() async {
    // Ответ `/mcp …`, пришедший позже, отбрасывается (D21).
    _commandSeq++;
    _unbindStatus();
    await _workspaceSubscription.cancel();
    return super.close();
  }
}
