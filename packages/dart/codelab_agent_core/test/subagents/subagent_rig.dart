import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart' show expect, fail, isEmpty, pumpEventQueue;

import '../config/config_support.dart' show baseValues, layer;
import '../host/core_harness.dart' show inMemoryJournal, noExec;
import '../support/models.dart';

/// Шаги скриптованной модели одного участника дерева.
typedef Steps = List<Map<String, Object?>>;

/// Ядро над памятью со скриптами по участникам дерева (корень и дети).
///
/// Почему не `CoreHarness`: у него один скрипт на всё ядро, а `n`-й запрос
/// получает `n`-й шаг. Дети работают параллельно, и порядок их запросов к
/// модели не должен определять, какой шаг кому достанется. Здесь скрипт
/// выбирается по **тексту первого user-сообщения запроса**: у корня это
/// текст `session.prompt`, у ребёнка — аргумент `prompt` вызова `agent`
/// (`agent-subagents` «Сборка ребёнка»: ребёнок получает одно user-сообщение
/// с текстом `prompt`). Поэтому у участников дерева в тестах разные
/// `prompt` (design.md change `add-subagents-and-tasks`, D1, D5).
///
/// Как использовать: `scripts` — карта «первое сообщение → шаги»; `open()`
/// создаёт корневую сессию и собирает её события в [events]; `run('go')` —
/// ход корня. Запросы к модели лежат в [requests] по ключу скрипта.
/// Запрос без скрипта получает ошибку `badRequest` (она видна в
/// [requestsOf] и в отчёте ребёнка).
///
/// Время — `FakeClock`: шаг с `delayMs` ждёт `clock.elapse`, поэтому тест
/// управляет параллельностью без `Future.delayed`.
final class SubagentRig {
  SubagentRig({
    required Map<String, Steps> scripts,
    CoreConfig? config,
    Map<HostCapability, CapabilityState> narrow = noExec,
    PermissionGate? gate,
    ExecutionEnv? baseEnv,
    ProjectFilesSource? projectFiles,
    SkillFilesSource? skillFiles,
    AgentConfigPaths? agentConfigPaths,
    MemorySessionStore? store,
    FakeClock? clock,
    String profile = 'agent-serve',
    LayeredConfigSource? source,
    ExecutionEnv? hostFiles,
    ModelCatalog? models,
  }) : clock = clock ?? FakeClock(),
       store = store ?? MemorySessionStore() {
    for (final MapEntry(:key, :value) in scripts.entries) {
      _scripts[key] = ScriptedStreamFunction.fromJson({
        'steps': value,
      }, clock: this.clock);
    }
    core = buildAgentCore(
      profile: HostProfile.of(
        profile,
      ).narrowed({...inMemoryJournal, ...narrow}),
      services: AgentCoreServices(
        baseEnv: baseEnv ?? MemoryExecutionEnv(cwd: '/proj', clock: this.clock),
        gate: gate,
        logger: logger,
        clock: this.clock,
        ids: SequentialIdGenerator(),
        sessions: this.store,
        projectFiles: projectFiles,
        skillFiles: skillFiles,
        agentConfigPaths: agentConfigPaths,
        config: source,
        hostFiles: hostFiles,
        models:
            models ??
            (source == null
                ? null
                : StaticModelCatalog(
                    source.initial.config!.providers,
                    logger: logger,
                  )),
      ),
      config:
          source?.initial.config ??
          config ??
          CoreConfig(defaultModel: subagentTestModel),
      streamFunction: _route,
      modelsFor: source == null
          ? null
          : (config) => (
              stream: _route,
              catalog: StaticModelCatalog(config.providers, logger: logger),
            ),
    );
  }

  final FakeClock clock;
  final MemorySessionStore store;
  final logger = RecordingLogger();
  late final BuiltAgentCore core;
  late AgentSession session;

  /// События корневой сессии в порядке прихода.
  final events = <AgentEvent>[];

  /// Все запросы к модели в порядке прихода.
  final contexts = <LlmContext>[];

  /// Запросы по ключу скрипта (текст первого user-сообщения).
  final requests = <String, List<LlmContext>>{};

  final _scripts = <String, ScriptedStreamFunction>{};
  final _missing = ScriptedStreamFunction.fromJson(const {'steps': []});

