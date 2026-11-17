import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
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
/// в памяти `InProcessAcpLink`.
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

/// Отказ рукопожатия WebSocket: сервер ответил HTTP-статусом, отличным от 101.
///
/// Почему: `WebSocketException` из `dart:io` при отказе несёт только текст без
/// кода, а разбирать текст запрещено (design.md change
/// `add-app-settings-shell`, D12): он зависит от SDK и ОС.
///
/// Для чего: типизированная причина (`cause`) `AcpTransportException` с
/// кодом `startFailed`, по которой вызывающий отличает «нужна авторизация»
/// (401/403) от «агент недоступен». Новый `AcpTransportErrorCode` не введён
/// намеренно: исчерпывающие `switch` по нему есть у потребителей.
///
/// Как использовать: `error.cause is AcpWebSocketHandshakeRejected`. Текст и
/// поля не содержат URL, заголовков и токена.
final class AcpWebSocketHandshakeRejected implements Exception {
  const AcpWebSocketHandshakeRejected(this.statusCode);

  /// Числовой HTTP-статус ответа на запрос обновления соединения.
  final int statusCode;

  @override
  String toString() => 'AcpWebSocketHandshakeRejected(statusCode: $statusCode)';
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
