import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

import '../config/config_support.dart' show layer;
import '../host/core_harness.dart' show inMemoryJournal, noExec, textStep;
import '../mcp/fake_mcp_connector.dart';
import '../permissions/fake_gate.dart';
import 'manual_stream.dart';

/// Литералы вложенных карт выводятся как `Map<String, String>`, а загрузчик
/// отдаёт `Map<String, Object?>`: слияние слоёв различает их, поэтому тесты
/// приводят дерево к типу загрузчика.
Map<String, Object?> norm(Map<String, Object?> source) => {
  for (final MapEntry(:key, :value) in source.entries)
    key: switch (value) {
      final Map<dynamic, dynamic> map => norm(map.cast<String, Object?>()),
      _ => value,
    },
};

/// Глобальный слой тестов конфигурации сессии: провайдер `p` с моделью `m`.
Map<String, Object?> baseUser() => norm({
  'providers': {
    'p': {
      'kind': 'openai-compatible',
      'base_url': 'https://p.test/v1',
      'models': {'m': <String, Object?>{}},
    },
  },
  'agent': {'default_model': 'p/m'},
});

/// Проектный провайдер `local` с моделями `m` и `m2` и модель по умолчанию из
/// него: так «This project only» проекта попадает в `config.local.yaml`.
Map<String, Object?> localProvider({String id = 'local'}) => norm({
  'providers': {
    id: {
      'kind': 'openai-compatible',
      'base_url': 'https://$id.test/v1',
      'models': {'m': <String, Object?>{}, 'm2': <String, Object?>{}},
    },
  },
  'agent': {'default_model': '$id/m'},
});

/// Доверенные проекты, закреплённые при старте (как `initial` настоящего
/// источника): `/A`, `/B`, `/C`.
const trustedRoots = ['/A', '/B', '/C'];

/// Результат загрузки папки [path] из слоёв: глобальный, `config.yaml` и
/// `config.local.yaml`. Строится настоящим `CoreConfig.fromLayers`, поэтому
/// доверие и ограничения слоёв — те же, что в продукте.
ConfigLoadResult folderResult(
  String path, {
  Map<String, Object?>? user,
  Map<String, Object?> project = const {},
  Map<String, Object?> local = const {},
  bool trusted = true,
}) => CoreConfig.fromLayers(
  [
    layer(user ?? baseUser()),
    if (project.isNotEmpty)
      layer(
        norm(project),
        kind: ConfigLayerKind.project,
        source: '$path/.codelab/config.yaml',
      ),
    if (local.isNotEmpty)
      layer(
        norm(local),
        kind: ConfigLayerKind.projectLocal,
        source: '$path/.codelab/config.local.yaml',
      ),
  ],
  environment: const {},
  projectRoot: path,
  pinnedTrustedProjects: trusted ? trustedRoots : const ['/A'],
);

/// Порт `ProjectConfigLoader` для тестов: карта «папка → результат», счётчик
/// вызовов, записанные пути и управляемый `Completer` на папку.
final class FakeProjectConfigLoader implements ProjectConfigLoader {
  /// Результат на каждый вызов: функция, чтобы тест менял его между
  /// сессиями (кэша быть не должно).
  final results = <String, ConfigLoadResult Function()>{};

  /// Вызовы в порядке поступления: каноническая папка.
  final calls = <String>[];

  /// Пока `Completer` папки не завершён, `loadForProject` ждёт.
  final gates = <String, Completer<void>>{};

  /// Завершается при первом вызове на папку: тест знает, что сессия дошла до
  /// порта, и не ждёт `Future.delayed`.
  final entered = <String, Completer<void>>{};

  Completer<void> enteredOf(String path) =>
      entered.putIfAbsent(path, Completer.new);

  Object? throwOn;

  @override
  Future<ConfigLoadResult> loadForProject(String canonicalCwd) async {
    calls.add(canonicalCwd);
    if (!enteredOf(canonicalCwd).isCompleted) {
      enteredOf(canonicalCwd).complete();
    }
    if (gates[canonicalCwd] case final gate?) {
      await gate.future;
    }
    if (throwOn case final error?) {
      throw error;
    }
    final result = results[canonicalCwd];
    if (result == null) {
      throw StateError('no result for $canonicalCwd');
    }
    return result();
  }
}

/// Окружение с символическими ссылками поверх памяти: `realpath` раскрывает
/// [links], остальные пути возвращает нормализованными.
final class LinkingEnv implements ExecutionEnv, DirectoryListing, PathResolver {
  LinkingEnv([this.links = const {}]);

  final Map<String, String> links;
  final _inner = MemoryExecutionEnv(cwd: '/A');

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async {
    var key = path;
    while (key.length > 1 && key.endsWith('/')) {
      key = key.substring(0, key.length - 1);
    }
    return Ok(links[key] ?? key);
  }

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => _inner.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      _inner.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => _inner.stat(path);

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) =>
      _inner.listDir(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}

