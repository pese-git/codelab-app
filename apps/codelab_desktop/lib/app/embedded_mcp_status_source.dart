import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_embedded/codelab_embedded.dart' show McpStatusPort;

import '../features/settings/application/embedded_mcp_status_source.dart';
import 'embedded_transport_resolver.dart';

/// Порт состояния MCP по агенту текущего соединения (design.md change
/// `add-provider-setup-ui`, D12 «Механизм в коде»).
///
/// Почему в `lib/app/`: агента держит [EmbeddedTransportResolver] —
/// деталь composition root; `features/` видят только узкий порт
/// [EmbeddedMcpStatusSource].
///
/// Для чего: `resolver.currentAgent?.mcpStatus(id.value)`; id сессии ACP у
/// встроенного агента совпадает с `SessionId` рантайма. Закрывшийся агент
/// даёт `null` (Q18), поэтому отдельной очистки не нужно.
///
/// Как использовать: composition root передаёт экземпляр в
/// `McpSettingsCubit(statusSource:)`; порты не кэшируются.
final class ResolverMcpStatusSource implements EmbeddedMcpStatusSource {
  const ResolverMcpStatusSource(this._resolver);

  final EmbeddedTransportResolver _resolver;

  @override
  McpStatusPort? statusOf(SessionId id) =>
      _resolver.currentAgent?.mcpStatus(id.value);
}
