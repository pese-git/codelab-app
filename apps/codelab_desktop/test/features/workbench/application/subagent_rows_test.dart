// Красные тесты задачи 2.1 (app) change `add-subagents-and-tasks`: маппер
// ленты строит компактную строку вызова `agent` из полей kit
// (`ToolCallView.subagentCall`, `subagentSummary`; D24, D27, D28) —
// agent-workbench-ui «Завершённый субагент свёрнут», «Неуспешный субагент
// сохраняет тег», «Без дерева — строка прогресса».
//
// Вынесены в отдельный файл, чтобы отсутствующее пока API kit
// (`SubagentCallView`, `SubagentSummaryView`) и `CodeLabToolCallRow.subagent`
// не ломали компиляцию `ui_mappers_test.dart`. Имена kit-типов — рабочие
// (в дельте acp-client-kit названы только поля): при расхождении с kit
// переименовать здесь, поведение не меняется.
//
// Границы: заголовок «Subagent <type>: <description>» собирается из
// структурированных полей (`subagentCall.type`, `rawInput.description`), а не
// разбором `title` (D27, п. «Опознание вызова agent»); решение «это вызов
// agent» принимает kit, маппер только переносит его.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

CodeLabToolCallRow _rowOf(ToolCallView details, {String title = 'agent'}) {
  final rows = transcriptRowsOf(
    [
      TranscriptItem.toolCall(
        id: 't1/tool-call-1',
        toolCallId: const ToolCallId('call-1'),
        title: title,
        details: details,
      ),
    ],
    cwd: '/work',
    approvalsEnabled: true,
    onApprovalSelected: (_, _) {},
  );
  return rows.single as CodeLabToolCallRow;
}

const _call = SubagentCallView(id: 'sub_a1', type: 'explore');
const _input = <String, Object?>{
  'type': 'explore',
  'description': 'Find auth code',
  'task': 'Where is the session restored?',
};

void main() {
  group('agent call row', () {
    test('completed: title from type and description, compact summary', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.succeeded,
          rawInput: _input,
          subagentCall: _call,
          subagentSummary: SubagentSummaryView(
            toolCalls: 4,
            inputTokens: 15200,
            outputTokens: 3000,
            duration: Duration(seconds: 48),
          ),
          textOutput: ['Auth lives in lib/auth/session.dart.'],
        ),
        // Заголовок агента не разбирается: структурированные поля главнее.
        title: 'whatever the agent wrote',
      );

      expect(row.status, CodeLabToolCallStatus.succeeded);
      expect(row.label, 'Subagent explore: Find auth code');
      expect(row.detail, isEmpty);
      expect(row.subagent?.stats, '4 tool calls · 18.2k · 48s');
      expect(row.subagent?.progress, isNull);
      // Отчёт — в раскрытии как текстовый вывод.
      expect(row.output, ['Auth lives in lib/auth/session.dart.']);
    });

    test('without description the agent title is the heading', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.succeeded,
          subagentCall: _call,
        ),
        title: 'Find auth code',
      );

      // Без description заголовок — title агента как есть, без разбора и без
      // добавленного типа (D27, D33).
      expect(row.label, 'Find auth code');
      expect(row.subagent?.stats, isNull);
    });

    test('failed keeps its status together with the summary', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.failed,
          rawInput: _input,
          subagentCall: _call,
          subagentSummary: SubagentSummaryView(
            toolCalls: 4,
            inputTokens: 15200,
            outputTokens: 3000,
            duration: Duration(seconds: 48),
          ),
        ),
      );

      expect(row.status, CodeLabToolCallStatus.failed);
      expect(row.subagent?.stats, '4 tool calls · 18.2k · 48s');
    });

    test('cancelled keeps its status', () {
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.cancelled,
          rawInput: _input,
          subagentCall: _call,
        ),
      );

      expect(row.status, CodeLabToolCallStatus.cancelled);
      expect(row.subagent, isNotNull);
    });

    test('a third-party think call without the sign is a regular row', () {
      // Сторонний агент без `_meta.codelab.subagent` (D28): прежняя строка
      // с тегом, без компактного вида.
      final row = _rowOf(
        const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.succeeded,
          rawInput: _input,
        ),
        title: 'Thinking about it',
      );

      expect(row.subagent, isNull);
      expect(row.label, isNot(startsWith('Subagent')));
    });
  });
}