/// Источник конфигурации корня: `initial` и управляемая загрузка.
final class FakeRootSource implements ConfigSource {
  FakeRootSource(this.initial, this.next);

  @override
  final ConfigLoadResult initial;

  /// Результат очередной загрузки.
  ConfigLoadResult Function() next;

  /// Если задан, `load` ждёт его (порядок завершений задаёт тест).
  Completer<void>? gate;

  final loadStarted = Completer<void>();

  /// Сколько раз вызывалась `load` (проверка и перезагрузка).
  var loads = 0;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async {
    loads++;
    if (!loadStarted.isCompleted) {
      loadStarted.complete();
    }
    if (gate case final gate?) {
      await gate.future;
    }
    return next();
  }

  @override
  Stream<void> get changes => const Stream.empty();
}

/// Ядро с портом конфигурации папки: корень `/A`, фейковые загрузчик, MCP и
/// шлюз разрешений, `modelsFor` с записью конфигураций.
final class ProjectConfigRig {
  ProjectConfigRig._({
    required this.core,
    required this.logger,
    required this.clock,
    required this.loader,
    required this.mcp,
    required this.gate,
    required this.store,
    required this.modelsForCalls,
    required this.streamRoots,
    required this.source,
    required this.manual,
  });

  static ProjectConfigRig create({
    Map<String, Object?> rootProject = const {},
    Map<String, Object?> rootLocal = const {},
    bool withPort = true,
    bool withSource = false,
    bool holdRoot = false,
    ExecutionEnv? env,
    List<Map<String, Object?>>? steps,
    bool Function(CoreConfig config)? failModelsFor,
  }) {
    final clock = FakeClock();
    final logger = RecordingLogger(clock: clock);
    final loader = FakeProjectConfigLoader();
    final mcp = FakeMcpConnector();
    final gate = FakeGate();
    final store = MemorySessionStore();
    final manual = holdRoot ? ManualStream(clock) : null;
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': steps ?? [for (var i = 0; i < 40; i++) textStep('ok')],
    }, clock: clock);
    final modelsForCalls = <CoreConfig>[];
    final streamRoots = <String?>[];

    StreamFunction streamOf(CoreConfig config) => (ref, context, {cancel}) {
      streamRoots.add(config.projectRoot);
      if (manual != null && config.projectRoot == '/A') {
        return manual.call(ref, context, cancel: cancel);
      }
      return scripted.call(ref, context, cancel: cancel);
    };

    ConfiguredModels makeModels(CoreConfig config) {
      if (failModelsFor?.call(config) ?? false) {
        throw StateError('models are not built for ${config.projectRoot}');
      }
      modelsForCalls.add(config);
      return (
        stream: streamOf(config),
        catalog: StaticModelCatalog(config.providers, logger: logger),
      );
    }

    final root = folderResult('/A', project: rootProject, local: rootLocal);
    loader.results['/A'] = () => root;
    final initial = root.config!;
    final models = makeModels(initial);
    final source = withSource ? FakeRootSource(root, () => root) : null;

    final core = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: env ?? LinkingEnv(),
        gate: gate,
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
        models: models.catalog,
        mcp: mcp,
        config: source,
        projectConfig: withPort ? loader : null,
      ),
      config: initial,
      streamFunction: models.stream,
      modelsFor: makeModels,
    );
    return ProjectConfigRig._(
      core: core,
      logger: logger,
      clock: clock,
      loader: loader,
      mcp: mcp,
      gate: gate,
      store: store,
      modelsForCalls: modelsForCalls,
      streamRoots: streamRoots,
      source: source,
      manual: manual,
    );
  }

  final BuiltAgentCore core;
  final RecordingLogger logger;
  final FakeClock clock;
  final FakeProjectConfigLoader loader;
  final FakeMcpConnector mcp;
  final FakeGate gate;
  final MemorySessionStore store;

  /// Конфигурации, по которым строились функции модели и каталоги.
  final List<CoreConfig> modelsForCalls;

  /// Корень конфигурации функции модели, обслужившей каждый запрос.
  final List<String?> streamRoots;
  final FakeRootSource? source;
  final ManualStream? manual;

  AgentRuntime get runtime => core.runtime;

  /// Результат папки [path] и фиксация его в загрузчике.
  void setFolder(
    String path, {
    Map<String, Object?> project = const {},
    Map<String, Object?> local = const {},
    bool trusted = true,
  }) {
    final result = folderResult(
      path,
      project: project,
      local: local,
      trusted: trusted,
    );
    loader.results[path] = () => result;
  }

  Future<AgentSession> session(String cwd) =>
      runtime.createSession(SessionSpec(cwd: cwd));

  /// Модели каталога сессии как `provider/id`.
  static List<String> modelIds(AgentSession session) => [
    for (final m in session.models.models) m.id.value,
  ];
}
