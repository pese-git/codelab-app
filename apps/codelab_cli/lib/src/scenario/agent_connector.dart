import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:path/path.dart' as p;

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
/// Как использовать: `ScenarioAgent(profile, environment: …)`; [skipReason]
/// до прогона — фикстура, которую этому агенту не сыграть; [connector] —
/// для `runAgentFixtureOver`.
final class ScenarioAgent {
  ScenarioAgent(this.profile, {required Map<String, String> environment})
    : _resolver = ioTransportResolver(secrets: EnvSecretSource(environment));

  /// Подстрока аргументов stdio-профиля, которую заменяет путь фикстуры.
  static const fixturePlaceholder = '{fixture}';

  final ConnectionProfile profile;
  final TransportResolver _resolver;

  /// Профиль — бинарь `codelab-agent`: он принимает `--llm-script`.
  bool get isCodelabAgent => switch (profile) {
    StdioProfile(:final command) => p.basename(command) == 'codelab-agent',
    WebSocketProfile() => false,
  };

  /// Агент получает фикстуру целиком через `{fixture}` (повторитель).
  bool get takesFixture => switch (profile) {
    StdioProfile(:final args) => args.any(
      (arg) => arg.contains(fixturePlaceholder),
    ),
    WebSocketProfile() => false,
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
  AgentFixtureConnector connector({required String fixturePath}) =>
      (setup) async {
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
      };

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
