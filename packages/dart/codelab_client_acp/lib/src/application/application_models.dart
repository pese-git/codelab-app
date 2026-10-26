import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
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

/// Страница списка сессий агента — результат `session/list`.
///
/// Почему: ACP отдаёт список страницами с непрозрачным курсором
/// (`04-Session List.md`, «Pagination»), и размер страницы выбирает агент.
///
/// Для чего: результат `AcpClientApplication.listSessions`; элементы —
/// `SessionInfo` протокола как результат запроса, долгоживущим состоянием
/// клиента они не становятся (design D1 change `add-session-list-and-reload`).
///
/// Как использовать: [nextCursor] передаётся в следующий вызов как есть;
/// `null` — страница последняя. Курсор не разбирают и не сохраняют.
@freezed
sealed class SessionListPage with _$SessionListPage {
  const factory SessionListPage({
    required List<SessionInfo> sessions,
    String? nextCursor,
  }) = _SessionListPage;
}