  /// Скрипт по ключу, чтобы тест мог вызвать `verify()`.
  ScriptedStreamFunction scriptOf(String key) => _scripts[key]!;

  AssistantMessageEventStream _route(
    ModelRef ref,
    LlmContext context, {
    CancelToken? cancel,
  }) {
    contexts.add(context);
    final key = firstUserText(context);
    requests.putIfAbsent(key, () => []).add(context);
    return (_scripts[key] ?? _missing).call(ref, context, cancel: cancel);
  }

  /// Создаёт корневую сессию и подписывается на её события.
  Future<AgentSession> open({
    String cwd = '/proj',
    SessionHostPorts ports = const SessionHostPorts(),
  }) async {
    session = await core.runtime.createSession(
      SessionSpec(cwd: cwd, ports: ports),
    );
    session.events.listen(events.add);
    return session;
  }

  /// Открывает сохранённую корневую сессию [id] и подписывается на события.
  Future<AgentSession> load(
    SessionId id, {
    SessionHostPorts ports = const SessionHostPorts(),
    String? cwd,
  }) async {
    session = await core.runtime.loadSession(id, ports, cwd: cwd);
    session.events.listen(events.add);
    return session;
  }

  /// Ход корня с текстом [text].
  Future<TurnResult> run(String text, {CancelToken? cancel}) =>
      session.prompt([TextContent(text)], cancel: cancel);

  List<LlmContext> requestsOf(String key) => requests[key] ?? const [];

  /// События типа [T] в порядке прихода.
  List<T> eventsOf<T extends AgentEvent>() => events.whereType<T>().toList();

  /// Короткие описания событий корня: для проверки порядка.
  List<String> get trace => [for (final e in events) traceOf(e)];

  /// Журнал корневой сессии текстом JSONL.
  String get rootJournal => store.textOf(session.id)!;
}

/// Текст первого user-сообщения запроса: ключ скрипта.
String firstUserText(LlmContext context) {
  final first = context.messages.whereType<UserMessage>().first;
  return first.content.whereType<TextContent>().map((b) => b.text).join('\n');
}

/// Имена схем запроса в порядке запроса.
List<String> toolNamesOf(LlmContext context) => [
  for (final tool in context.tools) tool.name,
];

/// Схема инструмента [name] запроса.
ToolSchema schemaOf(LlmContext context, String name) =>
    context.tools.singleWhere((t) => t.name == name);

/// Текст результата вызова [toolCallId] в сообщениях запроса.
String resultText(LlmContext context, String toolCallId) => context.messages
    .whereType<ToolResultMessage>()
    .singleWhere((m) => m.toolCallId == toolCallId)
    .content
    .whereType<TextContent>()
    .map((b) => b.text)
    .join('\n');

/// `isError` результата вызова [toolCallId] в сообщениях запроса.
bool resultIsError(LlmContext context, String toolCallId) => context.messages
    .whereType<ToolResultMessage>()
    .singleWhere((m) => m.toolCallId == toolCallId)
    .isError;

/// Короткое описание события: `ToolCallStarted(c1)`, `TurnEnded(cancelled)`.
///
/// Только события, которые есть в иерархии до change; события субагентов
/// описываются тестами сами, по полям.
String traceOf(AgentEvent e) => switch (e) {
  ToolCallStarted(:final toolCallId) => 'ToolCallStarted($toolCallId)',
  ToolCallFinished(:final toolCallId, :final outcome) =>
    'ToolCallFinished($toolCallId ${outcome.name})',
  TurnEnded(:final reason) => 'TurnEnded(${reason.name})',
  TaskListChanged() => 'TaskListChanged',
  _ => e.runtimeType.toString(),
};

/// Шаг ответа с несколькими вызовами инструментов: `(id, имя, аргументы)`.
Map<String, Object?> multiCallStep(
  List<(String, String, Map<String, Object?>)> calls, {
  Map<String, Object?>? usage,
  int? delayMs,
}) => {
  'reply': [
    for (final (id, name, args) in calls)
      {
        'toolCall': {'id': id, 'name': name, 'arguments': args},
      },
  ],
  'usage': ?usage,
  'delayMs': ?delayMs,
};

/// Шаг с одним вызовом.
Map<String, Object?> oneCallStep(
  String id,
  String name,
  Map<String, Object?> args, {
  Map<String, Object?>? usage,
  int? delayMs,
}) => multiCallStep([(id, name, args)], usage: usage, delayMs: delayMs);

