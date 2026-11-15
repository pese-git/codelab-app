// Приёмка панели Agents v1 на реальном агенте (change
// `add-subagents-and-tasks`, задача 5b.5, D49 Т12; agent-workbench-ui
// «Панель Agents v1»).
//
// Сценарий модели `llm_scripts/agents_pane.json`: корень запускает ребёнка,
// ребёнок — внука, внук просит `exec`. В режиме разрешений `standard` запрос
// идёт к пользователю: строка внука `waiting for approval`, «Go to approval»
// прокручивает ленту к блоку, «Allow» в ленте возвращает строку в `running`,
// выбранная строка показывает дерево шагов.
//
// Идёт только в режимах `dart` и `embedded`: scripted-агент из
// `codelab_acp_testing` субагентов не исполняет. Решает «опасно ли» агент, а
// ответ даёт пользователь в ленте (PERM-4), панель Agents ответа не шлёт.
//
// В `feature/*` файл не запускается (AGENTS.md §21): его проверяет только
// `fvm flutter analyze`; прогон — `test:e2e:app:dart-agent` и
// `test:e2e:app:embedded` в `release/*`.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show SubagentRowState, SubagentRowView;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final e2e = E2eAgent.current;
  final skipScripted = e2e.kind == E2eAgentKind.scripted;

  testWidgets(
    'lists the child and the grandchild, leads to the approval block of the '
    'grandchild, returns the row to running after Allow and shows its steps'
    '${skipScripted ? ' [skipped: the scripted agent does not run subagents]' : ''}',
    skip: skipScripted,
    (tester) async {
      await tester.pumpWidget(e2e.bootstrap());
      await tester.pumpAndSettle();

      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_agents_pane_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });
      // Режим задаёт только `--permission-mode standard`, а сценарий модели
      // назван отдельно (D49 Т12): `CodelabCompatibleStdioAgentMode` не
      // расширяется.
      final launch = await e2e.launch(
        agentDirectory,
        mode: CodelabCompatibleStdioAgentMode.withPermissionRequest,
        script: 'agents_pane',
      );
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await launch.connect(tester, shellCubit);
      expect(find.text('Connected'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'audit the subagents',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

      // Запрос внука приходит через реальный обмен с агентом: ждём по
      // состоянию Cubit-а, а не по кадрам. Не `pumpAndSettle`: ход ждёт
      // одобрения, и спиннер отправки не даёт кадрам успокоиться.
      List<SubagentRowView> rows() => shellCubit.state.agents.rows;
      SubagentRowView? grandchild() {
        for (final row in rows()) {
          if (row.depth == 2) {
            return row;
          }
        }
        return null;
      }

      Future<void> waitFor(bool Function() done, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!done() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(done(), isTrue, reason: reason);
      }

      await waitFor(
        () => grandchild()?.state == SubagentRowState.awaitingApproval,
        'the grandchild must wait for approval of its exec',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // У панели без строк переключателя нет; он появляется с первым
      // субагентом (D49 Т11).
      final toggle = find.byKey(const ValueKey('tool-toggle-agents'));
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 300));

      final child = rows().firstWhere((row) => row.depth == 1);
      final grand = grandchild()!;
      expect(child.state, SubagentRowState.running);
      expect(
        find.byKey(CodeLabAgentsPane.rowKey(child.toolCallId.value)),
        findsOneWidget,
      );
      expect(
        find.byKey(CodeLabAgentsPane.rowKey(grand.toolCallId.value)),
        findsOneWidget,
      );
      final goToApproval = find.byKey(
        CodeLabAgentsPane.goToApprovalKey(grand.toolCallId.value),
      );
      expect(goToApproval, findsOneWidget);

      await tester.tap(goToApproval);
      await tester.pump(const Duration(milliseconds: 300));

      // При окне уже 1280 px док лежит поверх ленты: пользователь сначала
      // убирает его (как в permission_flow_test), вкладка Agents остаётся.
      shellCubit.dismissDockOverlay();
      await tester.pump(const Duration(milliseconds: 500));
      final allow = find.byKey(CodeLabApprovalPrompt.allowKey);
      expect(allow, findsOneWidget);
      // «Go to approval» прокрутила ленту: кнопка внутри окна, а не за краем.
      final window = tester.view.physicalSize / tester.view.devicePixelRatio;
      final center = tester.getCenter(allow);
      expect(
        Rect.fromLTWH(0, 0, window.width, window.height).contains(center),
        isTrue,
        reason: 'the approval block must be scrolled into view',
      );
      expect(find.textContaining('echo subagent-hello'), findsWidgets);

      await tester.tap(allow);
      await tester.pump();

      // Сценарий держит ответ внука 3 с (`delayMs`), поэтому строка успевает
      // побыть `running`, а не сразу `completed`.
      await waitFor(
        () => grandchild()?.state != SubagentRowState.awaitingApproval,
        'the row must leave awaiting approval after Allow',
      );
      expect(grandchild()?.state, SubagentRowState.running);

      shellCubit.openPane(ToolPane.agents);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(CodeLabAgentsPane.rowKey(grand.toolCallId.value)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(shellCubit.state.selectedAgentId, grand.toolCallId.value);
      final steps = find.byKey(CodeLabAgentsPane.stepsKey);
      expect(steps, findsOneWidget);
      expect(
        find.descendant(
          of: steps,
          matching: find.textContaining('subagent-hello', findRichText: true),
        ),
        findsWidgets,
        reason: 'the step tree of the grandchild shows its exec',
      );

      // Ход доходит до конца, строки терминальные.
      await waitFor(
        () => !shellCubit.state.isPromptSubmitting,
        'the turn must complete',
      );
      expect(grandchild()?.state, SubagentRowState.completed);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
