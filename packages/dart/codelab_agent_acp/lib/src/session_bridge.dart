import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Сессия ACP поверх `AgentSession` (§13.7).
///
/// Почему отдельный объект: у сессии ACP есть состояние, которого нет в
/// ядре, — соединение-владелец, JSON-RPC id идущего `session/prompt`,
/// подписка проекции. Сервер хранит мосты по `sessionId`, чтобы
/// переподключение нашло сессию из другого соединения (§13.5, шаг 3b).
///
/// Как использовать: сервер создаёт мост в `session/new` и `session/load`;
/// ход, отмена и опции идут через него (итерации 2 и 3, design.md, D11).
final class SessionBridge {
  SessionBridge(this.session);

  final AgentSession session;
}
