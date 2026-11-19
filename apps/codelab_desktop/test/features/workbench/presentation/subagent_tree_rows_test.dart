// Widget-тесты задачи 5.1 (app) change `add-subagents-and-tasks`:
// дерево вызовов потомков в ленте — agent-workbench-ui «Вложенные вызовы
// потомков» («Свёрнутые шаги ребёнка», «Тихие строки потомка»), «Строка вызова
// субагента» («Хвост работающего субагента», «Без дерева — строка прогресса»),
// «Запрос одобрения от субагента под строкой корня» («Вопрос внука не
// раскрывает дерево»); design.md D24, D25, D27, D47 Т9 и Т11, D48 п. 3.
//
// Что проверяется (реализация — задачи 5.4 kit и 5.5 app):
//  - маппер `transcriptRowsOf` заполняет `CodeLabToolCallRow.children`,
//    `CodeLabSubagentCall.tail` и `tailMore`, а `CodeLabToolCallTile` рисует
//    вложенные строки и хвост;
//  - счётчик работающего `N tool calls` приходит из kit (`ToolRowFormatter`:
//    `summaryShort` у завершённого, `runningCounter` у работающего).
// Отдельно закреплено, что не должно сломаться: «Без дерева — строка
// прогресса», хвост не показывается после завершения, блок вопроса внука под
// свёрнутой строкой корня.
//
// Границы: дерево, хвост, счётчик и путь вопроса строит kit, маппер лишь
// переносит готовое в `CodeLabToolCallRow`; решает «опасно ли» и выбирает
// исход не виджет, а пользователь панелью решения (PERM-4). Тексты, которые
// пишет модель (команда вложенного вызова), показываются через
// `escapeForDisplay`.
//
// Тесты строят `ToolCallItem` напрямую (как `subagent_approval_block_test`), а
// не проекцией kit на `session/update`: проекция дерева — задача 5.4.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _allow = PermissionOption(
  optionId: PermissionOptionId('allow-once'),
  name: 'Allow',
  kind: PermissionOptionKind.allowOnce,
);
const _reject = PermissionOption(
  optionId: PermissionOptionId('reject-once'),
  name: 'Reject',
  kind: PermissionOptionKind.rejectOnce,
);

/// Id строки корня в ленте: маппер даёт `tool-<индекс + 1>` у верхнего уровня.
const _rootRowId = 'tool-1';

/// Вызов `read` потомка корня `call_1`; id — `<ход>/tool-<цепочка>` (D47 Т11).
ToolCallItem _read(
  int n, {
  String parent = 'call_1',
  ToolCallStatusView status = ToolCallStatusView.succeeded,
}) => ToolCallItem(
  id: 't1/tool-$parent/call_$n',
  toolCallId: ToolCallId('$parent/call_$n'),
  title: 'Read',
  details: ToolCallView(
    kind: ToolKind.read,
    status: status,
    rawInput: {'path': '/work/lib/a$n.dart'},
    parentToolCallId: parent,
  ),
);

const _summary = SubagentSummaryView(
  toolCalls: 5,
  inputTokens: 15200,
  outputTokens: 3000,
  duration: Duration(seconds: 48),
);

/// Строка `agent` корня: [children] — вложенные элементы kit, [tail] и
/// [subtreeCalls] — хвост и счётчик, которые считает kit (D25, D47 Т9).
ToolCallItem _agent({
  ToolCallStatusView status = ToolCallStatusView.succeeded,
  List<TranscriptItem> children = const [],
  SubagentTailView tail = const SubagentTailView(),
  int subtreeCalls = 0,
  List<String> textOutput = const [],
  SubagentSummaryView? summary,
  List<ApprovalStateView> childApprovals = const [],
}) => ToolCallItem(
  id: 't1/tool-call_1',
  toolCallId: const ToolCallId('call_1'),
  title: 'agent',
  details: ToolCallView(
    kind: ToolKind.think,
    status: status,
    rawInput: const {'type': 'explore', 'description': 'Find auth code'},
    subagentCall: const SubagentCallView(id: 'sub_a1', type: 'explore'),
    subagentSummary: summary,
    textOutput: textOutput,
  ),
  children: children,
  tail: tail,
  subtreeCalls: subtreeCalls,
  childApprovals: childApprovals,
);

List<CodeLabTranscriptRow> _rows(
  List<TranscriptItem> items, {
  void Function(PendingApprovalView, String)? onSelected,
}) => transcriptRowsOf(
  items,
  cwd: '/work',
  approvalsEnabled: true,
  onApprovalSelected: onSelected ?? (_, _) {},
  l10n: AppLocalizationsEn(),
);

