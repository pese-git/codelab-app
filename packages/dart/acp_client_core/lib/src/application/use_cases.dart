import 'package:acp_transports/acp_transports.dart';
import 'package:fpdart/fpdart.dart';

import '../domain/domain_models.dart';
import '../domain/state_machines.dart';
import 'acp_client_application.dart';
import 'application_models.dart';

typedef CreateSessionResult =
    TaskEither<AcpClientApplicationFailure, AcpSession>;
typedef LoadSessionResult = TaskEither<AcpClientApplicationFailure, AcpSession>;
typedef SendPromptResult = TaskEither<AcpClientApplicationFailure, PromptTurn>;
typedef CancelTurnResult = TaskEither<AcpClientApplicationFailure, PromptTurn>;
typedef ReconnectResult =
    TaskEither<AcpClientApplicationFailure, AcpTransportState>;
typedef RespondToPermissionResult =
    TaskEither<AcpClientApplicationFailure, ApprovalRequest>;

final class CreateSession {
  const CreateSession(this._client);

  final AcpClientApplication _client;

  CreateSessionResult call(CreateSessionCommand command) {
    return TaskEither.tryCatch(
      () => _client.createSession(command),
      _mapApplicationFailure,
    );
  }
}

final class LoadSession {
  const LoadSession(this._client);

  final AcpClientApplication _client;

  LoadSessionResult call(LoadSessionCommand command) {
    return TaskEither.tryCatch(
      () => _client.loadSession(command),
      _mapApplicationFailure,
    );
  }
}

final class SendPrompt {
  const SendPrompt(this._client);

  final AcpClientApplication _client;

  SendPromptResult call(SendPromptCommand command) {
    return TaskEither.tryCatch(
      () => _client.sendPrompt(command),
      _mapApplicationFailure,
    );
  }
}

final class CancelTurn {
  const CancelTurn(this._client);

  final AcpClientApplication _client;

  CancelTurnResult call(CancelTurnCommand command) {
    return TaskEither.tryCatch(
      () => _client.cancelTurn(command),
      _mapApplicationFailure,
    );
  }
}

final class Reconnect {
  const Reconnect(this._client);

  final AcpClientApplication _client;

  ReconnectResult call(ReconnectCommand command) {
    return TaskEither.tryCatch(
      () => _client.reconnect(command),
      _mapApplicationFailure,
    );
  }
}

final class RespondToPermission {
  const RespondToPermission(this._client);

  final AcpClientApplication _client;

  RespondToPermissionResult call(RespondToPermissionCommand command) {
    return TaskEither.tryCatch(
      () => _client.respondToPermission(command),
      _mapApplicationFailure,
    );
  }
}

AcpClientApplicationFailure _mapApplicationFailure(
  Object error,
  StackTrace stackTrace,
) {
  if (error case AcpClientApplicationException(:final message, :final cause)) {
    if (error case MissingAcpSessionException(:final sessionId)) {
      return AcpClientApplicationFailure.missingSession(
        sessionId: sessionId,
        message: message,
        cause: error,
      );
    }
    if (cause case AcpTransportException(:final code)) {
      return AcpClientApplicationFailure.transport(
        message: message,
        code: code,
        cause: cause,
      );
    }
    return AcpClientApplicationFailure.unexpected(
      message: message,
      cause: cause ?? error,
    );
  }
  if (error case AcpTransportException(:final message, :final code)) {
    return AcpClientApplicationFailure.transport(
      message: message,
      code: code,
      cause: error,
    );
  }
  if (error case StateTransitionException(:final message)) {
    return AcpClientApplicationFailure.stateRejected(
      message: message,
      cause: error,
    );
  }

  return AcpClientApplicationFailure.unexpected(
    message: error.toString(),
    cause: error,
  );
}
