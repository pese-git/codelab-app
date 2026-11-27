// Журнал рабочего места и текст ошибки агента (задача 7.5 change
// `redesign-protocol-pane`; design.md D3, «Текст ошибки агента»; spec
// acp-client-kit «Диагностика без текста ошибки агента»).
//
// Текст для пользователя несёт текст агента при любой политике, а запись
// журнала при `metadataOnly` — только префикс CodeLab и метаданные.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabNoticeRow;
import 'package:codelab_desktop/features/workbench/application/shell_part.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_logger.dart';
import '../../../support/transcript_rows.dart';
import 'shell_cubit_characterization/harness.dart';

const _marker = 'AGENT_MSG_MARKER /home/u/secret.txt';
const _dataMarker = 'AGENT_DATA_MARKER';

JsonRpcError _agentError() => const JsonRpcError(
  code: -32603,
  message: _marker,
  data: {'detail': _dataMarker},
);

AcpClientApplicationException _wrapped() => AcpClientApplicationException(
  'ACP request session/new failed: $_marker',
  cause: _agentError(),
);

void main() {
  setUp(setUpCharacterization);

  group('ShellDiagnostics.recordFailure', () {
    test('metadataOnly writes the prefix and the description without the '
        'agent text', () {
      final recorder = RecordingLogger();
      ShellDiagnostics(
        logger: recorder,
        payloads: ProtocolPayloadPolicy.metadataOnly,
      ).recordFailure('Failed to create ACP session', _wrapped(), source: 's');

      expect(
        recorder.entries.single['event'],
        startsWith('Failed to create ACP session: '),
      );
      expect(recorder.entries.single['event'], contains('-32603'));
      expect(
        recorder.entries.single['event'],
        isNot(contains('AGENT_MSG_MARKER')),
      );
      expect(recorder.entries.single['event'], isNot(contains(_dataMarker)));
    });

    test('metadataOnly is the default policy', () {
      final recorder = RecordingLogger();
      ShellDiagnostics(
        logger: recorder,
      ).recordFailure('Failed', _agentError(), source: 's');

      expect(
        recorder.entries.single['event'],
        isNot(contains('AGENT_MSG_MARKER')),
      );
    });

    test('full writes the agent text after masking', () {
      final recorder = RecordingLogger();
      ShellDiagnostics(
        logger: recorder,
        payloads: ProtocolPayloadPolicy.full,
      ).recordFailure(
        'Failed',
        AcpClientApplicationException(
          'failed: $_marker token=sk-live-abcdefghijklmnop',
          cause: _agentError(),
        ),
        source: 's',
      );

      expect(recorder.entries.single['event'], contains('AGENT_MSG_MARKER'));
      expect(
        recorder.entries.single['event'],
        isNot(contains('sk-live-abcdefghijklmnop')),
      );
    });
  });

  group('ошибка агента при старте и создании сессии', () {
    FakeAcpTransport failingInitialize() =>
        FakeAcpTransport()..autoRespondToInitialize = false;

    /// Отвечает ошибкой агента на `initialize`: уже отправленный кадр
    /// берётся из истории, ещё не отправленный — из потока.
    void failInitialize(FakeAcpTransport agent) {
      void fail(JsonRpcRequest request) => agent.emitInbound(
        JsonRpcMessage.response(id: request.id, error: _agentError()),
      );
      for (final message in agent.sentMessages) {
        if (message is JsonRpcRequest && message.method == initializeMethod) {
          fail(message);
          return;
        }
      }
      agent.sent
          .firstWhere(
            (m) => m is JsonRpcRequest && m.method == initializeMethod,
          )
          .then((m) => fail(m as JsonRpcRequest));
    }

    String journal(ShellHarness h) => h.logEvents.join('\n');

    test('start failure: the journal has no agent text under metadataOnly, '
        'the banner stays', () async {
      final agent = failingInitialize();
      final h = ShellHarness(agent: agent, debugBuild: false);
      await h.projectReady();
      failInitialize(agent);

      await h.cubit.startOnLaunch();
      await h.settle();

      expect(journal(h), contains('Failed to start stdio ACP agent: '));
      expect(journal(h), isNot(contains('AGENT_MSG_MARKER')));
      expect(journal(h), isNot(contains(_dataMarker)));
      // Баннер строит kit (`_publishFailure`): сбой `initialize` пользователь
      // видит как общий текст CodeLab о согласовании версии, а не как сообщение
      // агента. Так задумано: это состояние соединения, а текст агента
      // показывает заметка хода (тест ниже).
      expect(
        h.cubit.state.connectionMessage,
        'Failed to negotiate ACP protocol version.',
      );
    });

    test(
      'start failure under full keeps the agent text in the journal',
      () async {
        final agent = failingInitialize();
        final h = ShellHarness(agent: agent, debugBuild: true);
        await h.projectReady();
        failInitialize(agent);

        await h.cubit.startOnLaunch();
        await h.settle();

        expect(journal(h), contains('AGENT_MSG_MARKER'));
      },
    );

    test(
      'restart failure: no agent text in the journal under metadataOnly',
      () async {
        final second = failingInitialize();
        final transports = [FakeAcpTransport(), second];
        var starts = 0;
        final h = ShellHarness(
          agent: transports.first,
          debugBuild: false,
          stdioTransportFactory: (_) => transports[starts++],
        );
        await h.connect();
        failInitialize(second);

        await h.cubit.restartAgent();
        await h.settle();

        expect(journal(h), contains('Failed to reconnect stdio ACP agent: '));
        expect(journal(h), isNot(contains('AGENT_MSG_MARKER')));
        expect(journal(h), isNot(contains(_dataMarker)));
        // Баннер строит kit (`_publishFailure`): сбой `initialize` пользователь
        // видит как общий текст CodeLab о согласовании версии, а не как сообщение
        // агента. Так задумано: это состояние соединения, а текст агента
        // показывает заметка хода (тест ниже).
        expect(
          h.cubit.state.connectionMessage,
          'Failed to negotiate ACP protocol version.',
        );
      },
    );

    test('prompt failure: the user sees the agent text masked, the journal '
        'has none under metadataOnly', () async {
      final h = ShellHarness(debugBuild: false);
      await h.connect();
      await h.createSession('s1');
      final turn = await h.startTurn('hello');
      h.agent.emitInbound(
        JsonRpcMessage.response(
          id: turn.request.id,
          error: const JsonRpcError(
            code: -32603,
            message: '$_marker token=sk-live-abcdefghijklmnop',
            data: {'detail': _dataMarker},
          ),
        ),
      );
      await turn.done;
      await h.settle();

      final notice = h.cubit.state.transcriptRows
          .whereType<CodeLabNoticeRow>()
          .lastWhere((row) => row.id.startsWith('prompt-error-'));
      // Текст для пользователя несёт текст агента при любой политике (D3),
      // секреты маскирует ядро.
      expect(notice.text, contains('AGENT_MSG_MARKER'));
      expect(notice.text, isNot(contains('sk-live-abcdefghijklmnop')));
      expect(journal(h), isNot(contains('AGENT_MSG_MARKER')));
      expect(journal(h), isNot(contains(_dataMarker)));
    });

    test('session creation failure: no agent text in the journal under '
        'metadataOnly', () async {
      final h = ShellHarness(debugBuild: false);
      await h.connect();
      final request = h.nextSent(sessionNewMethod);
      final create = h.cubit.createSession();
      final sent = await request as JsonRpcRequest;
      h.agent.emitInbound(
        JsonRpcMessage.response(id: sent.id, error: _agentError()),
      );
      await create;
      await h.settle();

      // Экранного текста у сбоя создания сессии нет: сессия не появляется,
      // причина — только в журнале (без текста агента).
      expect(h.cubit.state.sessions, isEmpty);
      expect(journal(h), contains('Failed to create ACP session: '));
      expect(journal(h), isNot(contains('AGENT_MSG_MARKER')));
      expect(journal(h), isNot(contains(_dataMarker)));
    });
  });
}
