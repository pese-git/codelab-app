import '../connection/connection_profile.dart';

/// Операция `ClientWorkspace` отклонена до обращения к агенту.
///
/// Почему: вызов в неподходящем состоянии (сессия без соединения,
/// переподключение без профиля) — ошибка вызывающего, а не протокола; ей
/// нужен типизированный вид, а не `StateError` (`AGENTS.md` §15).
///
/// Для чего: хост различает отказ kit и ошибку транспорта или агента
/// (исключения `codelab_client_acp`) и показывает [message] пользователю.
///
/// Как использовать: ловить при вызове `connect`, `reconnect`, `newSession`;
/// состояние рабочего пространства при этом не меняется, кроме случая
/// [UnsupportedConnectionProfileException].
class ClientWorkspaceException implements Exception {
  const ClientWorkspaceException(this.message);

  final String message;

  @override
  String toString() => 'ClientWorkspaceException: $message';
}

/// Ни один резолвер не умеет открыть транспорт для [profile].
///
/// Почему: набор резолверов задаёт хост (CLI без WebSocket, тест только со
/// stdio); профиль без резолвера — сбой подключения, а не падение
/// (spec acp-client-kit, «Профиль без резолвера»).
///
/// Для чего: `ClientWorkspace.connect` публикует `ConnectionFailed` с этим
/// [message] и бросает исключение вызывающему; транспорт не открывается.
final class UnsupportedConnectionProfileException
    extends ClientWorkspaceException {
  UnsupportedConnectionProfileException(this.profile)
    : super('No transport resolver supports profile "${profile.label}".');

  final ConnectionProfile profile;
}
