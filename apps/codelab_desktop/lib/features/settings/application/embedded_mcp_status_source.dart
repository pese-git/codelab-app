import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_embedded/codelab_embedded.dart' show McpStatusPort;

/// Откуда страница «MCP servers» берёт порт состояния MCP встроенного агента.
///
/// Почему порт: агента текущего соединения держит `EmbeddedTransportResolver`
/// из `lib/app/`, а `features/` не должны знать резолвер и открывать агентов;
/// виджеты агента не видят (design.md change `add-provider-setup-ui`, D12).
///
/// Для чего: одна операция — порт сессии [id]. `null` — агента нет, он уже
/// закрыт или сессия неизвестна/закрыта (решение Q18): панель тогда
/// недоступна.
///
/// Как использовать: composition root реализует как
/// `resolver.currentAgent?.mcpStatus(id.value)`; `McpSettingsCubit` вызывает
/// при каждой привязке подписки и портов не кэширует.
abstract interface class EmbeddedMcpStatusSource {
  McpStatusPort? statusOf(SessionId id);
}
