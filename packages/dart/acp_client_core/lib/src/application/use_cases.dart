import 'package:acp_transports/acp_transports.dart';
import 'package:fpdart/fpdart.dart';

import '../domain/domain_models.dart';
import '../domain/state_machines.dart';
import 'acp_client_application.dart';
import 'application_models.dart';

typedef CreateSessionResult =
    TaskEither<AcpClientApplicationFailure, AcpSession>;
typedef SendPromptResult = TaskEither<AcpClientApplicationFailure, PromptTurn>;

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
