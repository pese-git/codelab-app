import 'dart:io';

import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'support/build_host.dart';

/// `AgentHost.build` передаёт ядру `ProjectFilesLoader` с `$CODELAB_HOME`
/// процесса (agent-binary «Файлы проекта в бинаре», сценарий «Шаблон
/// пользователя» в части контекста; design.md change
/// `add-agent-project-files`, D16). Хост поднимается в процессе теста,
/// настоящий `~/.codelab` не читается.
void main() {
  test(r'the user file and the project file reach the session; the log '
      'names them and does not quote them', () async {
    final temp = await Directory.systemTemp.createTemp('codelab_host_pf_');
    addTearDown(() => temp.delete(recursive: true));
    final project = '${temp.path}/project';
    final home = '${temp.path}/home';
    Directory(project).createSync();
    Directory(home).createSync();
    File('$home/AGENTS.md').writeAsStringSync('user-rule-text\n');
    File('$project/AGENTS.md').writeAsStringSync('project-rule-text\n');
    File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_env: LLM_KEY
    models:
      m: {}
agent:
  default_model: p/m
''');
    final logger = RecordingLogger();
    final host = await buildHost(
      parseServeArgs(
        ['serve', '--stdio'],
        environment: {'CODELAB_HOME': home, 'LLM_KEY': 'sk-test'},
      ),
      cwd: project,
      logger: logger,
    );
    addTearDown(() => host.shutdown(grace: Duration.zero));

    await host.core.runtime.createSession(SessionSpec(cwd: project));

    final loaded = logger.eventsOf('project_context.loaded').single;
    expect(loaded.fields['files'], [r'$CODELAB_HOME/AGENTS.md', 'AGENTS.md']);
    expect(loaded.fields['root'], 'cwd');
    expect(
      [for (final r in logger.records) r.toString()].join('\n'),
      isNot(contains('rule-text')),
    );
  });

  test('over WebSocket the port is not passed: one project_files.skipped, '
      'no project_context.loaded, even for CODELAB_HOME', () async {
    final temp = await Directory.systemTemp.createTemp('codelab_host_ws_');
    addTearDown(() => temp.delete(recursive: true));
    final project = '${temp.path}/project';
    final home = '${temp.path}/home';
    Directory(project).createSync();
    Directory(home).createSync();
    File('$home/AGENTS.md').writeAsStringSync('user-rule-text\n');
    File('$project/AGENTS.md').writeAsStringSync('project-rule-text\n');
    File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_env: LLM_KEY
    models:
      m: {}
agent:
  default_model: p/m
''');
    final logger = RecordingLogger();
    final host = await buildHost(
      parseServeArgs(
        ['serve', '--ws', '--port', '0'],
        environment: {
          'CODELAB_HOME': home,
          'LLM_KEY': 'sk-test',
          'CODELAB_AGENT_TOKEN': 'secret-token',
        },
      ),
      cwd: project,
      logger: logger,
    );
    addTearDown(() => host.shutdown(grace: Duration.zero));

    await host.core.runtime.createSession(SessionSpec(cwd: project));

    final skipped = logger.eventsOf('project_files.skipped').single;
    expect(skipped.fields['transport'], 'ws');
    expect(logger.eventsOf('project_context.loaded'), isEmpty);
  });
}
