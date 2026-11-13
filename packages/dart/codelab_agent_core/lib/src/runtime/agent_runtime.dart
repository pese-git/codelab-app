import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart'
    show DeepCollectionEquality, ListEquality;
import 'package:meta/meta.dart' show visibleForTesting;

import '../agents/agent_definition.dart';
import '../cancel/cancel_token.dart';
import '../commands/builtin_commands.dart';
import '../commands/command_template.dart';
import '../commands/command_line.dart';
import '../commands/expand_command.dart';
import '../commands/slash_command.dart';
import '../compaction/compactor.dart';
import '../compaction/estimate.dart';
import '../compaction/settings.dart';
import '../compaction/summarizer.dart';
import '../config/config_issue.dart';
import '../config/config_reload_plan.dart';
import '../config/config_source.dart';
import '../config/core_config.dart';
import '../config/host_settings.dart';
import '../config/project_config.dart';
import '../config/key_path.dart' show pathComponents, samePath;
import '../env/bounded_env.dart';
import '../env/execution_env.dart';
import '../llm/event_stream.dart';
import '../llm/messages.dart';
import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';
import '../llm/usage.dart';
import '../llm/stream_function.dart';
import '../loop/agent.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../mcp/mcp_connector.dart';
import '../mcp/mcp_server_config.dart';
import '../mcp/mcp_status_port.dart';
import '../mcp/mcp_tool_name.dart';
import '../permissions/agent_config_paths.dart';
import '../permissions/modes.dart';
import '../permissions/policy.dart';
import '../project/project_context.dart';
import '../project/project_files.dart';
import '../skills/active_skills.dart' as active;
import '../skills/catalog_entries.dart';
import '../skills/skill_commands.dart';
import '../skills/skill_invocation.dart';
import '../skills/skill_catalog.dart';
import '../skills/skill_files.dart';
import '../skills/skills_config.dart' show defaultSkillsCatalogMaxChars;
import '../prompts/compose.dart';
import '../secrets/secret_lookup.dart';
import '../secrets/secret_resolver.dart';
import '../secrets/secret_template.dart' show UnusableSecretReference;
import '../session/ids.dart';
import '../session/projections.dart';
import '../session/records.dart';
import '../session/session_store.dart';
import '../session/session_writer.dart';
import '../session/summary.dart';
import '../session/tree.dart';
import '../tools/agent_tool.dart';
import '../tools/builtin/exec.dart';
import '../tools/builtin/read.dart';
import '../tools/builtin/skill.dart';
import '../tools/executor.dart';
import '../tools/registry.dart';
import '../util/logger.dart';
import '../util/result.dart';
import '../host/host_profile.dart';
import '../host/last_model_store.dart';
import '../host/services.dart';
import 'agent_session.dart';
import 'config_reload.dart';
import 'select_session_model.dart';

/// Кто пишет журналы этого ядра (поле `agent` заголовка, §8.2.1).
/// Предел фазы чтения файлов проекта в `session/new` (D6).
const _projectFilesTimeout = Duration(seconds: 5);

const coreAgentVersion = '0.1.0';
const coreAgentInfo = AgentInfo(
  name: 'codelab-agent',
  version: coreAgentVersion,
);

/// Среда выполнения ядра (`agent-core-architecture` §5.6): создаёт,
/// открывает и перечисляет сессии этого процесса.
///
/// Почему отдельный объект: сессии делят сервисы хоста (хранилище журнала,
/// часы, id, модель), а хост и ACP-адаптер получают их через одну точку —
/// `buildAgentCore` (HOST-6).
///
/// Как использовать: [createSession] — новая сессия с журналом;
/// [loadSession] — продолжение сохранённой; [listSessions] — страница
/// сводок из хранилища; [dispose] — при выходе хоста (design.md change
/// `add-agent-core-sessions-and-compaction`, D4, D5).
abstract interface class AgentRuntime {
  Future<AgentSession> createSession(SessionSpec spec);

  /// Каталог моделей сборки: опция `model` и `AgentSession.setModel`
  /// (§2.12.2, §13.6).
  ModelCatalog get models;

  /// Открывает журнал, дописывает синтетические результаты прерванных
  /// вызовов и восстанавливает транскрипт, режим, план и усилие
  /// рассуждения. [model] — модель сессии; `null` — последняя
  /// `model_change` ветки, найденная в [models], иначе модель по умолчанию
  /// конфигурации с логом `session.model.not_restored` (design.md change
  /// `add-dart-agent-acp-server`, D3). [cwd] — рабочая папка клиента: если
  /// она не совпадает с заголовком, сессия работает в ней и пишет `custom`
  /// `codelab.cwd_changed` (§13.5, шаг 2).
  ///
  /// [mcpServers] — серверы MCP, которые клиент прислал в `session/load`
  /// (`origin: session`); описания серверов в журнал не пишутся, поэтому
  /// клиент присылает их заново (§13.5; design.md change
  /// `add-agent-mcp-client`, D6).
  Future<AgentSession> loadSession(
    SessionId id,
    SessionHostPorts ports, {
    ModelRef? model,
    String? cwd,
    List<McpServerConfig> mcpServers = const [],
  });

  /// Страница сводок хранилища; неверный курсор — `InvalidCursor`.
  Future<SessionPage> listSessions({
    String? cwd,
    String? cursor,
    int pageSize = 50,
  });

  /// Перезагружает конфигурацию из [AgentCoreServices.config] и применяет
  /// её к работающему агенту (design.md change
  /// `add-config-writer-and-reload`, D8; CFG-15, CFG-16).
  ///
  /// Почему на рантайме: снимок, функция модели и каталог заменяются одной
  /// атомарной операцией, а живые сессии получают `ModelOptionsChanged`.
  /// Вызывают сигнал `ConfigSource.changes` (рантайм подписан сам),
  /// `/config reload` и `/mcp reload`. Не бросает: ошибка загрузки или
  /// повторной проверки — итог `failed` с прежним снимком. Перезагрузка,
  /// начатая во время идущей, ставит не больше одного повтора, и все такие
  /// вызовы получают его итог. После `dispose()` результат отбрасывается
  /// (итог `unchanged`, снимок не меняется). Без источника — [StateError].
  Future<ConfigApplyReport> reloadConfig();

  /// Загружает конфигурацию без применения (`/config check`): по доверию,
  /// закреплённому в `ConfigSource.initial`. Отложенные до перезапуска ключи
  /// (новое `trusted_projects` и др.) приходят предупреждениями результата с
  /// событием `config.reload.restart_required` и ключом в `key` — команда
  /// печатает их строкой `Restart required`. Состояние рантайма не меняется.
  /// Исключение загрузки уходит вызывающему. Без источника — [StateError].
  Future<ConfigLoadResult> checkConfig();

  /// Состояние конфигурации на момент вызова; без источника — снимок
  /// сборки без источников.
  ConfigStatus configStatus();

  /// Порт состояния MCP-серверов открытой сессии [id] для хоста (design.md
  /// change `add-provider-setup-ui`, D12, решение Q18): снимок `servers`,
  /// поток `changes` и `reconnect(name)`.
  ///
  /// Порт есть у любой открытой сессии: без серверов `servers` пуст, а
  /// `changes` пришлёт список, когда серверы появятся после перезагрузки
  /// конфига (рантайм переподписывается на новый `McpSessionTools` сам).
  /// `null` — сессия неизвестна или закрыта. Поток закрывается вместе с
  /// сессией и с `dispose()`.
  McpStatusPort? mcpStatus(SessionId id);

  /// Отменяет идущие ходы, дожидается записи журналов и закрывает потоки
  /// событий.
  Future<void> dispose();
}

/// Реализация среды выполнения; создаётся только `buildAgentCore` (HOST-6).
final class AgentRuntimeImpl implements AgentRuntime {
  AgentRuntimeImpl({
    required this.profile,
    required this.services,
    required CoreConfig config,
    required this.registry,
    required StreamFunction stream,
    this.modelsFor,
    this.configCommand = true,
  }) : _applied = _Applied(
         config: config,
         stream: stream,
         catalog: services.models ?? FixedModelCatalog([config.defaultModel]),
         values: services.config?.initial.values ?? const {},
         host: services.config?.initial.host,
         loadedAt: services.clock.now(),
         sources: services.config?.initial.sources ?? const [],
       ) {
    // Подписка принадлежит рантайму и живёт до `dispose()`; сигнал после
    // `dispose()` не приходит (D8, «Конкурентность и поздние события»).
    _configSubscription = services.config?.changes.listen(_onConfigSignal);
  }

  final HostProfile profile;
  final AgentCoreServices services;
  final ToolRegistry registry;

  /// Функция хоста: функция модели и каталог по `CoreConfig` применённого
  /// снимка (D8). `null` — перезагрузки нет. При сборке не вызывается.
  final ConfiguredModels Function(CoreConfig config)? modelsFor;

  /// Объявлять ли встроенную команду `/config` (`false` у `serve --ws`, R0-3).
  /// Потребитель — встроенные команды (задача 7.2); рантайм только хранит
  /// флаг, чтобы сессии объявили команды по нему и по `services.config`.
  final bool configCommand;

  /// Применённый снимок: заменяется целиком одним присваиванием (D8,
  /// «Двойной снимок невозможен»). Шаг, ход или проверка читают его один раз.
  _Applied _applied;

  /// Применённый `CoreConfig` (шов тестов и `forSessionCwd` сессий).
  @visibleForTesting
  CoreConfig get config => _applied.config;

  /// `values` применённого снимка: прежние значения отложенных листьев
  /// (D8, шаг 5). Шов тестов.
  @visibleForTesting
  Map<String, Object?> get appliedValues => _applied.values;

  /// Прежние `HostSettings`: ключи хоста `restartRequired` и до перезапуска не
  /// меняются. Шов тестов; `null` без источника.
  @visibleForTesting
  HostSettings? get appliedHost => _applied.host;

  /// Функция модели применённого снимка.
  StreamFunction get stream => _applied.stream;

  @override
  ModelCatalog get models => _applied.catalog;
  final _sessions = <_Session>[];

  StreamSubscription<void>? _configSubscription;
  var _disposed = false;

  /// Идущая перезагрузка и повтор, поставленный во время неё (шаг 1 D8).
  Future<ConfigApplyReport>? _reloading;
  Completer<ConfigApplyReport>? _repeat;

  /// Ключи, ждущие перезапуска, по последней успешной перезагрузке. Сравнение
  /// идёт с применённым снимком, где отложенные листья остаются прежними,
  /// поэтому множество уже накопительное, а вернувшийся в файле ключ из него
  /// пропадает.
  var _pending = const <String>[];
  DateTime? _lastFailureAt;
  var _lastIssues = const <ConfigIssue>[];

  /// Корни, для которых `config.session.outside_root` уже записан: одна
  /// запись на `cwd` за жизнь рантайма (D9).
  final _outsideRootLogged = <String>{};

  /// Папки, для которых `config.session.project` уже записан: одна запись на
  /// папку за жизнь рантайма, как у [_outsideRootLogged] (D21).
  final _projectLogged = <String>{};

  /// Папки, для которых `config.session.process_keys_ignored` уже записан.
  final _processKeysLogged = <String>{};

  /// Отменяется в [dispose]: подключение MCP-серверов не должно пережить
  /// рантайм (`McpConnectRequest.cancel`).
  final _shutdown = CancelTokenSource();

  SessionStore get _store => services.sessions;

  @override
  Future<AgentSession> createSession(SessionSpec spec) async {
    // Снимок начала: сессия, создаваемая во время замены, получает его
    // целиком (D8, «Создание сессии»).
    final start = _applied;
    // Id и время фиксируются до конфигурации папки: журнал создаётся только
    // после неё (D21, «Журнал — после конфигурации»), а id нужен логам шагов.
    final sessionId = newSessionId(services.clock, services.ids);
    final createdAt = services.clock.now();
    final resolved = await _canonicalCwd(spec.cwd);
    final canonicalCwd = resolved.path;
    final sessionLogger = spec.ports.logger ?? services.logger;
    final scope = await _sessionConfig(
      start,
      sessionId,
      spec.cwd,
      canonicalCwd,
      resolved.resolved,
      sessionLogger,
    );
    final settings = scope.settings;
    final header = SessionHeader(
      id: sessionId,
      cwd: spec.cwd,
      created: createdAt,
      agent: coreAgentInfo,
      metadata: {'profile': profile.name},
    );
    await _store.create(header);
    final model = spec.model != null
        ? _resolve(scope.applied, spec.model!, settings.effort)
        : await _selectModel(scope.applied, settings, header.id, sessionLogger);
    final session = await _open(
      snapshot: SessionSnapshot.empty(header),
      cwd: spec.cwd,
      canonicalCwd: canonicalCwd,
      cwdResolved: resolved.resolved,
      settings: settings,
      mode: spec.mode ?? settings.permissions.mode ?? profile.defaultMode,
      model: model,
      effort: settings.effort,
      ports: spec.ports,
      extraBeforeToolCall: [
        ...spec.extraBeforeToolCall,
        ...spec.ports.extraBeforeToolCall,
      ],
      extraAfterToolCall: [
        ...spec.extraAfterToolCall,
        ...spec.ports.extraAfterToolCall,
      ],
      mcpServers: spec.mcpServers,
      scope: scope,
    );
    try {
      await session._writer.append(
        (id, parent, at) => _modelChange(id, parent, at, model),
      );
    } on Object {
      await _abandon(session);
      rethrow;
    }
    // Явная модель вызывающего — выбор пользователя: запоминается после
    // записи в журнал (D6). Автоматический выбор память не трогает.
    if (spec.model != null) {
      await rememberLastModel(
        services.lastModel,
        model,
        sessionLogger,
        header.id,
      );
    }
    // «Живая» для перезагрузки — возвращённая вызывающему (ACP-8: до ответа
    // `session/new` уведомлений нет).
    session._handedOut = true;
    return session;
  }

  /// Модель новой сессии без `spec.model` (D5): цепочка «явная → последняя →
  /// первый провайдер» через [selectSessionModel]; порт читается только когда
  /// модель конфига неявная. Сбой чтения не ломает сессию: событие
  /// `model.last_used.ignored {reason: <runtimeType>}` (без текста ошибки, в
  /// нём могут быть пути), шаг 3. Итог пишется событием
  /// `session.model.selected` с источником (§16).
  Future<ModelRef> _selectModel(
    _Applied start,
    CoreConfig settings,
    SessionId sessionId,
    Logger logger,
  ) async {
    ModelId? last;
    final port = services.lastModel;
    if (port != null &&
        settings.defaultModelSource != DefaultModelSource.config) {
      try {
        last = await port.read();
      } on Object catch (error) {
        logger.log(
          LogLevel.warning,
          'model.last_used.ignored',
          fields: {
            'session_id': sessionId.value,
            'reason': error.runtimeType.toString(),
          },
        );
      }
    }
    final (picked, source) = selectSessionModel(
      settings,
      last,
      start.catalog,
      effort: settings.effort,
    );
    final model = _resolve(start, picked, settings.effort);
    if (last != null && source != DefaultModelSource.lastUsed) {
      // Память есть, но модели в каталоге сессии нет (провайдер удалён или
      // сессия вне корня запуска): причину видно в логе, содержимого файла
      // состояния в записи нет (§16).
      logger.log(
        LogLevel.info,
        'model.last_used.ignored',
        fields: {'session_id': sessionId.value, 'reason': 'not in catalog'},
      );
    }
    logger.log(
      LogLevel.info,
      'session.model.selected',
      fields: {
        'session_id': sessionId.value,
        'model': '${model.provider}/${model.id}',
        'source': source.wireName,
      },
    );
    return model;
  }

  /// Сессия не вернулась вызывающему: серверы MCP, подключённые в `_open`,
  /// закрываются, иначе их процессы пережили бы неудавшийся `session/new`.
  Future<void> _abandon(_Session session) async {
    _sessions.remove(session);
    try {
      await session._mcp.close();
    } on Object catch (error, stack) {
      session._logger.log(
        LogLevel.warning,
        'mcp.server.failed',
        fields: {
          'session_id': session.id.value,
          'reason': 'closing MCP servers failed: ${error.runtimeType}',
        },
        error: error.runtimeType,
        stack: stack,
      );
    }
  }

