import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:test/test.dart';

import '../skills/skills_support.dart';
import '../support/package_dir.dart';

/// Промпт ребёнка с навыками (agent-prompts «Детерминированная сборка
/// системного промпта», сценарий «Промпт ребёнка с навыками»; PR-3, PR-6;
/// design.md change `add-subagents-and-tasks`, D34, D36 Т11; задача 2s.1;
/// `agent-core/17-3-subagents.md` §17.3.3, шаг 8).
///
/// Красный до задач 2.4 и 2s.2: у `PromptInputs` нет поля `subagent`, а
/// секции `subagent/system` и профиля типа не собираются.
///
/// Фиксируемый API: `PromptInputs.subagent` — запись `({String name, String
/// body, TaskItem? task})?`: тип, тело определения и назначенный пункт
/// (`null` — пункта нет). Текст `subagent/system` в golden — дословно §17.3.3
/// (файл `prompts/subagent/system.md`); тело профиля в golden задаёт сам
/// тест, а не `prompts/subagent/types/general.md`, поэтому правка текста
/// встроенного типа golden не ломает.
void main() {
  const toolNames = {
    'read',
    'write',
    'edit',
    'ls',
    'search',
    'exec',
    'skill',
    'task_update',
    'task_list',
    'task_get',
  };

  final skills = parse([
    validSkill('release-notes'),
    validSkill('flutter-golden'),
  ]).modelVisible;

  PromptInputs child({
    Set<String> tools = toolNames,
    List<SkillDefinition>? catalog,
  }) => PromptInputs(
    cwd: '/proj',
    platform: 'linux',
    today: DateTime.utc(2026, 1, 15, 23, 59),
    mode: ModeId.standard,
    profile: HostProfile.of('agent-serve'),
    toolNames: tools,
    skills: catalog ?? skills,
    subagent: (
      name: 'general',
      body: 'Handle the assignment end to end.',
      task: null,
    ),
  );

  PromptInputs parent() => PromptInputs(
    cwd: '/proj',
    platform: 'linux',
    today: DateTime.utc(2026, 1, 15, 23, 59),
    mode: ModeId.standard,
    profile: HostProfile.of('agent-serve'),
    toolNames: {...toolNames, 'task_create', 'agent'},
    skills: skills,
  );

  String skillsSection(String prompt) {
    final from = prompt.indexOf('## Skills');
    expect(from, isNonNegative);
    final end = prompt.indexOf('You are a subagent');
    return (end < 0 ? prompt.substring(from) : prompt.substring(from, end))
        .trimRight();
  }

  test('сценарий «Промпт ребёнка с навыками»: совпадает с '
      'test/prompts/golden/subagent-general-skills.txt', () {
    final text = composeSystemPrompt(child());

    final file = File(
      corePath('test/prompts/golden/subagent-general-skills.txt'),
    );
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    expect(file.existsSync(), isTrue, reason: 'запустите с UPDATE_GOLDEN=1');
    expect(text, file.readAsStringSync());
  });

  test('секция ## Skills побайтово равна секции родителя, перед ней нет '
      'tools/tasks (у ребёнка нет task_create), после — subagent/system и '
      'профиль типа', () {
    final childPrompt = composeSystemPrompt(child());
    final parentPrompt = composeSystemPrompt(parent());

    expect(skillsSection(childPrompt), skillsSection(parentPrompt));
    expect(childPrompt, isNot(contains('# Task list')));
    expect(
      childPrompt.indexOf('## Skills'),
      lessThan(childPrompt.indexOf('You are a subagent')),
    );
    expect(
      childPrompt.indexOf('You are a subagent'),
      lessThan(childPrompt.indexOf('## Agent profile: general')),
    );
  });

  test('PR-6: без skill в наборе ребёнка секции каталога нет, хотя снимок '
      'передан', () {
    final text = composeSystemPrompt(
      child(tools: {...toolNames}..remove('skill')),
    );

    expect(text, isNot(contains('## Skills')));
    expect(text, contains('## Agent profile: general'));
  });

  test('одинаковые входы дают одинаковые байты', () {
    expect(composeSystemPrompt(child()), composeSystemPrompt(child()));
  });
}
