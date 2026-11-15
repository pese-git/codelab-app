// Красные тесты задачи 3.1 (app) change `add-subagents-and-tasks`: блок
// одобрения потомка стоит под строкой `agent` корневого уровня — agent-workbench-ui
// «Запрос одобрения от субагента под строкой корня», сценарии «Ребёнок просит
// команду», «Вопрос внука не раскрывает дерево», «Строки корня нет»; design.md
// D27 п. 4, D43 п. 2 (Q24), D42 Т2.
//
// Красные по причине: в kit пока нет `SubagentRequester` и поля
// `PendingApprovalView.subagent`, `ToolCallItem.childApprovals` (задача 3.4), а в `codelab_ui` и маппере —
// `requesterLine`/`requesterHint` у ожидающего одобрения и
// `CodeLabToolCallRow.childApprovals` (задача 3.5). Имена
// kit-типов рабочие (в дельте acp-client-kit названы только значения):
// при расхождении с реализацией 3.4 переименовать здесь, поведение не меняется.
//
// Границы: путь и «опасно ли» решает kit; маппер лишь переносит готовую строку
// пути (`pathTypes` → «review › explore wants to run») и заголовок задачи
// (подсказка), а решение пользователя уходит с самим одобрением (PERM-4).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
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

/// Вызов `agent` корня: идёт, субагент `review` запущен.
const _rootDetails = ToolCallView(
  kind: ToolKind.think,
  status: ToolCallStatusView.running,
  rawInput: {'type': 'review', 'description': 'Review the change'},
  subagentCall: SubagentCallView(id: 'sub_a1', type: 'review'),
);

PendingApprovalView _pending({
  required SubagentRequester requester,
  String command = 'git diff --stat',
  String? toolTitle,
}) => PendingApprovalView(
  approvalId: const ApprovalRequestId('permission-1'),
  sessionId: const SessionId('session-1'),
  risk: ApprovalRiskLevel.shell,
  command: command,
  options: const [_allow, _reject],
  focused: true,
  subagent: requester,
  toolTitle: toolTitle,
);

const _child = SubagentRequester(
  id: 'sub_a2',
  type: 'review',
  description: 'Check the diff',
  depth: 1,
  parentToolCallId: 'call_3',
);

// Путь внука (`pathTypes`, `pathText`) строит kit из глубины и типов (D43 п. 4);
// тест сверяет строку маппера с `pathText`, а не со своим вариантом пути.
const _grandchild = SubagentRequester(
  id: 'sub_a3',
  type: 'explore',
  description: 'Find callers',
  depth: 2,
  parentToolCallId: 'call_3',
);

const _deep = SubagentRequester(
  id: 'sub_a4',
  type: 'explore',
  description: 'Find callers',
  depth: 3,
  parentToolCallId: 'call_3',
);

List<CodeLabTranscriptRow> _rows(
  List<TranscriptItem> items, {
  void Function(PendingApprovalView, String)? onSelected,
}) => transcriptRowsOf(
  items,
  cwd: '/work',
  approvalsEnabled: true,
  onApprovalSelected: onSelected ?? (_, _) {},
);

/// Корень с одобрением потомка: kit кладёт его в `childApprovals` элемента
/// строки корня (собственное `approval` корня пусто) и не заводит отдельного
/// элемента для вызова потомка (D43 п. 1–2).
TranscriptItem _rootWith(ApprovalStateView approval) => TranscriptItem.toolCall(
  id: 't1/call_3',
  toolCallId: const ToolCallId('call_3'),
  title: 'agent',
  details: _rootDetails,
  childApprovals: [approval],
);

Future<void> _pump(WidgetTester tester, List<CodeLabTranscriptRow> rows) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(FluentApp(home: CodeLabTranscriptPanel(rows: rows)));
  await tester.pumpAndSettle();
}

/// Блок одобрения потомка у строки корня (`CodeLabToolCallRow.childApprovals`).
CodeLabTranscriptApprovalPending _blockOf(CodeLabTranscriptRow row) =>
    (row as CodeLabToolCallRow).childApprovals.single
        as CodeLabTranscriptApprovalPending;