  @override
  Future<AgentSession> loadSession(
    SessionId id,
    SessionHostPorts ports, {
    ModelRef? model,
    String? cwd,
    List<McpServerConfig> mcpServers = const [],
  }) async {
    final start = _applied;
    final snapshot = await _store.open(id);
    final restored = buildLlmContext(snapshot);
    final resolved = await _canonicalCwd(cwd ?? snapshot.header.cwd);
    final canonicalCwd = resolved.path;
    final scope = await _sessionConfig(
      start,
      id,
      cwd ?? snapshot.header.cwd,
      canonicalCwd,
      resolved.resolved,
      ports.logger ?? services.logger,
    );
    final settings = scope.settings;
    final effort =
        ReasoningEffort.values
            .where((e) => e.name == restored.config['effort'])
            .firstOrNull ??
        settings.effort;
    // Модель журнала выигрывает, если её знает каталог (D3); иначе —
    // поведение этапа 3: модель конфигурации и новая model_change.
    final journalModel = switch (restored.model) {
      final ModelChangeRecord record => scope.applied.catalog.resolve(
        ModelId('${record.provider}/${record.modelId}'),
        effort: effort,
      ),
      null => null,
    };
    final chosen = model != null
        ? _resolve(scope.applied, model, effort)
        : journalModel ??
              _resolve(scope.applied, settings.defaultModel, effort);
    final header = snapshot.header.cwd;
    final session = await _open(
      snapshot: snapshot,
      cwd: cwd ?? header,
      canonicalCwd: canonicalCwd,
      cwdResolved: resolved.resolved,
      settings: settings,
      mode:
          ModeId.values.where((m) => m.value == restored.modeId).firstOrNull ??
          settings.permissions.mode ??
          profile.defaultMode,
      model: chosen,
      effort: effort,
      ports: ports,
      extraBeforeToolCall: ports.extraBeforeToolCall,
      extraAfterToolCall: ports.extraAfterToolCall,
      mcpServers: mcpServers,
      scope: scope,
    );
    try {
      await session._heal();
      if (restored.model case final journal?
          when journal.provider != chosen.provider ||
              journal.modelId != chosen.id) {
        session._logger.log(
          LogLevel.warning,
          'session.model.not_restored',
          fields: {
            'session_id': id.value,
            'journal': '${journal.provider}/${journal.modelId}',
            'model': '${chosen.provider}/${chosen.id}',
          },
        );
        await session._writer.append(
          (id, parent, at) => _modelChange(id, parent, at, chosen),
        );
      }
      // Явная модель вызывающего запоминается после `model_change` (как у
      // `setModel`, D6); восстановленная из журнала и модель конфигурации —
      // нет.
      if (model != null) {
        await rememberLastModel(
          services.lastModel,
          chosen,
          session._logger,
          id,
        );
      }
      session._restoreHistory();
      final base = _agentBaseOf(snapshot, scope.applied.catalog);
      await session._restoreAgent(
        restored.config['agent'],
        baseMode: base.mode ?? settings.permissions.mode ?? profile.defaultMode,
        baseModel:
            base.model ??
            _resolve(scope.applied, settings.defaultModel, effort),
      );
      if (cwd != null && cwd != header) {
        await session._writer.append(
          (id, parent, at) => CustomRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            customType: 'codelab.cwd_changed',
            data: {'from': header, 'to': cwd},
          ),
        );
      }
    } on Object {
      await _abandon(session);
      rethrow;
    }
    session._handedOut = true;
    return session;
  }

  /// База агента из журнала: режим и модель до записи, которая перевела
  /// сессию из `default` в агента (D11). Поля `null` — записей не было, и
  /// вызывающий берёт значения конфигурации сессии.
  ({ModeId? mode, ModelRef? model}) _agentBaseOf(
    SessionSnapshot snapshot,
    ModelCatalog catalog,
  ) {
    ModeId? mode;
    ModelRef? model;
    ({ModeId? mode, ModelRef? model}) base = (mode: null, model: null);
    String current = defaultAgentName;
    for (final record in pathToLeaf(snapshot)) {
      switch (record) {
        case ModeChangeRecord(:final modeId):
          mode = ModeId.values.where((m) => m.value == modeId).firstOrNull;
        case ModelChangeRecord(:final provider, modelId: final id):
          model = catalog.resolve(ModelId('$provider/$id'));
        case ConfigChangeRecord(optionId: 'agent', :final value):
          if (current == defaultAgentName && value != defaultAgentName) {
            base = (mode: mode, model: model);
          }
          current = value;
        default:
          break;
      }
    }
    return base;
  }

  /// Конфигурация сессии: снимок корня, снимок без проекта или конфигурация
  /// её папки (design.md change `add-agent-configuration`, D9; `require-
  /// project-folder`, D21; agent-runtime «Конфигурация сессии вне корня
  /// запуска»).
  ///
  /// Почему: проектные слои 3–4 прочитаны для корня запуска хоста. Сессия в
  /// другом каталоге (`session/new` с иным `cwd`, подкаталог со своим
  /// `.codelab/`) не должна получать MCP-серверы и правила `allow` чужого
  /// проекта (приоритет 1 — безопасность). Без порта [ProjectConfigLoader]
  /// она берёт снимок без проектных слоёв; с портом — полный `CoreConfig`
  /// своей папки, каталог и функцию модели (тройка сессии), которые держит до
  /// закрытия. Ключи сборки (capability, профиль) остаются общими: они уже
  /// вошли в [services] и [profile].
  ///
  /// `cwd` перед сравнением канонизируется ([_canonicalCwd]): корень проекта в
  /// конфигурации уже канонический, и сессия, открытая по symlink на проект,
  /// иначе получила бы снимок без проекта и потеряла бы его `permissions.deny`
  /// (приоритет 1).
  Future<_SessionScope> _sessionConfig(
    _Applied start,
    SessionId id,
    String cwd,
    String canonical,
    bool canonicalResolved,
    Logger logger,
  ) async {
    final config = start.config;
    final port = services.projectConfig;
    final root = config.projectRoot;
    if (port != null && root != null && !samePath(canonical, root)) {
      return _projectScope(
        start,
        port,
        id,
        cwd,
        canonical,
        canonicalResolved,
        logger,
      );
    }
    final settings = config.forSessionCwd(canonical);
    if (!identical(settings, config) &&
        _outsideRootLogged.add(pathComponents(cwd).join('/'))) {
      logger.log(
        LogLevel.info,
        'config.session.outside_root',
        fields: {
          'session_id': id.value,
          'cwd': cwd,
          'config_root': config.projectRoot,
        },
      );
    }
    return _SessionScope(settings: settings, applied: start);
  }

  /// Тройка сессии папки, отличной от корня запуска (D21): `loadForProject`,
  /// `validateSnapshot`, `modelsFor` — по порядку, без кэша.
  ///
  /// Любая проблема — [ProjectConfigException] (fail closed): ни снимок корня,
  /// ни снимок без проекта не подставляются, потому что сессия без запретов
  /// своего проекта слабее, чем ждёт пользователь (приоритет 1). Остановка
  /// рантайма прерывает ожидание загрузки: сессия не создаётся, MCP не
  /// стартует.
  Future<_SessionScope> _projectScope(
    _Applied start,
    ProjectConfigLoader port,
    SessionId id,
    String cwd,
    String canonical,
    bool canonicalResolved,
    Logger logger,
  ) async {
    final ConfigLoadResult result;
    try {
      final load = port.loadForProject(canonical);
      // Порядок завершений задаёт хост: остановка не ждёт зависшую загрузку.
      final raced = await Future.any<ConfigLoadResult?>([
        load,
        _shutdown.token.onCancel.then((_) => null),
      ]);
      if (raced == null) {
        // Загрузка, завершившаяся после остановки, не теряется молча (§12):
        // класс ошибки — в `debug`, без текста (в нём могут быть пути).
        unawaited(
          load.then<void>(
            (_) {},
            onError: (Object error) {
              logger.log(
                LogLevel.debug,
                'config.session.project_load_after_shutdown',
                fields: {'error_class': error.runtimeType.toString()},
              );
            },
          ),
        );
        throw const CancelledException(ShutdownCancel());
      }
      result = raced;
    } on CancelledException {
      rethrow;
    } on Object catch (error) {
      // Текст исключения мог бы нести пути или значения: наружу — только класс.
      throw _refuseProject(canonical, logger, [
        ConfigIssue(
          kind: ConfigIssueKind.semantic,
          key: '',
          source: 'project config',
          message:
              'the project config could not be loaded (${error.runtimeType})',
        ),
      ]);
    }
    if (_disposed) {
      throw const CancelledException(ShutdownCancel());
    }
    final config = result.config;
    if (config == null || result.issues.isNotEmpty) {
      throw _refuseProject(
        canonical,
        logger,
        result.issues.isNotEmpty
            ? result.issues
            : [
                ConfigIssue(
                  kind: ConfigIssueKind.semantic,
                  key: '',
                  source: 'project config',
                  message: 'the config source returned no config',
                ),
              ],
      );
    }
    final recheck = config.validateSnapshot();
    if (recheck.isNotEmpty) {
      throw _refuseProject(canonical, logger, recheck);
    }
    final build = modelsFor;
    if (build == null) {
      throw StateError(
        'the runtime has a ProjectConfigLoader but no modelsFor',
      );
    }
    final ConfiguredModels models;
    try {
      models = build(config);
    } on Object catch (error) {
      throw _refuseProject(canonical, logger, [
        ConfigIssue(
          kind: ConfigIssueKind.semantic,
          key: '',
          source: 'project config',
          message:
              'the model catalog could not be built (${error.runtimeType})',
        ),
      ]);
    }
    final folder = pathComponents(canonical).join('/');
    if (_projectLogged.add(folder)) {
      logger.log(
        LogLevel.info,
        'config.session.project',
        fields: {
          'session_id': id.value,
          'cwd': cwd,
          'config_root': start.config.projectRoot,
          'trusted':
              canonicalResolved &&
              config.trustedProjects.any((r) => samePath(r, canonical)),
        },
      );
    }
    // Ключи процесса из слоёв папки не применяются (таблица D21): сравниваются
    // только ключи, которые папка задаёт иначе, чем применённый снимок.
    final ignored = _ignoredProcessKeys(start.values, result.values);
    if (ignored.isNotEmpty && _processKeysLogged.add(folder)) {
      logger.log(
        LogLevel.warning,
        'config.session.process_keys_ignored',
        fields: {'session_id': id.value, 'keys': ignored},
      );
    }
    return _SessionScope(
      settings: config,
      applied: _Applied(
        config: config,
        stream: models.stream,
        catalog: models.catalog,
        values: result.values,
        host: start.host,
        loadedAt: services.clock.now(),
        sources: result.sources,
      ),
      isolated: true,
    );
  }

  /// Ключи процесса (`HostSettings`, `exec.*`, `compaction.enabled`,
  /// `trusted_projects`), которые [folder] задаёт иначе, чем [applied]; только
  /// имена, без значений (§16).
  static List<String> _ignoredProcessKeys(
    Map<String, Object?> applied,
    Map<String, Object?> folder,
  ) {
    const sections = [
      'secrets',
      'sessions',
      'logging',
      'config',
      'profile',
      'exec',
      'trusted_projects',
      'compaction.enabled',
    ];
    bool isProcessKey(String key) => sections.any(
      (s) => key == s || key.startsWith('$s.') || key.startsWith('$s['),
    );
    const equality = DeepCollectionEquality();
    return [
      for (final entry in folder.entries)
        if (isProcessKey(entry.key) &&
            !equality.equals(applied[entry.key], entry.value))
          entry.key,
    ]..sort();
  }

  /// Отказ по конфигурации папки: лог `config.session.project_invalid` (только
  /// источник, позиция, ключ и класс проблемы, без текстов и значений, §16) и
  /// исключение для вызывающего.
  ProjectConfigException _refuseProject(
    String canonical,
    Logger logger,
    List<ConfigIssue> issues,
  ) {
    logger.log(
      LogLevel.error,
      'config.session.project_invalid',
      fields: {
        'cwd': canonical,
        'issues': [
          for (final issue in issues)
            {
              'source': issue.source,
              'line': issue.line,
              'column': issue.column,
              'key': issue.key,
              'kind': issue.kind.name,
            },
        ],
      },
    );
    return ProjectConfigException(
      cwd: canonical,
      issues: List.unmodifiable(issues),
    );
  }

  /// Канонический `cwd` сессии: `realpath` необязательного `PathResolver`
  /// базового окружения (design.md change `add-agent-configuration`, D9;
  /// `add-agent-project-files`, D4).
  ///
  /// Один результат служит и выбору снимка конфигурации, и сравнению с
  /// `trustedProjects`, и запросу порту файлов проекта: сессия по symlink на
  /// доверенный корень не должна терять доверие, а symlink на чужой каталог —
  /// получать его (приоритет 1). IO остаётся в порте: ядро путь сам не
  /// раскрывает. Путь не раскрылся (нет файла, нет `PathResolver`) —
  /// `resolved: false`: для снимка конфигурации путь берётся как есть, но
  /// доверия проекту он не даёт (fail closed): лексическое `..` или symlink,
  /// не раскрытые резолвером, не должны совпасть с доверенным корнем.
  Future<({String path, bool resolved})> _canonicalCwd(String cwd) async {
    if (services.baseEnv case final PathResolver resolver) {
      if (await resolver.realpath(cwd) case Ok(:final value)) {
        return (path: value, resolved: true);
      }
    }
    return (path: cwd, resolved: false);
  }

  /// Ссылка каталога с уровнем рассуждения сессии; модели нет в каталоге —
  /// ссылка как есть, но тоже с уровнем только при рассуждении (§2.12.3).
  ModelRef _resolve(_Applied from, ModelRef model, ReasoningEffort effort) =>
      from.catalog.resolve(
        ModelId('${model.provider}/${model.id}'),
        effort: effort,
      ) ??
      _withEffort(model, model.supportsReasoning ? effort : null);

  @override
  Future<SessionPage> listSessions({
    String? cwd,
    String? cursor,
    int pageSize = 50,
  }) => _store.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> dispose() async {
    // Сначала отказ от сигналов и отбрасывание идущей перезагрузки: её
    // результат после `dispose()` не применяется (D8, шаг 2).
    _disposed = true;
    await _configSubscription?.cancel();
    _configSubscription = null;
    if (_repeat case final repeat? when !repeat.isCompleted) {
      repeat.complete(_discarded());
    }
    _repeat = null;
    _shutdown.cancel(const ShutdownCancel());
    for (final session in _sessions) {
      await session.close();
    }
    _sessions.clear();
  }

  // ---- перезагрузка конфигурации (design.md change
  // `add-config-writer-and-reload`, D8, D14; CFG-15, CFG-16) -----------------

  ConfigSource _requireSource() =>
      services.config ?? (throw StateError('the runtime has no ConfigSource'));

  /// Итог перезагрузки, результат которой отброшен из-за `dispose()`.
  ConfigApplyReport _discarded() =>
      ConfigApplyReport(outcome: ConfigReloadOutcome.unchanged);

  /// Сигнал `ConfigSource.changes`: ошибка перезагрузки не должна уйти в зону
  /// хоста (AGENTS.md §12). `reloadConfig` не бросает, а эта защита в глубину
  /// пишет `config.reload.failed` с `error_class`, если что-то всё же бросило.
  void _onConfigSignal(void _) {
    unawaited(
      reloadConfig().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          services.logger.log(
            LogLevel.error,
            'config.reload.failed',
            fields: {'error_class': error.runtimeType.toString()},
            error: error.runtimeType,
            stack: stack,
          );
        },
      ),
    );
  }

  @override
  Future<ConfigApplyReport> reloadConfig() {
    final source = _requireSource();
    if (_disposed) {
      return Future.value(_discarded());
    }
    // Шаг 1 (коалесценция): во время идущей перезагрузки ставится не больше
    // одного повтора, и все такие вызовы получают его итог — он видит
    // последние файлы.
    if (_reloading != null) {
      return (_repeat ??= Completer<ConfigApplyReport>()).future;
    }
    return _startReload(source);
  }

  Future<ConfigApplyReport> _startReload(ConfigSource source) {
    final run = _reloadOnce(source);
    _reloading = run;
    // `run` не завершается ошибкой: исключения превращены в итог `failed`.
    unawaited(
      run.whenComplete(() {
        _reloading = null;
        final repeat = _repeat;
        _repeat = null;
        if (repeat == null || repeat.isCompleted) {
          return;
        }
        repeat.complete(_disposed ? _discarded() : _startReload(source));
      }),
    );
    return run;
  }

  Future<ConfigApplyReport> _reloadOnce(ConfigSource source) async {
    final ConfigLoadResult result;
    try {
      result = await source.load();
    } on Object catch (error, stack) {
      return _failedByException(error, stack);
    }
    // Шаг 2: после `dispose()` результат отбрасывается; дальше до замены
    // снимка нет ни одного `await` (D8, «Двойной снимок невозможен»).
    if (_disposed) {
      return _discarded();
    }
    final ConfigApplyReport report;
    // Замены серверов конфига живых сессий (шаг 7а), начатые этим снимком.
    final applies = <Future<void>>[];
    try {
      report = _applyLoaded(result, applies);
    } on Object catch (error, stack) {
      return _failedByException(error, stack);
    }
    // Шаг 7а: серверы конфига живых сессий (D10). Ожидание — после замены
    // снимка, поэтому «двойного снимка» нет; сбой замены не меняет итог
    // (`_applyMcpServers` не бросает).
    if (applies.isNotEmpty) {
      await Future.wait(applies);
    }
    return report;
  }

  ConfigApplyReport _applyLoaded(
    ConfigLoadResult result,
    List<Future<void>> applies,
  ) {
    final loaded = result.config;
    // Шаг 3: невалидный конфиг — прежний снимок цел, клиентам ничего (CFG-15).
    if (loaded == null || result.issues.isNotEmpty) {
      return _failedByIssues(
        result.issues.isNotEmpty
            ? result.issues
            : [
                ConfigIssue(
                  kind: ConfigIssueKind.semantic,
                  key: '',
                  source: 'config reload',
                  message: 'the config source returned no config',
                ),
              ],
        result.sources,
      );
    }
    final previous = _applied;
    // Шаги 4–5: ключи diff, отложенные ключи, прежние значения отложенных.
    final plan = planConfigReload(
      previousValues: previous.values,
      previous: previous.config,
      nextValues: result.values,
      next: loaded,
    );
    // План покрывает оба снимка: полный и без проекта (R0-1); применяется
    // он целиком или не применяется вовсе.
    final merged = CoreConfig.withDeferred(
      previous.config,
      loaded,
      plan.deferred,
      withoutProjectValues: plan.appliedWithoutProjectValues,
    );
    final recheck = merged.validateSnapshot();
    if (recheck.isNotEmpty) {
      return _failedByIssues(recheck, result.sources);
    }
    // Шаг 6: пересборка функции модели и сброс кэша секретов — при каждой
    // успешной загрузке, даже без изменённых ключей: значение в хранилище или
    // переменная могли смениться, а цепочки провайдеров держат ключ. Сброс
    // идёт после сборки: если `modelsFor` бросил, снимок прежний, и кэш его
    // секретов не сбрасывается. Сборка ключ не читает
    // (`createConfiguredStreamFunction` разрешает лениво); если начнёт —
    // сброс нужно вернуть до сборки.
    final build =
        modelsFor ??
        (throw StateError('the runtime has a ConfigSource but no modelsFor'));
    final models = build(merged);
    services.secrets?.invalidate();
    // Одна атомарная замена записи: снимок, значения, функция модели и
    // каталог. `HostSettings` не меняются до перезапуска (D8, шаг 5).
    final next = _Applied(
      config: merged,
      stream: models.stream,
      catalog: models.catalog,
      values: plan.appliedValues,
      host: previous.host,
      loadedAt: services.clock.now(),
      sources: result.sources,
    );
    _applied = next;
    _pending = plan.restartRequiredKeys;
    _lastIssues = const [];
    // Шаг 7: серверы конфига живых сессий применяет шаг 7а (задача 6.4, через
    // `replaceServers` и очередь сессии); здесь — модель и опции (7б).
    _notifySessions(previous, next);
    if (!plan.isEmpty) {
      applies.addAll([
        for (final session in [..._sessions])
          if (session._handedOut && !session._closed && !session._isolated)
            session._applyConfigMcp(),
      ]);
    }
    if (plan.restartRequiredKeys.isNotEmpty) {
      services.logger.log(
        LogLevel.warning,
        'config.reload.restart_required',
        fields: {'keys': plan.restartRequiredKeys},
      );
    }
    if (plan.isEmpty) {
      services.logger.log(LogLevel.debug, 'config.reload.noop');
      return ConfigApplyReport(outcome: ConfigReloadOutcome.unchanged);
    }
    services.logger.log(
      LogLevel.info,
      'config.reload.applied',
      fields: {
        'keys': plan.changedKeys,
        'restart_required': plan.restartRequiredKeys,
      },
    );
    return ConfigApplyReport(
      outcome: ConfigReloadOutcome.applied,
      changedKeys: plan.changedKeys,
      restartRequiredKeys: plan.restartRequiredKeys,
    );
  }

  /// Шаг 7: живые сессии — возвращённые вызывающему и не закрытые. Сессия,
  /// чья модель исчезла из каталога, закрепляется за прежней функцией модели;
  /// изменившийся список моделей даёт `ModelOptionsChanged`.
  void _notifySessions(_Applied before, _Applied after) {
    final listChanged = !const ListEquality<String>().equals(
      [for (final m in before.catalog.models) m.id.value],
      [for (final m in after.catalog.models) m.id.value],
    );
    for (final session in [..._sessions]) {
      // Сессия папки с портом держит снимок открытия до закрытия (D21, Q19).
      if (!session._handedOut || session._closed || session._isolated) {
        continue;
      }
      session._afterCatalogReplaced(before, after);
      if (listChanged) {
        session._publishFromRuntime(ModelOptionsChanged(session.id));
      }
    }
  }

  ConfigApplyReport _failedByIssues(
    List<ConfigIssue> issues,
    List<String> sources,
  ) {
    _lastFailureAt = services.clock.now();
    _lastIssues = List.unmodifiable(issues);
    // Только источник, позиция, путь и класс проблемы: значения ключей в лог не
    // попадают (CFG-2, D14).
    services.logger.log(
      LogLevel.error,
      'config.reload.failed',
      fields: {
        'sources': sources,
        'issues': [
          for (final issue in issues)
            {
              'source': issue.source,
              'line': issue.line,
              'column': issue.column,
              'key': issue.key,
              'kind': issue.kind.name,
            },
        ],
      },
    );
    return ConfigApplyReport(
      outcome: ConfigReloadOutcome.failed,
      issues: issues,
    );
  }

  ConfigApplyReport _failedByException(Object error, StackTrace stack) {
    if (_disposed) {
      return _discarded();
    }
    final issue = ConfigIssue(
      kind: ConfigIssueKind.semantic,
      key: '',
      source: 'config reload',
      message: 'the config could not be reloaded (${error.runtimeType})',
    );
    _lastFailureAt = services.clock.now();
    _lastIssues = [issue];
    // Текст исключения мог бы содержать значение: в лог идёт только класс.
    services.logger.log(
      LogLevel.error,
      'config.reload.failed',
      fields: {'error_class': error.runtimeType.toString()},
      error: error.runtimeType,
      stack: stack,
    );
    return ConfigApplyReport(
      outcome: ConfigReloadOutcome.failed,
      issues: [issue],
    );
  }

  @override
  Future<ConfigLoadResult> checkConfig() async {
    final source = _requireSource();
    // Проверка не сдвигает базу наблюдателя: иначе правка, ждущая debounce,
    // перестала бы давать сигнал и не применилась бы (D7, D8).
    final result = await source.load(rebase: false);
    final config = result.config;
    if (config == null || result.issues.isNotEmpty) {
      return result;
    }
    final plan = planConfigReload(
      previousValues: _applied.values,
      previous: _applied.config,
      nextValues: result.values,
      next: config,
    );
    // То, что отклонила бы перезагрузка (`failed`), `check` не выдаёт за
    // «valid»: тот же пересчёт снимка с отложенными частями и его проверка.
    final recheck = CoreConfig.withDeferred(
      _applied.config,
      config,
      plan.deferred,
    ).validateSnapshot();
    if (recheck.isNotEmpty) {
      return ConfigLoadResult(
        warnings: result.warnings,
        issues: recheck,
        sources: result.sources,
      );
    }
    if (plan.restartRequiredKeys.isEmpty) {
      return result;
    }
    // Отложенные ключи — предупреждения результата: команда `/config check`
    // печатает их строкой `Restart required` (D8, шаг 5).
    return ConfigLoadResult(
      config: result.config,
      host: result.host,
      issues: result.issues,
      warnings: [
        ...result.warnings,
        for (final key in plan.restartRequiredKeys)
          ConfigIssue(
            kind: ConfigIssueKind.semantic,
            key: key,
            source: 'config reload',
            message: 'applies only after a restart',
            event: 'config.reload.restart_required',
            fields: {'key': key},
          ),
      ],
      sources: result.sources,
      values: result.values,
    );
  }

  @override
  McpStatusPort? mcpStatus(SessionId id) {
    for (final session in _sessions) {
      if (session.id == id && !session._closed) {
        return session._mcpStatus;
      }
    }
    return null;
  }

  @override
  ConfigStatus configStatus() => ConfigStatus(
    loadedAt: _applied.loadedAt,
    sources: _applied.sources,
    lastFailureAt: _lastFailureAt,
    lastIssues: _lastIssues,
    pendingRestartKeys: _pending,
  );

  static ModelChangeRecord _modelChange(
    String id,
    String? parent,
    DateTime at,
    ModelRef model,
  ) => ModelChangeRecord(
    id: id,
    parentId: parent,
    timestamp: at,
    provider: model.provider,
    modelId: model.id,
    baseUrl: model.baseUrl.toString(),
  );

  /// Общая сборка новой и загруженной сессии: env, политика, агент,
  /// писатель журнала.
  Future<_Session> _open({
    required SessionSnapshot snapshot,
    required String cwd,
    required String canonicalCwd,
    required bool cwdResolved,
    required CoreConfig settings,
    required ModeId mode,
    required ModelRef model,
    required ReasoningEffort effort,
    required SessionHostPorts ports,
    List<BeforeToolCallHook> extraBeforeToolCall = const [],
    List<AfterToolCallHook> extraAfterToolCall = const [],
    List<McpServerConfig> mcpServers = const [],
    required _SessionScope scope,
  }) async {
    final id = snapshot.header.id;
    final catalog = scope.applied.catalog;
    final logger = ports.logger ?? services.logger;
    // Конфигурация сессии на момент обращения: у сессии папки — её собственная,
    // у остальных — по применённому снимку корня (после перезагрузки новая).
    CoreConfig settingsOf() => scope.isolated
        ? scope.applied.config
        : _applied.config.forSessionCwd(canonicalCwd);
    // Реестр сессии: копия базового плюс MCP-инструменты её серверов, чужие
    // сессии их не видят (design.md change `add-agent-mcp-client`, D6).
    final sessionRegistry = ToolRegistry();
    for (final tool in registry.tools) {
      sessionRegistry.register(tool);
    }
    final mcp = _McpState(
      baseNames: {for (final tool in registry.tools) tool.name},
      // Токен сессии: `close()` отменяет подключение серверов, не дожидаясь
      // `connectTimeout`; отмена рантайма доходит через родителя.
      cancel: CancelTokenSource(parent: _shutdown.token),
    );
    // Файлы проекта читаются до подключения MCP: отменённая загрузка не
    // оставляет за собой процессов серверов (D6).
    // Фаза навыков идёт параллельно (design.md change `add-agent-skills`,
    // D1, D16): у каждой свой таймер и свой дочерний токен, медленный корень
    // навыков не отнимает у сессии `AGENTS.md`.
    final loaded = await Future.wait<Object>([
      _loadProjectFiles(
        id: id,
        canonicalCwd: canonicalCwd,
        cwdResolved: cwdResolved,
        settings: settings,
        logger: logger,
        cancel: mcp.cancel.token,
        catalog: catalog,
      ),
      _loadSkills(
        id: id,
        canonicalCwd: canonicalCwd,
        cwdResolved: cwdResolved,
        settings: settings,
        logger: logger,
        cancel: mcp.cancel.token,
      ),
    ]);
    final project = loaded[0] as _ProjectLoad;
    final skillsLoad = loaded[1] as _SkillsLoad;
    final skills = skillsLoad.catalog;
    final projectContext = project.context;
    // Граница env строится после фаз загрузки: корни только для чтения —
    // каталоги загруженных навыков вне рабочей папки (D5, D17). Фазы env
    // сессии не используют. `execInReadOnlyRoots`: `ports.env == null` —
    // сессия исполняет на `baseEnv` хоста, то есть на машине агента; клиентский
    // env — только если хост явно сказал `execOnHost`.
    final hostFiles = services.hostFiles;
    final readOnlyRoots = hostFiles == null
        ? const <String>[]
        : skills.readOnlyRoots(canonicalCwd);
    final execOnHost =
        hostFiles != null && (ports.env == null || ports.execOnHost);
    final env = await BoundedEnv.wrap(
      ports.env ?? services.baseEnv,
      cwd,
      readOnlyRoots: readOnlyRoots,
      readOnlyFs: hostFiles,
      execInReadOnlyRoots: execOnHost,
    );
    // Сессия создаётся после агента, а аварийное сжатие — её метод; инструмент
    // `skill` тоже читает журнал сессии лениво, при вызове (D18).
    late final _Session session;
    // Инструменты сессии, зависящие от снимка (D17). `register` заменяет
    // одноимённый инструмент на месте, порядок схем (кэш промпта) прежний;
    // инструмент хоста другого типа с тем же именем не заменяется.
    if (skills.modelVisible.isNotEmpty) {
      // Повтор активации: функция читает журнал сессии на момент вызова (D18).
      sessionRegistry.register(
        SkillTool(
          skills,
          sessionId: id,
          activeSkills: () => session._activeSkills(),
        ),
      );
    }
    if (skills.skills.isNotEmpty &&
        sessionRegistry.lookup('read') is ReadTool) {
      sessionRegistry.register(ReadTool(skills: skills, root: canonicalCwd));
    }
    if (readOnlyRoots.isNotEmpty &&
        sessionRegistry.lookup('exec') is ExecTool) {
      sessionRegistry.register(
        ExecTool(readOnlyRoots: readOnlyRoots, execInReadOnlyRoots: execOnHost),
      );
    }
    await _connectMcp(
      id: id,
      cwd: cwd,
      settings: settings,
      servers: mcpServers,
      logger: logger,
      registry: sessionRegistry,
      state: mcp,
    );
    // Отмена во время подключения (`dispose()`, закрытие сессии): коннектор
    // вернулся, не дожидаясь зависшего раскрытия секретов, но серверы,
    // подключившиеся раньше, уже в `mcp`. Сессию с ними не выдаём — иначе она
    // попала бы в `_sessions` после `dispose()` (agent-runtime «Закрытие
    // во время раскрытия секретов»).
    if (_disposed || mcp.cancel.token.isCancelled) {
      await mcp.close();
      mcp.cancel.token.throwIfCancelled();
      throw const CancelledException(ShutdownCancel());
    }
    final tools = ToolServices(clock: services.clock, logger: logger);
    final gate = profile.isOn(HostCapability.interactiveApproval)
        ? ports.gate ?? services.gate
        : null;
    final policy = PermissionPolicy(
      mode: mode,
      modeOverride: settings.permissions.modeOverride,
      gate: gate,
      rules: settings.permissions.rules,
      extraDeniedTiers: settings.permissions.extraDeniedTiers,
      logger: logger,
      // Пути PERM-11 от хоста пересчитываются через резолвер хоста (D8):
      // через `BoundedEnv` сессии защищаемые пути вне корня не раскрыть.
      // Пути сессии (PERM-11, Q27): корни навыков, зависящие от `cwd`, и
      // каталоги снимка для E1–E3; поле хоста при этом не меняется.
      agentConfigPaths: _sessionConfigPaths(skillsLoad),
      // Резолвер — окружение сессии, если оно само `PathResolver`, иначе
      // `baseEnv` хоста. Окружение сессии `serve` клиентское
      // (`AcpClientExecutionEnv`, `ListingOverlayEnv`) и `PathResolver` не
      // реализует; без второй ветки PERM-11 терял канонизацию и второй проход
      // exec (ревью итерации 5).
      pathResolver: switch ((ports.env, services.baseEnv)) {
        (final PathResolver resolver, _) => resolver,
        (_, final PathResolver resolver) => resolver,
        _ => null,
      },
    );
    final compaction = profile.isOn(HostCapability.compaction);
    final agent = Agent(
      config: AgentLoopConfig(
        sessionId: id,
        model: model,
        // Функция модели читается в начале каждого шага из применённого
        // снимка (или закреплённая за сессией, чья модель исчезла из каталога):
        // перезагрузка действует «со следующего шага» (CFG-16, D8).
        stream: (ref, context, {cancel}) =>
            session._streamNow(ref, context, cancel: cancel),
        executor: ToolCallExecutor(
          registry: sessionRegistry,
          env: env,
          services: tools,
          // Вызов инструмента вне набора агента (CFG-7, D11): текст ошибки
          // строит сессия, она знает выбранного агента.
          unavailableText: (name) => session._unavailableText(name),
        ),
        clock: services.clock,
        ids: services.ids,
        budget: settings.budget,
        beforeToolCall: [
          policy.asHook(sessionRegistry.lookup),
          ...extraBeforeToolCall,
        ],
        afterToolCall: extraAfterToolCall,
        // Смена модели или усилия посреди хода действует со следующего шага
        // (§13.6): идущий запрос не прерывается.
        prepareNextStep: (_) async => session._takeStepUpdate(),
        approvalWait: tools.approvalWait,
        logger: logger,
        // Без capability compaction — поведение этапа 2: размер не
        // проверяется, overflow — обычная ошибка шага.
        estimateTokens: compaction ? estimateLlmContext : null,
        emergencyCompact: compaction
            ? (cause, cancel) => session._emergency(cause, cancel)
            : null,
        contextWindowCap: settings.compaction.contextWindowCap,
      ),
      systemPrompt: _systemPrompt(
        cwd,
        mode,
        sessionRegistry,
        mcp,
        projectContext,
        skills: skills,
        skillsCatalogMaxChars: settings.skills.catalogMaxChars,
      ),
      tools: sessionRegistry.tools,
    );
    // План эмитится через очередь агента: PlanUpdated приходит подписчикам
    // между ToolCallStarted и ToolCallFinished своего вызова (design.md
    // этапа 2, D5).
    tools.plan.publish = (entries) =>
        agent.emit(PlanUpdated(id, entries: entries));
    session = _Session(
      id: id,
      cwd: cwd,
      mode: mode,
      model: model,
      effort: effort,
      canonicalCwd: canonicalCwd,
      // Сессия папки с портом держит собственную тройку, остальные читают
      // применённый снимок при каждом обращении (D8; D21).
      isolated: scope.isolated,
      catalogOf: scope.isolated
          ? () => scope.applied.catalog
          : () => _applied.catalog,
      streamOf: scope.isolated
          ? () => scope.applied.stream
          : () => _applied.stream,
      settingsOf: settingsOf,
      agent: agent,
      policy: policy,
      tools: tools,
      env: env,
      registry: sessionRegistry,
      mcp: mcp,
      clientMcp: mcpServers,
      // Встроенные команды (D12): `config` — только с источником конфига и
      // `configCommand` (R0-3), `mcp` — с capability профиля.
      reloadConfig: services.config != null && configCommand
          ? reloadConfig
          : null,
      checkConfig: checkConfig,
      // `/status` показывает конфигурацию только там, где объявлена `/config`
      // (R0-3, D7 change `add-agent-builtin-slash-commands`).
      configStatus: services.config != null && configCommand
          ? configStatus
          : null,
      mcpCommand: profile.isOn(HostCapability.mcp),
      // Снимок на момент применения, а не на момент создания сессии: после
      // перезагрузки конфига сервера конфига берутся из нового снимка (D10).
      replaceMcp: (servers) => _replaceMcp(
        id: id,
        cwd: cwd,
        settings: settingsOf(),
        servers: servers,
        logger: logger,
        registry: sessionRegistry,
        state: mcp,
      ),
      services: services,
      logger: logger,
      compose: (cwd, mode, agent) => _systemPrompt(
        cwd,
        mode,
        sessionRegistry,
        mcp,
        projectContext,
        agent: agent,
        skills: skills,
        skillsCatalogMaxChars: settings.skills.catalogMaxChars,
      ),
      snapshot: snapshot,
      compactionOn: compaction,
      compaction: compaction ? settings.compaction : null,
      templates: project.templates,
      agents: project.agents,
      skills: skills,
      modeFloor: settings.permissions.mode ?? profile.defaultMode,
    );
    _sessions.add(session);
    return session;
  }

  static ModelRef _withEffort(ModelRef model, ReasoningEffort? effort) =>
      ModelRef(
        provider: model.provider,
        id: model.id,
        api: model.api,
        baseUrl: model.baseUrl,
        contextWindow: model.contextWindow,
        maxOutputTokens: model.maxOutputTokens,
        cost: model.cost,
        supportsImages: model.supportsImages,
        supportsReasoning: model.supportsReasoning,
        reasoningEffort: effort,
        hiddenReasoning: model.hiddenReasoning,
        thinkingMode: model.thinkingMode,
        supportsTools: model.supportsTools,
      );

  /// Системный промпт сессии (§11.5): собирается при создании и загрузке
  /// сессии и при смене режима; дата — по часам хоста.
  String _systemPrompt(
    String cwd,
    ModeId mode,
    ToolRegistry sessionRegistry,
    _McpState mcp,
    ProjectContext? projectContext, {
    AgentDefinition? agent,
    SkillCatalog? skills,
    int skillsCatalogMaxChars = defaultSkillsCatalogMaxChars,
  }) {
    // Инструменты вне набора агента не входят в промпт: секции инструментов
    // и строки MCP-серверов описывают то, что модель реально видит (PR-6,
    // D11).
    final visible = [
      for (final tool in sessionRegistry.tools)
        if (agent?.allowsTool(tool.name) ?? true) tool.name,
    ];
    return composeSystemPrompt(
      PromptInputs(
        cwd: cwd,
        platform: services.platform,
        today: services.clock.now(),
        mode: mode,
        profile: profile,
        toolNames: visible.toSet(),
        mcpServers: agent?.tools == null
            ? mcp.summaries
            : [
                for (final server in mcp.summaries)
                  McpServerSummary(
                    name: server.name,
                    toolCount: visible
                        .where(
                          (n) => n.startsWith(mcpServerPrefix(server.name)),
                        )
                        .length,
                  ),
              ],
        projectContext: projectContext,
        agentProfile: agent == null
            ? null
            : (name: agent.name, body: agent.prompt),
        skills: skills?.modelVisible ?? const [],
        skillsCatalogMaxChars: skillsCatalogMaxChars,
      ),
    );
  }

  /// Общая ограниченная фаза открытия сессии (файлы проекта, навыки):
  /// гонка «ответ порта / отмена сессии / таймаут» на одном `Completer`, чтобы
  /// исправления гонки не расходились между фазами (design.md change
  /// `add-agent-skills`, D16).
  ///
  /// [run] получает дочерний токен: по таймауту он отменяется, и порт
  /// перестаёт читать. Возвращает [_PhaseDone], [_PhaseTimeout] или
  /// [_PhaseFailed] (исключение порта; в лог уходит только его тип). Отмена
  /// [cancel] (закрытие сессии, `dispose()`) выбрасывает результат и бросает
  /// `CancelledException`. Таймер и дочерний токен освобождаются всегда.
  Future<_PhaseResult<T>> _boundedPhase<T>({
    required CancelToken cancel,
    required Future<T> Function(CancelToken token) run,
  }) async {
    final loadCancel = CancelTokenSource(parent: cancel);
    final outcome = Completer<T?>();
    void giveUp() {
      if (!outcome.isCompleted) {
        outcome.complete(null);
      }
    }

    final timer = services.clock.timer(_projectFilesTimeout, giveUp);
    unawaited(cancel.onCancel.then((_) => giveUp()));
    unawaited(
      Future.sync(() => run(loadCancel.token)).then(
        (value) {
          if (!outcome.isCompleted) {
            outcome.complete(value);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!outcome.isCompleted) {
            outcome.completeError(error, stack);
          }
        },
      ),
    );
    try {
      final result = await outcome.future;
      cancel.throwIfCancelled();
      if (result == null) {
        loadCancel.cancel();
        return _PhaseTimeout<T>();
      }
      return _PhaseDone<T>(result);
    } on CancelledException {
      rethrow;
    } on Object catch (error) {
      cancel.throwIfCancelled();
      return _PhaseFailed<T>(error);
    } finally {
      timer.cancel();
      loadCancel.dispose();
    }
  }

  /// Читает навыки сессии портом и строит снимок каталога (design.md change
  /// `add-agent-skills`, D1, D10, D16; capability `agent-skills`, «Порт
  /// файлов навыков»).
  ///
  /// Почему отдельная фаза, а не часть [_loadProjectFiles]: свой таймаут 5 с и
  /// своя отмена. Порт не вызывается без `services.skillFiles` и при
  /// выключенной capability. Таймаут и исключение дают пустой снимок и
  /// `project_files.diagnostic` (`timeout` / `unexpected`, только тип
  /// исключения); отмена выбрасывает результат и бросает `CancelledException`.
  /// `skills.loaded` пишется лишь когда порт вернул результат. Тела навыков в
  /// лог не попадают.
  Future<_SkillsLoad> _loadSkills({
    required SessionId id,
    required String canonicalCwd,
    required bool cwdResolved,
    required CoreConfig settings,
    required Logger logger,
    required CancelToken cancel,
  }) async {
    final source = services.skillFiles;
    if (source == null ||
        !profile.isOn(HostCapability.skills) ||
        !settings.skills.enabled) {
      return _SkillsLoad.none;
    }
    void diagnostic(
      DiagnosticLevel level,
      String path,
      String code,
      String message, {
      int? line,
      int? column,
    }) => logger.log(
      level == DiagnosticLevel.info ? LogLevel.debug : LogLevel.warning,
      'project_files.diagnostic',
      fields: {
        'session_id': id.value,
        'path': path,
        'line': line,
        'column': column,
        'code': code,
        'message': message,
      },
    );

    final projectTrusted =
        cwdResolved &&
        settings.trustedProjects.any((root) => samePath(root, canonicalCwd));
    final phase = await _boundedPhase<SkillFiles>(
      cancel: cancel,
      run: (token) => source.loadSkills(
        SkillFilesQuery(
          cwd: canonicalCwd,
          projectTrusted: projectTrusted,
          extraRoots: settings.skills.extraRoots,
          cancel: token,
        ),
      ),
    );
    final SkillFiles files;
    switch (phase) {
      case _PhaseTimeout<SkillFiles>():
        diagnostic(
          DiagnosticLevel.warning,
          canonicalCwd,
          'timeout',
          'skills were not read within '
              '${_projectFilesTimeout.inSeconds} s; the session has none',
        );
        return _SkillsLoad.none;
      case _PhaseFailed<SkillFiles>(:final error):
        diagnostic(
          DiagnosticLevel.error,
          canonicalCwd,
          'unexpected',
          'skills could not be read: ${error.runtimeType}',
        );
        return _SkillsLoad.none;
      case _PhaseDone<SkillFiles>(:final value):
        files = value;
    }
    final catalog = parseSkills(
      files,
      settings.skills,
      rules: settings.permissions.rules,
    );
    for (final item in [...files.diagnostics, ...catalog.diagnostics]) {
      diagnostic(
        item.level,
        item.path,
        item.code,
        item.message,
        line: item.line,
        column: item.column,
      );
    }
    logger.log(
      LogLevel.info,
      'skills.loaded',
      fields: {
        'session_id': id.value,
        'count': catalog.skills.length,
        'names': [for (final skill in catalog.skills) skill.name],
        // «Читались ли корни проекта» (D13): как `commands.loaded`.
        'project': projectTrusted,
      },
    );
    // Лог усечения каталога — один раз на сессию при открытии (создание и
    // `session/load`): секция одинакова на каждом шаге, повтор был бы шумом
    // (D6, D17). Считает та же функция, что строит секцию промпта.
    if (catalog.modelVisible.isNotEmpty) {
      final entries = skillsCatalogEntries(
        catalog.modelVisible,
        settings.skills.catalogMaxChars,
      );
      if (entries.shortened + entries.omitted > 0) {
        logger.log(
          LogLevel.warning,
          'skills.catalog.truncated',
          fields: {
            'session_id': id.value,
            'shortened': entries.shortened,
            'omitted': entries.omitted,
          },
        );
      }
    }
    return _SkillsLoad(catalog, files.sessionRoots);
  }

  /// Политика сессии: значение хоста плюс корни навыков сессии и каталоги
  /// снимка (D9, D17). Без того и другого — поле хоста как есть.
  AgentConfigPaths? _sessionConfigPaths(_SkillsLoad load) {
    final dirs = [for (final s in load.catalog.skills) s.dir];
    if (load.sessionRoots.isEmpty && dirs.isEmpty) {
      return services.agentConfigPaths;
    }
    return (services.agentConfigPaths ??
            // Поля хоста нет: регистр файловой системы — по платформе хоста
            // (macOS и Windows его не различают), как у `agentConfigPathsFor`.
            AgentConfigPaths(
              paths: const [],
              caseInsensitive:
                  services.platform == 'macos' ||
                  services.platform == 'windows',
            ))
        .withSession(paths: load.sessionRoots, skillDirs: dirs);
  }

  /// Читает файлы проекта сессии портом и собирает контекст инструкций
  /// (design.md change `add-agent-project-files`, D1, D4, D5, D6, D14).
  ///
  /// Загрузка — одна фаза внутри `_open`, до ответа `session/new`. Ошибки
  /// файлов порт возвращает диагностикой; непредвиденное исключение порта не
  /// роняет сессию (она создаётся без файлов), в лог идёт только тип
  /// исключения. Фаза ограничена [_projectFilesTimeout]: порт, не ответивший
  /// вовремя, даёт сессию без файлов и диагностику `timeout`. Отмена ([cancel]: `close()` сессии или `dispose()` рантайма)
  /// выбрасывает результат: сессия не создаётся. В лог не попадает ни
  /// содержимое файлов, ни фрагменты сообщений исключений (D14).
  Future<_ProjectLoad> _loadProjectFiles({
    required SessionId id,
    required String canonicalCwd,
    required bool cwdResolved,
    required CoreConfig settings,
    required Logger logger,
    required CancelToken cancel,
    required ModelCatalog catalog,
  }) async {
    final source = services.projectFiles;
    if (source == null) {
      return _ProjectLoad.none;
    }
    void diagnostic(
      DiagnosticLevel level,
      String path,
      String code,
      String message, {
      int? line,
      int? column,
    }) => logger.log(
      level == DiagnosticLevel.info ? LogLevel.debug : LogLevel.warning,
      'project_files.diagnostic',
      fields: {
        'session_id': id.value,
        'path': path,
        'line': line,
        'column': column,
        'code': code,
        'message': message,
      },
    );

    // Без раскрытого `realpath` доверия нет (D4, приоритет 1).
    final projectTrusted =
        cwdResolved &&
        settings.trustedProjects.any((root) => samePath(root, canonicalCwd));
    final phase = await _boundedPhase<ProjectFiles>(
      cancel: cancel,
      run: (token) => source.load(
        ProjectFilesQuery(
          cwd: canonicalCwd,
          projectTrusted: projectTrusted,
          contextMaxBytes: settings.projectContextMaxBytes,
          cancel: token,
        ),
      ),
    );
    final ProjectFiles files;
    switch (phase) {
      case _PhaseTimeout<ProjectFiles>():
        diagnostic(
          DiagnosticLevel.warning,
          canonicalCwd,
          'timeout',
          'project files were not read within '
              '${_projectFilesTimeout.inSeconds} s; the session has none',
        );
        return _ProjectLoad.none;
      case _PhaseFailed<ProjectFiles>(:final error):
        diagnostic(
          DiagnosticLevel.error,
          canonicalCwd,
          'unexpected',
          'project files could not be read: ${error.runtimeType}',
        );
        return _ProjectLoad.none;
      case _PhaseDone<ProjectFiles>(:final value):
        files = value;
    }
    for (final item in files.diagnostics) {
      diagnostic(
        item.level,
        item.path,
        item.code,
        item.message,
        line: item.line,
        column: item.column,
      );
    }
    final context = assembleProjectContext(
      files.context,
      settings.projectContextMaxBytes,
    );
    if (context != null) {
      logger.log(
        LogLevel.info,
        'project_context.loaded',
        fields: {
          'session_id': id.value,
          'files': [for (final file in context.files) file.path],
          'bytes': context.bytes,
          'truncated': context.truncated,
          'omitted': context.omitted,
          'root': files.contextRoot.name,
        },
      );
    }
    // Шаблоны команд: проверка ядром, диагностика без содержимого файлов
    // (D3, D14). Ошибка шаблона не прерывает создание сессии.
    final parsed = parseCommandTemplates(files.templates);
    for (final item in parsed.diagnostics) {
      diagnostic(
        item.level,
        item.path,
        item.code,
        item.message,
        line: item.line,
        column: item.column,
      );
    }
    logger.log(
      LogLevel.info,
      'commands.loaded',
      fields: {
        'session_id': id.value,
        'count': parsed.templates.length,
        // «Читался ли каталог проекта»: каталог шаблонов проекта читается
        // только для доверенного проекта (D4).
        'project': projectTrusted,
      },
    );
    // Определения агентов: та же проверка и тот же канал диагностики. Каталог
    // моделей сборки решает, существует ли модель определения (D10); тела
    // определений в лог не пишутся (D14).
    final agents = parseAgentDefinitions(files.agents, models: catalog);
    for (final item in agents.diagnostics) {
      diagnostic(
        item.level,
        item.path,
        item.code,
        item.message,
        line: item.line,
        column: item.column,
      );
    }
    logger.log(
      LogLevel.info,
      'agents.loaded',
      fields: {
        'session_id': id.value,
        'names': [for (final agent in agents.agents) agent.name],
      },
    );
    return _ProjectLoad(context, parsed.templates, agents.sessionAgents);
  }

  /// Подключает MCP-серверы сессии до возврата сессии (D6): слияние
  /// конфигурации и клиента, фильтр по capability `mcp`, подключение
  /// коннектором, регистрация инструментов в реестре сессии.
  Future<void> _connectMcp({
    required SessionId id,
    required String cwd,
    required CoreConfig settings,
    required List<McpServerConfig> servers,
    required Logger logger,
    required ToolRegistry registry,
    required _McpState state,
  }) async {
    final accepted = _planMcp(id, logger, settings, servers);
    if (accepted.isEmpty) {
      return;
    }
    await _connectAccepted(
      id: id,
      cwd: cwd,
      accepted: accepted,
      logger: logger,
      registry: registry,
      state: state,
    );
  }

  /// Слияние и фильтр списка серверов (D6) — общая часть первого подключения
  /// и `AgentSession.setMcpServers`, поэтому правила у них одни. Возвращает
  /// принятые серверы в порядке регистрации: серверы конфига, затем серверы
  /// клиента; отброшенные пишутся `mcp.server.skipped`.
  List<McpServerConfig> _planMcp(
    SessionId id,
    Logger logger,
    CoreConfig settings,
    List<McpServerConfig> servers, {
    bool logConfigSkips = true,
  }) {
    if (settings.mcpServers.isEmpty && servers.isEmpty) {
      return const [];
    }
    // Повторная смена набора не переписывает в лог пропуски серверов
    // конфига: они уже записаны при создании сессии.
    final configServers = Set<McpServerConfig>.identity()
      ..addAll(settings.mcpServers);
    void skipped(McpServerConfig server, String reason) {
      if (!logConfigSkips && configServers.contains(server)) {
        return;
      }
      logger.log(
        LogLevel.info,
        'mcp.server.skipped',
        fields: {
          'session_id': id.value,
          'server': server.name,
          'transport': server.transport,
          'reason': reason,
        },
      );
    }

    // Серверы клиента заменяют серверы конфига с тем же именем; дубликаты и
    // пустые имена внутри источника пропускаются (§13.4, шаг 2).
    final clientNames = {for (final s in servers) s.name};
    final merged = <McpServerConfig>[];
    for (final (source, list) in [
      (McpServerOrigin.config, settings.mcpServers),
      (McpServerOrigin.session, servers),
    ]) {
      final seen = <String>{};
      for (final server in list) {
        if (server.name.isEmpty) {
          skipped(server, 'empty server name');
        } else if (!seen.add(server.name)) {
          skipped(server, 'duplicate server name in the same source');
        } else if (source == McpServerOrigin.config &&
            clientNames.contains(server.name)) {
          skipped(
            server,
            'replaced by a server of the client with the same name',
          );
        } else {
          merged.add(server);
        }
      }
    }

    final connector = services.mcp;
    final capability = profile.states[HostCapability.mcp];
    final accepted = <McpServerConfig>[];
    for (final server in merged) {
      switch (capability) {
        case CapabilityOff(:final reason):
          skipped(server, reason);
        case CapabilityTransport(:final transports, :final reason)
            when !transports.contains(server.transport):
          skipped(
            server,
            'transport ${server.transport} is off in profile '
            '${profile.name}: $reason',
          );
        case _ when connector == null:
          skipped(server, 'сервис MCP не передан');
        case _:
          accepted.add(server);
      }
    }
    return accepted;
  }

  /// Замыкание раскрытия `${secret:…}` для коннектора (design.md change
  /// `add-config-writer-and-reload`, D11, «Секреты при переподключении»;
  /// agent-secrets «Секреты MCP-серверов конфигурации»).
  ///
  /// Почему замыкание, а не раскрытие до `connect`: коннектор зовёт его перед
  /// каждой попыткой, в том числе повторной, поэтому после
  /// `SecretResolver.invalidate` новая попытка берёт новое значение, а
  /// значение не живёт в коннекторе. Сервер, чей секрет не задан или
  /// недоступен, не выпадает из списка, а становится `failed` с `lastError`
  /// «secret NAME is not set» или «secret NAME cannot be read: BACKEND is
  /// unavailable» (без значения) и повторяется по расписанию. Серверы без
  /// шаблонов (клиента ACP: `${secret:…}` от клиента — литерал) проходят как
  /// есть, и коннектор замыкание для них не зовёт.
  McpSecretExpander get _secretExpander => (server) async {
    final (expanded, reason) = await _expandServerSecrets(
      server,
      services.secrets,
    );
    if (expanded == null) {
      throw McpSecretsException(reason ?? 'secret cannot be read');
    }
    return expanded;
  };

  /// Один сервер: раскрытый конфиг или причина отказа; не бросает.
  Future<(McpServerConfig?, String?)> _expandServerSecrets(
    McpServerConfig server,
    SecretResolver? resolver,
  ) async {
    if (server.secretValues.isEmpty) {
      return (server, null);
    }
    // В ссылку вписан сам секрет (CFG-9, пункт 3): отказ до любого
    // обращения к хранилищу, чтобы значение не ушло в `secrets.lookup` и
    // тексты (design.md change `add-config-literal-secrets-and-migrate`, D4).
    for (final MapEntry(key: field, value: template)
        in server.secretValues.entries) {
      if (template.parts.any((part) => part is UnusableSecretReference)) {
        return (
          null,
          'secret reference mcp.servers[${server.name}].$field looks like a '
              'secret value, not a name; run: codelab secret migrate',
        );
      }
    }
    if (resolver == null) {
      return (null, 'no secret store');
    }
    final values = <String, String>{};
    for (final MapEntry(key: field, value: template)
        in server.secretValues.entries) {
      final purpose = 'mcp.servers[${server.name}].$field';
      final found = <String, String>{};
      for (final name in template.names) {
        switch (await resolver.secret(name, purpose: purpose)) {
          case SecretFound(:final value):
            found[name] = value;
          case SecretMissing():
            return (null, 'secret $name is not set');
          case SecretUnavailable(:final backend):
            return (
              null,
              'secret $name cannot be read: $backend is unavailable',
            );
        }
      }
      values[field] = template.render(found);
    }
    return (server.withSecrets(values), null);
  }

  /// Подключает принятые серверы; сбой коннектора целиком не роняет сессию.
  Future<void> _connectAccepted({
    required SessionId id,
    required String cwd,
    required List<McpServerConfig> accepted,
    required Logger logger,
    required ToolRegistry registry,
    required _McpState state,
  }) async {
    final connector = services.mcp;
    if (connector == null) {
      return;
    }
    try {
      final connected = await connector.connect(
        McpConnectRequest(
          sessionId: id,
          cwd: cwd,
          servers: accepted,
          reservedNames: state.baseNames,
          logger: logger,
          cancel: state.cancel.token,
          expandSecrets: _secretExpander,
        ),
      );
      state.apply(connected, registry, logger, id);
    } on Object catch (error, stack) {
      _logConnectorFailure(id, logger, accepted, error, stack);
    }
  }

  /// `AgentSession.setMcpServers` (D11): тот же список, что при создании
  /// сессии, но из новых серверов клиента. Коннектору отдаётся полный
  /// желаемый список — серверы конфига и клиента в порядке регистрации, —
  /// поэтому серверы конфига остаются нетронутыми, а вытесненный клиентом
  /// сервер конфига закрывается и возвращается, когда клиент перестаёт его
  /// присылать. Реестр сессии обновляется по итогу, даже если коннектор
  /// сломался на полпути: правдой остаётся то, что он сейчас держит.
  Future<void> _replaceMcp({
    required SessionId id,
    required String cwd,
    required CoreConfig settings,
    required List<McpServerConfig> servers,
    required Logger logger,
    required ToolRegistry registry,
    required _McpState state,
  }) async {
    final accepted = _planMcp(
      id,
      logger,
      settings,
      servers,
      logConfigSkips: false,
    );
    final current = state.tools;
    if (current == null) {
      // Сессия начиналась без серверов: подключаем как при создании.
      if (accepted.isNotEmpty) {
        await _connectAccepted(
          id: id,
          cwd: cwd,
          accepted: accepted,
          logger: logger,
          registry: registry,
          state: state,
        );
      }
      return;
    }
    try {
      await current.replaceServers(accepted);
    } on Object catch (error, stack) {
      _logConnectorFailure(id, logger, accepted, error, stack);
    }
    state.refresh(registry, logger, id);
  }

  void _logConnectorFailure(
    SessionId id,
    Logger logger,
    List<McpServerConfig> servers,
    Object error,
    StackTrace stack,
  ) {
    // Сбой коннектора не должен ронять `session/new` (§13.4, шаг 4).
    logger.log(
      LogLevel.warning,
      'mcp.server.failed',
      fields: {
        'session_id': id.value,
        'server': servers.map((s) => s.name).join(','),
        'transport': servers.map((s) => s.transport).toSet().join(','),
        'reason': 'MCP connector failed: ${error.runtimeType}',
      },
      error: error.runtimeType,
      stack: stack,
    );
  }
}

