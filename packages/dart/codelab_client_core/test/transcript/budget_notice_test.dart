// Заметка хода `turnStopped` с причиной бюджета (задача 2.6 change
// `add-usage-extension`; spec acp-client-kit «Инкрементальная проекция
// транскрипта»: «Лимит стоимости», «Причина неизвестна»; design.md, D10,
// D21 Т6).
//
// Красные тесты: ответ `session/prompt` с `_meta.codelab.budgetExceeded`
// пока не попадает в `PromptTurn.budgetExceeded` (задача 2.8), а
// `_stoppedNoticeText` не принимает ход (задача 2.9): тесты компилируются
// и падают на тексте заметки. Прежний текст без причины защищает
// существующий `transcript_projector_test.dart` («max_turn_requests gives
// its own text»), он не меняется.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_core/src/transcript/transcript_projector.dart';
import 'package:test/test.dart';

const _noReason = 'The turn reached the limit of model requests.';

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication application;
  late TranscriptProjector projector;
  const session = SessionId('s-1');

  setUp(() async {
    transport = FakeAcpTransport();
    application = AcpClientApplication(transport: FakeAcpTransport());
    projector = TranscriptProjector();
    final subscription = application.sessionChanges.listen(projector.apply);
    addTearDown(() async {
      await subscription.cancel();
      await application.dispose();
    });
    await application.connect(transport);
    final request = _next(transport, sessionNewMethod);
    final created = application.createSession(
      const CreateSessionCommand(cwd: '/work'),
    );
    transport.emitInbound(
      JsonRpcMessage.response(
        id: (await request).id,
        result: {'sessionId': session.value},
      ),
    );
    await created;
  });

  /// Ход, завершённый ответом [result]; возвращает заметки `turnStopped`.
  Future<List<NoticeItem>> stoppedBy(Map<String, Object?> result) async {
    final requested = _next(transport, sessionPromptMethod);
    final done = application.sendPrompt(
      const SendPromptCommand(
        sessionId: session,
        prompt: [ContentBlock.text(text: 'go')],
      ),
    );
    final request = await requested;
    transport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: {
          'sessionId': session.value,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'partial'},
          },
        },
      ),
    );
    transport.emitInbound(
      JsonRpcMessage.response(id: request.id, result: result),
    );
    await done;
    return projector.items
        .whereType<NoticeItem>()
        .where((notice) => notice.kind == NoticeKind.turnStopped)
        .toList();
  }

  Map<String, Object?> maxTurn([Object? reason]) => {
    'stopReason': 'max_turn_requests',
    if (reason != null)
      '_meta': {
        'codelab': {'budgetExceeded': reason},
      },
  };

  for (final limit in ['cost', 'steps', 'tokens', 'duration', 'deadline']) {
    test('budget $limit names the limit', () async {
      final notices = await stoppedBy(maxTurn(limit));

      expect(notices, hasLength(1));
      expect(notices.single.text, 'The turn stopped: budget exceeded: $limit.');
    });
  }

  test('no reason keeps the old text', () async {
    final notices = await stoppedBy(maxTurn());

    expect(notices.single.text, _noReason);
  });

  test('an unknown reason (energy) keeps the old text', () async {
    final notices = await stoppedBy(maxTurn('energy'));

    expect(notices.single.text, _noReason);
  });

  test('a non-string reason keeps the old text', () async {
    final notices = await stoppedBy(maxTurn(7));

    expect(notices.single.text, _noReason);
  });

  test('other stop reasons ignore the budget reason', () async {
    final notices = await stoppedBy({
      'stopReason': 'max_tokens',
      '_meta': {
        'codelab': {'budgetExceeded': 'cost'},
      },
    });

    expect(
      notices.single.text,
      'The model reached its token limit, so the turn ended.',
    );
  });

  test(
    'incremental projection equals a full rebuild for a budget stop',
    () async {
      await stoppedBy(maxTurn('cost'));

      final current = application.sessionById(session)!;
      expect(projector.items, projectTranscript(current));
    },
  );
}

Future<JsonRpcRequest> _next(FakeAcpTransport transport, String method) async =>
    await transport.sent.firstWhere(
          (message) => message is JsonRpcRequest && message.method == method,
        )
        as JsonRpcRequest;
