import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «session/load и реплей», сценарий «Повторная загрузка
/// открытой сессии не читает файлы проекта» (design.md change
/// `add-agent-project-files`, D6; §17.2.1 документа ядра).
///
/// Характеризационный тест: `session/load` уже открытой в процессе сессии
/// идёт через `reattach` и не вызывает `AgentRuntime.loadSession`, поэтому
/// порт файлов проекта читается один раз, а изменение `AGENTS.md` между
/// загрузками видно только со следующей сессии. Тест фиксирует это, чтобы
/// правка `agent_server.dart` не вернула перечитывание файлов на каждый
/// `session/load`.
void main() {
  commandsAfterNew();

  test('a second session/load of an open session does not read project '
      'files', () async {
    final port = _CountingPort(
      ProjectFiles(
        context: [ContextFile(path: 'AGENTS.md', content: 'rule A')],
      ),
    );
    final h = await ServerHarness.start(
      projectFiles: port,
      steps: [
        {
          'expect': {
            'systemPrompt': {r'$textContains': 'rule A'},
          },
          'reply': [
            {'text': 'Done.'},
          ],
        },
      ],
    );
    addTearDown(h.dispose);
    await h.initialize();
    final sessionId = await h.newSession();
    expect(port.queries, hasLength(1));

    // AGENTS.md изменён после открытия сессии.
    port.files = ProjectFiles(
      context: [ContextFile(path: 'AGENTS.md', content: 'rule B')],
    );
    final load = await h.client.request('session/load', {
      'sessionId': sessionId,
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });
    expect(load.error, isNull);
    final response = await h.prompt(sessionId, 'Go');

    expect(port.queries, hasLength(1));
    // Модель получила прежний текст: иначе `expect` сценария упал бы.
    expect(response.resultMap['stopReason'], 'end_turn');
    expect(h.model.requests.single.systemPrompt, isNot(contains('rule B')));
  });
}

/// D9: `input` в `available_commands_update` — только при подсказке ввода,
/// `_meta` не добавляется; кадр идёт сразу после ответа `session/new`.
void commandsAfterNew() {
  test('a command without a hint has no input, one with placeholders has '
      'one', () async {
    final h = await ServerHarness.start(
      projectFiles: _CountingPort(
        ProjectFiles(
          templates: [
            MarkdownFile(
              path: '/home/prompts/test.md',
              scope: ExtensionScope.user,
              body: 'Run the tests.',
              bodyLine: 1,
            ),
            MarkdownFile(
              path: '/home/prompts/fix.md',
              scope: ExtensionScope.user,
              body: 'Fix \$1.',
              bodyLine: 1,
            ),
          ],
        ),
      ),
    );
    addTearDown(h.dispose);
    await h.initialize();

    final response = await h.client.request('session/new', {
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });
    final frames = await h.client.drain();
    final update = TestClient.updates(frames).single;

    expect(response.error, isNull);
    expect(update['sessionUpdate'], 'available_commands_update');
    expect(update['availableCommands'], [
      {
        'name': 'fix',
        'description': 'Fix \$1.',
        'input': {'hint': 'arguments'},
      },
      {'name': 'test', 'description': 'Run the tests.'},
    ]);
  });
}

/// Порт, который считает вызовы [load].
final class _CountingPort implements ProjectFilesSource {
  _CountingPort(this.files);

  ProjectFiles files;
  final queries = <ProjectFilesQuery>[];

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async {
    queries.add(query);
    return files;
  }
}