/// Итог фазы файлов проекта: контекст инструкций, шаблоны команд и
/// определения агентов.
/// Применённый снимок рантайма: заменяется одним присваиванием (D8).
///
/// Почему запись, а не отдельные поля: шаг, ход и проверка разрешения читают
/// полный `CoreConfig`, функцию модели и каталог вместе и не должны видеть
/// смесь двух снимков. [values] и [host] — основа следующего сравнения;
/// [host] не меняется до перезапуска (ключи хоста `restartRequired`).
final class _Applied {
  const _Applied({
    required this.config,
    required this.stream,
    required this.catalog,
    required this.values,
    required this.host,
    required this.loadedAt,
    required this.sources,
  });

  final CoreConfig config;
  final StreamFunction stream;
  final ModelCatalog catalog;
  final Map<String, Object?> values;
  final HostSettings? host;
  final DateTime loadedAt;
  final List<String> sources;
}

/// Конфигурация, с которой открывается сессия (D21).
///
/// [settings] — `CoreConfig` сессии. [applied] — тройка «конфигурация,
/// каталог, функция модели»: для сессии папки с портом это её собственная
/// запись ([isolated]), для остальных — применённый снимок на момент
/// открытия, из которого берутся каталог и выбор модели.
final class _SessionScope {
  const _SessionScope({
    required this.settings,
    required this.applied,
    this.isolated = false,
  });

