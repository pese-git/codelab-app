import '../env/execution_env.dart';
import '../llm/model_catalog.dart';
import '../mcp/mcp_connector.dart';
import '../permissions/gate.dart';
import '../session/session_store.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';

/// Всё внешнее, что хост передаёт ядру (`agent-core-architecture` §10.3).
///
/// Почему одним объектом: ядро не создаёт порты само (PKG-6), а сборка
/// проверяет, что у каждой включённой capability есть её сервис (HOST-3).
///
/// Как использовать: хост заполняет поля и передаёт объект в
/// `buildAgentCore`; следующие этапы добавляют сервисы.
final class AgentCoreServices {
  const AgentCoreServices({
    required this.baseEnv,
    required this.logger,
    required this.clock,
    required this.ids,
    required this.sessions,
    this.gate,
    this.platform = 'unknown',
    this.models,
    this.mcp,
  });

  /// Local | ACP client | memory (tests).
  final ExecutionEnv baseEnv;

  /// `null` → `interactiveApproval` is off.
  final PermissionGate? gate;
  final Logger logger;
  final Clock clock;
  final IdGenerator ids;

  /// Хранилище журналов (§8.3). Обязательно: журнал пишется всегда, а
  /// выключенная `sessionPersistence` означает лишь «не на постоянном
  /// носителе» (design.md этапа 3, D12).
  final SessionStore sessions;

  /// Платформа хоста для системного промпта (`linux`, `macos`, `windows`,
  /// `web`). Почему сервис: ядро web-безопасно и не читает
  /// `Platform.operatingSystem`, а модели полезно знать, какой shell и какие
  /// пути её ждут (§11.5). Хост на `dart:io` передаёт
  /// `Platform.operatingSystem`.
  final String platform;

  /// Каталог моделей для опции `model` и смены модели сессии (§2.12.2,
  /// §13.6). `null` — каталог из одной `CoreConfig.defaultModel`: тесты и
  /// хосты без конфига провайдеров (design.md change
  /// `add-dart-agent-acp-server`, D3).
  final ModelCatalog? models;

  /// Подключение MCP-серверов сессии (§10.3; design.md change
  /// `add-agent-mcp-client`, D3). `null` — capability `mcp` выключена с
  /// причиной «сервис MCP не передан»: серверы сессии пропускаются, сессия
  /// создаётся.
  final McpConnector? mcp;
}
