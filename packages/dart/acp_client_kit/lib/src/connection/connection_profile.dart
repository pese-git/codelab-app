import 'package:freezed_annotation/freezed_annotation.dart';

part 'connection_profile.freezed.dart';

/// Профиль подключения к агенту: что запустить или куда подключиться.
///
/// Почему: app и будущий CLI описывают агента одинаково, а превращение
/// описания в транспорт зависит от платформы (процесс, сокет). Профиль —
/// чистые данные, транспорт из него строит [TransportResolver]
/// (`09-10`, «Публичный API `acp_client_kit`»; design D8).
///
/// Для чего: вход `ClientWorkspace.connect`/`reconnect` и ключ выбора
/// резолвера. Секреты в профиле не хранятся: у [WebSocketProfile] только
/// ссылка [WebSocketProfile.tokenRef], значение даёт `SecretSource`.
///
/// Как использовать: app собирает профиль из формы подключения перед
/// `connect`; [id] — стабильный ключ хранения профилей, [label] — имя для
/// UI и диагностики.
@freezed
sealed class ConnectionProfile with _$ConnectionProfile {
  const ConnectionProfile._();

  /// Агент — дочерний процесс с ACP поверх stdin/stdout.
  ///
  /// [runInProjectDirectory] — процесс стартует в папке проекта, иначе в
  /// рабочей папке клиента (как переключатель app «Run agent from project
  /// directory»).
  const factory ConnectionProfile.stdio({
    required String id,
    required String label,
    required String command,
    @Default([]) List<String> args,
    @Default({}) Map<String, String> env,
    @Default(false) bool runInProjectDirectory,
  }) = StdioProfile;

  /// Агент за WebSocket-адресом [uri]; [tokenRef] — ссылка на Bearer-токен
  /// в `SecretSource`, `null` — подключение без токена.
  const factory ConnectionProfile.webSocket({
    required String id,
    required String label,
    required Uri uri,
    String? tokenRef,
  }) = WebSocketProfile;
}