  final CoreConfig settings;
  final _Applied applied;
  final bool isolated;
}

final class _ProjectLoad {
  const _ProjectLoad(this.context, this.templates, this.agents);

  /// Порта нет, он упал или не уложился в таймаут: сессия без файлов проекта.
  static const none = _ProjectLoad(null, [], []);

  final ProjectContext? context;
  final List<CommandTemplate> templates;

  /// Определения для опции `agent` сессии (`scope` `session` и `both`).
  final List<AgentDefinition> agents;
}

/// MCP-часть состояния сессии: подключённые серверы и имена их
/// инструментов в реестре сессии (design.md change `add-agent-mcp-client`,
/// D6).
final class _McpState {
  _McpState({required this.baseNames, required this.cancel});

  /// Отмена подключений серверов этой сессии (первого и замен): `close()`
  /// сессии отменяет её до ожидания идущей замены.
  final CancelTokenSource cancel;

  /// Имена базового реестра: инструмент MCP с таким именем не регистрируется.
  final Set<String> baseNames;
  McpSessionTools? tools;
  var summaries = const <McpServerSummary>[];
  var _names = <String>[];

  /// Поток состояний серверов для `McpStatusPort` (D12, Q18): один
  /// контроллер на сессию. Он переживает смену `McpSessionTools` (первый
  /// сервер после перезагрузки конфига создаёт его позже) и закрывается
  /// только с сессией. `sync`: событие коннектора доходит до подписчика
  /// порта в том же вызове, как у самого коннектора.
  final _status = StreamController<List<McpServerSummary>>.broadcast(
    sync: true,
  );
  StreamSubscription<List<McpServerSummary>>? _statusSubscription;
  var _statusClosed = false;

