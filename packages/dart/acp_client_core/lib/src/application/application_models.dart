import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'application_models.freezed.dart';

@freezed
sealed class CreateSessionCommand with _$CreateSessionCommand {
  const CreateSessionCommand._();

  const factory CreateSessionCommand({
    required String cwd,
    @Default([]) List<McpServer> mcpServers,
    Map<String, Object?>? meta,
  }) = _CreateSessionCommand;
}

@freezed
sealed class SendPromptCommand with _$SendPromptCommand {
  const SendPromptCommand._();

  const factory SendPromptCommand({
    required SessionId sessionId,
    required List<ContentBlock> prompt,
    Map<String, Object?>? meta,
  }) = _SendPromptCommand;
}

@freezed
sealed class AcpClientApplicationFailure with _$AcpClientApplicationFailure {
  const AcpClientApplicationFailure._();

  const factory AcpClientApplicationFailure.transport({
    required String message,
    AcpTransportErrorCode? code,
    Object? cause,
  }) = AcpClientTransportFailure;

  const factory AcpClientApplicationFailure.protocol({
    required String message,
    Object? cause,
  }) = AcpClientProtocolFailure;

  const factory AcpClientApplicationFailure.stateRejected({
    required String message,
    Object? cause,
  }) = AcpClientStateRejectedFailure;

  const factory AcpClientApplicationFailure.missingSession({
    required SessionId sessionId,
    required String message,
    Object? cause,
  }) = AcpClientMissingSessionFailure;

  const factory AcpClientApplicationFailure.unexpected({
    required String message,
    Object? cause,
  }) = AcpClientUnexpectedFailure;
}