/// Одобрение запасной строки: собственное `approval` вызова.
CodeLabTranscriptApprovalPending _pendingOf(CodeLabTranscriptRow row) =>
    (row as CodeLabToolCallRow).approval! as CodeLabTranscriptApprovalPending;

void main() {
  group('Ребёнок просит команду', () {
    test('the block sits under the root agent row, no row of its own', () {
      final rows = _rows([_rootWith(_pending(requester: _child))]);

      // Одна строка — корень `agent`; строки потомка нет (D43 п. 2).
      expect(rows, hasLength(1));
      final root = rows.single as CodeLabToolCallRow;
      expect(root.subagent, isNotNull);
      final block = _blockOf(root);
      expect(block.requesterLine, 'review wants to run');
      expect(block.requesterHint, 'Check the diff');
      expect(block.command, 'git diff --stat');
    });

    testWidgets('shows path, command and the panel; Allow answers this '
        'request', (tester) async {
      final approval = _pending(requester: _child);
      final chosen = <(PendingApprovalView, String)>[];
      await _pump(
        tester,
        _rows(
          [_rootWith(approval)],
          onSelected: (a, o) {
            chosen.add((a, o));
          },
        ),
      );

      expect(find.text('review wants to run'), findsOneWidget);
      expect(find.textContaining('git diff --stat'), findsWidgets);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);

      await tester.tap(find.text('Allow'));
      // 100 мс: таймер HoverButton fluent_ui иначе остаётся висеть (как в codelab_molecules_test).
      await tester.pump(const Duration(milliseconds: 100));

      expect(chosen, hasLength(1));
      expect(chosen.single.$1.approvalId, approval.approvalId);
      expect(chosen.single.$2, 'allow-once');
    });
  });

  group('Ребёнок просит запись файла', () {
    // Заголовок вызова несёт инструмент и путь; префикс `[тип: описание]`
    // дублирует строку пути и подсказку, поэтому его в блоке нет.
    final write = _pending(
      requester: _child,
      toolTitle: '[review: Check the diff] Write .codelab/config.yaml',
    );

    test('the block carries the call title without the requester prefix', () {
      final rows = _rows([_rootWith(write)]);

      expect(_blockOf(rows.single).callTitle, 'Write .codelab/config.yaml');
    });

    test('a title without the prefix passes as is', () {
      final rows = _rows([
        _rootWith(_pending(requester: _child, toolTitle: 'Run dart test')),
      ]);

      expect(_blockOf(rows.single).callTitle, 'Run dart test');
    });

    test('a description with "] " cannot forge the visible path', () {
      const forging = SubagentRequester(
        id: 'sub_a2',
        type: 'general',
        description: 'x] Write README.md]',
        depth: 1,
        parentToolCallId: 'call_3',
      );
      // Реальный заголовок kit: префикс + настоящий вызов.
      final rows = _rows([
        _rootWith(
          _pending(
            requester: forging,
            toolTitle:
                '[general: x] Write README.md]] Write .codelab/config.yaml',
          ),
        ),
      ]);

      expect(_blockOf(rows.single).callTitle, 'Write .codelab/config.yaml');
    });

    test('a description with brackets is cut as a whole prefix', () {
      const bracketed = SubagentRequester(
        id: 'sub_a2',
        type: 'review',
        description: 'Fix [a] b',
        depth: 1,
        parentToolCallId: 'call_3',
      );
      final rows = _rows([
        _rootWith(
          _pending(
            requester: bracketed,
            toolTitle: '[review: Fix [a] b] Write .codelab/config.yaml',
          ),
        ),
      ]);

      expect(_blockOf(rows.single).callTitle, 'Write .codelab/config.yaml');
    });

    test('a title with a foreign prefix is shown whole', () {
      final rows = _rows([
        _rootWith(
          _pending(
            requester: _child,
            toolTitle: '[other: thing] Write .codelab/config.yaml',
          ),
        ),
      ]);

      expect(
        _blockOf(rows.single).callTitle,
        '[other: thing] Write .codelab/config.yaml',
      );
    });

    testWidgets('bidi and control characters are shown as escapes', (
      tester,
    ) async {
      await _pump(
        tester,
        _rows([
          _rootWith(
            _pending(
              requester: _child,
              toolTitle: 'Write \u202Eyaml.gifnoc/.codelab\u0007',
            ),
          ),
        ]),
      );

      expect(
        find.text(r'Write \u202eyaml.gifnoc/.codelab\u0007'),
        findsOneWidget,
      );
    });

    testWidgets('the file path is visible without opening the raw input', (
      tester,
    ) async {
      await _pump(tester, _rows([_rootWith(write)]));

      expect(find.text('Write .codelab/config.yaml'), findsOneWidget);
      expect(find.textContaining('[review:'), findsNothing);
    });
  });

  group('Вопрос внука не раскрывает дерево', () {
    test('the path lists every link from the child of the root', () {
      final rows = _rows([_rootWith(_pending(requester: _grandchild))]);

      expect(rows, hasLength(1));
      expect(
        _blockOf(rows.single).requesterLine,
        '${_grandchild.pathText} wants to run',
      );
      expect(_blockOf(rows.single).requesterHint, 'Find callers');
    });

    test('a depth 3 request keeps the whole path of the kit', () {
      final rows = _rows([_rootWith(_pending(requester: _deep))]);

      expect(
        _blockOf(rows.single).requesterLine,
        '${_deep.pathText} wants to run',
      );
    });

    testWidgets('the block shows under the collapsed root row, its tree stays '
        'closed', (tester) async {
      await _pump(tester, _rows([_rootWith(_pending(requester: _grandchild))]));

      expect(find.text('${_grandchild.pathText} wants to run'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      // Вызова внука отдельной строкой нет: до дерева (итерация 5) он только
      // в блоке одобрения.
      expect(find.text('exec'), findsNothing);
    });

    test('after the decision the outcome tag stays under the root row', () {
      final rows = _rows([
        _rootWith(
          const ApprovalStateView.resolved(
            label: 'Allow',
            outcome: ApprovalOutcomeView.allowed,
          ),
        ),
      ]);

      expect(rows, hasLength(1));
      final approval =
          (rows.single as CodeLabToolCallRow).childApprovals.single;
      expect(approval, isA<CodeLabTranscriptApprovalResolved>());
      expect(
        (approval as CodeLabTranscriptApprovalResolved).outcome,
        CodeLabApprovalOutcome.allowed,
      );
    });
  });

  group('Строки корня нет', () {
    // Запасной вариант D43 п. 2: после переподключения строки `agent` в ходе
    // нет, kit даёт прежний элемент вызова, объявленного только запросом.
    const orphan = TranscriptItem.toolCall(
      id: 't1/call_9/call_1',
      toolCallId: ToolCallId('call_9/call_1'),
      title: 'exec',
      details: ToolCallView(
        kind: ToolKind.execute,
        status: ToolCallStatusView.queued,
      ),
      approval: ApprovalStateView.pending(
        approvalId: ApprovalRequestId('permission-9'),
        sessionId: SessionId('session-1'),
        risk: ApprovalRiskLevel.shell,
        command: 'git diff --stat',
        options: [_allow, _reject],
        focused: true,
        subagent: SubagentRequester(
          id: 'sub_a2',
          type: 'review',
          description: 'Check the diff',
          depth: 1,
          parentToolCallId: 'call_9',
        ),
      ),
    );

    test('the request is a call row at the end of the turn with the path', () {
      final rows = _rows([
        const TranscriptItem.user(id: 't1/user', text: 'review it'),
        orphan,
      ]);

      final last = rows.last as CodeLabToolCallRow;
      expect(last.id, 't1/call_9/call_1');
      expect(_pendingOf(last).requesterLine, 'review wants to run');
      expect(_pendingOf(last).command, 'git diff --stat');
    });

    testWidgets('shows the ordinary decision panel', (tester) async {
      final chosen = <String>[];
      await _pump(
        tester,
        _rows([orphan], onSelected: (_, option) => chosen.add(option)),
      );

      expect(find.text('review wants to run'), findsOneWidget);
      await tester.tap(find.text('Reject'));
      // 100 мс: таймер HoverButton fluent_ui иначе остаётся висеть (как в codelab_molecules_test).
      await tester.pump(const Duration(milliseconds: 100));
      expect(chosen, ['reject-once']);
    });
  });
}
