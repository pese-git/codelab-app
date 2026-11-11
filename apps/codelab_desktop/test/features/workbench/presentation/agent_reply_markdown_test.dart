// Ответ агента в ленте рабочего места без сырых маркеров (задача 2.5 change
// `add-desktop-markdown`; регресс SMK-07 #177; spec agent-workbench-ui
// «Markdown в ответе агента», сценарии «Ответ со smoke без сырых маркеров» и
// «Мысли без разметки», MODIFIED «Transcript reads as a conversation» и
// «Model thoughts in a collapsible block»).
//
// Сквозная проверка: ответ приходит `agent_message_chunk` через фальшивый
// транспорт, проходит клиентский слой, маппер и ленту собранного app и
// рисуется без `**`, обратных кавычек и строк ограды. Красный до задач
// 2.2–2.4: ответ рисуется одним `CodeLabText` без разбора.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app_scope.dart';

/// Ответ из сценария smoke 2026-10-30: «Готово.» обрамлено `**`, команда в
/// строке — обратными кавычками, ниже огороженный блок `bash`.
const _smokeAnswer =
    '**Готово.** Запустите `dart test` ещё раз.\n\n'
    '```bash\n'
    'dart test\n'
    '```\n';

void main() {
  late FakeAcpTransport agent;
  late CodeLabShellCubit cubit;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  /// Подключённое приложение с сессией `session-1`.
  Future<void> pumpConnected(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => agent,
    );
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    await tester.pump();
    cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.runAsync(() => cubit.connect());
    await tester.pump();

    agent.drainSentMessages();
    unawaited(cubit.createSession());
    await settle(tester);
    final request = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
      (r) => r.method == sessionNewMethod,
    );
    agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const {'sessionId': 'session-1'},
      ),
    );
    await settle(tester);
  }

  void emit(SessionUpdate update) => agent.emitInbound(
    JsonRpcMessage.notification(
      method: sessionUpdateMethod,
      params: SessionNotification(
        sessionId: const SessionId('session-1'),
        update: update,
      ).toJson(),
    ),
  );

  /// Ход: промпт, дельты [updates], конец хода.
  Future<void> runTurn(
    WidgetTester tester,
    String prompt,
    List<SessionUpdate> updates,
  ) async {
    agent.drainSentMessages();
    final submit = cubit.submitPrompt(prompt);
    await settle(tester);
    final request = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
      (r) => r.method == sessionPromptMethod,
    );
    updates.forEach(emit);
    await settle(tester);
    agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await tester.runAsync(() => submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  }

  /// Видимый текст ленты: всё, что рисуют `RichText` внутри панели.
  String transcriptText(WidgetTester tester) => tester
      .widgetList<RichText>(
        find.descendant(
          of: find.byType(CodeLabTranscriptPanel),
          matching: find.byType(RichText),
        ),
      )
      .map((w) => w.text.toPlainText())
      .join('\n');

  testWidgets('the smoke answer is shown without raw markdown markers '
      '(SMK-07)', (tester) async {
    await pumpConnected(tester);

    await runTurn(tester, 'run the tests', [
      SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: _smokeAnswer),
      ),
    ]);

    expect(tester.takeException(), isNull);
    final text = transcriptText(tester);
    expect(text, contains('Готово.'));
    expect(text, contains('dart test'));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('`')));
    // Блок кода bash: подпись языка и «Copy» ответа (строка agent-2).
    expect(find.text('bash'), findsOneWidget);
    expect(find.byKey(const ValueKey('code-copy-agent-2-0')), findsOneWidget);

    await tearDownApp(tester);
  });

  testWidgets('the prompt and the thoughts stay as typed while the answer is '
      'rendered', (tester) async {
    await pumpConnected(tester);

    await runTurn(tester, 'keep **my** prompt', [
      SessionUpdate.agentThoughtChunk(
        content: ContentBlock.text(text: '**plan**: read files'),
      ),
      SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: '**done**'),
      ),
    ]);

    expect(tester.takeException(), isNull);
    final text = transcriptText(tester);
    // Промпт пользователя показан как есть.
    expect(text, contains('keep **my** prompt'));
    // Ответ размечен: звёздочек нет, слово есть.
    expect(find.textContaining('**done**', findRichText: true), findsNothing);
    expect(find.textContaining('done', findRichText: true), findsWidgets);

    // Мысли после хода свёрнуты; раскрытые показывают текст как есть.
    await tester.tap(find.text('Thoughts'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.textContaining('**plan**: read files', findRichText: true),
      findsOneWidget,
    );

    await tearDownApp(tester);
  });

  testWidgets('a /mcp list style reply is a code block without fence lines', (
    tester,
  ) async {
    await pumpConnected(tester);

    await runTurn(tester, '/mcp list', [
      SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(
          text: '```text\nMCP servers (1)\n  a  ok\n```',
        ),
      ),
    ]);

    expect(tester.takeException(), isNull);
    // Не `transcriptText`: старый моноширинный блок рисует `SelectableText`
    // (EditableText), `findRichText` видит оба вида.
    expect(
      find.textContaining('MCP servers (1)', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('```', findRichText: true), findsNothing);
    expect(find.text('text'), findsOneWidget);
    expect(find.byKey(const ValueKey('code-copy-agent-2-0')), findsOneWidget);

    await tearDownApp(tester);
  });
}
