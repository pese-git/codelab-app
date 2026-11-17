import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

/// Ошибка запуска stdio-транспорта не несёт аргументов команды (agent-transports
/// «Ошибка запуска stdio transport без аргументов»; design.md change
/// `redact-cli-stdio-profile-args`, D8).
///
/// Почему: `ProcessException.toString()` печатает `Command: <exe> <args>`, а
/// аргументы агента могут содержать ключи (`--api-key sk-…`).
void main() {
  const marker = 'sk-test-leak-0123456789';
  const executable = '/nonexistent/agent';

  test(
    'start() throws a ProcessException without arguments, type and errno kept',
    () async {
      final transport = StdioAcpTransport(
        const StdioAcpTransportConfig(
          command: executable,
          args: ['--api-key', marker, marker],
        ),
      );
      final events = <AcpTransportEvent>[];
      final subscription = transport.events.listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await transport.close();
      });

      Object? thrown;
      try {
        await transport.start();
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<ProcessException>());
      final error = thrown! as ProcessException;
      expect(error.executable, executable);
      expect(error.arguments, isEmpty);
      expect(error.errorCode, isNot(0));
      expect(error.message, isNotEmpty);
      expect(error.toString(), isNot(contains(marker)));
      expect(error.toString(), isNot(contains('--api-key')));

      final failures = events
          .whereType<AcpTransportFailure>()
          .map((event) => event.error)
          .toList();
      expect(failures, hasLength(1));
      final failure = failures.single;
      expect(failure.code, AcpTransportErrorCode.startFailed);
      final cause = failure.cause;
      expect(cause, isA<ProcessException>());
      final causeError = cause! as ProcessException;
      expect(causeError.arguments, isEmpty);
      expect(causeError.errorCode, error.errorCode);
      expect(causeError.message, error.message);
      expect(causeError.toString(), isNot(contains(marker)));
      expect(causeError.toString(), isNot(contains('--api-key')));
      expect(failure.toString(), isNot(contains(marker)));
    },
  );
}
