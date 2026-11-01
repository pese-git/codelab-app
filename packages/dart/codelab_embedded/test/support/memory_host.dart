import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:http/http.dart' as web;

/// Конфигурация встроенного агента в памяти: профиль без `exec` и журнала на
/// диск, модель `p/m` (design.md change `add-embedded-agent-mode`, D3: так же
/// собирает ядро web-smoke).
///
/// Почему в `test/support`: сборку без файловой системы используют тесты
/// жизненного цикла и сборки; настоящий хост строит `io.dart`.
EmbeddedAgentConfig memoryConfig({
  String profile = 'embedded-cli',
  ModelRef? model,
}) => EmbeddedAgentConfig(
  hostProfile: profile,
  core: CoreConfig(
    defaultModel:
        model ??
        ModelRef(
          provider: 'p',
          id: 'm',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://p.invalid/v1'),
          contextWindow: 32000,
          maxOutputTokens: 4096,
        ),
  ),
  host: const HostSettings(
    profileNarrowing: {
      'embedded-cli': {
        HostCapability.shellExec: CapabilityOff('test'),
        HostCapability.sessionPersistence: CapabilityOff('test'),
      },
    },
  ),
);

/// Службы хоста над памятью: окружение, журнал, секреты; часы и id —
/// детерминированные (PKG-6).
EmbeddedHostServices memoryServices(Logger logger, web.Client http) {
  final clock = FakeClock();
  return EmbeddedHostServices(
    baseEnv: MemoryExecutionEnv(cwd: '/t', clock: clock),
    localEnv: (cwd) => MemoryExecutionEnv(cwd: cwd, clock: clock),
    sessions: MemorySessionStore(),
    secrets: SecretResolver(
      store: MemorySecretStore(),
      environment: const {},
      logger: logger,
    ),
    http: http,
    closeHttpOnDispose: true,
    logger: logger,
    clock: clock,
    ids: SequentialIdGenerator(),
    random: Random(0),
    platform: 'test',
  );
}