  Stream<List<McpServerSummary>> get statusChanges => _status.stream;

  /// Подписка на `changes` нового `McpSessionTools` (Q18): сразу шлёт текущий
  /// список — подписчик порта, взятого до появления сервера, узнаёт о нём без
  /// нового `mcpStatus`. Вызывается из [apply], то есть один раз за сессию:
  /// `McpSessionTools` создаётся при первом подключении и не заменяется, а
  /// дальнейшие перезагрузки идут через его `replaceServers`. Отмена прежней
  /// подписки — защита на случай, если рантайм когда-нибудь начнёт заменять
  /// `McpSessionTools`; сегодня она ничего не отменяет.
  void _watch(McpSessionTools connected) {
    unawaited(_statusSubscription?.cancel());
    _statusSubscription = null;
    if (_statusClosed) {
      return;
    }
    _statusSubscription = connected.changes.listen((list) {
      if (!_statusClosed) {
        _status.add(List.unmodifiable(list));
      }
    });
    _status.add(List.unmodifiable(connected.servers));
  }

  /// Первая регистрация после подключения.
  void apply(
    McpSessionTools connected,
    ToolRegistry registry,
    Logger logger,
    SessionId id,
  ) {
    tools = connected;
    _watch(connected);
    _replace(connected.tools, connected.servers, registry, logger, id);
  }

  /// Набор после `replaceServers` (D11): реестр сессии снова равен тому, что
  /// держит коннектор.
  void refresh(ToolRegistry registry, Logger logger, SessionId id) {
    final connected = tools;
    if (connected != null) {
      _replace(connected.tools, connected.servers, registry, logger, id);
    }
  }

  /// Ожидающее `tools/list_changed`; `true` — набор сессии изменился.
  bool takeUpdate(ToolRegistry registry, Logger logger, SessionId id) {
    final update = tools?.takeUpdate();
    if (update == null) {
      return false;
    }
    _replace(update.tools, update.servers, registry, logger, id);
    return true;
  }

  void _replace(
    List<AgentTool> next,
    List<McpServerSummary> nextSummaries,
    ToolRegistry registry,
    Logger logger,
    SessionId id,
  ) {
    for (final name in _names) {
      registry.unregister(name);
    }
    final accepted = <AgentTool>[];
    for (final tool in next) {
      // Защита в глубину: коннектор уже проверил коллизии, но порт открыт
      // для других реализаций (HOST-5, TOOL-10).
      final reason = !isMcpToolName(tool.name)
          ? 'name has no mcp__ prefix'
          : baseNames.contains(tool.name) || registry.lookup(tool.name) != null
          ? 'name collides with a built-in tool'
          : null;
      if (reason != null) {
        logger.log(
          LogLevel.warning,
          'mcp.tool.invalid',
          fields: {'session_id': id.value, 'tool': tool.name, 'reason': reason},
        );
        continue;
      }
      registry.register(tool);
      accepted.add(tool);
    }
    _names = [for (final tool in accepted) tool.name];
    summaries = List.unmodifiable(nextSummaries);
  }

  Future<void> close() async {
    // Поток порта закрывается первым: события закрывающегося коннектора и
    // поздние события после `close()` до хоста не доходят (D21).
    _statusClosed = true;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    await _status.close();
    await tools?.close();
  }
}

/// Порт состояния MCP сессии: `servers` — живое состояние коннектора,
/// `changes` — поток `_McpState`, `reconnect` — действие через очередь замен.
final class _SessionMcpStatus implements McpStatusPort {
  _SessionMcpStatus(this._state, this._reconnect);

  final _McpState _state;
  final Future<void> Function(String name) _reconnect;

  @override
  List<McpServerSummary> get servers =>
      List.unmodifiable(_state.tools?.servers ?? const <McpServerSummary>[]);

  @override
  Stream<List<McpServerSummary>> get changes => _state.statusChanges;

  @override
  Future<void> reconnect(String name) => _reconnect(name);
}

final class _Session implements AgentSession {
  _Session({
    required this.id,
    required this.cwd,
    required ModeId mode,
    required ModelRef model,
    required ReasoningEffort effort,
    required this.canonicalCwd,
    required bool isolated,
    required ModelCatalog Function() catalogOf,
    required StreamFunction Function() streamOf,
    required CoreConfig Function() settingsOf,
    required Agent agent,
    required PermissionPolicy policy,
    required ToolServices tools,
    required ExecutionEnv env,
    required ToolRegistry registry,
    required _McpState mcp,
    required Future<void> Function(List<McpServerConfig> servers) replaceMcp,
    required List<McpServerConfig> clientMcp,
    required Future<ConfigApplyReport> Function()? reloadConfig,
    required Future<ConfigLoadResult> Function() checkConfig,
    required ConfigStatus Function()? configStatus,
    required bool mcpCommand,
    required AgentCoreServices services,
    required Logger logger,
    required String Function(String cwd, ModeId mode, AgentDefinition? agent)
    compose,
    required SessionSnapshot snapshot,
    required bool compactionOn,
    required CompactionOverrides? compaction,
    required List<CommandTemplate> templates,
    required List<AgentDefinition> agents,
    required this.skills,
    required ModeId modeFloor,
  }) : _mode = mode,
       _modeFloor = modeFloor,
       agents = List.unmodifiable(agents),
       _effort = effort,
       _isolated = isolated,
       _catalogOf = catalogOf,
       _streamOf = streamOf,
       _settingsOf = settingsOf,
       _compactionOn = compactionOn,
       _compaction = compaction,
       _model = model,
       _agent = agent,
       _policy = policy,
       _tools = tools,
       _env = env,
       _registry = registry,
       _mcp = mcp,
       _replaceMcp = replaceMcp,
       _clientMcp = List.unmodifiable(clientMcp),
       _services = services,
       _logger = logger,
       _compose = compose,
       _templates = List.unmodifiable(templates),
       commands = List.unmodifiable([
         ...BuiltinCommands.declare(
           compact: compactionOn,
           config: reloadConfig != null,
           mcp: mcpCommand,
         ),
         ...availableCommands(templates),
         ...skillSlashCommands(skills),
       ]),
       _titled = _hasTitle(snapshot) {
    _writer = SessionWriter(
      store: services.sessions,
      snapshot: snapshot,
      ids: services.ids,
      clock: services.clock,
      logger: logger,
      onFailure: _onStorageFailure,
    );
    // Писатель — первый подписчик агента: запись идёт до того, как событие
    // увидят остальные (§8.3, SES-8).
    _agent.subscribe(_onEvent);
    _builtin = BuiltinCommands(
      reloadConfig: reloadConfig,
      checkConfig: () async {
        try {
          return await checkConfig();
        } on Object catch (error) {
          // Текст ответа без сообщения исключения (оно может нести путь или
          // значение); причина — в логе только с классом (D12, §16).
          _logger.log(
            LogLevel.warning,
            'config.check.failed',
            fields: {
              'session_id': id.value,
              'error_class': error.runtimeType.toString(),
            },
          );
          rethrow;
        }
      },
      configStatus: configStatus,
      compactNow: _compactionOn ? _compactNow : null,
      templateNames: {for (final t in _templates) t.name},
      skillCommandNames: {for (final s in skills.commands) s.name},
      skillBranch: skills.skills.isNotEmpty,
      mcpDeclared: mcpCommand,
      currentMode: () => _mode,
      setMode: setMode,
      currentModel: () => '${_model.provider}/${_model.id}',
      hasModel: (model) => _catalog.resolve(ModelId(model)) != null,
      setModel: _setModelFromCommand,
      workingDirectory: cwd,
      commands: () => commands,
      servers: () => _mcp.tools?.servers ?? const [],
      reconnect: (name, cancelled) => _runMcpAction(
        (tools) => tools.reconnect(name),
        server: name,
        action: 'reconnect',
        cancelled: cancelled,
      ),
      setEnabled: (name, enabled, cancelled) => _runMcpAction(
        (tools) => tools.setEnabled(name, enabled),
        server: name,
        action: enabled ? 'enable' : 'disable',
        cancelled: cancelled,
      ),
    );
  }

