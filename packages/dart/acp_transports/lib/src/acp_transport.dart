import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'acp_transport.freezed.dart';

/// Заменяемый транспорт сообщений ACP.
///
/// Почему: код клиента и агента не должен знать, идут ли кадры по stdio, по
/// WebSocket или в памяти (agent-transports «Общий порт transport»).
///
/// Для чего: один порт для обеих сторон соединения — клиентские транспорты
/// (`StdioAcpTransport`, `WebSocketAcpTransport`), серверные транспорты
/// агента (`StdioServerAcpTransport`, `WebSocketServerAcpTransport`) и пара
/// в памяти тестов.
///
/// Как использовать: [start], затем подписка на [inbound] и [send];
/// [close] — штатное завершение. Сбой соединения приходит в [events].
abstract interface class AcpTransport {
  /// Разобранные сообщения JSON-RPC от другой стороны соединения: агента —
  /// у клиента, клиента — у агента.
  Stream<JsonRpcMessage> get inbound;

  /// События жизненного цикла, диагностика и сбои транспорта.
  Stream<AcpTransportEvent> get events;

  /// Текущее состояние — для синхронного показа статуса.
  AcpTransportState get state;

  /// Открывает соединение, запускает процесс или начинает чтение потоков.
  Future<void> start();

  /// Отправляет одно сообщение JSON-RPC другой стороне соединения.
  Future<void> send(JsonRpcMessage message);

  /// Штатно закрывает транспорт и освобождает ресурсы.
  Future<void> close({Duration? timeout});
}

enum AcpTransportState { idle, connecting, connected, closing, closed, failed }

@freezed
sealed class AcpTransportEvent with _$AcpTransportEvent {
  const factory AcpTransportEvent.stateChanged(AcpTransportState state) =
      AcpTransportStateChanged;

  const factory AcpTransportEvent.diagnostic({
    required String message,
    @Default(AcpTransportDiagnosticSeverity.info)
    AcpTransportDiagnosticSeverity severity,
    String? source,
  }) = AcpTransportDiagnostic;

  const factory AcpTransportEvent.failure(AcpTransportException error) =
      AcpTransportFailure;
}

enum AcpTransportDiagnosticSeverity { debug, info, warning, error }

@freezed
abstract class AcpTransportException
    with _$AcpTransportException
    implements Exception {
  const AcpTransportException._();

  const factory AcpTransportException({
    required AcpTransportErrorCode code,
    required String message,
    Object? cause,
    StackTrace? stackTrace,
  }) = _AcpTransportException;

  @override
  String toString() => 'AcpTransportException($code): $message';
}

enum AcpTransportErrorCode {
  startFailed,
  sendFailed,
  receiveFailed,
  protocolViolation,
  closed,
  timeout,
  disconnected,
  unknown,
}
