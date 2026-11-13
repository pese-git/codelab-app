import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/io.dart';
import 'package:test/test.dart';

import '../support/acp_client.dart';
import '../support/openai_script.dart';

/// Навыки и их файлы во встроенном агенте: `localEmbeddedAgentOpener`
/// передаёт ядру `skillFiles` и `hostFiles`, поэтому навыки `$CODELAB_HOME` и
/// `~/.agents` видны сессии, их файлы читаются с файловой системы процесса
/// клиента, а `exec` в каталоге навыка идёт на машине процесса (agent-skills
/// «Навыки в хостах», «Сопутствующие файлы и скрипты навыка», сценарии
/// «Чтение файла пользовательского навыка», «Запись в каталог навыка»,
/// «Скрипт навыка во встроенном агенте», «Скрипт по абсолютному пути при
/// локальном исполнении»; design.md change `add-agent-skills`, D3, D5, D17;
/// решения Q17, Q25; задачи 5.1 и 5.3).
///
/// Всё во временном каталоге: `CODELAB_HOME` и `HOME` — словарь окружения
/// открывателя, настоящие `~/.codelab` и `~/.agents` не читаются; ключ
/// провайдера — фейковый, сеть — `MockClient`. Процесс запускается только в
/// `exec`-тестах (`sh` со скриптом навыка из временного каталога).
///
/// Красные до 5.2: открыватель ещё не создаёт `skillFiles` и `hostFiles`
/// (`EmbeddedHostServices` без этих полей; их добавляет 5.2) — нет команд и
/// каталога, чтение файла навыка и `exec` с `cwd` в каталоге навыка
/// отклоняются как `outsideWorkspace`; запуск скрипта навыка по абсолютному
/// пути в `bypass` спрашивается как «запись в конфигурацию агента» (каталог
/// `$CODELAB_HOME` защищён PERM-11, а исключения E1–E3 действуют только для
/// загруженного навыка). Стражи (зелёные сразу): запись в каталог навыка —
/// `outsideWorkspace`; перенаправление в каталог навыка в `bypass` —
/// критический вопрос без `allow_always`.
void main() {
  late Directory temp;
  late String home;
  late String userHome;
  late String project;
  late RecordingLogger logger;
  EmbeddedAgent? agent;
  TestAcpClient? client;
  final permissions = <Map<String, Object?>>[];
  var permissionAnswer = 'allow_once';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_opener_skills_');
    home = '${temp.path}/home';
    userHome = '${temp.path}/userhome';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    Directory(userHome).createSync();
    project = (Directory(
      '${temp.path}/project',
    )..createSync()).resolveSymbolicLinksSync();
    logger = RecordingLogger();
    permissions.clear();
    permissionAnswer = 'allow_once';
  });

  tearDown(() async {
    await client?.close();
    await agent?.dispose();
    agent = client = null;
    temp.deleteSync(recursive: true);
  });

  void writeConfig({String extra = ''}) =>
      File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key_secret: codelab/p
    models:
      m: {}
agent:
  default_model: p/m
