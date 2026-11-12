// Красные тесты задачи 1.1 (app) change `add-subagents-and-tasks`: spec
// agent-workbench-ui «Чек-лист задач с id, владельцем и блокерами» и «Тихие
// строки операций со списком задач» (D15, D27). Вынесены в отдельный файл,
// чтобы отсутствующий пока API (`CodeLabPlanEntry.taskId/ownerLabel/blockedBy`,
// `CodeLabTaskOpsRow`) не ломал компиляцию соседних тестов; при реализации
// (задача 1.8) файл можно оставить как есть.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _panel(
  List<CodeLabTranscriptRow> rows, {
  CodeLabViewMode viewMode = CodeLabViewMode.normal,
}) => FluentApp(
  home: SizedBox(
    width: 600,
    height: 400,
    child: CodeLabTranscriptPanel(rows: rows, viewMode: viewMode),
  ),
);

void main() {
  // Требование «Чек-лист задач с id, владельцем и блокерами» (agent-workbench-ui,
  // change `add-subagents-and-tasks`, D15, D27). Красные тесты: у
  // `CodeLabPlanEntry` пока нет `taskId`, `ownerLabel` и `blockedBy`.
  // `blockedBy` — уже отфильтрованные незавершённые блокеры: решение, какой
  // блокер завершён, принимает kit (acp-client-kit «Метаданные пунктов
  // плана»), виджет только рисует.
  group('CodeLabProgressChecklist task metadata', () {
    Widget wrap(Widget child) =>
        FluentApp(home: SizedBox(width: 620, height: 400, child: child));

    testWidgets('a task entry shows its id, owner label and open blocker', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CodeLabProgressChecklist.list(
            entries: const [
              CodeLabPlanEntry(
                content: 'Find auth code',
                status: CodeLabPlanEntryStatus.pending,
                priority: CodeLabPlanEntryPriority.medium,
                taskId: '1',
              ),
              CodeLabPlanEntry(
                content: 'Check callers',
                status: CodeLabPlanEntryStatus.inProgress,
                priority: CodeLabPlanEntryPriority.medium,
                taskId: '2',
                ownerLabel: 'explore',
                blockedBy: ['1'],
              ),
            ],
          ),
        ),
      );

      expect(find.textContaining('#1'), findsWidgets);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('explore'), findsOneWidget);
      expect(find.text('blocked by #1'), findsOneWidget);
    });

    testWidgets('several open blockers are listed in order', (tester) async {
      await tester.pumpWidget(
        wrap(
          CodeLabProgressChecklist.list(
            entries: const [
              CodeLabPlanEntry(
                content: 'Ship',
                status: CodeLabPlanEntryStatus.pending,
                priority: CodeLabPlanEntryPriority.medium,
                taskId: '4',
                blockedBy: ['1', '3'],
              ),
            ],
          ),
        ),
      );

      expect(find.text('blocked by #1, #3'), findsOneWidget);
    });

    testWidgets('no blocker mark once the blockers are completed', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CodeLabProgressChecklist.list(
            entries: const [
              CodeLabPlanEntry(
                content: 'Check callers',
                status: CodeLabPlanEntryStatus.inProgress,
                priority: CodeLabPlanEntryPriority.medium,
                taskId: '2',
                ownerLabel: 'explore',
              ),
            ],
          ),
        ),
      );

      expect(find.text('#2'), findsOneWidget);
      expect(find.textContaining('blocked by'), findsNothing);
    });

    testWidgets('an entry without metadata looks as before', (tester) async {
      await tester.pumpWidget(
        wrap(
          CodeLabProgressChecklist.list(
            entries: const [
              CodeLabPlanEntry(
                content: 'Read the module',
                status: CodeLabPlanEntryStatus.pending,
                priority: CodeLabPlanEntryPriority.low,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Read the module'), findsOneWidget);
      expect(find.textContaining('#'), findsNothing);
      expect(find.textContaining('blocked by'), findsNothing);
    });

    testWidgets('the expanded activity-bar section shows the same marks', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CodeLabActivityBar(
            sections: [
              CodeLabProgressChecklist.section(
                id: 'plan',
                entries: const [
                  CodeLabPlanEntry(
                    content: 'Check callers',
                    status: CodeLabPlanEntryStatus.pending,
                    priority: CodeLabPlanEntryPriority.medium,
                    taskId: '2',
                    blockedBy: ['1'],
                  ),
                ],
                onDismiss: () {},
              ),
            ],
          ),
        ),
      );
      // Секция свёрнута, пока пользователь её не раскрыл: раскрываем по
      // заголовку, как в соседних тестах activity bar.
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();

      expect(find.text('#2'), findsOneWidget);
      expect(find.text('blocked by #1'), findsOneWidget);
    });
  });

  // Требование «Тихие строки операций со списком задач» (agent-workbench-ui,
  // change `add-subagents-and-tasks`, D27, артборд 30). Красные тесты:
  // `CodeLabTaskOpsRow` ещё нет. Текст строки целиком даёт kit
  // (`TaskOpsItem`, acp-client-kit «Операции со списком задач в ленте»);
  // лента его не собирает и не разбирает.
  group('quiet task list rows (D27)', () {
    const ops = CodeLabTaskOpsRow(
      id: 'task-ops-1',
      text: 'Tasks #1–#4 added to the plan',
    );

    testWidgets('four merged creations are one quiet row without a Done tag', (
      tester,
    ) async {
      await tester.pumpWidget(_panel(const [ops]));

      expect(find.text('Tasks #1–#4 added to the plan'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(find.byType(CodeLabBadge), findsNothing);
      expect(find.byType(CodeLabToolCallTile), findsNothing);
    });

    testWidgets('the row stays quiet in every view mode', (tester) async {
      for (final mode in CodeLabViewMode.values) {
        await tester.pumpWidget(_panel(const [ops], viewMode: mode));

        expect(find.text('Tasks #1–#4 added to the plan'), findsOneWidget);
        expect(find.text('Done'), findsNothing);
        expect(find.byType(CodeLabToolCallTile), findsNothing);
      }
    });

    testWidgets('a failed operation is a regular call row with its reason', (
      tester,
    ) async {
      // Неуспешный вызов не тихий: kit оставляет его `ToolCallView`
      // (acp-client-kit «Отклонённая операция»), лента рисует обычную строку.
      // Причина видна в раскрытой строке (`verbose` раскрывает вызовы).
      const reason =
          'Invalid task: blocked_by would create a cycle: #2 -> #1 -> #2';
      await tester.pumpWidget(
        _panel(const [
          ops,
          CodeLabToolCallRow(
            id: 'tool-2',
            status: CodeLabToolCallStatus.failed,
            label: 'Task update',
            detail: '#2',
            secondary: reason,
          ),
        ], viewMode: CodeLabViewMode.verbose),
      );

      expect(find.text('Failed'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(find.byType(CodeLabToolCallTile), findsOneWidget);
      expect(find.text('Tasks #1–#4 added to the plan'), findsOneWidget);
    });
  });
}