Future<void> _pump(
  WidgetTester tester,
  List<CodeLabTranscriptRow> rows, {
  Map<String, bool> expanded = const {},
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FluentApp(
      home: CodeLabTranscriptPanel(rows: rows, expansionOverrides: expanded),
    ),
  );
  // Не pumpAndSettle: у работающего вызова крутится ProgressRing.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Строка из `Text.rich` (метка + деталь): `find.text` такие не видит.
Finder _titled(String text) => find.textContaining(text, findRichText: true);

void main() {
  group('Свёрнутые шаги ребёнка', () {
    final tree = _agent(
      summary: _summary,
      subtreeCalls: 3,
      textOutput: const ['Auth lives in lib/auth/session.dart.'],
      children: [_read(1), _read(2), _read(3)],
    );

    test('the mapper nests three read rows under the agent row only', () {
      final rows = _rows([tree]);

      // Вызовы потомков — только вложенными, верхний уровень — одна строка.
      expect(rows, hasLength(1));
      final root = rows.single as CodeLabToolCallRow;
      expect(root.subagent, isNotNull);
      expect(root.children.map((c) => (c as CodeLabToolCallRow).label), [
        'Read',
        'Read',
        'Read',
      ]);
      // Id вложенных строк уникальны и не зависят от индекса (D47 Т11).
      expect(
        root.children.map((c) => c.id).toSet(),
        hasLength(3),
        reason: 'ids of nested rows must be unique',
      );
    });

    testWidgets('collapsed by default: steps and report are hidden', (
      tester,
    ) async {
      await _pump(tester, _rows([tree]));

      expect(_titled('Subagent explore: Find auth code'), findsOneWidget);
      expect(_titled('Read lib/a1.dart'), findsNothing);
      expect(find.textContaining('Auth lives in'), findsNothing);
    });

    testWidgets('expanded: three Read rows indented under the row and the '
        'report', (tester) async {
      await _pump(tester, _rows([tree]), expanded: {_rootRowId: true});

      for (final n in [1, 2, 3]) {
        expect(_titled('Read lib/a$n.dart'), findsOneWidget);
      }
      expect(find.textContaining('Auth lives in'), findsOneWidget);
      // Отступ по глубине: шаги правее заголовка строки `agent`.
      expect(
        tester.getTopLeft(_titled('Read lib/a1.dart')).dx,
        greaterThan(tester.getTopLeft(_titled('Subagent explore')).dx),
      );
    });

    testWidgets('a nested agent is collapsed by default and opens by its own '
        'id', (tester) async {
      final nested = ToolCallItem(
        id: 't1/tool-call_1/call_2',
        toolCallId: const ToolCallId('call_1/call_2'),
        title: 'agent',
        details: const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.succeeded,
          rawInput: {'type': 'review', 'description': 'Check callers'},
          subagentCall: SubagentCallView(id: 'sub_a2', type: 'review'),
          parentToolCallId: 'call_1',
        ),
        children: [_read(1, parent: 'call_1/call_2')],
        subtreeCalls: 1,
      );
      final rows = _rows([
        _agent(subtreeCalls: 2, children: [nested]),
      ]);
      const nestedId = 't1/tool-call_1/call_2';

      // Корень раскрыт, вложенный `agent` — нет: свёрнут по умолчанию.
      await _pump(tester, rows, expanded: {_rootRowId: true});
      expect(_titled('Subagent review: Check callers'), findsOneWidget);
      expect(_titled('Read lib/a1.dart'), findsNothing);

      // Раскрытие вложенного — тем же `expansionOverrides`, что и у строк
      // верхнего уровня (его хранит `TranscriptViewCubit`, D47 Т11).
      await _pump(tester, rows, expanded: {_rootRowId: true, nestedId: true});
      expect(_titled('Read lib/a1.dart'), findsOneWidget);
    });

    testWidgets('a command of a nested call is shown with escapes', (
      tester,
    ) async {
      final exec = ToolCallItem(
        id: 't1/tool-call_1/call_1',
        toolCallId: const ToolCallId('call_1/call_1'),
        title: 'exec',
        details: const ToolCallView(
          kind: ToolKind.execute,
          status: ToolCallStatusView.succeeded,
          rawInput: {'command': 'echo \u202Eevil'},
          parentToolCallId: 'call_1',
        ),
      );
      await _pump(
        tester,
        _rows([
          _agent(subtreeCalls: 1, children: [exec]),
        ]),
        expanded: {_rootRowId: true},
      );

      // Команду пишет модель: bidi-символ не должен переставить видимый текст.
      expect(_titled(r'echo \u202eevil'), findsOneWidget);
      expect(find.textContaining('\u202E', findRichText: true), findsNothing);
    });
  });

  group('Тихие строки потомка', () {
    final ops = const TaskOpsItem(
      id: 't1/tool-call_1/call_2',
      completed: ['1', '3'],
    );

    test(
      'the mapper keeps an operation of the child as a quiet nested row',
      () {
        final rows = _rows([
          _agent(subtreeCalls: 2, children: [_read(1), ops]),
        ]);

        final root = rows.single as CodeLabToolCallRow;
        expect(root.children, hasLength(2));
        expect(root.children[0], isA<CodeLabToolCallRow>());
        expect(root.children[1], isA<CodeLabTaskOpsRow>());
        expect(
          (root.children[1] as CodeLabTaskOpsRow).text,
          'Tasks #1, #3 done',
        );
      },
    );

    testWidgets('expanded: a Read row and one quiet row without a tag', (
      tester,
    ) async {
      await _pump(
        tester,
        _rows([
          _agent(subtreeCalls: 2, children: [_read(1), ops]),
        ]),
        expanded: {_rootRowId: true},
      );

      expect(_titled('Read lib/a1.dart'), findsOneWidget);
      expect(find.text('Tasks #1, #3 done'), findsOneWidget);
      // Тихая строка без рамки: у неё нет своей шапки раскрывашки, значит
      // шапок две — корень и `Read`.
      expect(find.byKey(CodeLabToolCallTile.headerKey), findsNWidgets(2));
    });

    test('operations of the root do not merge with the ones of the child', () {
      // Слияние — работа kit (соседи одного родителя, D48 п. 3); маппер не
      // должен сливать строки сам: операция корня остаётся отдельной строкой.
      final rows = _rows([
        const TaskOpsItem(id: 't1/tool-1', added: ['1']),
        _agent(subtreeCalls: 1, children: [ops]),
      ]);

      expect(rows, hasLength(2));
      expect(rows[0], isA<CodeLabTaskOpsRow>());
      expect(
        ((rows[1] as CodeLabToolCallRow).children.single as CodeLabTaskOpsRow)
            .text,
        'Tasks #1, #3 done',
      );
    });
  });

  group('Хвост работающего субагента', () {
    // Пять вызовов потомков: хвост — три последних, остальные два — в
    // «+2 more tool calls» (kit считает, D25, D47 Т9).
    final calls = [for (var n = 1; n <= 5; n++) _read(n)];
    final running = _agent(
      status: ToolCallStatusView.running,
      subtreeCalls: 5,
      children: calls,
      tail: SubagentTailView(calls: calls.sublist(2), moreCount: 2),
      // Строка прогресса агента: при дереве она не показывается.
      textOutput: const ['Reading files in lib/'],
    );

    test('the mapper passes the tail and the counter of the kit', () {
      final root = _rows([running]).single as CodeLabToolCallRow;

      expect(root.subagent?.tail, hasLength(3));
      expect(root.subagent?.tailMore, 2);
      expect(root.subagent?.stats, '5 tool calls');
    });

    testWidgets('three last calls, "+2 more tool calls", no tokens and no '
        'progress line', (tester) async {
      await _pump(tester, _rows([running]));

      expect(_titled('Read lib/a3.dart'), findsOneWidget);
      expect(_titled('Read lib/a4.dart'), findsOneWidget);
      expect(_titled('Read lib/a5.dart'), findsOneWidget);
      expect(_titled('Read lib/a1.dart'), findsNothing);
      expect(_titled('Read lib/a2.dart'), findsNothing);
      expect(find.text('+2 more tool calls'), findsOneWidget);
      // Справа счётчик без токенов; токены — только из `summary` завершённого.
      expect(find.text('5 tool calls'), findsOneWidget);
      expect(find.textContaining('tokens'), findsNothing);
      expect(find.textContaining('18.2k'), findsNothing);
      // Строки прогресса нет.
      expect(find.textContaining('Reading files'), findsNothing);
    });

    testWidgets('after the end the tail is gone, the summary with tokens is '
        'on the right (characteristic)', (tester) async {
      // После завершения строка хвост не показывает; итог — из `summary` (D24).
      await _pump(
        tester,
        _rows([_agent(subtreeCalls: 5, children: calls, summary: _summary)]),
      );

      expect(find.text('+2 more tool calls'), findsNothing);
      expect(_titled('Read lib/a5.dart'), findsNothing);
      expect(find.text('5 tool calls · 18.2k · 48s'), findsOneWidget);
    });
  });

  group('Без дерева — строка прогресса', () {
    // Клиент без `subagentToolCalls`: вызовов потомков нет, агент присылает
    // две строки прогресса (§17.3.4) — под свёрнутой строкой последняя.
    testWidgets('the last progress line under the collapsed row '
        '(characteristic)', (tester) async {
      await _pump(
        tester,
        _rows([
          _agent(
            status: ToolCallStatusView.running,
            textOutput: const [
              'explore · 1 tool call',
              'explore · 2 tool calls',
            ],
          ),
        ]),
      );

      expect(find.text('explore · 2 tool calls'), findsOneWidget);
      expect(find.text('explore · 1 tool call'), findsNothing);
      expect(find.textContaining('more tool calls'), findsNothing);
    });
  });

  group('Вопрос внука не раскрывает дерево', () {
    // Внук `explore` ребёнка `review` просит `exec`, дерево есть: вызов внука
    // лежит внутри вложенного `agent`, а вопрос — в `childApprovals` корня и
    // у самой строки внука (D47 Т9). Панель решения — только под корнем.
    const grandchild = SubagentRequester(
      id: 'sub_a3',
      type: 'explore',
      description: 'Find callers',
      depth: 2,
      parentToolCallId: 'call_1',
      rootType: 'review',
    );
    const command = 'git diff --stat';

    ToolCallItem execOf(ApprovalStateView approval) => ToolCallItem(
      id: 't1/tool-call_1/call_2/call_1',
      toolCallId: const ToolCallId('call_1/call_2/call_1'),
      title: 'exec',
      details: const ToolCallView(
        kind: ToolKind.execute,
        status: ToolCallStatusView.queued,
        rawInput: {'command': command},
        parentToolCallId: 'call_1/call_2',
      ),
      approval: approval,
    );

    ToolCallItem treeWith(ApprovalStateView rootApproval, ToolCallItem exec) {
      final child = ToolCallItem(
        id: 't1/tool-call_1/call_2',
        toolCallId: const ToolCallId('call_1/call_2'),
        title: 'agent',
        details: const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.running,
          rawInput: {'type': 'explore', 'description': 'Find callers'},
          subagentCall: SubagentCallView(id: 'sub_a3', type: 'explore'),
          parentToolCallId: 'call_1',
        ),
        children: [exec],
        subtreeCalls: 1,
      );
      return _agent(
        status: ToolCallStatusView.running,
        subtreeCalls: 2,
        children: [child],
        childApprovals: [rootApproval],
      );
    }

    const pending = PendingApprovalView(
      approvalId: ApprovalRequestId('permission-1'),
      sessionId: SessionId('session-1'),
      risk: ApprovalRiskLevel.shell,
      command: command,
      options: [_allow, _reject],
      focused: true,
      subagent: grandchild,
    );
    const resolved = ApprovalStateView.resolved(
      label: 'Allow',
      outcome: ApprovalOutcomeView.allowed,
      agentLabel: 'Allow',
      subagent: grandchild,
    );

    testWidgets('the block with the panel stands under the collapsed root '
        'row (characteristic)', (tester) async {
      await _pump(tester, _rows([treeWith(pending, execOf(pending))]));

      expect(find.text('review › explore wants to run'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      // Корень остался свёрнутым: строки вызова внука не видно.
      expect(_titled('Run $command'), findsNothing);
    });

    testWidgets('Allow answers this request', (tester) async {
      final chosen = <(PendingApprovalView, String)>[];
      await _pump(
        tester,
        _rows([
          treeWith(pending, execOf(pending)),
        ], onSelected: (a, o) => chosen.add((a, o))),
      );

      await tester.tap(find.text('Allow'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(chosen, hasLength(1));
      expect(chosen.single.$1.approvalId, pending.approvalId);
      expect(chosen.single.$2, 'allow-once');
    });

    testWidgets('an opened tree shows the call of the grandchild on its own '
        'place, but there is only one decision panel', (tester) async {
      final rows = _rows([treeWith(pending, execOf(pending))]);
      const nestedId = 't1/tool-call_1/call_2';
      await _pump(tester, rows, expanded: {_rootRowId: true, nestedId: true});

      // Вызов внука виден на своём месте…
      expect(_titled('Run $command'), findsOneWidget);
      // …а панель решения одна: у блока под строкой корня.
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('review › explore wants to run'), findsOneWidget);
    });

    testWidgets('after the decision the call of the grandchild carries the '
        'outcome tag next to the one under the root', (tester) async {
      final rows = _rows([treeWith(resolved, execOf(resolved))]);
      const nestedId = 't1/tool-call_1/call_2';
      await _pump(tester, rows, expanded: {_rootRowId: true, nestedId: true});

      expect(_titled('Run $command'), findsOneWidget);
      // Тег исхода — под строкой корня и у вызова внука на своём месте.
      expect(find.text('Allow'), findsNWidgets(2));
      expect(find.text('Reject'), findsNothing);
    });
  });
}
