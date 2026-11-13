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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  // acp-golden-fixtures «Фикстуры файлов проекта этапа 8»: ключ
  // `trusted_projects` фабрика принимает, любой другой неизвестный ключ
  // остаётся громким провалом (design.md change `add-agent-project-files`,
  // D15): молча проигнорированная настройка сделала бы фикстуру ложно
  // зелёной.
  test('the factory still rejects an unknown config key', () async {
    for (final config in <Map<String, Object?>>[
      {
        'trusted_projects': [r'${cwd}'],
        'bogus': 1,
      },
      {'bogus': 1},
    ]) {
      final source = loadFixtureCorpus().firstWhere(
        (f) => f.id == 'acp/prompt-text-end-turn',
      );
      final json =
          jsonDecode(File(source.sourcePath!).readAsStringSync())
              as Map<String, Object?>;
      json['id'] = 'acp/unknown-config-key';
      (json['setup']! as Map<String, Object?>)['config'] = config;
      final fixture = AcpFixture.fromJson(
        json,
        fileName: 'unknown-config-key.json',
      );

      await expectLater(
        runAgentFixture(fixture, startAgent),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('config.bogus'),
          ),
        ),
      );
    }
  });

  // acp-golden-fixtures «Фикстуры файлов проекта этапа 8»: сервер
  // `mcp.servers` с `command`, которого нет среди `setup.mcp`, или с
  // `type` не `stdio` — громкий провал, а не запуск настоящего процесса.
  test('the factory rejects an mcp.servers entry that is not a fake', () async {
    for (final (server, fragment) in <(Map<String, Object?>, String)>[
      (
        {'name': 'x', 'type': 'stdio', 'command': 'npx'},
        'config.mcp.servers[0].command',
      ),
      (
        {'name': 'x', 'type': 'http', 'command': 'fake'},
        'config.mcp.servers[0].type',
      ),
      (
        {'name': 'x', 'type': 'stdio', 'command': 'fake', 'url': 'u'},
        'config.mcp.servers[0].url',
      ),
    ]) {
      final source = loadFixtureCorpus().firstWhere(
        (f) => f.id == 'acp/session-new-with-mcp',
      );
      final json =
          jsonDecode(File(source.sourcePath!).readAsStringSync())
              as Map<String, Object?>;
      json['id'] = 'acp/mcp-config-not-fake';
      (json['setup']! as Map<String, Object?>)['config'] = {
        'mcp': {
          'servers': [server],
        },
      };
      final fixture = AcpFixture.fromJson(
        json,
        fileName: 'mcp-config-not-fake.json',
      );

      await expectLater(
        runAgentFixture(fixture, startAgent),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(fragment),
          ),
        ),
      );
    }
  });

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
  // Пустой `$CODELAB_HOME` на прогон: шаблоны пользователя фикстуры не
  // читают, а настоящий `~/.codelab` разработчика не должен влиять на кадры
  // (design.md change `add-agent-project-files`, D15, D16).
  final home = Directory.systemTemp.createTempSync('agent_fixture_home_');
  final projectFiles = ProjectFilesLoader(
    home: home.path,
    local: LocalExecutionEnv(cwd: setup.cwd),
  );
  final core = buildAgentCore(
    profile: HostProfile.of(setup.profile),
    services: AgentCoreServices(
      baseEnv: LocalExecutionEnv(cwd: setup.cwd),
      // Сессии спрашивают через AcpPermissionGate соединения.
      gate: const _HostGate(),
      logger: logger,
      clock: clock,
      ids: SequentialIdGenerator(),
      sessions: store,
      // Один загрузчик отдаёт и файлы проекта, и навыки (design.md change
      // `add-agent-skills`, D3, D16): фикстуры `acp/skill-*` кладут навыки в
      // `setup.files` под `.codelab/skills/`.
      projectFiles: projectFiles,
      skillFiles: projectFiles,
      models: FixedModelCatalog(config.models),
      // Коннектор есть всегда: `mcpCapabilities.http` в `initialize` зависит
      // от него (design.md change `add-agent-mcp-client`, D11), а серверы
      // фикстуры берутся из `setup.mcp`.
      mcp: McpClientConnector(
        transports: McpTransports(
          // Серверы конфига идут к fake-серверу по `command`, серверы клиента
          // — по `name` (acp-golden-fixtures «Фикстуры файлов проекта этапа
          // 8»).
          stdio: _ConfigServerRouting(mcp.transports),
          // HTTP-сервер фикстуры — настоящий `StreamableHttpTransport` на
          // `MockClient` над `FakeMcpServer` (D15, задача 9.5).
          http: StreamableHttpTransportFactory(
            client: mcp.httpClient(),
            clock: clock,
          ),
        ),
        clock: clock,
      ),
    ),
    config: CoreConfig(
      defaultModel: config.defaultModel,
      effort: config.effort,
      budget: config.budget,
      compaction: config.compaction,
      trustedProjects: config.trustedProjects,
      mcpServers: config.mcpServers,
      skills: config.skills,
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
  return _ServedAgent(server, model, mcp, home);
}

final class _ServedAgent implements AgentUnderTest {
  _ServedAgent(this._server, this._model, this._mcp, this._home);

  final AcpAgentServer _server;
  final ScriptedStreamFunction _model;
  final _FixtureMcp _mcp;
  final Directory _home;

  @override
  void verify() {
    _model.verify();
    _mcp.verify();
  }

  @override
  Future<void> stop() async {
    await _server.shutdown(grace: Duration.zero);
    _home.deleteSync(recursive: true);
  }
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
/// `providers.<id>.models.<model>` (`context_window`, `reasoning`),
/// `skills` (`enabled`, `disabled`, `max_skills`, `catalog_max_chars`),
/// `trusted_projects` (список путей, `${cwd}` — временный `cwd` прогона:
/// доверие проекту, файлы которого лежат в `setup.files`; фикстуры этапа 8,
/// design.md change `add-agent-project-files`, D15).
/// Другой ключ — громкий провал: молча проигнорированная настройка сделала
/// бы фикстуру ложно зелёной.
final class _FixtureConfig {
  _FixtureConfig({
    required this.defaultModel,
    required this.models,
    required this.effort,
    required this.budget,
    required this.compaction,
    required this.trustedProjects,
    required this.mcpServers,
    required this.skills,
  });

  factory _FixtureConfig.parse(AgentFixtureSetup setup) {
    final config = setup.config;
    _keys(config, const {
      'agent',
      'budget',
      'compaction',
      'mcp',
      'providers',
      'skills',
      'trusted_projects',
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
    final trusted = switch (config['trusted_projects']) {
      null => const <String>[],
      final List<Object?> paths => [
        for (final path in paths)
          if (path is String)
            path.replaceAll(r'${cwd}', setup.cwd)
          else
            throw FormatException('config.trusted_projects: $path'),
      ],
      final value => throw FormatException('config.trusted_projects: $value'),
    };
    return _FixtureConfig(
      trustedProjects: trusted,
      mcpServers: _mcpServers(config['mcp'], setup),
      skills: _skills(config['skills']),
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
  final List<String> trustedProjects;

  /// Серверы `mcp.servers` (`origin: config`) для `CoreConfig.mcpServers`.
  final List<McpServerConfig> mcpServers;

  /// Раздел `skills` для `CoreConfig.skills`.
  final SkillsConfig skills;

  /// Ключ `skills` (acp-golden-fixtures «Фикстуры навыков»; design.md change
  /// `add-agent-skills`, D11): `enabled`, `disabled`, `max_skills`,
  /// `catalog_max_chars`.
  ///
  /// `extra_roots` драйвер не принимает: корень вне временного `cwd` сделал
  /// бы прогон зависимым от файлов разработчика — громкий провал, как у
  /// прочих неподдержанных ключей.
  static SkillsConfig _skills(Object? raw) {
    final skills = _object(raw, 'config.skills');
    _keys(skills, const {
      'enabled',
      'disabled',
      'max_skills',
      'catalog_max_chars',
    }, 'config.skills');
    const defaults = SkillsConfig();
    return SkillsConfig(
      enabled: skills['enabled'] as bool? ?? defaults.enabled,
      disabled: [...?(skills['disabled'] as List<Object?>?)?.cast<String>()],
      maxSkills: skills['max_skills'] as int? ?? defaults.maxSkills,
      catalogMaxChars:
          skills['catalog_max_chars'] as int? ?? defaults.catalogMaxChars,
    );
  }

  /// Ключ `mcp.servers` (design.md change `add-config-writer-and-reload`,
  /// D12; acp-golden-fixtures «Фикстуры файлов проекта этапа 8»).
  ///
  /// Почему так строго: сервер конфига фикстуры подключается только к
  /// fake-серверу из `setup.mcp`. Другой `command` или `type` — громкий
  /// провал, иначе фикстура запускала бы настоящий процесс или молча
  /// теряла сервер. Поля элемента: `name`, `type` (`stdio`), `command`,
  /// `args`, `env`, `enabled`.
  static List<McpServerConfig> _mcpServers(
    Object? raw,
    AgentFixtureSetup setup,
  ) {
    final mcp = _object(raw, 'config.mcp');
    _keys(mcp, const {'servers'}, 'config.mcp');
    final servers = switch (mcp['servers']) {
      null => const <Object?>[],
      final List<Object?> list => list,
      final value => throw FormatException('config.mcp.servers: $value'),
    };
    return [
      for (final (index, item) in servers.indexed)
        _mcpServer(_object(item, 'config.mcp.servers[$index]'), index, setup),
    ];
  }

  static McpServerConfig _mcpServer(
    Map<String, Object?> item,
    int index,
    AgentFixtureSetup setup,
  ) {
    final path = 'config.mcp.servers[$index]';
    _keys(item, const {
      'name',
      'type',
      'command',
      'args',
      'env',
      'enabled',
    }, path);
    if (item['type'] != 'stdio') {
      throw FormatException(
        '$path.type: the fixture driver supports only "stdio"',
      );
    }
    final command = item['command'];
    if (command is! String || !setup.mcp.containsKey(command)) {
      throw FormatException(
        '$path.command: must be the name of a setup.mcp fake server '
        '(${setup.mcp.keys.join(', ')}), got $command',
      );
    }
    return McpStdioServerConfig(
      name: item['name']! as String,
      command: command,
      args: [...?(item['args'] as List<Object?>?)?.cast<String>()],
      env: {...?(item['env'] as Map<String, Object?>?)?.cast<String, String>()},
      origin: McpServerOrigin.config,
      enabled: item['enabled'] as bool? ?? true,
    );
  }

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

  /// Клиент HTTP, который направляет запрос серверу по первой метке хоста
  /// (`https://<имя>.mcp.test/mcp`): `url` кадра `session/new` другого
  /// способа выбрать fake-сервер не даёт (D15). Отката «единственный сервер»
  /// нет: он маскировал бы неверный url фикстуры.
  http.Client httpClient() => MockClient.streaming((request, body) {
    final name = request.url.host.split('.').first;
    final server = servers[name];
    if (server == null) {
      throw http.ClientException(
        'fixture error: no setup.mcp server "$name" for ${request.url}; '
        'use https://<name>.mcp.test/mcp',
      );
    }
    return server.handleHttp(request, body);
  });

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

/// Направляет stdio-сервер конфига к fake-серверу по `command`, а сервер
/// клиента ACP — по `name`, как раньше.
///
/// Почему: `FakeMcpTransportFactory` ищет fake по имени сервера, а фикстура
/// `mcp.servers` называет fake в `command` (acp-golden-fixtures «Фикстуры
/// файлов проекта этапа 8»), и имя сервера конфига может отличаться от него.
final class _ConfigServerRouting implements McpTransportFactory {
  _ConfigServerRouting(this._inner);

  final McpTransportFactory _inner;

  @override
  Set<String> get transports => _inner.transports;

  @override
  Future<McpTransport> open(
    McpServerConfig server, {
    required String cwd,
    required CancelToken cancel,
    required Logger logger,
  }) {
    final routed = switch (server) {
      McpStdioServerConfig(origin: McpServerOrigin.config) =>
        McpStdioServerConfig(
          name: server.command,
          command: server.command,
          args: server.args,
          env: server.env,
          origin: server.origin,
          connectTimeout: server.connectTimeout,
          callTimeout: server.callTimeout,
          secretValues: server.secretValues,
          enabled: server.enabled,
        ),
      _ => server,
    };
    return _inner.open(routed, cwd: cwd, cancel: cancel, logger: logger);
  }
}
