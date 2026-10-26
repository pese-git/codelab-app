// Характеризация подключения `CodeLabShellCubit` (задача 5.0, tasks 1.1).
//
// Фиксирует поведение до переноса в `acp_client_kit`: переходы статуса,
// реакцию на сбой транспорта, отсутствие секретов в диагностике и отписку
// при `close()`. Текст тестов не меняется до конца change (design D1).

import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:codelab_app/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _token = 's3cr3t-token-value';

void main() {
  setUp(setUpCharacterization);

  test('connect() goes connecting → connected over stdio', () async {
    final h = ShellHarness();
    final (states, _) = h.recordStates();

    expect(h.cubit.state.connectionStatus, AcpConnectionStatus.disconnected);
    await h.connect();
    await h.settle();

    expect(
      states.map((state) => state.connectionStatus),
      containsAllInOrder([
        AcpConnectionStatus.connecting,
        AcpConnectionStatus.connected,
      ]),
    );
    expect(h.stdioStarts, 1);
  });

  test(
    'connect() without a stdio command fails and opens no transport',
    () async {
      final h = ShellHarness();

      h.cubit.updateStdioCommand('   ');
      await h.cubit.connect();

      expect(h.cubit.state.connectionStatus, AcpConnectionStatus.failed);
      expect(h.stdioStarts, 0);
      expect(
        h.logEvents,
        contains('Stdio command is required before connecting.'),
      );
    },
  );

  test('connect() over WebSocket without an endpoint fails', () async {
    var wsStarts = 0;
    final h = ShellHarness(
      webSocketTransportFactory: (_) {
        wsStarts++;
        return ThrowingStartTransport(StateError('unused'));
      },
    );

    h.cubit
      ..selectTransport(CodeLabTransportType.webSocket)
      ..updateWebSocketEndpoint('');
    await h.cubit.connect();

    expect(h.cubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(wsStarts, 0);
  });

  test(
    'a WebSocket connect failure is reported without the bearer token',
    () async {
      final h = ShellHarness(
        webSocketTransportFactory: (config) {
          expect(config.token, _token);
          return ThrowingStartTransport(
            const AcpTransportException(
              code: AcpTransportErrorCode.startFailed,
              message: 'handshake rejected: Authorization: Bearer $_token',
            ),
          );
        },
      );

      h.cubit
        ..selectTransport(CodeLabTransportType.webSocket)
        ..updateWebSocketEndpoint('wss://agent.example.test/acp')
        ..updateWebSocketToken(_token);
      await h.cubit.connect();

      expect(h.cubit.state.connectionStatus, AcpConnectionStatus.failed);
      expect(
        h.logEvents,
        contains(startsWith('Failed to connect WebSocket ACP agent')),
      );
      expect(h.logEvents.where((event) => event.contains(_token)), isEmpty);
    },
  );

  test('an unexpected transport failure marks the connection failed and '
      'logs no secrets', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');

    h.agent.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'agent exited; token=$_token',
      ),
    );

    expect(h.cubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(h.cubit.state.isPromptSubmitting, isFalse);
    expect(h.cubit.state.canCancel, isFalse);
    expect(h.cubit.state.activeSessionId, 'session-1');
    expect(h.logEvents, contains(startsWith('Connection to ACP agent lost')));
    expect(h.logEvents.where((event) => event.contains(_token)), isEmpty);
  });

  test('close() unsubscribes: a late session/update emits nothing', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final (states, _) = h.recordStates();
    final before = h.cubit.state;

    await h.cubit.close();
    // Без отписки `_handleSessionChange` вызвал бы `emit` после `close()`,
    // и `StateError` всплыл бы как необработанная ошибка теста.
    h.agentText('session-1', 'late text');
    await h.settle();

    expect(states, isEmpty);
    expect(h.cubit.state, same(before));
  });
}
