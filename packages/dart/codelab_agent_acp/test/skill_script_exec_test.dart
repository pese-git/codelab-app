import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Запуск скрипта навыка проекта через клиента ACP (`terminal/*`): оба шага
/// решения Q24 (а), Q26 (acp-golden-fixtures «Фикстуры навыков», задача 3.1
/// change `add-agent-skills`; design.md D5, D17).
///
/// Почему тест, а не только фикстура `acp/skill-script-exec`: второй шаг —
/// `exec` с абсолютным путём скрипта — требует знать временную папку прогона
/// в аргументах вызова модели, а `ScriptedStreamFunction` подставляет `${cwd}`
/// только в `text` и `thinking`. Фикстура проверяет первый шаг, тест — оба
/// на фейковом клиенте.
///
/// Тест закрепляет поведение итерации 2 (PERM-11, `execOnHost`), поэтому он
/// зелёный сразу; красным он был бы ошибкой: значит, навык проекта внутри
/// рабочей папки стал отклоняться как «вне рабочей папки» либо вопрос уровня
/// `exec` пропал или стал критическим.
void main() {
  late Directory root;
  late String cwd;
  late ServerHarness h;
  final created = <Map<String, Object?>>[];
  final permissions = <Map<String, Object?>>[];

  setUp(() async {
    created.clear();
    permissions.clear();
    root = Directory.systemTemp.createTempSync('skill_script_exec_');
    cwd = root.resolveSymbolicLinksSync();
    final skill = Directory('$cwd/.codelab/skills/pdf/scripts')
      ..createSync(recursive: true);
    File('$cwd/.codelab/skills/pdf/SKILL.md').writeAsStringSync(
      '---\nname: pdf\ndescription: Extract text from PDF files\n---\n'
      'Run scripts/extract.py on the PDF.\n',
    );
    File('${skill.path}/extract.py').writeAsStringSync("print('page 1')\n");

    final loader = ProjectFilesLoader(
      home: root.path,
      local: LocalExecutionEnv(cwd: cwd),
    );
    final script = '$cwd/.codelab/skills/pdf/scripts/extract.py';
    h = await ServerHarness.start(
      // Как у бинаря: база — машинный env, иначе E1–E3 не действуют.
      baseEnv: LocalExecutionEnv(cwd: cwd),
      projectFiles: loader,
      skillFiles: loader,
      trustedProjects: [cwd],
      steps: [
        {
          'reply': [
            {
              'toolCall': {
                'id': 'call_1',
                'name': 'exec',
                'arguments': {
                  'command': 'python3 scripts/extract.py',
                  'cwd': '.codelab/skills/pdf',
                },
              },
            },
          ],
          'stopReason': 'toolUse',
        },
        {
          'expect': {
            'toolResult': {'toolCallId': 'call_1', 'isError': false},
          },
          'reply': [
            {
              'toolCall': {
                'id': 'call_2',
                'name': 'exec',
                'arguments': {'command': 'python3 $script', 'cwd': '.'},
              },
            },
          ],
          'stopReason': 'toolUse',
        },
        {
          'expect': {
            'toolResult': {'toolCallId': 'call_2', 'isError': false},
          },
          'reply': [
            {'text': 'Готово.'},
          ],
          'stopReason': 'stop',
        },
      ],
    );
    h.client.handlers['session/request_permission'] = (request) {
      permissions.add(request.params! as Map<String, Object?>);
      return {
        'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
      };
    };
    h.client.handlers['terminal/create'] = (request) {
      created.add(request.params! as Map<String, Object?>);
      return {'terminalId': 'term_${created.length}'};
    };
    h.client.handlers['terminal/wait_for_exit'] = (_) => {'exitCode': 0};
    h.client.handlers['terminal/output'] = (_) => {
      'output': 'page 1\n',
      'truncated': false,
    };
    h.client.handlers['terminal/release'] = (_) => <String, Object?>{};
    await h.initialize();
  });

  tearDown(() async {
    await h.dispose();
    root.deleteSync(recursive: true);
  });

  test('step 1: cwd in the project skill dir; step 2: the absolute script '
      'path with the project cwd — each an ordinary exec question and a '
      'terminal/create', () async {
    final sessionId = await h.newSession(cwd: cwd);

    final response = await h.prompt(sessionId, 'Extract text from the PDF');

    expect(response.resultMap['stopReason'], 'end_turn');
    // Два обычных вопроса уровня `exec`: без критического шаблона есть
    // `allow_always` (Q24 (а), Q25).
    expect(permissions, hasLength(2));
    for (final request in permissions) {
      final kinds = [
        for (final option in request['options']! as List<Object?>)
          (option! as Map<String, Object?>)['kind'],
      ];
      expect(kinds, contains('allow_always'));
      expect(kinds, contains('allow_once'));
    }
    final script = '$cwd/.codelab/skills/pdf/scripts/extract.py';
    expect(created, hasLength(2));
    expect(created[0]['args'], ['-c', 'python3 scripts/extract.py']);
    expect(created[0]['cwd'], '$cwd/.codelab/skills/pdf');
    expect(created[1]['args'], ['-c', 'python3 $script']);
    expect(created[1]['cwd'], cwd);
    final completed = [
      for (final update in TestClient.updates(h.client.received))
        if (update['sessionUpdate'] == 'tool_call_update' &&
            update['status'] == 'completed')
          update['toolCallId'],
    ];
    expect(completed, ['call_1', 'call_2']);
  });
}
