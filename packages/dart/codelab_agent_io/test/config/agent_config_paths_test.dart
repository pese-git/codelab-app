import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show AgentConfigPaths, CancelToken, ModelId, SkillFilesQuery;
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// `agentConfigPathsFor` — пути PERM-11 для политики разрешений (design.md
/// change `add-config-writer-and-reload`, D7, D8; задача 5.9): те же файлы,
/// что наблюдает `ConfigWatcher` (`watchedConfigFiles`), плюс каталоги
/// `$CODELAB_HOME/agents` и `prompts`; пути абсолютные и канонические.
/// Всё идёт во временных каталогах, настоящий `~/.codelab` не читается.
void main() {
  late Directory tmp;
  late String base;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('agent_config_paths_');
    // Каталог самого `tmp` на macOS (`/var` → `/private/var`) — ссылка: берём
    // канонический, чтобы проверять только ссылки теста.
    base = tmp.resolveSymbolicLinksSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, String> env({
    String? home,
    String? codelabHome,
    String? config,
  }) => {
    'HOME': home ?? '$base/home',
    'CODELAB_HOME': ?codelabHome,
    'CODELAB_CONFIG': ?config,
  };

  test('the set is what ConfigWatcher watches plus agents and prompts', () {
    Directory('$base/root').createSync();
    final environment = env(codelabHome: '$base/state');

    final watched = watchedConfigFiles(
      cwd: '$base/root',
      environment: environment,
      extraConfig: '$base/extra.yaml',
      secretsFile: true,
    );
    final paths = agentConfigPathsFor(
      cwd: '$base/root',
      environment: environment,
      extraConfig: '$base/extra.yaml',
    );

    expect(watched, [
      '$base/state/config.yaml',
      '$base/extra.yaml',
      '$base/root/.codelab/config.yaml',
      '$base/root/.codelab/config.local.yaml',
      '$base/state/secrets.yaml',
    ]);
    // Файл последней модели — под PERM-11, но не в наблюдателе (design.md
    // change `optional-default-model`, D7): порядок — после файлов
    // конфигурации, до каталогов `agents` и `prompts`.
    expect(paths.paths, [
      ...watched,
      '$base/state/state/last-model.json',
      '$base/state/state',
      '$base/state/agents',
      '$base/state/prompts',
    ]);
  });

  test('last-model.json is protected by PERM-11 and is not watched '
      '(scenario "Файл под защитой PERM-11")', () {
    Directory('$base/root').createSync();
    final environment = env(codelabHome: '$base/state');

    final paths = agentConfigPathsFor(
      cwd: '$base/root',
      environment: environment,
    );
    final watched = watchedConfigFiles(
      cwd: '$base/root',
      environment: environment,
      secretsFile: true,
    );

    expect(paths.paths, contains('$base/state/state/last-model.json'));
    // Это не конфиг: перезагрузки по нему нет.
    expect(watched, isNot(contains('$base/state/state/last-model.json')));
    expect(watched.where((path) => path.endsWith('last-model.json')), isEmpty);
  });

  test('a symlink to last-model.json is protected by its real path', () {
    Directory('$base/root').createSync();
    Directory('$base/real').createSync();
    Directory('$base/state/state').createSync(recursive: true);
    Link('$base/state/state/last-model.json').createSync('$base/real/m.json');
    File('$base/real/m.json').writeAsStringSync('{}');

    final paths = agentConfigPathsFor(
      cwd: '$base/root',
      environment: env(codelabHome: '$base/state'),
    );

    expect(paths.paths, contains('$base/real/m.json'));
    // Лексический путь тоже под защитой: запись `FileLastModelStore`
    // (`rename` поверх ссылки) заменяет ссылку обычным файлом, и по
    // канонической цели защита больше не сработала бы.
    expect(paths.paths, contains('$base/state/state/last-model.json'));
    expect(paths.paths, contains('$base/state/state'));
  });

  test('after FileLastModelStore.write replaced the link, the lexical path '
      'is still protected', () async {
    Directory('$base/root').createSync();
    Directory('$base/real').createSync();
    Directory('$base/state/state').createSync(recursive: true);
    Link('$base/state/state/last-model.json').createSync('$base/real/m.json');
    File('$base/real/m.json').writeAsStringSync('{}');
    final environment = env(codelabHome: '$base/state');

    await FileLastModelStore(
      codelabHome: '$base/state',
    ).write(const ModelId('a/x'));
    final paths = agentConfigPathsFor(
      cwd: '$base/root',
      environment: environment,
    );

    expect(
      FileSystemEntity.typeSync(
        '$base/state/state/last-model.json',
        followLinks: false,
      ),
      FileSystemEntityType.file,
    );
    expect(paths.paths, contains('$base/state/state/last-model.json'));
  });

  test('secrets.yaml is protected with any backend', () {
    Directory('$base/root').createSync();
    final environment = env(codelabHome: '$base/state');

    final paths = agentConfigPathsFor(
      cwd: '$base/root',
      environment: environment,
    );
    final watched = watchedConfigFiles(
      cwd: '$base/root',
      environment: environment,
    );

    // Наблюдение зависит от бэкенда (перезагрузка), защита — нет (PERM-11).
    expect(paths.paths, contains('$base/state/secrets.yaml'));
    expect(watched, isNot(contains('$base/state/secrets.yaml')));
  });

  test('CODELAB_CONFIG and a relative --config resolve against the root', () {
    Directory('$base/root').createSync();

    final fromEnv = watchedConfigFiles(
      cwd: '$base/root',
      environment: env(
        codelabHome: '$base/state',
        config: '$base/from_env.yaml',
      ),
    );
    final relative = watchedConfigFiles(
      cwd: '$base/root',
      environment: env(codelabHome: '$base/state'),
      extraConfig: 'conf/agent.yaml',
    );

    expect(fromEnv, contains('$base/from_env.yaml'));
    expect(relative, contains('$base/root/conf/agent.yaml'));
  });

  test('~ is expanded and symlinks are resolved', () {
    Directory('$base/real_root/.codelab').createSync(recursive: true);
    Link('$base/root_link').createSync('$base/real_root');
    Directory('$base/home/dotfiles').createSync(recursive: true);
    Directory('$base/home/.codelab').createSync(recursive: true);
    File('$base/home/dotfiles/codelab.yaml').writeAsStringSync('a: 1\n');
    Link(
      '$base/home/.codelab/config.yaml',
    ).createSync('$base/home/dotfiles/codelab.yaml');

    final paths = agentConfigPathsFor(
      cwd: '$base/root_link',
      environment: env(codelabHome: '~/.codelab'),
    );

    expect(
      paths.paths,
      containsAll([
        // Ссылка dotfiles раскрыта до цели (agent-permissions «Символическая ссылка»).
        '$base/home/dotfiles/codelab.yaml',
        // Корень запуска по ссылке дан каноническим, файла ещё нет.
        '$base/real_root/.codelab/config.yaml',
        '$base/real_root/.codelab/config.local.yaml',
        // Каталога нет: самый глубокий существующий предок плюс остаток.
        '$base/home/.codelab/agents',
        '$base/home/.codelab/prompts',
      ]),
    );
    expect(paths.paths.where((p) => p.contains('root_link')), isEmpty);
  });

  test('a missing file below a linked directory resolves via the ancestor', () {
    Directory('$base/root').createSync();
    Directory('$base/elsewhere').createSync();
    Link('$base/root/.codelab').createSync('$base/elsewhere');

    final paths = agentConfigPathsFor(
      cwd: '$base/root',
      environment: env(codelabHome: '$base/state'),
    );

    expect(
      paths.paths,
      containsAll([
        '$base/elsewhere/config.yaml',
        '$base/elsewhere/config.local.yaml',
      ]),
    );
  });

  test('expansions carry HOME and CODELAB_HOME of the host environment', () {
    Directory('$base/root').createSync();

    final paths = agentConfigPathsFor(
      cwd: '$base/root',
      environment: env(home: '/h', codelabHome: '~/state'),
    );

    // Раскрытие в командах `exec` идёт по тем значениям, что видит оболочка:
    // лексическим, а не каноническим.
    expect(paths.expansions, {'HOME': '/h', 'CODELAB_HOME': '/h/state'});
  });

  test('CODELAB_HOME defaults to ~/.codelab', () {
    Directory('$base/root').createSync();

    final paths = agentConfigPathsFor(
      cwd: '$base/root',
      environment: env(home: '$base/home'),
    );

    expect(paths.expansions['CODELAB_HOME'], '$base/home/.codelab');
    expect(paths.paths, contains('$base/home/.codelab/config.yaml'));
  });

  test('caseInsensitive follows the argument, then the platform', () {
    Directory('$base/root').createSync();
    final environment = env(codelabHome: '$base/state');

    expect(
      agentConfigPathsFor(
        cwd: '$base/root',
        environment: environment,
        caseInsensitive: true,
      ).caseInsensitive,
      isTrue,
    );
    expect(
      agentConfigPathsFor(
        cwd: '$base/root',
        environment: environment,
        caseInsensitive: false,
      ).caseInsensitive,
      isFalse,
    );
    expect(
      agentConfigPathsFor(
        cwd: '$base/root',
        environment: environment,
      ).caseInsensitive,
      Platform.isMacOS || Platform.isWindows,
    );
  });

  group('skill roots (PERM-11; design.md change add-agent-skills, D9, Q9, '
      'Q16, Q27)', () {
    // Фиксируемый API: `agentConfigPathsFor(skillExtraRoots: …)` — корни
    // навыков от хоста; `sessionSkillRootsFor(cwd:, extraRoots:)` — корни,
    // зависящие от `cwd` сессии (уровни выше `cwd` и относительные элементы
    // `skills.extra_roots`), канонические пути, существующие или нет.
    // Оба списка строятся тем же кодом, что и список корней загрузчика.
    late String repo;
    late String work;

    setUp(() {
      repo = '$base/repo';
      work = '$repo/apps/demo';
      Directory('$repo/.git').createSync(recursive: true);
      Directory(work).createSync(recursive: true);
      Directory('$base/home').createSync();
    });

    AgentConfigPaths host({List<String> extra = const []}) =>
        agentConfigPathsFor(
          cwd: work,
          environment: env(codelabHome: '$base/state'),
          skillExtraRoots: extra,
        );

    test(r'$CODELAB_HOME/skills and ~/.agents/skills are protected even '
        'when they do not exist', () {
      final paths = host().paths;

      expect(
        paths,
        containsAll(['$base/state/skills', '$base/home/.agents/skills']),
      );
    });

    test('absolute extra_roots and ~/… elements are host paths', () {
      Directory('$base/team').createSync();

      final paths = host(extra: ['$base/team/skills', '~/shared/skills']).paths;

      expect(
        paths,
        containsAll(['$base/team/skills', '$base/home/shared/skills']),
      );
    });

    test('a symlinked absolute extra root is protected by its real path', () {
      Directory('$base/real/skills').createSync(recursive: true);
      Link('$base/linked').createSync('$base/real');

      final paths = host(extra: ['$base/linked/skills']).paths;

      expect(paths, contains('$base/real/skills'));
    });

    test('relative extra_roots and project levels are not host paths', () {
      final paths = host(extra: ['.claude/skills']).paths;

      expect(paths.where((p) => p.contains('.claude')), isEmpty);
      expect(paths.where((p) => p.startsWith(repo)), isEmpty);
    });

    test('session roots: levels above cwd up to the git root and relative '
        'extra_roots', () async {
      final roots = await sessionSkillRootsFor(
        cwd: work,
        extraRoots: ['.claude/skills', '../shared/skills', '$base/abs/skills'],
      );

      expect(
        roots,
        containsAll([
          '$repo/apps/.codelab/skills',
          '$repo/apps/.agents/skills',
          '$repo/.codelab/skills',
          '$repo/.agents/skills',
          '$work/.claude/skills',
          '$repo/apps/shared/skills',
        ]),
      );
      // Выше корня репозитория уровни не ищутся; абсолютные — путь хоста.
      expect(roots.where((p) => p.startsWith('$base/.')), isEmpty);
      expect(roots, isNot(contains('$base/abs/skills')));
    });

    test(
      'without a git repository only cwd is a level: nothing above it',
      () async {
        final plain = '$base/plain/deep';
        Directory(plain).createSync(recursive: true);

        final roots = await sessionSkillRootsFor(
          cwd: plain,
          extraRoots: ['.claude/skills'],
        );

        expect(roots.where((p) => p.startsWith('$base/plain/.')), isEmpty);
        expect(roots, contains('$plain/.claude/skills'));
      },
    );

    test('a symlinked relative extra root is given by its real path', () async {
      Directory('$base/elsewhere').createSync();
      Directory('$work/.claude').createSync();
      Link('$work/.claude/skills').createSync('$base/elsewhere');

      final roots = await sessionSkillRootsFor(
        cwd: work,
        extraRoots: ['.claude/skills'],
      );

      expect(roots, contains('$base/elsewhere'));
    });

    test('the lists cover every root the skills loader reads (one root list '
        'for the loader and PERM-11)', () async {
      // Навыки во всех видах корней; корень на уровне `cwd` защищает
      // проектное правило `.codelab/skills/**`/`.agents/skills/**` ядра.
      final team = '$base/team/skills';
      final roots = <String>[
        '$repo/.codelab/skills',
        '$repo/apps/.agents/skills',
        '$base/state/skills',
        '$base/home/.agents/skills',
        team,
        '$work/.claude/skills',
      ];
      for (final root in roots) {
        File('$root/s/SKILL.md')
          ..createSync(recursive: true)
          ..writeAsStringSync('---\nname: s\ndescription: d\n---\nbody\n');
      }
      final loaded =
          await ProjectFilesLoader(
            home: '$base/state',
            userHome: '$base/home',
            local: LocalExecutionEnv(cwd: base),
          ).loadSkills(
            SkillFilesQuery(
              cwd: work,
              projectTrusted: true,
              extraRoots: [team, '.claude/skills'],
              cancel: CancelToken.none,
            ),
          );
      final protected = [
        ...host(extra: [team]).paths,
        ...await sessionSkillRootsFor(
          cwd: work,
          extraRoots: ['.claude/skills'],
        ),
      ];

      expect(loaded.skills, hasLength(roots.length));
      for (final skill in loaded.skills) {
        final root = skill.dir.substring(0, skill.dir.lastIndexOf('/'));
        expect(
          protected.any((p) => root == p || root.startsWith('$p/')),
          isTrue,
          reason: root,
        );
      }
    });
  });
}
