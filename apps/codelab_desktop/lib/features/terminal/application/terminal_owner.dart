import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;

/// Владелец вкладок терминала: сессия в рамках профиля подключения.
///
/// Почему не один [SessionId]: ACP не обещает уникальности идентификаторов
/// сессий между агентами, и `s1` двух разных агентов не должен делить вкладки
/// (`add-integrated-terminal`, D5, «Владелец вкладок»).
///
/// Для чего: ключ реестра вкладок `TerminalTabsCubit`.
///
/// Как использовать: Cubit строит его из `WorkspaceState.profile.id` и
/// `activeSessionId` в момент активации сессии; значение с `==`.
final class TerminalOwner {
  const TerminalOwner(this.profileId, this.sessionId);

  final String profileId;
  final SessionId sessionId;

  @override
  bool operator ==(Object other) =>
      other is TerminalOwner &&
      other.profileId == profileId &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(profileId, sessionId);

  /// Без значений: идентификаторы не попадают в случайные журналы (D9).
  @override
  String toString() => 'TerminalOwner';
}