$extra''');

  /// Навык `<root>/<name>`; возвращает канонический каталог.
  String writeSkill(String root, String name, [Map<String, String>? files]) {
    final dir = Directory('$root/$name')..createSync(recursive: true);
    File('${dir.path}/SKILL.md').writeAsStringSync(
      '---\nname: $name\ndescription: Does the thing\n---\nFollow the steps.\n',
    );
    for (final MapEntry(:key, :value) in (files ?? const {}).entries) {
      File('${dir.path}/$key')
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    return dir.resolveSymbolicLinksSync();
  }

  /// Открывает агента с провайдером-сценарием и сессией в [project].
  Future<(String, OpenAiScript)> open(List<OpenAiStep> steps) async {
    final script = OpenAiScript(steps);
    final opened = await localEmbeddedAgentOpener(
      environment: {
        'CODELAB_HOME': home,
        'HOME': userHome,
        'CODELAB_SECRET_CODELAB_P': 'sk-test-0123456789',
      },
      logger: logger,
      httpClient: script.client,
    )(cwd: project, hostProfile: 'embedded-cli');
    agent = opened;
    client = TestAcpClient(opened.clientTransport);
    await client!.start();
    await client!.initialize();
    client!.handlers['session/request_permission'] = (request) {
      permissions.add(request.params! as Map<String, Object?>);
      return {
        'outcome': {'outcome': 'selected', 'optionId': permissionAnswer},
      };
    };
    return (await client!.newSession(project), script);
  }

  List<Object?> kindsOf(Map<String, Object?> request) => [
    for (final option in request['options']! as List<Object?>)
      (option! as Map<String, Object?>)['kind'],
  ];

  test(
    'scenario "Навык пользователя по stdio" for the embedded opener: '
    r'skills of $CODELAB_HOME and ~/.agents give commands and the catalog',
    () async {
      writeConfig();
      writeSkill('$home/skills', 'release-notes');
      writeSkill('$userHome/.agents/skills', 'agents-skill');
      final (session, script) = await open([const OpenAiStep.text('hi')]);

      await client!.prompt(session, 'go');

      final names = <String>{
        for (final update in client!.updates)
          if (update['sessionUpdate'] == 'available_commands_update')
            for (final c in update['availableCommands']! as List<Object?>)
              (c! as Map<String, Object?>)['name']! as String,
      };
      expect(names, containsAll(['skill:release-notes', 'skill:agents-skill']));
      final prompt = systemPromptOf(script.bodies.single);
      expect(prompt, contains('## Skills'));
      expect(prompt, contains('release-notes'));
      expect(prompt, contains('agents-skill'));
      expect(logger.eventsOf('skills.loaded').single.fields['names'], [
        'agents-skill',
        'release-notes',
      ]);
    },
  );

  test('scenario "Чтение файла пользовательского навыка": read of a file '
      'in the skill directory outside the project returns its text', () async {
    writeConfig();
    final dir = writeSkill('$home/skills', 'release-notes', {
      'template.md': 'template text\n',
    });
    final (session, script) = await open([
      OpenAiStep.tool('c1', 'read', {'path': '$dir/template.md'}),
    ]);

    await client!.prompt(session, 'go');

    final result = lastToolResultOf(script.bodies.last);
    expect(result, contains('template text'));
    expect(result, isNot(contains('outside the workspace')));
    expect(client!.agentRequests, isNot(contains('fs/read_text_file')));
  });

  test('guard, scenario "Запись в каталог навыка": write is outsideWorkspace '
      'and the file is unchanged', () async {
    writeConfig();
    final dir = writeSkill('$home/skills', 'release-notes', {
      'template.md': 'template text\n',
    });
    final (session, script) = await open([
      OpenAiStep.tool('c1', 'write', {
        'path': '$dir/template.md',
        'content': 'overwritten',
      }),
    ]);

    await client!.prompt(session, 'go');

    expect(
      lastToolResultOf(script.bodies.last),
      contains('Path is outside the workspace: $dir/template.md'),
    );
    expect(File('$dir/template.md').readAsStringSync(), 'template text\n');
  });

  test('scenario "Скрипт навыка во встроенном агенте" (Q17): exec with cwd '
      'in the skill directory is an ordinary question with allow_always and, '
      'once allowed, runs in that directory', () async {
    writeConfig();
    final dir = writeSkill('$home/skills', 'release-notes', {
      'scripts/x.sh': 'pwd\n',
    });
    final (session, script) = await open([
      OpenAiStep.tool('c1', 'exec', {'command': 'sh scripts/x.sh', 'cwd': dir}),
    ]);

    await client!.prompt(session, 'go');

    expect(permissions, hasLength(1));
    expect(
      kindsOf(permissions.single),
      containsAll(['allow_once', 'allow_always']),
    );
    final result = lastToolResultOf(script.bodies.last)!;
    expect(result, contains('/skills/release-notes'));
    expect(result, isNot(contains('outside the workspace')));
    expect(client!.agentRequests, isNot(contains('terminal/create')));
  });

  group('bypass', () {
    test('scenario "Скрипт по абсолютному пути при локальном исполнении": '
        'the script by absolute path with the project cwd runs without a '
        'question', () async {
      writeConfig(extra: 'permissions:\n  mode: bypass\n');
      final dir = writeSkill('$home/skills', 'release-notes', {
        'scripts/x.sh': 'pwd\n',
      });
      final (session, script) = await open([
        OpenAiStep.tool('c1', 'exec', {
          'command': 'sh $dir/scripts/x.sh',
          'cwd': '.',
        }),
      ]);

      await client!.prompt(session, 'go');

      expect(permissions, isEmpty);
      expect(lastToolResultOf(script.bodies.last), contains(project));
    });

    test(
      'scenario "Скрипт по абсолютному пути при локальном исполнении": '
      'a redirect into the skill directory in the same command is critical '
      '(a question without allow_always) and is not run after a reject',
      () async {
        writeConfig(extra: 'permissions:\n  mode: bypass\n');
        final dir = writeSkill('$home/skills', 'release-notes', {
          'scripts/x.sh': 'pwd\n',
        });
        permissionAnswer = 'reject_once';
        final (session, _) = await open([
          OpenAiStep.tool('c1', 'exec', {
            'command': 'sh $dir/scripts/x.sh > $dir/out.md',
            'cwd': '.',
          }),
        ]);

        await client!.prompt(session, 'go');

        expect(permissions, hasLength(1));
        expect(kindsOf(permissions.single), isNot(contains('allow_always')));
        expect(File('$dir/out.md').existsSync(), isFalse);
      },
    );
  });

  test('PERM-11, D19 (skillExtraRoots): write into an absolute '
      'skills.extra_roots of the launch root is a critical question (no '
      'allow_always) and does not change the file', () async {
    final extraTemp = Directory.systemTemp.createTempSync('codelab_extra_');
    addTearDown(() => extraTemp.deleteSync(recursive: true));
    final extra = extraTemp.resolveSymbolicLinksSync();
    writeConfig(extra: 'skills:\n  extra_roots: ["$extra"]\n');
    final dir = writeSkill(extra, 'shared');
    permissionAnswer = 'reject_once';
    final (session, _) = await open([
      OpenAiStep.tool('c1', 'write', {
        'path': '$dir/SKILL.md',
        'content': 'overwritten',
      }),
    ]);

    await client!.prompt(session, 'go');

    expect(permissions, hasLength(1));
    expect(kindsOf(permissions.single), isNot(contains('allow_always')));
    final meta = (permissions.single['toolCall']! as Map)['_meta'] as Map?;
    expect((meta?['codelab'] as Map?)?['critical'], isTrue);
    expect(File('$dir/SKILL.md').readAsStringSync(), contains('name: shared'));
  });
}
