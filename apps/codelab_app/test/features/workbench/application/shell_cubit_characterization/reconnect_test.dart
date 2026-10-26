// Характеризация переподключения `CodeLabShellCubit` (задача 5.0, tasks 1.7).
//
// Фиксирует одну попытку переподключения через фабрику текущего профиля без
// `session/load`, рост поколения соединения, игнорирование поздних кадров
// старого транспорта (`AGENTS.md` §9) и «одно событие — одно состояние».
// Текст тестов не меняется до конца change (design D1).

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUp(setUpCharacterization);

  test('reconnect() opens one new transport from the current profile, bumps '
      'the generation and sends no session/load', () async {
    final first = FakeAcpTransport();
    final second = FakeAcpTransport();
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
    );
    await h.connect();
    await h.createSession('session-1');
    final generation = h.application.generation;
    final (states, _) = h.recordStates();

    await h.cubit.reconnect();
    await h.settle();

    expect(starts, 2);
    expect(h.application.generation, generation + 1);
    expect(h.cubit.state.connectionStatus, AcpConnectionStatus.connected);
    expect(
      states.map((state) => state.connectionStatus),
      containsAllInOrder([
        AcpConnectionStatus.reconnecting,
        AcpConnectionStatus.connected,
      ]),
    );
    expect(first.state, AcpTransportState.closed);
    expect(
      second.sentMessages.map(
        (message) => message is JsonRpcRequest ? message.method : null,
      ),
      [initializeMethod],
    );
    expect(h.cubit.state.activeSessionId, 'session-1');
    expect(h.cubit.state.sessions.map((item) => item.id), ['session-1']);
  });

  test('a failed reconnect() is a single attempt and marks the connection '
      'failed', () async {
    var starts = 0;
    final agent = FakeAcpTransport();
    final h = ShellHarness(
      agent: agent,
      stdioTransportFactory: (_) => starts++ == 0
          ? agent
          : ThrowingStartTransport(
              const AcpTransportException(
                code: AcpTransportErrorCode.startFailed,
                message: 'agent binary missing',
              ),
            ),
    );
    await h.connect();

    await h.cubit.reconnect();

    expect(starts, 2);
    expect(h.cubit.state.connectionStatus, AcpConnectionStatus.failed);
    expect(
      h.logEvents,
      contains(startsWith('Failed to reconnect stdio ACP agent')),
    );
  });

  test('a late session/update from the previous transport changes nothing '
      'after reconnect()', () async {
    final old = FakeAcpTransport();
    final lingering = LingeringTransport(old);
    final fresh = FakeAcpTransport();
    var starts = 0;
    final h = ShellHarness(
      agent: old,
      stdioTransportFactory: (_) => starts++ == 0 ? lingering : fresh,
    );
    await h.connect();
    await h.createSession('session-1');
    await h.cubit.reconnect();
    expect(lingering.closeRequested, isTrue);
    final before = h.cubit.state;
    final (states, _) = h.recordStates();

    h.agentText('session-1', 'late text from the old connection', via: old);
    await h.settle();

    expect(states, isEmpty);
    expect(h.cubit.state, same(before));
    expect(h.cubit.state.transcriptEntries, isEmpty);
  });

  test('one session/update produces one state', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('hello');
    await h.settle();
    final (states, _) = h.recordStates();

    h.agentText('session-1', 'single chunk');
    await h.settle();

    expect(states, hasLength(1));
    expect(states.single.transcriptEntries.last.body, 'single chunk');

    h.endTurn(turn.request);
    await turn.done;
  });
}