  @override
  final SessionId id;
  final String cwd;

  /// Шаблоны сессии: строятся при открытии и не меняются до закрытия (D7).
  final List<CommandTemplate> _templates;

  @override
  final List<SlashCommand> commands;

  /// Исполнитель встроенных команд `/config` и `/mcp` (D12).
  late final BuiltinCommands _builtin;

  /// Слот хода занят встроенной командой: второй `prompt` отклоняется так
  /// же, как во время хода модели (D12, «Слот хода и ход модели»). Отдельный
  /// от `_agent.isRunning` флаг — команда не ход модели и не откладывает
  /// замену серверов до `TurnEnded` (D10).
  var _builtinRunning = false;

  /// Работа идущей команды с записью состояния (`compact`, `mode`, `model`):
  /// `close()` ждёт её до закрытия журнала, как `_background` (D14).
  Future<Object?>? _builtinStateWork;

  /// Сигнал отмены ожидания ответа команды (`session/cancel`, токен
  /// промпта); перезагрузка, начатая рантаймом, при этом доводится до конца.
  Completer<void>? _builtinCancel;

  @override
  final List<AgentDefinition> agents;

  /// Снимок навыков, построенный при открытии (D10, SKL-4): единственное
  /// поле и единственный метод доступа для всех потребителей.
  @override
  final SkillCatalog skills;

  /// Выбранный агент; `null` — `default`.
  AgentDefinition? _activeAgent;

  /// Агент, по набору которого проверяются вызовы. Совпадает с
  /// [_activeAgent], кроме выбора посреди хода: пакет текущего шага
  /// проверяется прежним набором, новый действует со следующего шага (D11,
  /// как режим политики).
  AgentDefinition? _enforcedAgent;

  /// Режим и модель на момент перехода из `default` (D11): от них считаются
  /// возврат к `default` и переход между агентами.
  ({ModeId mode, ModelRef model})? _agentBase;

  /// Режим конфигурации сессии — пол для режима определения агента (D11, OQ3).
  final ModeId _modeFloor;

  /// Агент выбран во время хода: схемы и промпт доедут на границе шага.
  var _agentPending = false;
  ModeId _mode;
  ModelRef _model;
  ReasoningEffort _effort;

  /// Канонический `cwd`: по нему выбирается снимок конфигурации сессии.
  final String canonicalCwd;

  /// Конфигурацию сессии построил `ProjectConfigLoader` (D21): перезагрузка
  /// корня её не меняет (Q19 (a)), события `ModelOptionsChanged` и замена
  /// серверов конфигурации (шаг 7а) её пропускают.
  final bool _isolated;

  /// Каталог моделей сессии. У сессии в корне — каталог применённого
  /// снимка, который читается при каждой смене модели, поэтому `setModel`
  /// видит модели после перезагрузки (D8). У сессии папки с портом — каталог
  /// её собственной тройки, построенный при открытии и неизменный до закрытия
  /// (D21).
  final ModelCatalog Function() _catalogOf;
  ModelCatalog get _catalog => _catalogOf();

  @override
  ModelCatalog get models => _catalog;

  /// Функция модели сессии: у сессии в корне — применённого снимка, у сессии
  /// папки с портом — её тройки (D21).
  final StreamFunction Function() _streamOf;

  /// Конфигурация этой сессии: у сессии в корне — по применённому снимку
  /// (`forSessionCwd`), у сессии папки с портом — её собственный `CoreConfig`
  /// из тройки (D21), он не меняется до закрытия.
  final CoreConfig Function() _settingsOf;

  /// Функция модели прежнего снимка, закреплённая за сессией, чья модель
  /// исчезла из каталога (D8, «Модель сессии исчезла из каталога»).
  StreamFunction? _pinnedStream;

  /// Модель, о которой уже записано `config.reload.model_orphaned`: одна
  /// запись на сессию и модель.
  final _orphanLogged = <String>{};

  /// Сессия возвращена вызывающему; до этого перезагрузка её не уведомляет.
  bool _handedOut = false;

  /// Вызов функции модели шага: закреплённая или текущая.
  AssistantMessageEventStream _streamNow(
    ModelRef model,
    LlmContext context, {
    CancelToken? cancel,
  }) => (_pinnedStream ?? _streamOf())(model, context, cancel: cancel);

  /// Новая модель, которую идущий ход получит на границе шага.
  ModelRef? _pendingModel;
  final Agent _agent;
  final PermissionPolicy _policy;
  final ToolServices _tools;
  final ExecutionEnv _env;
  final ToolRegistry _registry;
  final _McpState _mcp;

  /// Порт состояния MCP для хоста (D12, Q18): создаётся один раз и живёт
  /// столько же, сколько сессия; `reconnect` идёт через очередь замен.
  late final McpStatusPort _mcpStatus = _SessionMcpStatus(
    _mcp,
    (name) => _runMcpAction(
      (tools) => tools.reconnect(name),
      server: name,
      action: 'reconnect',
      cancelled: () => false,
    ),
  );
  final Future<void> Function(List<McpServerConfig> servers) _replaceMcp;

  /// Серверы клиента (`session/new`, `session/load`, `setMcpServers`): при
  /// перезагрузке конфига к ним добавляются новые серверы конфига (D10).
  /// Берётся последний присланный список, а не тот, с которым сессия
  /// создана.
  List<McpServerConfig> _clientMcp;

  /// Хвост очереди смен MCP-серверов: смены идут по одной, а ход и закрытие
  /// сессии ждут её хвост, чтобы набор не менялся посреди хода (D11).
  Future<void>? _mcpWork;

  /// Набор, присланный во время хода: применяется после `TurnEnded`; поздний
  /// вызов заменяет ранний.
  List<McpServerConfig>? _pendingMcp;

  /// Номер последнего вызова `setMcpServers`: устаревший набор, стоявший в
  /// очереди, не применяется после нового (последний вызов побеждает).
  var _mcpGeneration = 0;

  /// Ручное действие над сервером закончилось во время хода модели: реестр
  /// и схемы инструментов обновит граница шага (D6, D11).
  var _mcpRefreshPending = false;
  var _closed = false;
  final AgentCoreServices _services;
  final Logger _logger;
  late final SessionWriter _writer;

  /// Переопределения сжатия; `null` — capability `compaction` выключена.
  /// Обновляются на границе хода из применённого снимка (`compaction.*` —
  /// со следующего хода, D8).
  CompactionOverrides? _compaction;
  final bool _compactionOn;

  /// Фоновое сжатие после хода: следующий [prompt] ждёт его (§9.5).
  Future<void>? _background;
  CancelTokenSource? _backgroundCancel;

  /// Сборка системного промпта для нового режима.
  final String Function(String cwd, ModeId mode, AgentDefinition? agent)
  _compose;
  final _live = StreamController<AgentEvent>.broadcast(sync: true);
  final _turn = <AgentEvent>[];
  TurnEnded? _ended;

  /// Заголовок уже есть в журнале: автоматический больше не пишется.
  bool _titled;

  @override
  ModeId get mode => _mode;

  @override
  ModelRef get model => _model;

  @override
  ReasoningEffort get effort => _effort;

  /// Очередь смен конфигурации: хвост предыдущей смены (см. [_serial]).
  Future<void> _configTail = Future<void>.value();

  /// Номер последней смены конфигурации (для [ConfigChangeResult.changeId]).
  var _changeSeq = 0;

