import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show Implementation;
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart' show JournalStore;

/// Conformance агента на корпусе golden-фикстур (задача 9.5; §14.9;
/// acp-golden-fixtures «Агентский драйвер фикстур»).
///
/// Агент поднимается так же, как бинарь по stdio: профиль фикстуры,
/// файлы и команды — через клиента (`AcpClientExecutionEnv`), листинг —
/// локально (`LocalExecutionEnv` над временным `cwd` драйвера). Расхождение
/// исправляется в коде агента; фикстура меняется только со ссылкой на
/// спецификацию (acp-golden-fixtures «Правила изменения фикстур»).
void main() {
  for (final fixture in loadFixtureCorpus()) {
    test(fixture.id, () async {
      final result = await runAgentFixture(fixture, startAgent);
      if (result.skipped) {
        markTestSkipped(result.skipReason!);
      }
    });
  }

  // acp-golden-fixtures «Формат golden-фикстуры ACP», сценарий «Лишний
  // вызов MCP-сервера»: `after.mcpCalls` проверяет `verify()` фабрики.
  test(
    'an unexpected tools/call of a fake MCP server fails verify()',
    () async {
      final source = loadFixtureCorpus().firstWhere(
        (f) => f.id == 'acp/mcp-stdio-tool-call',
      );
      final json =
          jsonDecode(File(source.sourcePath!).readAsStringSync())
              as Map<String, Object?>;
      json['id'] = 'acp/mcp-extra-call';
      json['after'] = {
        'mcpCalls': {'fake': <Object?>[]},
      };
      final fixture = AcpFixture.fromJson(
        json,
        fileName: 'mcp-extra-call.json',
      );

      await expectLater(
        runAgentFixture(fixture, startAgent),
        throwsA(
          isA<AgentFixtureFailure>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('fake'), contains('echo')),
          ),
        ),
      );
    },
  );
}

/// Фабрика агента для драйвера (§14.9, шаг 5).
Future<AgentUnderTest> startAgent(
  AcpTransport transport,
  AgentFixtureSetup setup,
) async {
  final clock = FakeClock();
  final logger = RecordingLogger();
  final config = _FixtureConfig.parse(setup);
  final store = JournalStore();
  // setup.sessions: состояние журнала, которого не получить кадрами
  // (прерванный ход, §8.8).
  for (final MapEntry(key: id, value: records) in setup.sessions.entries) {
    await store.create(SessionHeader.fromJson(records.first));
    for (final record in records.skip(1)) {
      await store.append(SessionId(id), SessionRecord.fromJson(record));
    }
  }
  final model = ScriptedStreamFunction.fromJson(
    setup.llm ?? const {'steps': <Object?>[]},
    clock: clock,
    cwd: setup.cwd,
  );
  final mcp = _FixtureMcp(setup);
  final core = buildAgentCore(
    // Как бинарь до итерации 3: HTTP-транспорта нет, `mcpCapabilities.http`
    // — `false` (задача 8.2; переход на `true` — задачи 9.5–9.6).
    profile: HostProfile.of(setup.profile).narrowed(const {
      HostCapability.mcp: CapabilityTransport({
        'stdio',
      }, 'HTTP-транспорт — итерация 3'),
    }),
    services: AgentCoreServices(
      baseEnv: LocalExecutionEnv(cwd: setup.cwd),
      // Сессии спрашивают через AcpPermissionGate соединения.
      gate: const _HostGate(),
      logger: logger,
      clock: clock,
      ids: SequentialIdGenerator(),
      sessions: store,
      models: FixedModelCatalog(config.models),
      // Коннектор есть всегда: `mcpCapabilities.http` в `initialize` зависит
      // от него (design.md change `add-agent-mcp-client`, D11), а серверы
      // фикстуры берутся из `setup.mcp`.
      mcp: McpClientConnector(
        transports: McpTransports(stdio: mcp.transports),
        clock: clock,
      ),
    ),
    config: CoreConfig(
      defaultModel: config.defaultModel,
      effort: config.effort,
      budget: config.budget,
      compaction: config.compaction,
      permissions: PermissionsConfig(
        mode: setup.mode == null ? null : ModeId.parse(setup.mode!),
      ),
    ),
    streamFunction: model.call,
  );
  final server = AcpAgentServer(
    core: core,
    config: AcpServerConfig(
      agentInfo: const Implementation(
        name: 'codelab-agent',
        title: 'CodeLab Agent',
        version: '0.1.0',
      ),
      localListing: (cwd) => LocalExecutionEnv(cwd: cwd),
    ),
    logger: logger,
    clock: clock,
  );
  unawaited(server.serve(transport));
  return _ServedAgent(server, model, mcp);
}

