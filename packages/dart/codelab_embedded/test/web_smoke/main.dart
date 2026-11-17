// Точка входа web-smoke: `melos run web-compile` компилирует её в JS и Wasm и
// так доказывает, что основной барель встроенного агента остаётся
// web-безопасным (без dart:io, dart:isolate, package:codelab_agent_io и
// IO-транспортов). На Dart VM тот же код проверяет `web_smoke_test.dart`
// (design.md change `add-embedded-agent-mode`, D3).
import 'dart:math';

// McpServerState и McpServerSummary должны прийти из основного бареля
// `codelab_embedded` (реэкспорт, D12), а не из ядра напрямую.
import 'package:codelab_agent_core/codelab_agent_core.dart'
    hide McpServerState, McpServerSummary;
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:http/http.dart' as web;

/// Итог web-smoke: профиль и инструменты из записи `host.plan`, состояние
/// клиентского транспорта до старта.
final class EmbeddedWebSmokeReport {
  const EmbeddedWebSmokeReport({
    required this.profile,
    required this.toolNames,
    required this.transportState,
    required this.unknownSessionStatus,
    required this.mcpStates,
  });

  final String profile;
  final List<String> toolNames;
  final Enum transportState;

  /// `mcpStatus` неизвестной сессии (embedded-agent «Состояние MCP-серверов
  /// для хоста»; design.md change `add-provider-setup-ui`, D12): `null`.
  final Object? unknownSessionStatus;

  /// Имена `McpServerState` и сводка `McpServerSummary` основного бареля:
  /// реэкспорт без `dart:io` проверяет сама компиляция в JS и Wasm.
  final List<String> mcpStates;
}

/// Клиент без сети: запрос к провайдеру в smoke не уходит.
final class _NoNetwork extends web.BaseClient {
  @override
  Future<web.StreamedResponse> send(web.BaseRequest request) =>
      throw StateError('web-smoke has no network');
}

/// Собирает встроенного агента на `MemoryExecutionEnv` и закрывает его.
///
/// Почему `embedded-cli`, а не `agent-serve`: основной барель принимает только
/// профили `embedded-*` (D8). Профиль сужен до того, что есть в браузере: без
/// shell и без постоянного журнала — так же, как в `test/web_smoke` ядра.
Future<EmbeddedWebSmokeReport> runEmbeddedWebSmoke() async {
  final clock = FakeClock();
  final logger = RecordingLogger();
  final http = _NoNetwork();
  final agent = await createEmbeddedAgent(
    config: EmbeddedAgentConfig(
      hostProfile: 'embedded-cli',
      core: CoreConfig(
        defaultModel: ModelRef(
          provider: 'smoke',
          id: 'model-1',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://smoke.invalid/v1'),
          contextWindow: 32000,
          maxOutputTokens: 4096,
        ),
      ),
      host: const HostSettings(
        profileNarrowing: {
          'embedded-cli': {
            HostCapability.shellExec: CapabilityOff('браузер без shell'),
            HostCapability.sessionPersistence: CapabilityOff('журнал в памяти'),
          },
        },
      ),
    ),
    services: EmbeddedHostServices(
      baseEnv: MemoryExecutionEnv(cwd: '/web', clock: clock),
      localEnv: (cwd) => MemoryExecutionEnv(cwd: cwd, clock: clock),
      sessions: MemorySessionStore(),
      secrets: SecretResolver(
        store: MemorySecretStore(),
        environment: const {},
        logger: logger,
      ),
      http: http,
      logger: logger,
      clock: clock,
      ids: SequentialIdGenerator(),
      random: Random(0),
      platform: 'web',
    ),
  );
  final plan = logger.eventsOf('host.plan').single.fields;
  final report = EmbeddedWebSmokeReport(
    profile: plan['profile']! as String,
    toolNames: (plan['tools']! as List).cast<String>(),
    transportState: agent.clientTransport.state,
    unknownSessionStatus: agent.mcpStatus('unknown'),
    mcpStates: [
      for (final state in McpServerState.values)
        '${const McpServerSummary(name: 'x', toolCount: 0).name}:${state.name}',
    ],
  );
  await agent.dispose();
  return report;
}

Future<void> main() async {
  final report = await runEmbeddedWebSmoke();
  // ignore: avoid_print
  print('embedded web smoke: ${report.profile} ${report.toolNames}');
}
