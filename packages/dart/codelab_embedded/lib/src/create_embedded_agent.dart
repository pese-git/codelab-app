import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'assemble.dart';
import 'embedded_agent.dart';
import 'embedded_agent_config.dart';

/// Профили, которые принимает основной барель: встроенный агент приложения и
/// CLI. `agent-serve` доступен только `testing.dart` (D8).
const _embeddedProfiles = {'embedded-app-desktop', 'embedded-cli'};

/// Единственная точка сборки встроенного агента (HOST-6).
///
/// Почему: ядро, ACP-сервер и пара транспортов должны собираться одинаково в
/// app и CLI, а расхождение с бинарём `codelab-agent` — только в профиле,
/// транспорте и env (design.md change `add-embedded-agent-mode`, D1, D2).
///
/// Для чего: функция модели строится из провайдеров [config] через
/// `createRoutedStreamFunction`, каталог моделей — `StaticModelCatalog`;
/// сценарий или свою функцию модели основной барель не принимает (D8).
///
/// Как использовать: [config] — результат загрузчика, [services] — ресурсы
/// хоста. Профиль вне `embedded-*` — [HostWiringException]; все ошибки
/// сборки приходят через `Future`, а не синхронно.
Future<EmbeddedAgent> createEmbeddedAgent({
  required EmbeddedAgentConfig config,
  required EmbeddedHostServices services,
}) async {
  if (!_embeddedProfiles.contains(config.hostProfile)) {
    throw HostWiringException(
      'createEmbeddedAgent accepts profiles '
      '${(_embeddedProfiles.toList()..sort()).join(', ')}, not '
      '${config.hostProfile}',
    );
  }
  final providers = config.core.providers;
  return assembleEmbeddedAgent(
    config: config,
    services: services,
    models: StaticModelCatalog(providers, logger: services.logger),
    streamFunction: createRoutedStreamFunction(
      [for (final provider in providers) provider.config],
      CoreLlmServices(
        httpClient: services.http,
        clock: services.clock,
        random: services.random,
        logger: services.logger,
      ),
      unavailable: config.core.providerProblems,
      keys: {
        for (final provider in providers) provider.config.name: ?provider.key,
      },
      headerTemplates: {
        for (final provider in providers)
          if (provider.headerTemplates.isNotEmpty)
            provider.config.name: provider.headerTemplates,
      },
      secrets: services.secrets,
    ),
  );
}
