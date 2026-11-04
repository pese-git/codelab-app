// Характеризация подключения `CodeLabShellCubit` (задача 5.0, tasks 1.1).
//
// Фиксирует поведение до переноса в `codelab_client_core`: переходы статуса,
// реакцию на сбой транспорта, отсутствие секретов в диагностике и отписку
// при `close()`. Задача 2.4 change `add-app-settings-shell` (D6): вызовы
// формы (`updateStdioCommand`, `selectTransport`, …) заменены выбором
// профиля — `connect(profile)`; проверяемые исходы прежние.

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _token = 's3cr3t-token-value';

void main() {
  setUp(setUpCharacterization);

  test('connect() goes connecting → connected over stdio', () async {
    final h = ShellHarness();
    final (states, _) = h.recordStates();

    expect(
      h.cubit.state.connectionStatus,
      CodeLabConnectionStatus.disconnected,
    );
    await h.connect();
    await h.settle();

    expect(
      states.map((state) => state.connectionStatus),
      containsAllInOrder([
        CodeLabConnectionStatus.connecting,
        CodeLabConnectionStatus.connected,
      ]),
    );
    expect(h.stdioStarts, 1);
  });

  test(
    'connect() without a stdio command fails and opens no transport',
    () async {
      final h = ShellHarness();

      await h.cubit.connect(
        const ConnectionProfile.stdio(
          id: 'blank',
          label: 'Blank',
          command: '   ',
        ),
      );

      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
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

    await h.cubit.connect(
      ConnectionProfile.webSocket(id: 'empty', label: 'Empty', uri: Uri()),
    );

    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
    expect(wsStarts, 0);
  });

  test(
    'a WebSocket connect failure is reported without the bearer token',
    () async {
      final h = ShellHarness(
        // Токен — значение переменной окружения app: профиль хранит только
        // ссылку `env:` (D13, D15).
        environment: {'DEVBOX_TOKEN': _token},
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

      await h.cubit.connect(
        ConnectionProfile.webSocket(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://agent.example.test/acp'),
          tokenRef: 'env:DEVBOX_TOKEN',
        ),
      );

      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
      expect(
        h.logEvents,
        contains(startsWith('Failed to connect WebSocket ACP agent')),
      );
      expect(h.logEvents.where((event) => event.contains(_token)), isEmpty);
    },
  );

  test('an unexpected transport failure marks the connection lost and '
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

    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.lost);
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