/// Шаг с текстовым ответом.
Map<String, Object?> replyStep(
  String text, {
  Map<String, Object?>? usage,
  int? delayMs,
}) => {
  'reply': [
    {'text': text},
  ],
  'usage': ?usage,
  'delayMs': ?delayMs,
};

/// Аргументы вызова `agent`.
Map<String, Object?> agentArgs(
  String prompt, {
  String description = 'Do the work',
  String? type,
  String? task,
}) => {
  'description': description,
  'prompt': prompt,
  'type': ?type,
  'task': ?task,
};

/// Определение агента из markdown-файла пользователя (как в
/// `agent_select_test.dart`): [scope] — `session | subagent | both`.
MarkdownFile agentFile(
  String name, {
  String scope = 'both',
  String body = 'Do it carefully.',
  Map<String, Object?> extra = const {},
}) => MarkdownFile(
  path: '/home/.codelab/agents/$name.md',
  scope: ExtensionScope.user,
  body: body,
  bodyLine: 6,
  frontmatter: ConfigTree(
    kind: ConfigLayerKind.user,
    source: '/home/.codelab/agents/$name.md',
    values: {
      'name': name,
      'description': 'The $name agent',
      'scope': scope,
      ...extra,
    },
  ),
);

/// Порт файлов проекта с фиксированным набором определений агентов.
final class AgentsPort implements ProjectFilesSource {
  AgentsPort(this.agents);

  final List<MarkdownFile> agents;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(agents: agents);
}

/// Конфигурация корня с режимом [mode] и бюджетом хода [budget].
///
/// Разделы `subagents` тест задаёт сам: `CoreConfig(defaultModel: subagentTestModel,
/// subagents: SubagentsConfig(...))`.
CoreConfig rigConfig({
  ModeId? mode,
  PermissionsConfig? permissions,
  TurnBudget budget = const TurnBudget(),
}) => CoreConfig(
  defaultModel: subagentTestModel,
  permissions: permissions ?? PermissionsConfig(mode: mode),
  budget: budget,
);

/// Крутит очередь событий, пока не выполнится [condition].
///
/// Почему: «ребёнок дошёл до ожидания таймера» наступает через несколько
/// асинхронных шагов ядра (слот, журнал, запрос к модели); число оборотов
/// очереди — деталь реализации, поэтому тест ждёт наблюдаемого условия, а не
/// `Future.delayed` и не магического числа. Бесконечного ожидания нет: после
/// [limit] оборотов тест падает с [reason].
Future<void> pumpUntil(
  bool Function() condition, {
  String reason = 'condition was not reached',
  int limit = 500,
}) async {
  for (var i = 0; i < limit; i++) {
    if (condition()) {
      return;
    }
    await pumpEventQueue(times: 5);
  }
  fail('pumpUntil: $reason');
}

/// Источник конфигурации с изменяемым слоем пользователя: `load()` — настоящий
/// `CoreConfig.fromLayers`, как у файлового источника, без файлов.
///
/// Как использовать: `source.user['subagents'] = {...}`, затем
/// `await runtime.reloadConfig()` — рантайм применяет новый снимок
/// (agent-runtime «Живая перезагрузка конфигурации»; CFG-15).
final class LayeredConfigSource implements ConfigSource {
  LayeredConfigSource([Map<String, Object?>? user])
    : user = user ?? windowedValues(baseValues()) {
    _initial = _load();
  }

  /// Слой пользователя; тест правит его между перезагрузками.
  final Map<String, Object?> user;
  late ConfigLoadResult _initial;

  ConfigLoadResult _load() {
    final result = CoreConfig.fromLayers([layer(user)], environment: const {});
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    return result;
  }

  @override
  ConfigLoadResult get initial => _initial;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async => _load();

  @override
  Stream<void> get changes => const Stream.empty();
}

/// `baseValues` с моделью, чьё окно проходит порог `agent` (D40).
Map<String, Object?> windowedValues(Map<String, Object?> values) => {
  ...values,
  'providers': {
    'p': {
      'kind': 'openai-compatible',
      'base_url': 'https://llm.test/v1',
      'models': {
        'm': {'context_window': 65536},
      },
    },
  },
};
