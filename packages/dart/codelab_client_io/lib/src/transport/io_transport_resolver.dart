import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_acp_transports/io.dart';

/// Резолвер профилей kit в настоящие транспорты: процесс агента для
/// `StdioProfile` и WebSocket-соединение для `WebSocketProfile`.
///
/// Почему: kit не открывает процессы и сокеты сам, а перевод профиля в
/// конфигурацию транспорта уже есть в `ConfigTransportResolver`; здесь
/// подставляются только фабрики `dart:io` (design D8 change
/// `extract-acp-client-kit`).
///
/// Как использовать: composition root CLI или другого хоста на `dart:io` —
/// `ClientWorkspace(resolvers: [ioTransportResolver(secrets: ...)])`;
/// [secrets] даёт значение токена по `WebSocketProfile.tokenRef`.
ConfigTransportResolver ioTransportResolver({SecretSource? secrets}) =>
    ConfigTransportResolver(
      stdio: StdioAcpTransport.new,
      webSocket: WebSocketAcpTransport.new,
      secrets: secrets,
    );
