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
///
/// Параметр `projectDirectory` метода [open] — **корень процесса агента**
/// (`WorkspaceState.agentDirectory`, D11/D15 change `require-project-folder`):
/// папка триггера, которым агент стартовал, а не обязательно выбранный проект.
/// Имя параметра сохранено ради совместимости публичного API kit и CLI; у
/// `connect` корень процесса совпадает с папкой проекта.
abstract interface class TransportResolver {
  bool supports(ConnectionProfile profile);

  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  });
}

/// Резолвер, который можно пересобрать с другим источником секретов.
///
/// Почему: проверка профиля с новым токеном (`ProfileProbe.probe(token:)`,
/// design.md change `add-provider-setup-ui`, D13) должна открыть тот же
/// транспорт теми же фабриками хоста, но с токеном из памяти формы, который
/// ещё нигде не сохранён. Подменить источник у резолвера «на месте» нельзя —
/// он общий с рабочим подключением.
///
/// Как использовать: [withSecrets] возвращает новый резолвер с теми же
/// фабриками и источником [secrets]; исходный резолвер не меняется.
abstract interface class SecretRebindableResolver implements TransportResolver {
  TransportResolver withSecrets(SecretSource secrets);
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
final class ConfigTransportResolver implements SecretRebindableResolver {
  const ConfigTransportResolver({this.stdio, this.webSocket, this.secrets});

  final StdioTransportFactory? stdio;
  final WebSocketTransportFactory? webSocket;
  final SecretSource? secrets;

  @override
  TransportResolver withSecrets(SecretSource secrets) =>
      ConfigTransportResolver(
        stdio: stdio,
        webSocket: webSocket,
        secrets: secrets,
      );

  @override
  bool supports(ConnectionProfile profile) => switch (profile) {
    StdioProfile() => stdio != null,
    WebSocketProfile() => webSocket != null,
    // Встроенный агент собирает хост своим резолвером (D7): здесь нет ни
    // процесса, ни сокета, а ядра агента kit не знает.
    EmbeddedProfile() => false,
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
      case EmbeddedProfile():
        throw UnsupportedConnectionProfileException(profile);
    }
  }
}
