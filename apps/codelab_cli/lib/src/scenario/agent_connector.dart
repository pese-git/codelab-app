import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:codelab_embedded/codelab_embedded.dart' show EmbeddedAgent;
// Сценарий модели встроенного агента: единственное место рабочего кода CLI,
// где разрешён `testing.dart` (правило сторожа; design.md change
// `add-embedded-agent-mode`, D3, D8).
import 'package:codelab_embedded/testing.dart';
import 'package:path/path.dart' as p;

import '../embedded_logger.dart';
import '../profiles/profile_arg.dart';

/// Агент `test-scenario` из профиля подключения: что ему можно передать и
/// как запустить его на фикстуру.
///
/// Почему: драйвер запускает агента заново для каждой фикстуры, а
/// подготовка зависит от агента — `codelab-agent` принимает сценарий
/// модели и режим флагами, агент-повторитель получает путь фикстуры через
/// `{fixture}`, сторонний агент — только профиль как есть (spec
/// cli-scenario-driver «Команда test-scenario»; design.md change
/// `add-codelab-cli`, D12).
///
/// Встроенный агент (`EmbeddedProfile`) открывается в процессе CLI открывателем
/// `scriptedEmbeddedAgentOpener`: блок `llm` фикстуры — сценарий модели, профиль
/// хоста — `setup.profile` (по умолчанию `agent-serve`: файлы и команды через
/// клиента-драйвер, как у бинаря по stdio), журнал сессий и `CODELAB_HOME` — во
/// временной папке фикстуры (design.md change `add-embedded-agent-mode`, D8).
///
/// Как использовать: `ScenarioAgent(profile, environment: …)`; [skipReason]
/// до прогона — фикстура, которую этому агенту не сыграть; [connector] —
/// для `runAgentFixtureOver`.
final class ScenarioAgent {
  ScenarioAgent(this.profile, {required Map<String, String> environment})
    : _resolver = ioTransportResolver(
        secrets: ProfileSecretSource(environment),
      );

  /// Профили хоста, которые встроенный агент играет в `test-scenario`.
  static const _embeddedProfiles = {'agent-serve', embeddedHostProfile};

  /// Подстрока аргументов stdio-профиля, которую заменяет путь фикстуры.
  static const fixturePlaceholder = '{fixture}';

  final ConnectionProfile profile;
  final TransportResolver _resolver;

  /// Профиль — бинарь `codelab-agent`: он принимает `--llm-script`.
  bool get isCodelabAgent => switch (profile) {
    StdioProfile(:final command) => p.basename(command) == 'codelab-agent',
    WebSocketProfile() => false,
    // Встроенный агент — не бинарь `codelab-agent` и флагов не принимает.
    EmbeddedProfile() => false,
  };

  /// Профиль — встроенный агент в процессе CLI.
  bool get isEmbedded => profile is EmbeddedProfile;

  /// Агент получает фикстуру целиком через `{fixture}` (повторитель).
  bool get takesFixture => switch (profile) {
    StdioProfile(:final args) => args.any(
      (arg) => arg.contains(fixturePlaceholder),
    ),
    WebSocketProfile() => false,
    EmbeddedProfile() => false,
  };

  /// Почему фикстуру нельзя сыграть этим агентом; `null` — можно.
  String? skipReason(AcpFixture fixture) {
    if (takesFixture) {
      return null;
    }
    final setup = fixture.setup;
    // Fake MCP-серверы `setup.mcp` живут в памяти фабрики агентского прогона
    // (design.md change `add-agent-mcp-client`, D15) и в процесс настоящего
    // агента не передаются: без пропуска он упал бы с `spawn failed` на
    // несуществующей команде fake-сервера. Агент-повторитель (`{fixture}`)
    // отсеян выше — он играет фикстуру сам.
    if (setup.mcp.isNotEmpty) {
      return 'setup.mcp cannot be passed to the agent process';
    }
    if (isEmbedded) {
      // Как у `codelab-agent`: эти входы сценарный открыватель не принимает,
      // поддержка «в процессе» — расширение вне этого change (D8).
      final unsupported = [
        if (setup.sessions.isNotEmpty) 'setup.sessions',
        if (setup.config != null) 'setup.config',
        if (setup.web != null) 'setup.web',
        if (setup.profile case final profile?
            when !_embeddedProfiles.contains(profile))
          'setup.profile "$profile"',
      ];
      return unsupported.isEmpty
          ? null
          : 'embedded: ${unsupported.join(', ')} cannot be played by the '
                'embedded agent';
    }
    if (isCodelabAgent) {
      final unsupported = [
        if (setup.sessions.isNotEmpty) 'setup.sessions',
        if (setup.config != null) 'setup.config',
        if (setup.web != null) 'setup.web',
        if (setup.profile case final profile? when profile != 'agent-serve')
          'setup.profile "$profile"',
      ];
      return unsupported.isEmpty
          ? null
          : 'codelab-agent: ${unsupported.join(', ')} cannot be passed to the '
                'agent process';
    }
    return fixture.llm == null
        ? null
        : 'third-party agent: llm script cannot be passed';
  }

