import 'dart:convert';
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

  test(r'prompt templates: the user one always, the project one only when '
      'the global config trusts the project', () async {
    Future<List<String>> commandsOf({required bool trusted}) async {
      final temp = await Directory.systemTemp.createTemp('codelab_host_tpl_');
      addTearDown(() => temp.delete(recursive: true));
      final project = '${temp.path}/project';
      final home = '${temp.path}/home';
      Directory('$project/.codelab/prompts').createSync(recursive: true);
      Directory('$home/prompts').createSync(recursive: true);
      File('$home/prompts/review.md').writeAsStringSync('Review \$1');
      File('$project/.codelab/prompts/deploy.md').writeAsStringSync('Deploy');
      final trust = trusted
          ? 'trusted_projects: [${jsonEncode(project)}]\n'
          : '';
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
$trust''');
      final host = await buildHost(
        parseServeArgs(
          ['serve', '--stdio'],
          environment: {'CODELAB_HOME': home, 'LLM_KEY': 'sk-test'},
        ),
        cwd: project,
        logger: RecordingLogger(),
      );
      addTearDown(() => host.shutdown(grace: Duration.zero));
      final session = await host.core.runtime.createSession(
        SessionSpec(cwd: project),
      );
      return [for (final c in session.commands) c.name];
    }

    expect(await commandsOf(trusted: false), ['review']);
    expect(await commandsOf(trusted: true), ['deploy', 'review']);
  });

  test(r'agent definitions: the user one always, the project one only when '
      'the global config trusts the project; a model outside the catalog is '
      'a diagnostic', () async {
    Future<(List<String>, RecordingLogger)> agentsOf({
      required bool trusted,
    }) async {
      final temp = await Directory.systemTemp.createTemp('codelab_host_agt_');
      addTearDown(() => temp.delete(recursive: true));
      final project = '${temp.path}/project';
      final home = '${temp.path}/home';
      Directory('$project/.codelab/agents').createSync(recursive: true);
      Directory('$home/agents').createSync(recursive: true);
      File('$home/agents/reviewer.md').writeAsStringSync(
        '---\nname: reviewer\ndescription: Reviews\nmodel: p/m\n---\n'
        'Review body\n',
      );
      File('$home/agents/ghost.md').writeAsStringSync(
        '---\nname: ghost\ndescription: Ghost\nmodel: nope/none\n---\nBody\n',
      );
      File('$project/.codelab/agents/local.md').writeAsStringSync(
        '---\nname: local\ndescription: Local\n---\nLocal body\n',
      );
      final trust = trusted
          ? 'trusted_projects: [${jsonEncode(project)}]\n'
          : '';
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
$trust''');
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
      final session = await host.core.runtime.createSession(
        SessionSpec(cwd: project),
      );
      return ([for (final a in session.agents) a.name], logger);
    }

    final (untrusted, untrustedLog) = await agentsOf(trusted: false);
    expect(untrusted, ['reviewer']);
    expect(
      untrustedLog
          .eventsOf('project_files.diagnostic')
          .map((e) => e.fields['code']),
      containsAll(['untrusted_project', 'invalid_value']),
    );
    expect((await agentsOf(trusted: true)).$1, ['local', 'reviewer']);
    expect(
      [for (final r in untrustedLog.records) r.toString()].join('\n'),
      isNot(contains('Review body')),
    );
  });
}
