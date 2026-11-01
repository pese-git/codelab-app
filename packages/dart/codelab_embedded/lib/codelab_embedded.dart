/// Встроенный агент CodeLab: ядро Dart-агента, собранное в процессе клиента
/// и соединённое с ним парой `InProcessAcpLink` в памяти.
///
/// Почему отдельный пакет: клиенты (CLI, desktop) не импортируют
/// `package:codelab_agent_*` (PKG-4), а встроенному режиму нужны ядро, ACP-сервер
/// и IO агента. Мост без префикса стороны (ADR-0002) даёт им агента одним
/// вызовом и не содержит клиентской логики (design.md change
/// `add-embedded-agent-mode`, D1).
///
/// Для чего: основной барель web-безопасен — он не тянет `dart:io`,
/// `dart:isolate`, `package:codelab_agent_io/` и `codelab_acp_transports/io.dart`
/// (D3, сторож `codelab_architecture_tests`). Настольный открыватель
/// (`io.dart`, итерация 2) и сценарий модели для тестов (`testing.dart`, D8)
/// лежат в отдельных точках входа, на которые барель не ссылается.
///
/// Как использовать: хост собирает [EmbeddedHostServices], вызывает
/// [createEmbeddedAgent] и отдаёт [EmbeddedAgent.clientTransport] ACP-клиенту;
/// при закрытии — [EmbeddedAgent.dispose].
library;

export 'package:codelab_agent_core/codelab_agent_core.dart'
    show LogLevel, Logger;

export 'src/create_embedded_agent.dart' show createEmbeddedAgent;
export 'src/embedded_agent.dart' show EmbeddedAgent, EmbeddedAgentOpener;
export 'src/embedded_agent_config.dart'
    show
        EmbeddedAgentConfig,
        EmbeddedAgentConfigException,
        EmbeddedHostServices;
