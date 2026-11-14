import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

import '../support/real_home.dart';

const _leak = 'sk-test-leak-0123456789';

/// `readAgentExtensions`: вид расширений по настоящим файлам временного
/// `CODELAB_HOME` и проекта (client-agent-setup «Обзор расширений агента»,
/// сценарии «Вид совпадает с каталогом сессии», «Недоверенный проект»;
/// design.md change `add-app-skills-page`, D3, D4, D7, D15; задача 1.5).
///
/// Почему на настоящих файлах: проверяется склейка трёх частей — снимок
/// `FileAgentConfigStore`, `loadProjectExtensions` (`codelab_agent_io`) и
/// построитель `agentExtensionsOf` (чистая часть проверена в
/// `test/extensions/agent_extensions_view_test.dart` на фейках). Ожидаемое
/// берётся из ядра: каталог — `parseSkills` над тем же загрузчиком, а не
/// списком, вписанным в тест, поэтому расхождение вида и сессии агента видно.
///
/// Фиксируемый API: `readAgentExtensions(snapshot, {codelabHome,
/// environment})`; кандидаты согласия — `SkillsSectionView.consents`, элемент
/// `SkillConsentView(entry, path, skillDirs, granted)` (design.md D4
/// «Кандидаты согласия», решение Q3).
void main() {
  late RealHome home;
  late String project;
  late String userHome;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  void skill(String root, String name, {String body = 'Do it.'}) => write(
    '$root/$name/SKILL.md',
    '---\nname: $name\ndescription: The $name skill\n---\n$body\n',
  );

  setUp(() {
    home = RealHome.create('read_agent_extensions_');
    // Домашний каталог процесса — корень временного дерева (`~/.agents/skills`
    // и `~/.claude/skills` лежат внутри него, настоящий `~` не читается).
    userHome = home.root.path;
    project = Directory(home.project).resolveSymbolicLinksSync();
  });

  tearDown(() => home.dispose());

  Map<String, String> env() => {'HOME': userHome, 'CODELAB_HOME': home.home};

  /// Пишет конфиг пользователя: провайдер, модель и [extra].
  void config({bool trusted = true, String extra = ''}) => home.writeConfig(
    '$gatewayProvider'
    'agent:\n  default_model: gw/m\n'
    '${trusted ? 'trusted_projects:\n  - $project\n' : ''}'
    '$extra',
  );

  Future<AgentExtensionsView> read() async {
    final snapshot = await home.load();
    expect(snapshot.loaded.config, isNotNull, reason: '${snapshot.issues}');
    return readAgentExtensions(
      snapshot,
      codelabHome: home.home,
      environment: env(),
    );
  }

  /// Каталог, который построит сессия этой папки: тот же загрузчик и та же
  /// `parseSkills`, что у рантайма (agent-skills «Каталог навыков сессии»).
  Future<SkillCatalog> sessionCatalog(
    AgentConfigSnapshot snapshot, {
    required bool trusted,
  }) async {
    final cfg = snapshot.loaded.config!;
    final loader = ProjectFilesLoader(
      home: home.home,
      userHome: userHome,
      local: LocalExecutionEnv(cwd: project, hostEnvironment: env()),
    );
    final files = await loader.loadSkills(
      SkillFilesQuery(
        cwd: project,
        projectTrusted: trusted,
        extraRoots: cfg.skills.extraRoots,
        cancel: CancelToken.none,
      ),
    );
    return parseSkills(files, cfg.skills, rules: cfg.permissions.rules);
  }

  group('сценарий «Вид совпадает с каталогом сессии»', () {
    test('навыки .codelab/skills, .agents/skills, ~/.agents/skills и '
        '\$CODELAB_HOME/skills: включённые строки — по именам каталог '
        'parseSkills, skills.disabled — строка disabled', () async {
      config(extra: 'skills:\n  disabled:\n    - b\n');
      skill('$project/.codelab/skills', 'a');
      skill('$project/.agents/skills', 'b');
      skill('$userHome/.agents/skills', 'c');
      skill('${home.home}/skills', 'd');
      final snapshot = await home.load();

      final view = await readAgentExtensions(
        snapshot,
        codelabHome: home.home,
        environment: env(),
      );

      final catalog = await sessionCatalog(snapshot, trusted: true);
      expect([for (final s in catalog.skills) s.name], ['a', 'c', 'd']);
      expect(view.trusted, isTrue);
      expect(view.folder, project);
      final enabled = [
        for (final e in view.skills.entries)
          if (e.availability == SkillAvailability.enabled) e.name,
      ];
      expect(enabled, [for (final s in catalog.skills) s.name]);
      final b = view.skills.entries.singleWhere((e) => e.name == 'b');
      expect(b.availability, SkillAvailability.disabled);
      expect(b.root.scope, ExtensionScope.project);
      expect(view.skills.outcome, isA<SectionRead>());
    });

    test('корень extra_roots даёт строки со scope extra и подписью '
        '«(extra root)»', () async {
      config(extra: 'skills:\n  extra_roots:\n    - ~/other\n');
      skill('$userHome/other', 'x');

      final view = await read();

      final x = view.skills.entries.single;
      expect(x.name, 'x');
      expect(x.root.scope, ExtensionScope.extra);
      expect(x.root.label, '~/other (extra root)');
    });

    test('цепочка и шаблоны читаются теми же файлами: AGENTS.md проекта и '
        'пользователя, шаблон проекта', () async {
      config();
      write('${home.home}/AGENTS.md', 'user rules');
      write('$project/AGENTS.md', 'project rules');
      write(
        '$project/.codelab/prompts/review.md',
        '---\ndescription: Review it\n---\nReview the diff.\n',
      );

      final view = await read();

      expect(
        [for (final f in view.context.files) f.scope],
        [ExtensionScope.user, ExtensionScope.project],
      );
      expect(view.context.files.first.openDir, home.home);
      expect(view.context.files.last.openDir, project);
      expect(view.templates.entries.single.command, '/review');
    });

    test(
      'skills.enabled: false — раздел выключен, файлы навыков не читаются',
      () async {
        config(extra: 'skills:\n  enabled: false\n');
        skill('$project/.codelab/skills', 'a');

        final view = await read();

        final off = view.skills.outcome as SectionOff;
        expect(off.source, '${home.home}/config.yaml');
        expect(view.skills.entries, isEmpty);
      },
    );
  });

  group('сценарий «Недоверенный проект»', () {
    test('папка не в trusted_projects: trusted == false, навыков и шаблонов '
        'проекта нет, цепочка AGENTS.md проекта есть, пользовательские '
        'навыки видны', () async {
      config(trusted: false);
      skill('$project/.codelab/skills', 'p');
      write(
        '$project/.codelab/prompts/review.md',
        '---\ndescription: Review it\n---\nBody\n',
      );
      write('$project/AGENTS.md', 'project rules');
      skill('$userHome/.agents/skills', 'c');
      final snapshot = await home.load();

      final view = await readAgentExtensions(
        snapshot,
        codelabHome: home.home,
        environment: env(),
      );

      expect(view.trusted, isFalse);
      final catalog = await sessionCatalog(snapshot, trusted: false);
      expect(
        [for (final e in view.skills.entries) e.name],
        [for (final s in catalog.skills) s.name],
      );
      expect([for (final e in view.skills.entries) e.name], ['c']);
      expect(view.templates.entries, isEmpty);
      expect(view.context.files.single.path, 'AGENTS.md');
    });
  });

  group('кандидаты согласия на каталоги других агентов (Q3)', () {
    test('только существующие каталоги, с числом подкаталогов с SKILL.md; '
        'порядок: проект, затем домашний', () async {
      config();
      skill('$project/.claude/skills', 'one');
      skill('$project/.claude/skills', 'two');
      Directory('$project/.claude/skills/not-a-skill').createSync();
      skill('$userHome/.claude/skills', 'home-one');

      final view = await read();

      final consents = view.skills.consents;
      expect(
        [for (final c in consents) c.entry],
        ['.claude/skills', '~/.claude/skills'],
      );
      expect([for (final c in consents) c.skillDirs], [2, 1]);
      expect(consents.first.path, '$project/.claude/skills');
      expect(consents.last.path, '$userHome/.claude/skills');
      expect([for (final c in consents) c.granted], [false, false]);
    });

    test('каталога нет — кандидата нет', () async {
      config();
      skill('$userHome/.claude/skills', 'home-one');

      final view = await read();

      expect(
        [for (final c in view.skills.consents) c.entry],
        ['~/.claude/skills'],
      );
    });

    test('«согласие дано» — по элементу в действующем extra_roots как он '
        'записан', () async {
      config(extra: 'skills:\n  extra_roots:\n    - .claude/skills\n');
      skill('$project/.claude/skills', 'one');
      skill('$userHome/.claude/skills', 'home-one');

      final view = await read();

      final granted = {
        for (final c in view.skills.consents) c.entry: c.granted,
      };
      expect(granted, {'.claude/skills': true, '~/.claude/skills': false});
      // Согласие действует: навык каталога — строка вида.
      expect(
        view.skills.entries.where((e) => e.root.scope == ExtensionScope.extra),
        hasLength(1),
      );
    });
  });

  group('SETUP-25: тела настоящих файлов не попадают в вид', () {
    test('маркер в AGENTS.md, SKILL.md и шаблоне не виден в toString() вида '
        'и строк', () async {
      config();
      write('$project/AGENTS.md', 'rules $_leak');
      skill('$project/.codelab/skills', 'a', body: 'Secret $_leak');
      write(
        '$project/.codelab/prompts/review.md',
        '---\ndescription: Review it\n---\nBody $_leak\n',
      );

      final view = await read();

      expect(view.context.files, isNotEmpty);
      expect(view.skills.entries, isNotEmpty);
      expect(view.templates.entries, isNotEmpty);
      final texts = [
        view.toString(),
        for (final f in view.context.files) f.toString(),
        for (final e in view.skills.entries) e.toString(),
        for (final t in view.templates.entries) t.toString(),
      ];
      for (final text in texts) {
        expect(text, isNot(contains(_leak)));
      }
    });
  });
}
