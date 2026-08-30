import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../domain/domain_models.dart';

part 'application_models.freezed.dart';

typedef AcpTransportFactory = FutureOr<AcpTransport> Function();

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
sealed class LoadSessionCommand with _$LoadSessionCommand {
  const LoadSessionCommand._();

  const factory LoadSessionCommand({
    required SessionId sessionId,
    required String cwd,
    @Default([]) List<McpServer> mcpServers,
    Map<String, Object?>? meta,
  }) = _LoadSessionCommand;
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
sealed class CancelTurnCommand with _$CancelTurnCommand {
  const CancelTurnCommand._();

  const factory CancelTurnCommand({
    required SessionId sessionId,
    Map<String, Object?>? meta,
  }) = _CancelTurnCommand;
}

@freezed
sealed class ReconnectCommand with _$ReconnectCommand {
  const ReconnectCommand._();

  const factory ReconnectCommand({
    Duration? closeTimeout,
    AcpTransportFactory? transportFactory,
  }) = _ReconnectCommand;
}

@freezed
sealed class SetSessionConfigOptionCommand
    with _$SetSessionConfigOptionCommand {
  const SetSessionConfigOptionCommand._();

  const factory SetSessionConfigOptionCommand({
    required SessionId sessionId,
    required SessionConfigId configId,
    required SessionConfigValueId value,
    Map<String, Object?>? meta,
  }) = _SetSessionConfigOptionCommand;
}

@freezed
sealed class RespondToPermissionCommand with _$RespondToPermissionCommand {
  const RespondToPermissionCommand._();

  const factory RespondToPermissionCommand.selected({
    required SessionId sessionId,
    required ApprovalRequestId approvalId,
    required PermissionOptionId optionId,
    Map<String, Object?>? meta,
  }) = SelectPermissionCommand;

  const factory RespondToPermissionCommand.cancelled({
    required SessionId sessionId,
    required ApprovalRequestId approvalId,
    Map<String, Object?>? meta,
  }) = CancelPermissionCommand;
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
