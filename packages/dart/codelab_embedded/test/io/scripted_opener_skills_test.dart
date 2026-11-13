import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

import '../support/acp_client.dart';

/// Сценарный открыватель подключает навыки как `--llm-script`: пользовательский
/// уровень не читается (agent-skills «Навыки в хостах», сценарий «Сценарий
/// модели без пользовательского уровня»; design.md change `add-agent-skills`,
/// D19, матрица хостов).
///
/// Страж (зелёный сразу и должен остаться после 5.2): навык из
/// `$CODELAB_HOME/skills` не виден — сейчас потому, что порта навыков нет,
/// после 5.2 потому, что `home: null`. Чтение абсолютного `skills.extra_roots`
/// и навыков доверенного проекта этим открывателем проверить нельзя: у
/// `scriptedEmbeddedAgentOpener` нет параметра конфигурации (конфигурация
/// строится из флагов `permissions.mode` и провайдера сценария, а
/// `trusted_projects` и `skills.*` ему не задать) — см. отчёт к задаче 5.1.
void main() {
  test('guard: a skill of \$CODELAB_HOME/skills is not read by the scripted '
      'opener', () async {
    final temp = Directory.systemTemp.createTempSync('codelab_scripted_sk_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final home = '${temp.path}/home';
    final project = Directory('${temp.path}/project')
      ..createSync(recursive: true);
    Directory('$home/skills/user-skill').createSync(recursive: true);
    File('$home/skills/user-skill/SKILL.md').writeAsStringSync(
      '---\nname: user-skill\ndescription: Does the thing\n---\nBody\n',
    );
    final logger = RecordingLogger();
    final agent = await scriptedEmbeddedAgentOpener(
      llm: {
        'steps': [
          {
            'reply': [
              {'text': 'ok'},
            ],
            'stopReason': 'stop',
          },
        ],
      },
      codelabHome: home,
      logger: logger,
    )(cwd: project.path, hostProfile: 'embedded-cli');
    addTearDown(agent.dispose);
    final client = TestAcpClient(agent.clientTransport);
    addTearDown(client.close);
    await client.start();
    await client.initialize();
    final session = await client.newSession(project.resolveSymbolicLinksSync());

    await client.prompt(session, 'go');

    final names = <String>{
      for (final update in client.updates)
        if (update['sessionUpdate'] == 'available_commands_update')
          for (final c in update['availableCommands']! as List<Object?>)
            (c! as Map<String, Object?>)['name']! as String,
    };
    expect(names.where((n) => n.startsWith('skill:')), isEmpty);
    for (final event in logger.eventsOf('skills.loaded')) {
      expect(event.fields['names'], isEmpty);
    }
  });
}
