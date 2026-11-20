// Тесты состояния панели Agents в app (задача 5b.4 change
// `add-subagents-and-tasks`, D33, D49 Т7–Т9): выбор строки и запрос показа в
// `TranscriptViewCubit`, цели переходов `AgentsPaneData` и строки панели.
// Поведение панели целиком проверяет `presentation/agents_pane_test.dart`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show ToolCallId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/agents_pane_data.dart';
import 'package:codelab_desktop/features/workbench/application/shell_part.dart';
import 'package:codelab_desktop/features/workbench/application/transcript_view_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

SubagentRowView _row(
  String id, {
  SubagentRowState state = SubagentRowState.running,
  List<String> path = const ['t/tool-1'],
  DateTime? startedAt,
  SubagentSummaryView? summary,
  List<String> taskIds = const [],
}) => SubagentRowView(
  toolCallId: ToolCallId(id),
  type: 'explore',
  title: 'Find auth code',
  state: state,
  depth: path.length,
  path: path,
  startedAt: startedAt,
  summary: summary,
  taskIds: taskIds,
);

void main() {
  group('TranscriptViewCubit для панели Agents', () {
    test('выбранная строка хранится по сессиям', () {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);

      cubit
        ..selectAgent(sessionId: 's1', agentId: 'call_1')
        ..selectAgent(sessionId: 's2', agentId: 'call_9');

      expect(cubit.state.selectedAgentFor('s1'), 'call_1');
      expect(cubit.state.selectedAgentFor('s2'), 'call_9');
      expect(cubit.state.selectedAgentFor('s3'), isNull);
      expect(cubit.state.selectedAgentFor(null), isNull);
    });

    test('запрос показа раскрывает путь и растит номер при каждом повторе', () {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);
      const target = AgentsShowTarget(
        rowId: 'tool-1',
        targetId: 't/tool-1/tool-2',
        expand: ['tool-1'],
      );

      cubit.setExpanded(sessionId: 's1', rowId: 'thought-2', expanded: false);
      cubit.requestShow(sessionId: 's1', target: target);
      cubit.requestShow(sessionId: 's1', target: target);

      expect(cubit.state.overridesFor('s1'), {
        'thought-2': false,
        'tool-1': true,
      });
      expect(cubit.state.showRequestFor('s1')?.serial, 2);
      expect(cubit.state.showRequestFor('s1')?.targetId, 't/tool-1/tool-2');
      // Запрос принадлежит своей сессии.
      expect(cubit.state.showRequestFor('s2'), isNull);
    });

    test('выбор строки не стирает раскрытие и запрос', () {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);
      const target = AgentsShowTarget(rowId: 'tool-1', targetId: 'tool-1');

      cubit
        ..requestShow(sessionId: 's1', target: target)
        ..selectAgent(sessionId: 's1', agentId: 'call_1')
        ..setExpanded(sessionId: 's1', rowId: 'tool-1', expanded: true);

      expect(cubit.state.showRequestFor('s1')?.serial, 1);
      expect(cubit.state.selectedAgentFor('s1'), 'call_1');
    });

    // Задача 2.3 change `fix-approval-focus` (D4): признак фокуса едет в том
    // же разовом запросе показа, что и прокрутка.
    test('requestShow(focusApproval: true) кладёт признак в запрос, по '
        'умолчанию его нет', () {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);
      const target = AgentsShowTarget(rowId: 'tool-1', targetId: 'perm-1');

      cubit.requestShow(sessionId: 's1', target: target);
      expect(cubit.state.showRequestFor('s1')?.focusApproval, isFalse);

      cubit.requestShow(sessionId: 's1', target: target, focusApproval: true);
      final request = cubit.state.showRequestFor('s1');
      expect(request?.focusApproval, isTrue);
      expect(request?.serial, 2);
      expect(request?.targetId, 'perm-1');
      // Переход ничего не раскрывает: строка `agent` корня остаётся прежней.
      expect(cubit.state.overridesFor('s1'), isEmpty);
    });

    test('смена сессии гасит запрос вместе с признаком фокуса', () {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);
      cubit.requestShow(
        sessionId: 's1',
        target: const AgentsShowTarget(rowId: 'tool-1', targetId: 'perm-1'),
        focusApproval: true,
      );
      expect(cubit.state.showRequestFor('s1')?.focusApproval, isTrue);

      cubit.dropShowRequestOutside('s2');

      expect(cubit.state.showRequest, isNull);
      expect(cubit.state.showRequestFor('s1'), isNull);
    });

    test('лента закончила показ: запрос с признаком гаснет', () {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);
      cubit.requestShow(
        sessionId: 's1',
        target: const AgentsShowTarget(rowId: 'tool-1', targetId: 'perm-1'),
        focusApproval: true,
      );

      cubit.finishShowRequest(1);

      expect(cubit.state.showRequest, isNull);
    });

    test('запрос разовый: уход фокуса в другую сессию гасит его', () {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);
      const target = AgentsShowTarget(
        rowId: 'tool-1',
        targetId: 'tool-1',
        expand: ['tool-1'],
      );
      cubit
        ..requestShow(sessionId: 's1', target: target)
        ..selectAgent(sessionId: 's1', agentId: 'call_1');

      // Фокус остался на s1: запрос живёт.
      cubit.dropShowRequestOutside('s1');
      expect(cubit.state.showRequestFor('s1')?.serial, 1);

      // Фокус ушёл в s2: запроса нет и при возврате в s1.
      cubit.dropShowRequestOutside('s2');
      expect(cubit.state.showRequest, isNull);
      expect(cubit.state.showRequestFor('s1'), isNull);
      // Выбор пользователя запрос не трогает.
      expect(cubit.state.selectedAgentFor('s1'), 'call_1');
      expect(cubit.state.overridesFor('s1'), {'tool-1': true});
    });

    test('лента сообщила о конце показа: запрос гаснет, номер растёт', () {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);
      const target = AgentsShowTarget(rowId: 'tool-1', targetId: 'tool-1');
      cubit.requestShow(sessionId: 's1', target: target);

      // Устаревший номер (лента могла отчитаться о прежнем показе) не гасит.
      cubit.finishShowRequest(0);
      expect(cubit.state.showRequestFor('s1')?.serial, 1);

      cubit.finishShowRequest(1);
      expect(cubit.state.showRequest, isNull);

      cubit.requestShow(sessionId: 's1', target: target);
      expect(cubit.state.showRequestFor('s1')?.serial, 2);
    });

    test('номер запроса не откатывается после гашения', () {
      // Лента помнит номер последнего исполненного запроса и исполняет
      // только больший: новый запрос с номером 1 после гашения был бы
      // проигнорирован.
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);
      const target = AgentsShowTarget(rowId: 'tool-1', targetId: 'tool-1');

      cubit
        ..requestShow(sessionId: 's1', target: target)
        ..requestShow(sessionId: 's1', target: target)
        ..dropShowRequestOutside('s2')
        ..requestShow(sessionId: 's1', target: target);

      expect(cubit.state.showRequestFor('s1')?.serial, 3);
    });
  });

  group('AgentsPaneData', () {
    test('«Show in transcript»: строка верхнего уровня — она сама', () {
      final data = AgentsPaneData(
        rows: [
          _row('call_1', path: ['t/tool-1']),
        ],
        topRowIds: const {'t/tool-1': 'tool-3'},
      );

      final target = data.showTargetOf('call_1')!;

      expect(target.rowId, 'tool-3');
      expect(target.targetId, 'tool-3');
      expect(target.expand, isEmpty);
      expect(data.showTargetOf('nope'), isNull);
    });

    test('«Show in transcript»: у внука раскрыты корень и промежуточный', () {
      final data = AgentsPaneData(
        rows: [
          _row('call_3', path: ['t/tool-1', 't/tool-1/tool-2', 't/tool-1/x']),
        ],
        topRowIds: const {'t/tool-1': 'tool-1'},
      );

      final target = data.showTargetOf('call_3')!;

      expect(target.rowId, 'tool-1');
      expect(target.targetId, 't/tool-1/x');
      expect(target.expand, ['tool-1', 't/tool-1/tool-2']);
    });

    test('устаревший выбор не даёт ни шагов, ни переходов', () {
      const data = AgentsPaneData();

      expect(data.stepsOf('call_1', const []), isEmpty);
      expect(data.approvalTargetOf('call_1', const []), isNull);
    });
  });

  group('agentRowsOf', () {
    final started = DateTime.utc(2026, 11, 16, 12);

    test('время работающей строки — от startedAt, только пока занята', () {
      final rows = [_row('call_1', startedAt: started)];

      final busy = agentRowsOf(
        AgentsPaneData(rows: rows, busy: true),
        now: started.add(const Duration(seconds: 125)),
        l10n: AppLocalizationsEn(),
      );
      final idle = agentRowsOf(
        AgentsPaneData(rows: rows),
        now: started.add(const Duration(seconds: 125)),
        l10n: AppLocalizationsEn(),
      );

      expect(busy.single.time, '2m 05s');
      expect(busy.single.state, CodeLabAgentRowState.running);
      expect(idle.single.time, isNull);
      expect(idle.single.state, CodeLabAgentRowState.running);
    });

    test('часы назад не дают отрицательного времени', () {
      final rows = agentRowsOf(
        AgentsPaneData(rows: [_row('call_1', startedAt: started)], busy: true),
        now: started.subtract(const Duration(seconds: 5)),
        l10n: AppLocalizationsEn(),
      );

      expect(rows.single.time, '0s');
    });

    test('терминальная строка: итог из summary и подсказка пункта плана', () {
      final rows = agentRowsOf(
        AgentsPaneData(
          rows: [
            _row(
              'call_1',
              state: SubagentRowState.completed,
              summary: const SubagentSummaryView(
                toolCalls: 2,
                inputTokens: 9000,
                outputTokens: 1200,
                duration: Duration(seconds: 19),
              ),
              taskIds: const ['2', '9'],
            ),
          ],
          planTitles: const {'2': 'Check callers'},
        ),
        now: started,
        l10n: AppLocalizationsEn(),
      );

      final row = rows.single;
      expect(row.state, CodeLabAgentRowState.done);
      expect(row.time, '19s');
      expect(row.tokens, '10.2k tokens');
      expect(row.items.map((item) => item.label), ['#2', '#9']);
      expect(row.items.first.hint, 'Check callers');
      expect(row.items.last.hint, isNull);
    });

    test('счётчики берутся из kit, а не пересчитываются по строкам UI', () {
      final counts = agentCountsOf(
        const AgentsPaneData(
          counts: {
            SubagentRowState.completed: 3,
            SubagentRowState.awaitingApproval: 1,
          },
        ),
      );

      expect(counts[CodeLabAgentRowState.done], 3);
      expect(counts[CodeLabAgentRowState.waitingForApproval], 1);
      expect(counts[CodeLabAgentRowState.running], 0);
      expect(counts[CodeLabAgentRowState.failed], 0);
      expect(counts[CodeLabAgentRowState.cancelled], 0);
    });
  });
}