final class _ServedAgent implements AgentUnderTest {
  _ServedAgent(this._server, this._model, this._mcp);

  final AcpAgentServer _server;
  final ScriptedStreamFunction _model;
  final _FixtureMcp _mcp;

  @override
  void verify() {
    _model.verify();
    _mcp.verify();
  }

  @override
  Future<void> stop() => _server.shutdown(grace: Duration.zero);
}

/// Gate хоста для сборки: включает `interactiveApproval`, а вопросы идут
/// через gate соединения.
final class _HostGate implements PermissionGate {
  const _HostGate();

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) => throw StateError('the server must use AcpPermissionGate');
}

/// Фрагмент конфига фикстуры (§15) в объёме, который читают фикстуры
/// этапов 0 и 4: `agent.default_model`, `agent.effort`, `budget.max_steps`,
/// `budget.max_tokens`, `compaction.keep_recent_tokens`,
/// `providers.<id>.models.<model>` (`context_window`, `reasoning`). Другой
/// ключ — громкий провал: молча проигнорированная настройка сделала бы
/// фикстуру ложно зелёной.
final class _FixtureConfig {
  _FixtureConfig({
    required this.defaultModel,
    required this.models,
    required this.effort,
    required this.budget,
    required this.compaction,
  });

  factory _FixtureConfig.parse(AgentFixtureSetup setup) {
    final config = setup.config;
    _keys(config, const {
      'agent',
      'budget',
      'compaction',
      'providers',
    }, 'config');
    final agent = _object(config['agent'], 'config.agent');
    _keys(agent, const {'default_model', 'effort'}, 'config.agent');
    final budget = _object(config['budget'], 'config.budget');
    _keys(budget, const {'max_steps', 'max_tokens'}, 'config.budget');
    final compaction = _object(config['compaction'], 'config.compaction');
    _keys(compaction, const {'keep_recent_tokens'}, 'config.compaction');
    final llmModel = _object(setup.llm?['model'], 'llm.model');
    final scripted = _model(
      llmModel['provider'] as String? ?? 'scripted',
      llmModel['modelId'] as String? ?? 'scripted-1',
      {'context_window': llmModel['contextWindow'] ?? 32768},
    );
    // Каталог — модели конфига; модель llm.model входит в него, только
    // если она модель по умолчанию (нет agent.default_model).
    final models = <ModelRef>[];
    final providers = _object(config['providers'], 'config.providers');
    for (final MapEntry(key: provider, value: raw) in providers.entries) {
      final entry = _object(raw, 'config.providers.$provider');
      _keys(entry, const {'models'}, 'config.providers.$provider');
      final declared = _object(
        entry['models'],
        'config.providers.$provider.models',
      );
      for (final MapEntry(key: id, value: info) in declared.entries) {
        final path = 'config.providers.$provider.models.$id';
        final fields = _object(info, path);
        _keys(fields, const {'context_window', 'reasoning'}, path);
        models
          ..removeWhere((m) => m.provider == provider && m.id == id)
          ..add(_model(provider, id, fields));
      }
    }
    final defaultId = agent['default_model'] as String?;
    var defaultModel = scripted;
    if (defaultId == null) {
      models.removeWhere(
        (m) => m.provider == scripted.provider && m.id == scripted.id,
      );
      models.add(scripted);
    } else {
      final slash = defaultId.indexOf('/');
      final provider = defaultId.substring(0, slash);
      final id = defaultId.substring(slash + 1);
      defaultModel = models.firstWhere(
        (m) => m.provider == provider && m.id == id,
        orElse: () {
          final model = _model(provider, id, const {});
          models.add(model);
          return model;
        },
      );
    }
    // Модель по умолчанию — первой в списке опции model (§13.6).
    models
      ..remove(defaultModel)
      ..insert(0, defaultModel);
    return _FixtureConfig(
      defaultModel: defaultModel,
      models: models,
      effort: switch (agent['effort']) {
        null => ReasoningEffort.medium,
        final String value => ReasoningEffort.values.byName(value),
        final value => throw FormatException('config.agent.effort: $value'),
      },
      compaction: CompactionOverrides(
        keepRecentTokens: compaction['keep_recent_tokens'] as int?,
      ),
      budget: TurnBudget(
        maxSteps: budget['max_steps'] as int? ?? 50,
        maxTokens: budget['max_tokens'] as int?,
      ),
    );
  }