  /// Подключение к агенту для фикстуры из файла [fixturePath].
  AgentFixtureConnector connector({required String fixturePath}) => isEmbedded
      ? _embeddedConnection
      : (setup) => _processConnection(setup, fixturePath);

  /// Встроенный агент на фикстуру: свой `CODELAB_HOME` и журнал во временной
  /// папке, которая удаляется после `dispose` агента.
  Future<AgentConnection> _embeddedConnection(AgentFixtureSetup setup) async {
    final temp = await Directory.systemTemp.createTemp(
      'codelab_scenario_embedded_',
    );
    try {
      final opener = scriptedEmbeddedAgentOpener(
        llm: Map<String, Object?>.from(
          expandRepeat(setup.llm ?? {'steps': <Object?>[]})! as Map,
        ),
        codelabHome: p.join(temp.path, 'home'),
        logger: const CliEmbeddedLogger.silent(),
        hostProfile: setup.profile,
        permissionMode: setup.mode,
        // Без журнала сессий агент не объявляет `loadSession` — а это часть
        // его контракта (`acp/initialize-capabilities`).
        sessionsDir: p.join(temp.path, 'sessions'),
      );
      final agent = await opener(cwd: setup.cwd, hostProfile: setup.profile);
      return AgentConnection(
        client: agent.clientTransport,
        agent: _EmbeddedUnderTest(agent, temp),
      );
    } on Object {
      await temp.delete(recursive: true);
      rethrow;
    }
  }

  Future<AgentConnection> _processConnection(
    AgentFixtureSetup setup,
    String fixturePath,
  ) async {
    final temp = await Directory.systemTemp.createTemp('codelab_scenario_');
    try {
      final transport = await _resolver.open(
        await _profileFor(setup, fixturePath, temp),
        projectDirectory: setup.cwd,
      );
      return AgentConnection(
        client: transport,
        agent: _ProcessAgent(() => temp.delete(recursive: true)),
      );
    } on Object {
      await temp.delete(recursive: true);
      rethrow;
    }
  }

  /// Профиль запуска на фикстуру: `{fixture}` заменён путём, у
  /// `codelab-agent` — сценарий модели, режим и свой `CODELAB_HOME`.
  Future<ConnectionProfile> _profileFor(
    AgentFixtureSetup setup,
    String fixturePath,
    Directory temp,
  ) async {
    final profile = this.profile;
    if (profile is! StdioProfile) {
      return profile;
    }
    final args = [
      for (final arg in profile.args)
        arg.replaceAll(fixturePlaceholder, fixturePath),
    ];
    if (!isCodelabAgent) {
      return profile.copyWith(args: args, runInProjectDirectory: true);
    }
    final script = File(p.join(temp.path, 'llm.json'))
      ..writeAsStringSync(
        jsonEncode({
          'llm': expandRepeat(setup.llm ?? {'steps': <Object?>[]}),
        }),
      );
    return profile.copyWith(
      args: [
        ...args,
        '--llm-script',
        script.path,
        // Без журнала сессий бинарь со сценарием держит их в памяти и не
        // объявляет `loadSession` — а это часть его контракта
        // (`acp/initialize-capabilities`).
        '--sessions-dir',
        p.join(temp.path, 'sessions'),
        if (setup.mode case final mode?) ...['--permission-mode', mode],
      ],
      // Журналы и логи прогона — во временной папке, а не в домашнем
      // `~/.codelab` пользователя.
      env: {...profile.env, 'CODELAB_HOME': p.join(temp.path, 'home')},
      runInProjectDirectory: true,
    );
  }
}

/// Процесс агента за транспортом: его завершает закрытие транспорта
/// драйвером, здесь — только уборка временной папки.
final class _ProcessAgent implements AgentUnderTest {
  _ProcessAgent(this._cleanup);

  final Future<void> Function() _cleanup;

  @override
  void verify() {}

  @override
  Future<void> stop() => _cleanup();
}

/// Встроенный агент за клиентским концом пары: `stop` ждёт его `dispose`
/// (журнал дописан, MCP закрыты) и удаляет временную папку фикстуры.
final class _EmbeddedUnderTest implements AgentUnderTest {
  _EmbeddedUnderTest(this._agent, this._temp);

  final EmbeddedAgent _agent;
  final Directory _temp;

  @override
  void verify() {}

  @override
  Future<void> stop() async {
    try {
      await _agent.dispose();
    } finally {
      await _temp.delete(recursive: true);
    }
  }
}
