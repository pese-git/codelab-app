import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart' show textStep;
import 'skill_command_rig.dart';
import 'skills_support.dart';

/// Наблюдаемость активации навыков (agent-skills «Наблюдаемость навыков»,
/// сценарий «Лог без тела»; agent-skills «Команды навыков» — абзац о логах;
/// design.md change `add-agent-skills`, D13; `AGENTS.md` §16).
///
/// Тело навыка, аргументы команды и содержимое сопутствующих файлов в логи не
/// попадают; в лог идут имя, способ активации и размер ввода. Сквозной тест
/// через `createSession` + `prompt`: события пишут инструмент `skill` (2.4) и
/// разбор `/skill:` (3.4).
void main() {
  const secretBody = 'secret-token-123';
  const secretArg = 'secret-arg';

  SkillFile releaseNotes() =>
      validSkill('release-notes', body: 'Use $secretBody as the key.');

  test('scenario "Лог без тела": skill.activated for the tool and for the '
      'command, command.expanded with args_bytes, no body and no '
      'arguments in any log', () async {
    final rig = SkillCommandRig(
      skills: [releaseNotes()],
      steps: [
        loadSkillStep('c1', 'release-notes'),
        textStep('done'),
        textStep('done 2'),
      ],
    );
    await rig.open();

    await rig.ask('go');
    await rig.ask('/skill:release-notes $secretArg');

    final activations = rig.logger.eventsOf('skill.activated');
    expect([for (final a in activations) a.fields['via']], ['tool', 'command']);
    for (final a in activations) {
      expect(a.level, LogLevel.info);
      expect(a.fields['name'], 'release-notes');
      expect(a.fields['session_id'], rig.session.id.value);
      expect(a.fields, contains('repeated'));
    }
    final expanded = rig.logger.eventsOf('command.expanded').single;
    expect(expanded.fields['source'], 'skill');
    expect(expanded.fields['args_bytes'], secretArg.length);
    expect(expanded.fields['session_id'], rig.session.id.value);
    expect(rig.allLogs, isNot(contains(secretBody)));
    expect(rig.allLogs, isNot(contains(secretArg)));
  });

  test('the command alone: via command, repeated false on the first '
      'activation, args_bytes counts UTF-8 bytes', () async {
    final rig = SkillCommandRig(
      skills: [releaseNotes()],
      steps: [textStep('done')],
    );
    await rig.open();

    await rig.ask('/skill:release-notes секрет');

    final activated = rig.logger.eventsOf('skill.activated').single;
    expect(activated.fields['via'], 'command');
    expect(activated.fields['repeated'], false);
    expect(
      rig.logger.eventsOf('command.expanded').single.fields['args_bytes'],
      'секрет'.length * 2,
    );
    expect(rig.allLogs, isNot(contains('секрет')));
  });

  test('an unknown skill logs no activation and no expansion', () async {
    final rig = SkillCommandRig(skills: [releaseNotes()]);
    await rig.open();

    await rig.ask('/skill:nope $secretArg');

    expect(rig.logger.eventsOf('skill.activated'), isEmpty);
    expect(rig.logger.eventsOf('command.expanded'), isEmpty);
    expect(rig.allLogs, isNot(contains(secretArg)));
  });
}