  final ModelRef defaultModel;
  final List<ModelRef> models;
  final ReasoningEffort effort;
  final TurnBudget budget;
  final CompactionOverrides compaction;

  static ModelRef _model(
    String provider,
    String id,
    Map<String, Object?> fields,
  ) => ModelRef(
    provider: provider,
    id: id,
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: fields['context_window'] as int? ?? 32768,
    maxOutputTokens: 4096,
    supportsReasoning: fields['reasoning'] as bool? ?? false,
  );

  static Map<String, Object?> _object(Object? value, String path) =>
      switch (value) {
        null => const {},
        final Map<String, Object?> map => map,
        _ => throw FormatException('$path must be an object'),
      };

  static void _keys(Map<String, Object?> map, Set<String> known, String path) {
    for (final key in map.keys) {
      if (!known.contains(key)) {
        throw FormatException(
          '$path.$key: the fixture driver does not support this key',
        );
      }
    }
  }
}

/// Fake MCP-серверы фикстуры: `setup.mcp` → `FakeMcpServer`, `after.mcpCalls`
/// → проверка в `verify()` (design.md change `add-agent-mcp-client`, D15).
///
/// Почему здесь, а не в драйвере: `codelab_acp_testing` не зависит от
/// пакетов агента и MCP; он лишь отдаёт данные фабрике.
final class _FixtureMcp {
  _FixtureMcp(AgentFixtureSetup setup)
    : _expected = setup.after?.mcpCalls ?? const {} {
    for (final MapEntry(key: name, value: description) in setup.mcp.entries) {
      servers[name] = FakeMcpServer(
        era: switch (description.era) {
          FixtureMcpEra.modern => FakeMcpEra.modern,
          FixtureMcpEra.legacy => FakeMcpEra.legacy,
        },
        tools: [for (final tool in description.tools) _tool(tool)],
        responses: {
          for (final MapEntry(key: tool, value: result)
              in description.results.entries)
            tool: FakeToolResponse.result(result),
        },
      );
    }
    transports = FakeMcpTransportFactory(servers);
  }

  final Map<String, List<FixtureMcpCall>> _expected;
  final servers = <String, FakeMcpServer>{};
  late final FakeMcpTransportFactory transports;

  static FakeMcpTool _tool(Map<String, Object?> json) => FakeMcpTool(
    json['name']! as String,
    title: json['title'] as String?,
    description: json['description'] as String?,
    inputSchema: json['inputSchema'] ?? const {'type': 'object'},
    annotations: json['annotations'] as Map<String, Object?>?,
    extra: {
      for (final MapEntry(:key, :value) in json.entries)
        if (!const {
          'name',
          'title',
          'description',
          'inputSchema',
          'annotations',
        }.contains(key))
          key: value,
    },
  );

  /// `after.mcpCalls`: точный список `tools/call` каждого сервера.
  void verify() {
    for (final MapEntry(key: name, value: expected) in _expected.entries) {
      final server = servers[name];
      if (server == null) {
        throw StateError(
          'after.mcpCalls names the MCP server "$name" that setup.mcp lacks',
        );
      }
      final actual = [
        for (final call in server.calls)
          '${call['name']} ${jsonEncode(call['arguments'])}',
      ];
      final wanted = [
        for (final call in expected)
          '${call.name} ${jsonEncode(call.arguments)}',
      ];
      if (jsonEncode(actual) != jsonEncode(wanted)) {
        throw StateError(
          'MCP server "$name": expected tools/call $wanted, got $actual',
        );
      }
    }
  }
}
