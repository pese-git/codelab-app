import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'assemble.dart';
import 'embedded_agent.dart';
import 'embedded_agent_config.dart';

/// Профили, которые принимает основной барель: встроенный агент приложения и
/// CLI. `agent-serve` доступен только `testing.dart` (D8).
const _embeddedProfiles = {'embedded-app-desktop', 'embedded-cli'};

/// Проверяет профиль до создания любых ресурсов: принимаются только
/// `embedded-*`, иначе [HostWiringException] (D2).
///
/// Как использовать: зовут `createEmbeddedAgent` и открыватель `io.dart` в
/// самом начале, чтобы чужой профиль не оставил HTTP-клиент и не читал секреты.
void checkEmbeddedProfile(String hostProfile) {
  if (!_embeddedProfiles.contains(hostProfile)) {
    throw HostWiringException(
      'createEmbeddedAgent accepts profiles '
      '${(_embeddedProfiles.toList()..sort()).join(', ')}, not $hostProfile',
    );
  }
}

/// Единственная точка сборки встроенного агента (HOST-6).
///
/// Почему: ядро, ACP-сервер и пара транспортов должны собираться одинаково в
/// app и CLI, а расхождение с бинарём `codelab-agent` — только в профиле,
/// транспорте и env (design.md change `add-embedded-agent-mode`, D1, D2).
///
/// Для чего: функция модели строится из провайдеров [config] через
/// `createConfiguredStreamFunction`, каталог моделей — `StaticModelCatalog`;
/// сценарий или свою функцию модели основной барель не принимает (D8).
///
/// Как использовать: [config] — результат загрузчика, [services] — ресурсы
/// хоста. Профиль вне `embedded-*` — [HostWiringException]; все ошибки
/// сборки приходят через `Future`, а не синхронно. [secretsInConfig] —
/// значение `EmbeddedAgent.secretsInConfig`, его вычисляет открыватель по
/// предупреждениям загрузки (change `add-config-literal-secrets-and-migrate`,
/// D8); без него признак `false`.
Future<EmbeddedAgent> createEmbeddedAgent({
  required EmbeddedAgentConfig config,
  required EmbeddedHostServices services,
  bool secretsInConfig = false,
}) async {
  checkEmbeddedProfile(config.hostProfile);
  // Одна функция строит и начальные модель и каталог, и каждый снимок
  // перезагрузки (change `add-config-writer-and-reload`, D13): разойтись им
  // нечему.
  ConfiguredModels modelsFor(CoreConfig core) => (
    stream: createConfiguredStreamFunction(
      core,
      CoreLlmServices(
        httpClient: services.http,
        clock: services.clock,
        random: services.random,
        logger: services.logger,
      ),
      secrets: services.secrets,
    ),
    catalog: StaticModelCatalog(core.providers, logger: services.logger),
  );
  final initial = modelsFor(config.core);
  return assembleEmbeddedAgent(
    config: config,
    services: services,
    secretsInConfig: secretsInConfig,
    models: initial.catalog,
    streamFunction: initial.stream,
    // Нужна перезагрузке корня и сессиям других папок (D21): порт бывает без
    // источника.
    modelsFor: services.configSource == null && services.projectConfig == null
        ? null
        : modelsFor,
  );
}
