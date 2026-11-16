import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        ConfigLoadResult,
        ConfigSnapshot,
        ConfigLayer,
        ConfigTarget,
        CoreConfig,
        ModelRef,
        ProviderApi,
        SecretBackendInfo;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// `agentDefinitionRowsAt` на реальных каталогах во временном `CODELAB_HOME`
/// (client-agent-setup «Строки определений агентов в мосте»: «Тот же разбор,
/// что у config check», «Недоверенный проект», «Признак наличия каталогов»;
/// design.md change `add-settings-agents-modes`, D7). Настоящий `~/.codelab`
/// не читается.
///
/// Красные до задачи 2.4: `agentDefinitionRowsAt` — заглушка.
void main() {
  late String base;
  late String repo;
  late String home;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('agent_rows_at_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    home = '$base/home';
    Directory('$repo/.git').createSync(recursive: true);
  });

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  String agent(String name, {String extra = ''}) =>
      '---\nname: $name\ndescription: Agent $name\n$extra---\nBody\n';

  AgentConfigSnapshot snapshot({bool trusted = true}) =>
      AgentConfigSnapshot.fromLayers(
        cwd: repo,
        layers: {
          ConfigLayer.user: ConfigSnapshot(
            target: const ConfigTarget.user(),
            path: '$home/config.yaml',
            fingerprint: 'fp',
            values: const {},
          ),
        },
        loaded: ConfigLoadResult(
          config: CoreConfig(
            defaultModel: ModelRef(
              provider: 'test',
              id: 'model-1',
              api: ProviderApi.openaiChat,
              baseUrl: Uri.parse('http://localhost:8080/v1'),
              contextWindow: 32000,
              maxOutputTokens: 4096,
            ),
            trustedProjects: trusted ? [repo] : const [],
          ),
        ),
        secrets: const SecretBackendInfo(id: 'file', writable: true),
      );

  Future<AgentDefinitionRows> rowsAt({
    bool trusted = true,
    bool withFolder = true,
    String? folder,
  }) => agentDefinitionRowsAt(
    snapshot: snapshot(trusted: trusted),
    access: EditableSettings(
      ConfigPaths(
        codelabHome: home,
        projectDir: withFolder ? folder ?? repo : null,
      ),
    ),
    env: {'CODELAB_HOME': home},
  );

  test(
    'строки из пользовательского и доверенного проектного каталогов',
    () async {
      write('$home/agents/user-one.md', agent('user-one'));
      write('$repo/.codelab/agents/proj-one.md', agent('proj-one'));

      final result = await rowsAt();

      expect([
        for (final r in result.rows) r.name,
      ], containsAllInOrder(['default', 'proj-one', 'user-one']));
      expect(result.userDirectory, '$home/agents');
      expect(result.projectDirectory, '$repo/.codelab/agents');
      expect(result.userDirectoryExists, isTrue);
      expect(result.projectDirectoryExists, isTrue);
      expect(result.timedOut, isFalse);
    },
  );

  test('неизвестный ключ: Error со строкой 4 и без имени ключа', () async {
    write(
      '$home/agents/reviewer.md',
      '---\nname: reviewer\ndescription: R\ncolor: red\n---\nBody\n',
    );

    final result = await rowsAt();

    final row = result.rows.singleWhere((r) => r.name == 'reviewer');
    expect(row.status, AgentRowStatus.error);
    expect(row.errorLine, 4);
    expect(row.errorMessage, isNot(contains('color')));
  });

  test(
    'недоверенный проект: строк проекта нет, есть untrusted_project',
    () async {
      write('$repo/.codelab/agents/proj-one.md', agent('proj-one'));

      final result = await rowsAt(trusted: false);

      expect(result.rows.where((r) => r.name == 'proj-one'), isEmpty);
      expect([
        for (final d in result.diagnostics) d.code,
      ], contains('untrusted_project'));
    },
  );

  test(
    'признак наличия каталогов: пользовательского нет, проектный есть',
    () async {
      Directory('$repo/.codelab/agents').createSync(recursive: true);

      final result = await rowsAt();

      expect(result.userDirectoryExists, isFalse);
      expect(result.projectDirectoryExists, isTrue);
      expect(
        Directory('$home/agents').existsSync(),
        isFalse,
        reason: 'каталоги не создаются',
      );
    },
  );

  test('без папки: только каталог CODELAB_HOME, проектного пути нет', () async {
    write('$home/agents/user-one.md', agent('user-one'));
    write('$repo/.codelab/agents/proj-one.md', agent('proj-one'));

    final result = await rowsAt(withFolder: false);

    expect(result.projectDirectory, isNull);
    expect(result.projectDirectoryExists, isFalse);
    expect(result.rows.map((r) => r.name), contains('user-one'));
    expect(result.rows.map((r) => r.name), isNot(contains('proj-one')));
  });

  test('projectTrusted совпадает с доверием папки', () async {
    expect((await rowsAt()).projectTrusted, isTrue);
    expect((await rowsAt(trusted: false)).projectTrusted, isFalse);
    expect((await rowsAt(withFolder: false)).projectTrusted, isFalse);
  });

  test('Каталог-ссылка считается существующим', () async {
    final target = Directory('$base/elsewhere')..createSync();
    Directory('$repo/.codelab').createSync(recursive: true);
    Link('$repo/.codelab/agents').createSync(target.path);

    final result = await rowsAt();

    expect(result.projectDirectoryExists, isTrue);
  });

  test('Битая ссылка вместо каталога не считается существующей', () async {
    Directory('$repo/.codelab').createSync(recursive: true);
    Link('$repo/.codelab/agents').createSync('$base/missing-target');

    final result = await rowsAt();

    expect(result.projectDirectoryExists, isFalse);
  });

  test('папка за ссылкой: projectDirectory совпадает с путями строк', () async {
    write('$repo/.codelab/agents/proj-one.md', agent('proj-one'));
    Link('$base/link').createSync(repo);

    final result = await rowsAt(folder: '$base/link');

    final row = result.rows.singleWhere((r) => r.name == 'proj-one');
    expect(result.projectDirectory, '$repo/.codelab/agents');
    expect(row.path, startsWith('${result.projectDirectory}/'));
    expect(result.projectDirectoryExists, isTrue);
  });
}
