import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'acp_transport.freezed.dart';

/// Replaceable ACP message transport used by core/application code.
abstract interface class AcpTransport {
  /// Typed inbound JSON-RPC messages received from an agent.
  Stream<JsonRpcMessage> get inbound;

  /// Lifecycle, diagnostics, and failure events emitted by the transport.
  Stream<AcpTransportEvent> get events;

  /// Current lifecycle state for synchronous status rendering.
  AcpTransportState get state;

  /// Starts the underlying connection or process.
  Future<void> start();

  /// Sends one typed JSON-RPC message to the agent.
  Future<void> send(JsonRpcMessage message);

  /// Gracefully closes the transport and releases underlying resources.
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
