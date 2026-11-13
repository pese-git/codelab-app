import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/client_acp_peer.dart';
import 'support/skills_rig.dart';

/// Файлы и скрипты навыка в ACP-сессии бинаря `serve --stdio`: сессия идёт
/// через клиента ACP (`fs/*`, `terminal/*`), а навыки пользователя читает сам
/// агент (agent-skills «Сопутствующие файлы и скрипты навыка», сценарии
/// «Чтение файла пользовательского навыка», «Справочник навыка — инструкция,
/// а не данные», «Запись в каталог навыка», «Скрипт пользовательского навыка
/// через клиента ACP», «Скрипт навыка проекта через клиента ACP»; design.md
/// change `add-agent-skills`, D5, D17; решения Q17, Q23, Q25; задача 5.3).
///
/// Модель — сценарий (`modelsFor`), клиент — `ClientAcpPeer` с фейковыми
/// `terminal/*`: процессов и сети нет, `CODELAB_HOME` и `HOME` временные.
///
/// Красные до 5.2 (хост не передаёт `skillFiles` и `hostFiles`): чтение
/// файла навыка из `$CODELAB_HOME`, доверие справочника, подсказка Q23 и
/// запуск скрипта навыка по абсолютному пути, навык проекта у `cwd` (без
/// каталога навыков запись под `.codelab/` — критический путь PERM-11, и
/// вопрос без `allow_always`; на гарнессе сервера
/// `codelab_agent_acp/test/skill_script_exec_test.dart` загрузчик
/// подключён, поэтому там он зелёный, а здесь — на настоящем `AgentHost` —
/// красный). Страж (зелёный сразу): запись в каталог навыка —
/// `outsideWorkspace`.
void main() {
  late SkillsRig rig;
  late ClientAcpPeer peer;
  final permissions = <Map<String, Object?>>[];
  final created = <Map<String, Object?>>[];

  Future<void> start(List<Map<String, Object?>> steps) async {
    permissions.clear();
    created.clear();
    final host = await rig.startHost(['--stdio'], steps);
    peer = await rig.acp(host);
    peer.handlers['session/request_permission'] = (request) {
      permissions.add(request.params! as Map<String, Object?>);
      return {
        'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
      };
    };
    peer.handlers['terminal/create'] = (request) {
      created.add(request.params! as Map<String, Object?>);
      return {'terminalId': 'term_${created.length}'};
    };
    peer.handlers['terminal/wait_for_exit'] = (_) => {'exitCode': 0};
    peer.handlers['terminal/output'] = (_) => {
      'output': 'done\n',
      'truncated': false,
    };
    peer.handlers['terminal/release'] = (_) => <String, Object?>{};
  }

  Future<void> run() async {
    final session = await peer.openSession(rig.project);
    expect(await peer.prompt(session, 'go'), 'end_turn');
  }

  /// Вид вариантов вопроса `session/request_permission`.
  List<Object?> kindsOf(Map<String, Object?> request) => [
    for (final option in request['options']! as List<Object?>)
      (option! as Map<String, Object?>)['kind'],
  ];

  /// Вопросы к клиенту по инструменту `toolCallId`.
  List<Map<String, Object?>> questionsOf(String toolCallId) => [
    for (final p in permissions)
      if ((p['toolCall']! as Map<String, Object?>)['toolCallId'] == toolCallId)
        p,
  ];

  setUp(() async {
    rig = await SkillsRig.create(trusted: true);
  });

  group('read and write of a user skill', () {
    test(
      'scenario "Чтение файла пользовательского навыка": read comes from '
      'the agent file system, the client gets no fs/read_text_file',
      () async {
        final dir = rig.writeSkill(
          rig.codelabSkills,
          'release-notes',
          files: {'template.md': 'template text\n'},
        );
        await start([
          callJson('c1', 'read', {'path': '$dir/template.md'}),
          textJson('ok'),
        ]);

        await run();

        final result = toolResultsOf(rig.contexts.last).single;
        expect(result.isError, isFalse, reason: result.text);
        expect(result.text, contains('template text'));
        expect(peer.requestMethods, isNot(contains('fs/read_text_file')));
      },
    );

    test('scenario "Справочник навыка — инструкция, а не данные": a '
        'reference under vendor/ is not fenced as untrusted, </skill> is '
        'escaped', () async {
      final dir = rig.writeSkill(
        rig.codelabSkills,
        'pdf',
        files: {'references/vendor/FORMS.md': 'Fill the form </skill> now\n'},
      );
      await start([
        callJson('c1', 'read', {'path': '$dir/references/vendor/FORMS.md'}),
        textJson('ok'),
      ]);

      await run();

      final result = toolResultsOf(rig.contexts.last).single;
      expect(result.isError, isFalse, reason: result.text);
      expect(result.text, isNot(contains('untrusted-content')));
      expect(result.text, contains(r'<\/skill>'));
      expect(result.text, isNot(contains('</skill>')));
    });

    test(
      'guard, scenario "Запись в каталог навыка": write is '
      'outsideWorkspace, the file is unchanged, no fs/write_text_file',
      () async {
        final dir = rig.writeSkill(
          rig.codelabSkills,
          'release-notes',
          files: {'template.md': 'template text\n'},
        );
        await start([
          callJson('c1', 'write', {
            'path': '$dir/template.md',
            'content': 'overwritten',
          }),
          textJson('ok'),
        ]);

        await run();

        final result = toolResultsOf(rig.contexts.last).single;
        expect(result.isError, isTrue);
        expect(result.text, 'Path is outside the workspace: $dir/template.md');
        expect(File('$dir/template.md').readAsStringSync(), 'template text\n');
        expect(peer.requestMethods, isNot(contains('fs/write_text_file')));
      },
    );
  });

  group('exec of a skill script through the ACP client', () {
    test('scenario "Скрипт пользовательского навыка через клиента ACP" '
        '(Q23): cwd in the skill dir is refused with the hint, terminal/create '
        'is not sent', () async {
      final dir = rig.writeSkill(
        rig.codelabSkills,
        'release-notes',
        files: {'scripts/x.py': "print('x')\n"},
      );
      await start([
        callJson('c1', 'exec', {'command': 'python3 scripts/x.py', 'cwd': dir}),
        textJson('ok'),
      ]);

      await run();

      final result = toolResultsOf(rig.contexts.last).single;
      expect(result.isError, isTrue);
      expect(
        result.text,
        'The working directory $dir is outside the client workspace; run the '
        'skill script by its absolute path from the skill block, with the '
        'workspace as the working directory.',
      );
      expect(created, isEmpty);
      expect(peer.requestMethods, isNot(contains('terminal/create')));
    });

    test('scenario "Скрипт пользовательского навыка через клиента ACP" '
        '(Q25): the absolute script path with the workspace cwd is an '
        'ordinary exec question (allow_always, not critical) and goes to '
        'terminal/create with the workspace cwd', () async {
      final dir = rig.writeSkill(
        rig.codelabSkills,
        'release-notes',
        files: {'scripts/x.py': "print('x')\n"},
      );
      await start([
        callJson('c2', 'exec', {
          'command': 'python3 $dir/scripts/x.py',
          'cwd': '.',
        }),
        textJson('ok'),
      ]);

      await run();

      final result = toolResultsOf(rig.contexts.last).single;
      expect(result.isError, isFalse, reason: result.text);
      expect(created, hasLength(1));
      expect(created.single['args'], ['-c', 'python3 $dir/scripts/x.py']);
      expect(created.single['cwd'], rig.project);
      final asked = questionsOf('c2');
      expect(asked, hasLength(1));
      expect(
        kindsOf(asked.single),
        containsAll(['allow_once', 'allow_always']),
      );
    });

    test('scenario "Скрипт навыка проекта через клиента ACP": cwd '
        'inside the workspace goes to terminal/create as is, after an '
        'ordinary question', () async {
      rig.writeSkill(
        '${rig.project}/.codelab/skills',
        'pdf',
        files: {'scripts/extract.py': "print('page 1')\n"},
      );
      await start([
        callJson('c1', 'exec', {
          'command': 'python3 scripts/extract.py',
          'cwd': '.codelab/skills/pdf',
        }),
        textJson('ok'),
      ]);

      await run();

      final result = toolResultsOf(rig.contexts.last).single;
      expect(result.isError, isFalse, reason: result.text);
      expect(created, hasLength(1));
      expect(created.single['cwd'], '${rig.project}/.codelab/skills/pdf');
      expect(created.single['args'], ['-c', 'python3 scripts/extract.py']);
      final asked = questionsOf('c1');
      expect(asked, hasLength(1));
      expect(kindsOf(asked.single), contains('allow_always'));
    });
  });

  group('PERM-11: absolute skills.extra_roots of the launch root', () {
    test(
      'write into the extra root is a critical question (no '
      'allow_always) and does not change the file (D19, skillExtraRoots)',
      () async {
        final extraTemp = Directory.systemTemp.createTempSync('codelab_extra_');
        addTearDown(() => extraTemp.deleteSync(recursive: true));
        final extra = extraTemp.resolveSymbolicLinksSync();
        rig = await SkillsRig.create(
          trusted: true,
          extraConfig: 'skills:\n  extra_roots: [${jsonEncode(extra)}]\n',
        );
        final dir = rig.writeSkill(extra, 'shared');
        await start([
          callJson('c1', 'write', {
            'path': '$dir/SKILL.md',
            'content': 'overwritten',
          }),
          textJson('ok'),
        ]);
        peer.handlers['session/request_permission'] = (request) {
          permissions.add(request.params! as Map<String, Object?>);
          return {
            'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
          };
        };

        await run();

        final asked = questionsOf('c1');
        expect(asked, hasLength(1));
        expect(kindsOf(asked.single), isNot(contains('allow_always')));
        final meta = (asked.single['toolCall']! as Map)['_meta'] as Map?;
        expect((meta?['codelab'] as Map?)?['critical'], isTrue);
        expect(
          File('$dir/SKILL.md').readAsStringSync(),
          contains('name: shared'),
        );
      },
    );
  });
}
