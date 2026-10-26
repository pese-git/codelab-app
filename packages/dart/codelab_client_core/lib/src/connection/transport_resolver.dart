import 'package:codelab_acp_transports/codelab_acp_transports.dart';

import '../workspace/client_workspace_exception.dart';
import 'connection_profile.dart';
import 'secret_source.dart';

/// Превращает [ConnectionProfile] в транспорт ACP.
///
/// Почему: kit — чистый Dart и не открывает процессы и сокеты сам; как
/// получить транспорт, решает платформа хоста (spec acp-client-kit «Профили
/// и резолверы транспорта»).
///
/// Для чего: `ClientWorkspace` выбирает первый резолвер, у которого
/// [supports] вернул `true`, и вызывает [open] при подключении и при каждом
/// переподключении.
///
/// Как использовать: composition root регистрирует резолверы в
/// `ClientWorkspace(resolvers: ...)`. [open] может бросить исключение — оно
/// становится `ConnectionFailed` и уходит вызывающему `connect`.
abstract interface class TransportResolver {
  bool supports(ConnectionProfile profile);

  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  });
}

/// Фабрика stdio-транспорта по его конфигурации.
typedef StdioTransportFactory =
    AcpTransport Function(StdioAcpTransportConfig config);

/// Фабрика WebSocket-транспорта по его конфигурации.
typedef WebSocketTransportFactory =
    AcpTransport Function(WebSocketAcpTransportConfig config);

/// [TransportResolver] поверх фабрик конфигураций `codelab_acp_transports`.
///
/// Почему: перевод профиля в `StdioAcpTransportConfig` или
/// `WebSocketAcpTransportConfig` одинаков для всех хостов, а различаются
/// только фабрики: настоящие IO-транспорты в приложении и CLI, фейковые в
/// тестах (design D8).
///
/// Для чего: единственное место, где [StdioProfile.runInProjectDirectory]
/// превращается в `cwd` процесса, а ссылка [WebSocketProfile.tokenRef] — в
/// значение токена из [secrets].
///
/// Как использовать: `ConfigTransportResolver(stdio: StdioAcpTransport.new,
/// webSocket: WebSocketAcpTransport.new, secrets: ...)`; вид профиля без
/// фабрики не поддерживается.
final class ConfigTransportResolver implements TransportResolver {
  const ConfigTransportResolver({this.stdio, this.webSocket, this.secrets});

  final StdioTransportFactory? stdio;
  final WebSocketTransportFactory? webSocket;
  final SecretSource? secrets;

  @override
  bool supports(ConnectionProfile profile) => switch (profile) {
    StdioProfile() => stdio != null,
    WebSocketProfile() => webSocket != null,
  };

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    switch (profile) {
      case StdioProfile(:final command, :final args, :final env):
        final factory = stdio;
        if (factory == null) {
          throw UnsupportedConnectionProfileException(profile);
        }
        return factory(
          StdioAcpTransportConfig(
            command: command,
            args: args,
            env: env,
            cwd: profile.runInProjectDirectory ? projectDirectory : null,
          ),
        );
      case WebSocketProfile(:final uri, :final tokenRef):
        final factory = webSocket;
        if (factory == null) {
          throw UnsupportedConnectionProfileException(profile);
        }
        final token = tokenRef == null ? null : await secrets?.read(tokenRef);
        return factory(WebSocketAcpTransportConfig(uri: uri, token: token));
    }
  }
}
