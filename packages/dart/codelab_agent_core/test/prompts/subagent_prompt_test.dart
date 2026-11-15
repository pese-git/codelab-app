import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:test/test.dart';

import '../support/package_dir.dart';

/// Промпт ребёнка с назначенным пунктом (agent-prompts «Детерминированная
/// сборка системного промпта», сценарий «Промпт ребёнка»; PR-3, PR-6, TSK-4;
/// design.md change `add-subagents-and-tasks`, D10, D45 Т1, Т8;
/// `agent-core/17-3-subagents.md` §17.3.3, шаг 8).
///
/// Характеризующий, зелёный сразу: `composeSystemPrompt` уже собирает секцию
/// 14 `subagent/task` из `PromptInputs.subagent.task` (D45 Т1), поэтому
/// golden фиксирует вид промпта. Красная часть — подключение пункта рантаймом
/// (`PromptInputs.subagent.task` у ребёнка корня передаётся `null`) —
/// проверяется в `test/tools/tasks/task_list_owner_test.dart`, задача 4.5.
void main() {
  const toolNames = {
    'read',
    'ls',
    'search',
    'task_update',
    'task_list',
    'task_get',
  };

  PromptInputs child({TaskItem? task}) => PromptInputs(
    cwd: '/proj',
    platform: 'linux',
    today: DateTime.utc(2026, 1, 15, 23, 59),
    mode: ModeId.plan,
    profile: HostProfile.of('agent-serve'),
    toolNames: toolNames,
    subagent: (
      name: 'explore',
      body: 'Search the code read-only and report what you found.',
      task: task,
    ),
  );

  final assigned = TaskItem(id: '2', subject: 'Locate the parser');

  test(
    'сценарий «Промпт ребёнка»: после секций базы идут subagent/system, '
    '## Agent profile: explore и строка Your task; секции tools/tasks нет; '
    'результат совпадает с test/prompts/golden/subagent-explore-plan.txt',
    () {
      final text = composeSystemPrompt(child(task: assigned));

      final file = File(
        corePath('test/prompts/golden/subagent-explore-plan.txt'),
      );
      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      }
      expect(file.existsSync(), isTrue, reason: 'запустите с UPDATE_GOLDEN=1');
      expect(text, file.readAsStringSync());
      expect(
        text.indexOf('You are a subagent'),
        lessThan(text.indexOf('## Agent profile: explore')),
      );
      expect(
        text.indexOf('## Agent profile: explore'),
        lessThan(text.indexOf('Your task: #2 Locate the parser')),
      );
      expect(text, isNot(contains('# Task list')));
    },
  );

  test('без назначенного пункта строки Your task нет', () {
    expect(composeSystemPrompt(child()), isNot(contains('Your task:')));
  });

  test('одинаковые входы дают одинаковые байты', () {
    expect(
      composeSystemPrompt(child(task: assigned)),
      composeSystemPrompt(child(task: assigned)),
    );
  });
}
