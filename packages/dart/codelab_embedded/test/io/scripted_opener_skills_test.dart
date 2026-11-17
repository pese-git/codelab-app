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
/// Страж: навыки из `$CODELAB_HOME/skills` и проекта не видны, потому что у
/// загрузчика `home: null`, а проект недоверенный. Чтение абсолютного `skills.extra_roots`
/// и навыков доверенного проекта этим открывателем проверить нельзя: у
/// `scriptedEmbeddedAgentOpener` нет параметра конфигурации (конфигурация
/// строится из флагов `permissions.mode` и провайдера сценария, а
/// `trusted_projects` и `skills.*` ему не задать) — см. отчёт к задаче 5.1.
void main() {
  test(
    'guard: skills of \$CODELAB_HOME/skills and of the project are not read by the scripted '
    'opener',
    () async {
      final temp = Directory.systemTemp.createTempSync('codelab_scripted_sk_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final home = '${temp.path}/home';
      final project = Directory('${temp.path}/project')
        ..createSync(recursive: true);
      Directory('$home/skills/user-skill').createSync(recursive: true);
      File('$home/skills/user-skill/SKILL.md').writeAsStringSync(
        '---\nname: user-skill\ndescription: Does the thing\n---\nBody\n',
      );
      // Навык проекта: проект сценарного открывателя недоверенный, поэтому
      // `.codelab/skills` и `.agents/skills` тоже не читаются.
      for (final root in ['.codelab/skills', '.agents/skills']) {
        Directory(
          '${project.path}/$root/project-skill',
        ).createSync(recursive: true);
        File('${project.path}/$root/project-skill/SKILL.md').writeAsStringSync(
          '---\nname: project-skill\ndescription: Does the thing\n---\nBody\n',
        );
      }
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
      final session = await client.newSession(
        project.resolveSymbolicLinksSync(),
      );

      await client.prompt(session, 'go');

      final names = <String>{
        for (final update in client.updates)
          if (update['sessionUpdate'] == 'available_commands_update')
            for (final c in update['availableCommands']! as List<Object?>)
              (c! as Map<String, Object?>)['name']! as String,
      };
      expect(names.where((n) => n.startsWith('skill:')), isEmpty);
      // Порт подключён (D19), поэтому фаза навыков отработала ровно один раз и
      // не нашла ни одного навыка; проект недоверенный. Системный промпт
      // сценарного открывателя тест не видит (`llm` не отдаёт запрос), поэтому
      // отсутствие секции каталога следует из пустого `skills.loaded` и
      // отсутствия команд.
      final loaded = logger.eventsOf('skills.loaded').single;
      expect(loaded.fields['names'], isEmpty);
      expect(loaded.fields['project'], isFalse);
    },
  );
}