  /// Выполняет смену конфигурации строго после всех ранее начатых.
  ///
  /// Почему: `setMode`, `setModel`, `setEffort` и `setAgent` читают состояние
  /// сессии, делают `await` на запись журнала и только потом дописывают
  /// результат; два параллельных вызова (два запроса клиента) перемешивались
  /// и портили базу агента и режим (ревью итерации 3). Очередь делает итог
  /// параллельных вызовов равным последовательному, а `next*`/`base`
  /// вычисляются уже под очередью.
  ///
  /// Сбой операции возвращается её вызывающему и не блокирует хвост. Вызов
  /// изнутри операции (вложенный `setMode`) запрещён: внутри используются
  /// `_applyMode`/`_changeModel`, иначе очередь ждала бы сама себя.
  Future<T> _serial<T>(Future<T> Function(int changeId) operation) {
    final changeId = ++_changeSeq;
    final run = _configTail.then((_) {
      // Закрытие дожидается начатой смены, а стоявшие в очереди отклоняются.
      if (_closed) {
        throw StateError('the session is closed');
      }
      return operation(changeId);
    });
    _configTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<ConfigChangeResult> setModel(ModelId id) => _serial((changeId) async {
    final model =
        _catalog.resolve(id, effort: _effort) ??
        (throw ArgumentError.value(id.value, 'id', 'not in the model catalog'));
    await _changeModel(model);
    // После `model_change` внутри той же `_serial`: две быстрые смены пишут
    // память в порядке операций (D6, «Гонки»).
    await rememberLastModel(_services.lastModel, model, _logger, this.id);
    return ConfigChangeResult(changeId: changeId, model: model);
  });

  /// Каталог моделей заменён перезагрузкой (D8, «Модель сессии исчезла из
  /// каталога»). Модель, бывшая в прежнем каталоге и пропавшая из нового,
  /// остаётся модели сессии, а сессия закрепляется за функцией модели прежнего
  /// снимка до смены модели; `config.reload.model_orphaned` пишется один раз
  /// на сессию и модель. Модель вернулась в каталог — закрепление снимается.
  void _afterCatalogReplaced(_Applied before, _Applied after) {
    final id = ModelId('${_model.provider}/${_model.id}');
    if (after.catalog.resolve(id) != null) {
      _pinnedStream = null;
      return;
    }
    if (_pinnedStream == null && before.catalog.resolve(id) != null) {
      _pinnedStream = before.stream;
    }
    if (_pinnedStream != null && _orphanLogged.add(id.value)) {
      _logger.log(
        LogLevel.info,
        'config.reload.model_orphaned',
        fields: {'session_id': this.id.value, 'model': id.value},
      );
    }
  }

  Future<void> _changeModel(ModelRef model) async {
    // Явная смена модели возвращает сессию на текущую функцию модели.
    _pinnedStream = null;
    _apply(model);
    await _writer.append(
      (id, parent, at) => AgentRuntimeImpl._modelChange(id, parent, at, model),
    );
  }

  @override
  Future<void> setEffort(ReasoningEffort effort) => _serial((_) async {
    _effort = effort;
    _apply(
      _catalog.resolve(
            ModelId('${_model.provider}/${_model.id}'),
            effort: effort,
          ) ??
          AgentRuntimeImpl._withEffort(
            _model,
            _model.supportsReasoning ? effort : null,
          ),
    );
    await _writer.append(
      (id, parent, at) => ConfigChangeRecord(
        id: id,
        parentId: parent,
        timestamp: at,
        optionId: 'effort',
        value: effort.name,
      ),
    );
  });

  /// Модель следующего хода — сразу, идущего — на границе шага.
  void _apply(ModelRef model) {
    _model = model;
    _agent.config = _agent.config.copyWith(model: model);
    if (_agent.isRunning) {
      _pendingModel = model;
    }
  }

  /// Граница шага: новая модель и новый набор MCP-инструментов действуют со
  /// следующего запроса, внутри пакета вызовов набор не меняется (D6).
  Future<StepUpdate?> _takeStepUpdate() async {
    final model = _pendingModel;
    _pendingModel = null;
    final agentChanged = _agentPending;
    _agentPending = false;
    _flushPendingPolicyMode();
    final mcpChanged = _applyMcpUpdate();
    if (model == null && !mcpChanged && !agentChanged) {
      return null;
    }
    // Схемы и промпт встают вместе: после выбора агента или обновления MCP-
    // инструментов модель видит согласованный набор (D11, D6).
    final toolsChanged = mcpChanged || agentChanged;
    return StepUpdate(
      model: model,
      tools: toolsChanged ? _visibleTools() : null,
      systemPrompt: toolsChanged ? _agent.systemPrompt : null,
    );
  }

  /// Забирает ожидающее обновление MCP-инструментов: реестр сессии, набор
  /// агента и системный промпт (секция `mcp`, §11.5).
  bool _applyMcpUpdate() {
    var changed = _mcp.takeUpdate(_registry, _logger, id);
    if (_mcpRefreshPending) {
      _mcpRefreshPending = false;
      _mcp.refresh(_registry, _logger, id);
      changed = true;
    }
    if (!changed) {
      return false;
    }
    _agent
      ..tools = _visibleTools()
      ..systemPrompt = _compose(cwd, _mode, _activeAgent);
    return true;
  }

  @override
  Stream<AgentEvent> get events => Stream.multi((controller) {
    for (final event in _turn) {
      controller.add(event);
    }
    final subscription = _live.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  @override
  Future<TurnResult> prompt(
    List<ContentBlock> content, {
    CancelToken? cancel,
  }) async {
    if (_background case final background?) {
      await background;
    }
    // Смена MCP-серверов, начатая между ходами, заканчивается до хода: иначе
    // набор поменялся бы посреди него (D11). Цикл — на случай новой смены,
    // поставленной, пока ждали прежнюю.
    for (var work = _mcpWork; work != null; work = _mcpWork) {
      await work;
    }
    if (_agent.isRunning || _builtinRunning) {
      throw StateError('a turn is already running');
    }
    // Встроенная команда перехватывается до разворачивания шаблонов под тем
    // же слотом хода; слот занимается без `await` после проверки (D12).
    if (_matchBuiltin(content) case final call?) {
      return _runBuiltin(call, content, cancel);
    }
    _policy.clearTurnGrants();
    _tools.approvalWait.reset();
    _refreshSettings();
    _ended = null;
    // Выбор агента между ходами уже в `_agent`; отложенный флаг прошлого хода
    // не нужен.
    _agentPending = false;
    _flushPendingPolicyMode();
    // Между ходами изменение набора применяется перед началом хода (D6).
    _applyMcpUpdate();
    cancel?.onCancel.then((_) => _agent.abort(cancel.reason));
    final message = _expandCommand(content);
    try {
      await _agent.prompt([message]);
    } finally {
      // `TurnEnded` уже опубликован: набор, присланный во время хода,
      // применяется теперь, а не в ответе на запрос (D11).
      _startPendingMcp();
    }
    final ended = _ended!;
    if (ended.reason == TurnEndReason.completed ||
        ended.reason == TurnEndReason.maxTokens) {
      _compactAfterTurn();
    }
    return TurnResult(
      reason: ended.reason,
      usage: ended.usage,
      budgetExceeded: ended.budgetExceeded,
      held: ended.held,
    );
  }

  /// Бюджет хода и параметры сжатия — из применённого снимка на границе хода
  /// (`budget.*`, `compaction.*` действуют «со следующего хода», CFG-16, D8).
  /// Права и режим здесь не читаются: они меняются только перезапуском
  /// (R0-1).
  void _refreshSettings() {
    final settings = _settingsOf();
    _agent.config = _agent.config.copyWith(
      budget: settings.budget,
      contextWindowCap: (value: settings.compaction.contextWindowCap),
    );
    if (_compactionOn) {
      _compaction = settings.compaction;
    }
  }

  /// Событие уровня сессии вне очереди агента (перезагрузка конфигурации):
  /// закрытой сессии не шлётся (D8, «Гонка с close() сессии»).
  ///
  /// Только живым подписчикам, мимо буфера хода `_turn`: событие описывает
  /// момент перезагрузки, а новый подписчик получает буфер как «события
  /// текущего хода» и не должен проигрывать старое `ModelOptionsChanged`.
  void _publishFromRuntime(AgentEvent event) {
    if (!_closed && !_live.isClosed) {
      _live.add(event);
    }
  }

  BuiltinInvocation? _matchBuiltin(List<ContentBlock> content) {
    final index = content.indexWhere((block) => block is TextContent);
    if (index < 0) {
      return null;
    }
    return _builtin.match((content[index] as TextContent).text);
  }

  /// Даёт подписчикам `events` получить опубликованные события.
  ///
  /// Почему: `events` — `Stream.multi`, он доставляет события цепочкой
  /// микрозадач. Ход модели отдаёт управление при записи журнала, а у
  /// встроенной команды записи нет: без паузы `prompt` вернулся бы раньше,
  /// чем подписчик без паузы подписки (мост ACP) увидел `TurnEnded`, и ответ
  /// на `session/prompt` стал бы ошибкой (ACP-3, D12). Один оборот цикла
  /// событий гарантирует, что все микрозадачи доставки выполнены, сколько бы
  /// звеньев в цепочке ни было. Это не ожидание по времени и не таймер
  /// ожидания (PKG-6).
  Future<void> _drainSubscribers() => Future<void>(() {});

  /// Исполняет встроенную команду без модели (CFG-18, D12): события хода
  /// публикуются мимо писателя журнала, ответ — одно сообщение; ни промпт, ни
  /// ответ в журнал не пишутся, а запись состояния самой командой
  /// (`mode_change`, `model_change`, `compaction`) — пишется.
  ///
  /// Слот занят на всё время команды. Команды без побочных записей (`status`,
  /// `help`, `config`, `mcp`, неизвестная) при отмене (`session/cancel`, токен
  /// промпта) сразу завершают ход `cancelled` без текста; начатая
  /// перезагрузка доводится до конца — её результат общий.
  ///
  /// Команды, меняющие состояние (`compact`, `mode`, `model`), всегда ждут
  /// свою работу, а ответ строится по факту (D14): применено — сообщение и
  /// `completed`; отмена пришла до применения — `cancelled` без записи и без
  /// события смены. Так ни одно событие смены не приходит после `TurnEnded`,
  /// а `close()` ждёт работу и не оставляет записи после закрытия журнала.
  Future<TurnResult> _runBuiltin(
    BuiltinInvocation call,
    List<ContentBlock> content,
    CancelToken? cancel,
  ) async {
    _builtinRunning = true;
    final cancelled = _builtinCancel = Completer<void>();
    // Тот же сигнал отмены токеном для команд с записью: компактор отменяет
    // запрос суммаризатора и не пишет запись `compaction` (CMP-4), `/mode` и
    // `/model` не начинают смену.
    // Родитель — токен промпта: уже отменённый токен отменяет команду до
    // первого действия, а не через оборот микрозадач (D14).
    final stopSource = CancelTokenSource(parent: cancel);
    cancelled.future.then((_) => stopSource.cancel());
    cancel?.onCancel.then((_) {
      if (!cancelled.isCompleted) {
        cancelled.complete();
      }
    });
    // Имя и подкоманда для логов; у неизвестной команды набранного слова нет
    // ни в одном поле (D4, §16).
    final (logName, logSub) = switch (call) {
      final BuiltinCall c => (c.name.name, c.subcommand),
      UnknownCall() => ('unknown', 'unknown'),
    };
    final stateful = call is BuiltinCall && call.name.changesState;
    try {
      _ended = null;
      final now = _services.clock.now();
      _publish(
        TurnStarted(
          id,
          turnId: TurnId(_services.ids.nextId()),
          input: [UserMessage(content, timestamp: now)],
        ),
      );
      switch (call) {
        case UnknownCall(:final nameBytes, :final skillName):
          _logger.log(
            LogLevel.info,
            'command.unknown',
            fields: {
              'session_id': id.value,
              'name_bytes': nameBytes,
              // Слово неизвестного навыка в лог не идёт, только размер (D18).
              if (skillName != null) 'source': 'skill',
            },
          );
        case BuiltinCall():
          _logger.log(
            LogLevel.info,
            'command.builtin',
            fields: {
              'session_id': id.value,
              'name': logName,
              'subcommand': logSub,
            },
          );
      }
      // Ошибка `run` или порта становится исходом, а не необработанной
      // ошибкой: после отмены её никто не ждёт.
      final work = _builtin
          .run(
            call,
            cancelled: () => cancelled.isCompleted,
            cancel: stopSource.token,
          )
          .then<({BuiltinReply? reply, Object? error})>(
            (reply) => (reply: reply, error: null),
            onError: (Object error) => (reply: null, error: error),
          );
      if (stateful) {
        _builtinStateWork = work;
      }
      final outcome = stateful
          ? await work
          : await Future.any<({BuiltinReply? reply, Object? error})?>([
              work,
              cancelled.future.then((_) => null),
            ]);
      // Отмена порта могла прийти ошибкой раньше сигнала: это отмена, а не
      // провал команды.
      // Закрытая сессия: смена, стоявшая в очереди `_serial`, получила
      // `StateError('the session is closed')` — это следствие отмены закрытием,
      // а не сбой команды (ложное предупреждение в логе не нужно).
      if (outcome == null ||
          (cancelled.isCompleted &&
              (outcome.error is CancelledException ||
                  (_closed && outcome.error is StateError)))) {
        _logger.log(
          LogLevel.info,
          'command.builtin.cancelled',
          fields: {
            'session_id': id.value,
            'name': logName,
            'subcommand': logSub,
          },
        );
        _publish(
          TurnEnded(id, reason: TurnEndReason.cancelled, usage: const Usage()),
        );
      } else if (outcome.error case final error?) {
        // Тот же путь, что у сбоя хода модели: `AgentError` и
        // `TurnEnded(failed)`; мост ACP отвечает `-32603`. В событии и в логе
        // только класс ошибки: текст может нести путь или значение (§16).
        final errorClass = error.runtimeType.toString();
        _logger.log(
          LogLevel.warning,
          'command.builtin.failed',
          fields: {
            'session_id': id.value,
            'name': logName,
            'subcommand': logSub,
            'error_class': errorClass,
          },
        );
        _publish(
          AgentError(
            id,
            cls: AgentErrorClass.hook,
            message: 'the built-in command failed ($errorClass)',
          ),
        );
        _publish(
          TurnEnded(id, reason: TurnEndReason.failed, usage: const Usage()),
        );
      } else if (outcome.reply is BuiltinTurnFailed) {
        // `AgentError(compaction)` уже опубликован компактором (Q9): ход
        // кончается `failed` без сообщения агента.
        _publish(
          TurnEnded(id, reason: TurnEndReason.failed, usage: const Usage()),
        );
      } else {
        final text = (outcome.reply! as BuiltinText).text;
        final message = AssistantMessage(
          content: [TextContent(text)],
          model: _model,
          usage: const Usage(),
          stopReason: StopReason.stop,
          timestamp: now,
        );
        _publish(MessageStarted(id, message: message));
        _publish(MessageDelta(id, delta: text, partial: message));
        _publish(MessageEnded(id, message: message));
        _publish(
          TurnEnded(id, reason: TurnEndReason.completed, usage: const Usage()),
        );
      }
      await _drainSubscribers();
      final ended = _ended!;
      return TurnResult(reason: ended.reason, usage: ended.usage);
    } finally {
      _builtinCancel = null;
      _builtinStateWork = null;
      _builtinRunning = false;
    }
  }

  /// Сообщение пользователя; команда шаблона разворачивается здесь, до записи
  /// в журнал, поэтому ACP, встроенный режим и CLI ведут себя одинаково
  /// (design.md change `add-agent-project-files`, D8).
  ///
  /// Разбирается только первый текстовый блок. Развёрнутый текст идёт первым,
  /// остальные блоки — после него в исходном порядке. В лог не пишутся
  /// аргументы: пользователь мог вставить туда секрет (D14, §16).
  UserMessage _expandCommand(List<ContentBlock> content) {
    final index = content.indexWhere((block) => block is TextContent);
    if (index >= 0) {
      final typed = (content[index] as TextContent).text;
      if (_expandSkill(typed) case final expanded?) {
        final message = UserMessage([
          TextContent(expanded.text),
          for (final (i, block) in content.indexed)
            if (i != index) block,
        ], timestamp: _services.clock.now());
        _writer.noteCommand(message, expanded.command);
        return message;
      }
    }
    if (index >= 0 && _templates.isNotEmpty) {
      final typed = (content[index] as TextContent).text;
      if (expandCommand(typed, _templates) case Expanded(
        text: final body,
        :final command,
      )) {
        final message = UserMessage([
          TextContent(body),
          for (final (i, block) in content.indexed)
            if (i != index) block,
        ], timestamp: _services.clock.now());
        _writer.noteCommand(message, command);
        _logger.log(
          LogLevel.info,
          'command.expanded',
          fields: {
            'session_id': id.value,
            'name': command.name,
            'source': command.source,
            'args_bytes': utf8.encode(command.args).length,
          },
        );
        return message;
      }
    }
    return UserMessage(content, timestamp: _services.clock.now());
  }

  /// Активные навыки по журналу сессии на этот момент (D15, D18): ими
  /// пользуются инструмент `skill` и команда `/skill:` для повтора.
  List<active.ActiveSkill> _activeSkills() =>
      active.activeSkills(_writer.snapshot, skills, _settingsOf().skills);

  /// Разворачивает `/skill:<name> <args>` (design.md change
  /// `add-agent-skills`, D8, D18; agent-skills «Команды навыков»,
  /// «Повторная активация»).
  ///
  /// Порядок разбора: встроенная и шаблон проверены раньше (`match`,
  /// `expandCommand`), здесь остаётся слово `skill:<name>` существующего
  /// навыка с `user-invocable`; остальное `match` уже ответил как неизвестное.
  /// Если навык активен и содержимое совпало — вместо блока короткая строка
  /// повтора. В лог идут имя, способ и размер ввода; тело и аргументы — нет
  /// (D13, §16).
  ({String text, CommandRef command})? _expandSkill(String typed) {
    final line = parseCommandLine(typed);
    if (line == null || !line.word.startsWith(skillCommandPrefix)) {
      return null;
    }
    final skill = skills.skill(line.word.substring(skillCommandPrefix.length));
    if (skill == null || !skill.userInvocable) {
      return null;
    }
    final invocation = invokeSkill(skill, line.raw);
    final repeated = _activeSkills().any(
      (a) => a.name == skill.name && a.full && a.content == invocation.content,
    );
    _logger.log(
      LogLevel.info,
      'skill.activated',
      fields: {
        'session_id': id.value,
        'name': skill.name,
        'via': 'command',
        'repeated': repeated,
      },
    );
    _logger.log(
      LogLevel.info,
      'command.expanded',
      fields: {
        'session_id': id.value,
        'name': skill.name,
        'source': SlashCommandSource.skill.wire,
        'args_bytes': utf8.encode(line.raw).length,
      },
    );
    return (
      text: repeated ? invocation.repeat : invocation.full,
      command: CommandRef(
        source: SlashCommandSource.skill.wire,
        name: skill.name,
        args: line.raw,
      ),
    );
  }

  @override
  Future<void> setMcpServers(List<McpServerConfig> servers) async {
    if (_closed) {
      throw StateError('the session is closed');
    }
    final next = List<McpServerConfig>.unmodifiable(servers);
    _clientMcp = next;
    _mcpGeneration++;
    if (_agent.isRunning) {
      _pendingMcp = next;
      return;
    }
    await _enqueueMcp(next, _mcpGeneration);
  }

  /// Шаг 7а перезагрузки конфига (D10): желаемый список — серверы нового
  /// снимка, затем серверы клиента на момент применения — идёт через ту же
  /// очередь и счётчик поколений, что `setMcpServers`: последний побеждает.
  /// Без хода замена завершена к возврату; во время хода (промпт, ушедший в
  /// цикл) она откладывается до `TurnEnded`.
  Future<void> _applyConfigMcp() async {
    if (_closed) {
      return;
    }
    _mcpGeneration++;
    if (_agent.isRunning) {
      _pendingMcp = _clientMcp;
      return;
    }
    await _enqueueMcp(_clientMcp, _mcpGeneration);
  }

  void _startPendingMcp() {
    final pending = _pendingMcp;
    _pendingMcp = null;
    if (pending != null && !_closed) {
      unawaited(_enqueueMcp(pending, _mcpGeneration));
    }
  }

  /// Смены идут по одной в порядке вызовов; [_mcpWork] — их хвост.
  Future<void> _enqueueMcp(List<McpServerConfig> servers, int generation) =>
      _enqueueMcpJob(() => _applyMcpServers(servers, generation));

  /// Ставит задание в общую очередь замен: ручное действие `/mcp` не
  /// обгоняет идущую замену и не подключает сервер, который она удаляет
  /// (D10, D11).
  Future<void> _enqueueMcpJob(Future<void> Function() job) {
    final previous = _mcpWork ?? Future<void>.value();
    late final Future<void> work;
    work = previous.then((_) => job()).whenComplete(() {
      if (identical(_mcpWork, work)) {
        _mcpWork = null;
      }
    });
    _mcpWork = work;
    return work;
  }

  /// Ручное действие над сервером (`reconnect`, `setEnabled`) через очередь
  /// замен; после него реестр инструментов и промпт приводятся к набору
  /// коннектора. Не бросает: сбой — запись в лог (как у замены).
  ///
  /// [cancelled] — команда отменена, пока задание стояло в очереди: оно не
  /// выполняется. Во время хода модели набор не меняется (D6, D11): реестр и
  /// агент обновит граница шага через [_applyMcpUpdate].
  Future<void> _runMcpAction(
    Future<void> Function(McpSessionTools tools) run, {
    required String server,
    required String action,
    required bool Function() cancelled,
  }) => _enqueueMcpJob(() async {
    final tools = _mcp.tools;
    if (_closed || tools == null || cancelled()) {
      return;
    }
    try {
      await run(tools);
      if (_agent.isRunning) {
        _mcpRefreshPending = true;
        return;
      }
      _mcp.refresh(_registry, _logger, id);
      _agent
        ..tools = _visibleTools()
        ..systemPrompt = _compose(cwd, _mode, _activeAgent);
    } on Object catch (error, stack) {
      _logger.log(
        LogLevel.warning,
        'mcp.server.failed',
        fields: {
          'session_id': id.value,
          'server': server,
          'transport': tools.servers
              .where((s) => s.name == server)
              .map((s) => s.transport)
              .firstOrNull,
          'action': action,
          'reason': 'MCP action failed: ${error.runtimeType}',
        },
        error: error.runtimeType,
        stack: stack,
      );
    }
  });

  /// Не бросает: сбой смены — запись в лог, а прежний набор остаётся
  /// (`session/load` не должен падать из-за сервера MCP, §13.4, шаг 4).
  Future<void> _applyMcpServers(
    List<McpServerConfig> servers,
    int generation,
  ) async {
    if (_closed || generation != _mcpGeneration) {
      return;
    }
    try {
      await _replaceMcp(servers);
      _agent
        ..tools = _visibleTools()
        ..systemPrompt = _compose(cwd, _mode, _activeAgent);
    } on Object catch (error, stack) {
      _logger.log(
        LogLevel.warning,
        'mcp.server.failed',
        fields: {
          'session_id': id.value,
          'server': servers.map((s) => s.name).join(','),
          'transport': servers.map((s) => s.transport).toSet().join(','),
          'reason': 'MCP connector failed: ${error.runtimeType}',
        },
        error: error.runtimeType,
        stack: stack,
      );
    }
  }

  @override
  Future<void> cancel() async {
    _agent.abort(const UserCancel());
    _cancelBuiltin();
  }

  /// Завершает ожидание ответа идущей встроенной команды (`session/cancel`,
  /// закрытие сессии): ход заканчивается `cancelled`, слот свободен.
  void _cancelBuiltin() {
    final waiting = _builtinCancel;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
  }

  @override
  Future<ConfigChangeResult> setMode(ModeId mode) => _serial((changeId) async {
    await _applyMode(mode, changeId, deferPolicy: false);
    return ConfigChangeResult(changeId: changeId, mode: mode);
  });

  /// Режим политики, который выбор агента во время хода применит на границе
  /// шага: вызовы текущего пакета решаются прежним режимом (D11).
  ModeId? _pendingPolicyMode;

  /// Ставит режим сессии. Сам режим и промпт меняются сразу; режим политики —
  /// сразу для [setMode] (спека: «со следующего вызова инструмента») и на
  /// границе шага для выбора агента во время хода ([deferPolicy]).
  Future<void> _applyMode(
    ModeId mode,
    int changeId, {
    required bool deferPolicy,
  }) async {
    _mode = mode;
    if (deferPolicy && _agent.isRunning) {
      _pendingPolicyMode = mode;
    } else {
      _pendingPolicyMode = null;
      _policy.mode = mode;
    }
    // Режим plan добавляет свою секцию: промпт меняется со следующего хода.
    _agent.systemPrompt = _compose(cwd, mode, _activeAgent);
    await _sessionEvent(ModeChanged(id, mode: mode, changeId: changeId));
  }

  void _flushPendingPolicyMode() {
    _enforcedAgent = _activeAgent;
    if (_pendingPolicyMode case final mode?) {
      _policy.mode = mode;
      _pendingPolicyMode = null;
    }
  }

  @override
  String get agent => _activeAgent?.name ?? defaultAgentName;

  /// Схемы сессии за вычетом инструментов вне набора агента (CFG-7, D11).
  List<AgentTool> _visibleTools() => [
    for (final tool in _registry.tools)
      if (_activeAgent?.allowsTool(tool.name) ?? true) tool,
  ];

  /// Текст отказа для инструмента реестра, которого нет в наборе агента;
  /// `null` — инструмент не отфильтрован агентом (его просто нет).
  String? _unavailableText(String toolName) {
    final active = _enforcedAgent;
    if (active == null ||
        active.allowsTool(toolName) ||
        _registry.lookup(toolName) == null) {
      return null;
    }
    return 'Tool not available for agent ${active.name}: $toolName';
  }

  @override
  Future<ConfigChangeResult> setAgent(String name) =>
      _serial((changeId) => _setAgentNow(name, changeId));

  Future<ConfigChangeResult> _setAgentNow(String name, int changeId) async {
    if (_closed) {
      throw StateError('the session is closed');
    }
    final AgentDefinition? target;
    if (name == defaultAgentName) {
      target = null;
    } else {
      target =
          agents.where((a) => a.name == name).firstOrNull ??
          (throw ArgumentError.value(
            name,
            'name',
            'not an agent of the session',
          ));
    }
    if (target?.name == _activeAgent?.name) {
      return ConfigChangeResult(changeId: changeId);
    }
    // База запоминается только при переходе из `default`; `default` её
    // возвращает и забывает (D11).
    final base = _agentBase ?? (mode: _mode, model: _model);
    final wantedMode = target?.mode;
    // Пол режима — режим конфигурации, а не текущий: пользователь мог сам
    // перейти в `accept-edits`, и агент `accept-edits` не должен отказывать;
    // но смягчить режим ниже конфига выбор агента не может (OQ3).
    final modeApplied = wantedMode == null || wantedMode.fitsFloor(_modeFloor);
    final nextMode = target == null || !modeApplied || wantedMode == null
        ? base.mode
        : wantedMode;
    // Ссылка пересобирается с усилием сессии: база из журнала хранится без
    // него (§2.12.3).
    final wanted = target?.model ?? base.model;
    final nextModel =
        _catalog.resolve(
          ModelId('${wanted.provider}/${wanted.id}'),
          effort: _effort,
        ) ??
        wanted;

    // Состояние агента ставится до первого `await`: идущий ход получит его на
    // ближайшей границе шага, а не вперемешку с записью журнала.
    _activeAgent = target;
    if (!_agent.isRunning) {
      _enforcedAgent = target;
    }
    _agentBase = target == null ? null : base;
    _agentPending = _agent.isRunning;
    _agent
      ..tools = _visibleTools()
      ..systemPrompt = _compose(cwd, _mode, target);
    // Запись выбора идёт раньше `model_change`/`mode_change`: по ней
    // `loadSession` находит базу — режим и модель до этой записи (D11).
    await _writer.append(
      (id, parent, at) => ConfigChangeRecord(
        id: id,
        parentId: parent,
        timestamp: at,
        optionId: 'agent',
        value: name,
      ),
    );
    final modelChanged =
        nextModel.provider != _model.provider || nextModel.id != _model.id;
    if (modelChanged) {
      await _changeModel(nextModel);
    }
    final modeChanged = nextMode != _mode;
    if (modeChanged) {
      // Режим политики — со следующего шага: остальные вызовы пакета решаются
      // прежним режимом (D11).
      await _applyMode(nextMode, changeId, deferPolicy: true);
    }
    if (!modeApplied) {
      _logger.log(
        LogLevel.warning,
        'agent.mode.not_applied',
        fields: {
          'session_id': id.value,
          'agent': name,
          'mode': wantedMode!.value,
          'floor': _modeFloor.value,
        },
      );
    }
    _logger.log(
      LogLevel.info,
      'agent.selected',
      fields: {
        'session_id': id.value,
        'agent': name,
        'source': target?.source,
        'model': '${_model.provider}/${_model.id}',
        'mode': _mode.value,
        'mode_applied': modeApplied,
        'tools': _visibleTools().length,
      },
    );

    return ConfigChangeResult(
      changeId: changeId,
      mode: modeChanged ? nextMode : null,
      model: modelChanged ? nextModel : null,
    );
  }

  /// Возвращает агента журнала при `loadSession` (D11, D14): режим и модель
  /// восстановлены из собственных записей, здесь только состояние агента.
  ///
  /// База режима зажимается полом конфигурации (fail-closed): конфигурацию
  /// могли ужесточить после записи, и возврат к `default` не должен дать
  /// режим мягче пола. Пропавшее определение пишет в журнал
  /// `config_change {agent: default}` (как `session.model.not_restored`):
  /// иначе поздний `loadSession` считал бы базу от устаревшего перехода.
  Future<void> _restoreAgent(
    String? name, {
    required ModeId baseMode,
    required ModelRef baseModel,
  }) async {
    if (name == null || name == defaultAgentName) {
      return;
    }
    final definition = agents.where((a) => a.name == name).firstOrNull;
    if (definition == null) {
      _logger.log(
        LogLevel.warning,
        'agent.definition.missing',
        fields: {'session_id': id.value, 'agent': name},
      );
      await _writer.append(
        (id, parent, at) => ConfigChangeRecord(
          id: id,
          parentId: parent,
          timestamp: at,
          optionId: 'agent',
          value: defaultAgentName,
        ),
      );
      return;
    }
    _activeAgent = definition;
    _enforcedAgent = definition;
    _agentBase = (
      mode: baseMode.fitsFloor(_modeFloor) ? baseMode : _modeFloor,
      model: baseModel,
    );
    _agent
      ..tools = _visibleTools()
      ..systemPrompt = _compose(cwd, _mode, definition);
  }

  @override
  Iterable<AgentEvent> replay() =>
      buildReplay(_writer.snapshot, logger: _logger);

  @override
  Future<void> close() async {
    _closed = true;
    _pendingMcp = null;
    _cancelBuiltin();
    // Идущая замена серверов не должна держать закрытие до `connectTimeout`.
    _mcp.cancel.cancel(const ShutdownCancel());
    _agent.abort(const ShutdownCancel());
    _backgroundCancel?.cancel(const ShutdownCancel());
    await _agent.waitForIdle();
    await _background;
    // Сжатие или смена по команде не должны писать в журнал после его
    // закрытия (D14): отменённый компактор доходит до выхода, смена — до конца.
    await _builtinStateWork;
    // Начатая смена конфигурации доходит до конца (запись журнала), стоявшие
    // за ней получают StateError.
    await _configTail;
    // Идущая смена серверов доходит до конца, иначе её новые процессы
    // остались бы без владельца.
    await _mcpWork;
    // Транспорты MCP закрываются после простоя хода: идущий вызов успевает
    // получить отмену (design.md change `add-agent-mcp-client`, D6).
    try {
      await _mcp.close();
    } on Object catch (error, stack) {
      _logger.log(
        LogLevel.warning,
        'mcp.server.failed',
        fields: {
          'session_id': id.value,
          'reason': 'closing MCP servers failed: ${error.runtimeType}',
        },
        error: error,
        stack: stack,
      );
    }
    await _services.sessions.close(id);
    if (!_live.isClosed) {
      await _live.close();
    }
  }

  /// Синтетические результаты прерванных вызовов — сразу после открытия, до
  /// реплея и нового шага (§8.8, SES-10).
  Future<void> _heal() async {
    final snapshot = _writer.snapshot;
    final meta = <String, ToolMeta>{
      for (final call in findInterruptedCalls(snapshot))
        call.id: await _describe(call),
    };
    final healed = healInterruptedTurn(
      snapshot,
      _services.ids,
      _services.clock,
      meta: meta,
    );
    for (final record in healed) {
      await _writer.appendBuilt(record, durable: true);
    }
  }

  /// Заголовок прерванного вызова — тот же `present()`, что дал бы
  /// `ToolCallStarted`; без инструмента или при ошибке — его имя.
  Future<ToolMeta> _describe(ToolCall call) async {
    final tool = _registry.lookup(call.name);
    if (tool == null) {
      return ToolMeta(title: call.name, kind: ToolKind.other);
    }
    try {
      final presented = await tool.present(
        call.arguments,
        ToolContext(
          env: _env,
          cancel: CancelTokenSource().token,
          onUpdate: (_) {},
          toolCallId: call.id,
          services: _tools,
        ),
      );
      return ToolMeta(
        title: presented.title,
        kind: tool.kind,
        locations: presented.locations,
      );
    } on Object {
      return ToolMeta(title: call.name, kind: tool.kind);
    }
  }

  /// Транскрипт и план из журнала после ремонта (§8.7).
  void _restoreHistory() {
    final snapshot = _writer.snapshot;
    _agent.replaceTranscript(
      _withModel(buildLlmContext(snapshot, logger: _logger).messages),
    );
    final plan = pathToLeaf(snapshot).whereType<PlanRecord>().lastOrNull;
    if (plan != null) {
      _tools.plan.restore(plan.entries);
    }
  }

  /// Ответы своей модели получают полную ссылку: журнал хранит только
  /// провайдера и id (§2.2).
  List<Message> _withModel(List<Message> messages) => [
    for (final message in messages)
      if (message is AssistantMessage &&
          message.model.provider == _model.provider &&
          message.model.id == _model.id)
        message.copyWith(model: _model)
      else
        message,
  ];

  int get _window => effectiveContextWindow(
    _agent.config.model,
    cap: _compaction?.contextWindowCap,
  );

  CompactionSettings get _settings =>
      CompactionSettings.forWindow(_window, overrides: _compaction);

  List<ToolSchema> get _schemas => [
    for (final tool in _agent.tools) tool.toSchema(),
  ];

  /// Сжатие журнала сессии по §9.8 с суммаризатором над моделью сессии
  /// (design.md, D8).
  Future<CompactionOutcome> _compact(
    CompactionTrigger trigger,
    CancelToken cancel, {
    required void Function(LlmContextProjection projection) onCompacted,
    String? focus,
  }) {
    final model = _agent.config.model;
    final settings = _settings;
    return compact(
      writer: _writer,
      trigger: trigger,
      summarize: modelSummarizer(
        stream: _streamNow,
        model: model,
        sessionId: id,
        settings: settings,
        clock: _services.clock,
      ),
      settings: settings,
      window: _window,
      systemPrompt: _agent.systemPrompt,
      tools: _schemas,
      ids: _services.ids,
      clock: _services.clock,
      cancel: cancel,
      emit: _sessionEvent,
      onCompacted: onCompacted,
      focus: focus,
      summaryModel: '${model.provider}/${model.id}',
      logger: _logger,
    );
  }

  /// Ручное сжатие по `/compact [focus]` (design.md change
  /// `add-agent-builtin-slash-commands`, D5; §9.5).
  ///
  /// Почему здесь, а не в `BuiltinCommands`: компактор работает с писателем
  /// журнала и транскриптом агента. Фоновое `afterTurn` к этому моменту уже
  /// дождались в начале [prompt], а слот хода исключает параллельный промпт:
  /// двух сжатий одной ветки одновременно нет. Параметры `compaction.*`
  /// берутся из снимка на границе хода, как у обычного хода (CFG-16).
  Future<CompactionOutcome> _compactNow(String? focus, CancelToken cancel) {
    _refreshSettings();
    return _compact(
      CompactionTrigger.manual,
      cancel,
      onCompacted: (p) => _agent.replaceTranscript(_withModel(p.messages)),
      focus: focus,
    );
  }

  /// `/model <provider/model>`: `setModel` и событие смены опции `model`.
  ///
  /// Почему [ModelOptionsChanged]: смену сделала не опция клиента, поэтому
  /// клиенту нужен `config_option_update` с полным снимком опций; мост ACP
  /// уже проецирует это событие так (§13.6 п. 4, §13.7), строя снимок из
  /// текущего состояния сессии. Событие идёт после записи `model_change` и
  /// до сообщения агента (D6, Q3).
  Future<String> _setModelFromCommand(String model) async {
    final result = await setModel(ModelId(model));
    _publish(ModelOptionsChanged(id));
    final changed = result.model!;
    return '${changed.provider}/${changed.id}';
  }

  /// Аварийное сжатие цикла (`preflight`, `overflow`): новый контекст шага
  /// из проекции; транскрипт агента цикл заменит сам после хода.
  Future<LoopContext?> _emergency(
    EmergencyCause cause,
    CancelToken cancel,
  ) async {
    LlmContextProjection? projection;
    final outcome = await _compact(
      cause == EmergencyCause.preflight
          ? CompactionTrigger.preflight
          : CompactionTrigger.overflow,
      cancel,
      onCompacted: (p) => projection = p,
    );
    if (outcome is! Compacted || projection == null) {
      return null;
    }
    return LoopContext(
      systemPrompt: _agent.systemPrompt,
      messages: _withModel(projection!.messages),
      tools: _agent.tools,
    );
  }

  /// `afterTurn` (§9.5): оценка выше порога — сжатие в фоне до следующего
  /// [prompt].
  void _compactAfterTurn() {
    if (_compaction == null) {
      return;
    }
    final tokens = estimateContextTokens(
      _agent.messages,
      systemPrompt: _agent.systemPrompt,
      tools: _schemas,
    );
    if (!shouldCompact(tokens, _window, _settings)) {
      return;
    }
    final source = CancelTokenSource();
    _backgroundCancel = source;
    _background = _runBackground(source.token).whenComplete(() {
      _background = null;
      _backgroundCancel = null;
    });
  }

  Future<void> _runBackground(CancelToken cancel) async {
    try {
      await _compact(
        CompactionTrigger.afterTurn,
        cancel,
        onCompacted: (p) => _agent.replaceTranscript(_withModel(p.messages)),
      );
    } on CancelledException {
      // Сессия закрывается: журнал не тронут (CMP-3).
    } on Object catch (error, stack) {
      // Ошибка фонового сжатия не должна теряться (AGENTS.md §12).
      _logger.log(
        LogLevel.error,
        'compaction.failed',
        fields: {'session_id': id.value, 'trigger': 'afterTurn'},
        error: error,
        stack: stack,
      );
      await _sessionEvent(
        AgentError(
          id,
          cls: AgentErrorClass.compaction,
          message: 'compaction failed: $error',
        ),
      );
    }
  }

  Future<void> _onEvent(AgentEvent event) async {
    await _writer.handle(event);
    _publish(event);
    if (event is TurnEnded) {
      await _afterTurn();
    }
  }

  /// Автоматический заголовок после первого хода со словами пользователя
  /// (§8.10, design.md D6).
  Future<void> _afterTurn() async {
    if (_titled) {
      return;
    }
    final title = summarize(_writer.snapshot, logger: _logger).title;
    if (title == null) {
      return;
    }
    _titled = true;
    await _sessionEvent(
      SessionTitleChanged(id, title: title, updatedAt: _services.clock.now()),
    );
  }

  /// Событие уровня сессии: сначала запись, потом подписчики.
  Future<void> _sessionEvent(AgentEvent event) async {
    await _writer.handle(event);
    _publish(event);
  }

  void _onStorageFailure(Object error) {
    _agent.abort(StorageFailure(error));
    // Не ждём: событие встаёт в очередь агента следом за текущим, а
    // текущее ждёт этого подписчика.
    unawaited(
      _agent.emit(
        AgentError(
          id,
          cls: AgentErrorClass.storage,
          message: 'session journal write failed: $error',
        ),
      ),
    );
  }

  void _publish(AgentEvent event) {
    if (event is TurnStarted) {
      _turn.clear();
    }
    if (event is TurnEnded) {
      _ended = event;
    }
    _turn.add(event);
    if (!_live.isClosed) {
      _live.add(event);
    }
  }

  static bool _hasTitle(SessionSnapshot snapshot) => pathToLeaf(
    snapshot,
  ).any((r) => r is SessionInfoRecord && (r.title?.isNotEmpty ?? false));
}

/// Запись явного выбора в порт последней модели (design.md change
/// `optional-default-model`, D6).
///
/// Почему отдельная функция: три точки (`createSession(spec.model)`,
/// `loadSession(model:)`, `setModel`) пишут одинаково, и сбой памяти не должен
/// ломать ни одну из них (приоритет 4: модель сессии уже в журнале).
///
/// Как использовать: вызывать после записи `model_change` в журнал; [port]
/// `null` — память не подключена, вызов ничего не делает. Сбой перехватывается
/// и логируется `model.last_used.write_failed {session_id, reason}` с именем
/// типа ошибки, без её текста (путь или секрет в сообщении); наружу ничего не
/// бросается.
Future<void> rememberLastModel(
  LastModelStore? port,
  ModelRef model,
  Logger logger,
  SessionId sessionId,
) async {
  if (port == null) {
    return;
  }
  try {
    await port.write(ModelId('${model.provider}/${model.id}'));
  } on Object catch (error) {
    logger.log(
      LogLevel.warning,
      'model.last_used.write_failed',
      fields: {
        'session_id': sessionId.value,
        'reason': error.runtimeType.toString(),
      },
    );
  }
}

/// Итог ограниченной фазы открытия сессии (`_boundedPhase`): исчерпывающий
/// `switch` без приведений типа.
sealed class _PhaseResult<T> {
  const _PhaseResult();
}

/// Порт ответил вовремя.
final class _PhaseDone<T> extends _PhaseResult<T> {
  const _PhaseDone(this.value);

  final T value;
}

/// Фаза не уложилась в таймаут.
final class _PhaseTimeout<T> extends _PhaseResult<T> {
  const _PhaseTimeout();
}

/// Порт фазы бросил исключение; в лог идёт только его тип.
final class _PhaseFailed<T> extends _PhaseResult<T> {
  const _PhaseFailed(this.error);

  final Object error;
}

/// Результат фазы навыков: снимок каталога и корни сессии для PERM-11
/// (design.md change `add-agent-skills`, D17).
final class _SkillsLoad {
  const _SkillsLoad(this.catalog, this.sessionRoots);

  /// Фаза не дала результата (нет порта, `skills.enabled: false`, таймаут,
  /// исключение): каталог пуст, путей сессии нет (известный предел, Q46 (а)).
  static final none = _SkillsLoad(SkillCatalog.empty, const []);

  final SkillCatalog catalog;
  final List<String> sessionRoots;
}
