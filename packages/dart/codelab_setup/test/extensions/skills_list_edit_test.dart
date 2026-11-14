import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// `skillsListEdit`: правило записи `skills.disabled` и `skills.extra_roots`
/// (client-agent-setup «Правила записи skills.disabled и skills.extra_roots»,
/// все сценарии; design.md change `add-app-skills-page`, D5, D15; решения
/// Q2, Q3; задача 2.1).
///
/// Почему настоящий `FileAgentConfigStore`: правило опирается на `origins`
/// итога загрузки, на правила доверия загрузчика (Q43, SKL-2) и на сырые
/// списки слоёв. Фейковый снимок повторил бы наши допущения о загрузчике, а не
/// его поведение; снимки строит настоящее хранилище на временных каталогах
/// (без `~/.codelab`, фиктивные значения). Единственный фейк — переменная
/// окружения: у ключей `skills.*` нет своей переменной, поэтому источник
/// `environment` задаётся через `externalOrigin`.
///
/// Фиксируемый API (решения, которых design не задаёт, — в отчёте итерации):
/// `skillsListEdit(snapshot, key, element, {required present})` возвращает
/// `SkillsListEditResult`: `SkillsListPlan(layer, base, edits)` — `base`
/// передаётся в `AgentConfigStore.apply` как есть — либо
/// `SkillsListRefused(refusal)` с `SkillsListNotEditable(source)`,
/// `SkillsListDisabledByProject(source)`, `SkillsListUntrustedProject()`.
/// `present: true` — элемент должен оказаться в списке (выключить навык,
/// дать согласие), `false` — выйти из него. Ключ вне двух поддерживаемых —
/// `ArgumentError`.
void main() {
  const disabledKey = 'skills.disabled';
  const rootsKey = 'skills.extra_roots';

  late Directory root;
  late String home;
  late String project;
  late String canonicalProject;

  void write(String path, String text) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  String userFile() => '$home/config.yaml';
  String projectFile() => '$project/.codelab/config.yaml';
  String localFile() => '$project/.codelab/config.local.yaml';

  const provider = '''
agent:
  default_model: p/m
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m:
        context_window: 32000
''';

  /// Конфиг пользователя: провайдер, доверие проекта и [extra].
  void user({bool trusted = true, String extra = ''}) => write(
    userFile(),
    '$provider${trusted ? 'trusted_projects: [$canonicalProject]\n' : ''}'
    '$extra',
  );

  Future<FileAgentConfigStore> open({String? extraConfig}) async {
    final environment = {'HOME': root.path, 'CODELAB_HOME': home};
    return FileAgentConfigStore(
      paths: ConfigPaths(
        codelabHome: home,
        projectDir: project,
        extraConfig: extraConfig,
      ),
      environment: environment,
      secrets: await ClientSecretAccess.open(
        codelabHome: home,
        environment: environment,
        logger: RecordingLogger(),
      ),
      logger: RecordingLogger(),
    );
  }

  Future<AgentConfigSnapshot> load({String? extraConfig}) async =>
      (await open(extraConfig: extraConfig)).snapshot(cwd: project);

  SkillsListPlan plan(SkillsListEditResult result) {
    expect(result, isA<SkillsListPlan>(), reason: '$result');
    return result as SkillsListPlan;
  }

  SkillsListRefusal refusal(SkillsListEditResult result) {
    expect(result, isA<SkillsListRefused>(), reason: '$result');
    return (result as SkillsListRefused).refusal;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('skills_list_edit_');
    home = '${root.path}/home';
    project = '${root.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    canonicalProject = Directory(project).resolveSymbolicLinksSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('сценарий «Ключ не задан»', () {
    test('skills.disabled нигде нет: SetValue([x]) в слой user, база — '
        'снимок слоя user', () async {
      user();
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, disabledKey, 'x', present: true),
      );

      expect(result.layer, ConfigLayer.user);
      expect(result.base, same(snapshot.layers[ConfigLayer.user]));
      expect(result.base.target, const ConfigTarget.user());
      expect(result.edits, [
        const SetValue(disabledKey, ['x']),
      ]);
    });

    test('skills.extra_roots нигде нет: согласие идёт в user (Q3)', () async {
      user();
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, rootsKey, '.claude/skills', present: true),
      );

      expect(result.layer, ConfigLayer.user);
      expect(result.edits, [
        const SetValue(rootsKey, ['.claude/skills']),
      ]);
    });
  });

  group('сценарий «Список в projectLocal»: пишется слой, чьё значение '
      'действует', () {
    test('local [a], user [c], выключается b: SetValue([a, b]) в '
        'projectLocal; список user не меняется', () async {
      user(extra: 'skills:\n  disabled: [c]\n');
      write(localFile(), 'skills:\n  disabled: [a]\n');
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, disabledKey, 'b', present: true),
      );

      expect(result.layer, ConfigLayer.projectLocal);
      expect(result.base.target, ConfigTarget.projectLocal(project));
      expect(result.base, same(snapshot.layers[ConfigLayer.projectLocal]));
      expect(result.edits, [
        const SetValue(disabledKey, ['a', 'b']),
      ]);
    });

    test('extra_roots в projectLocal доверенного проекта: дописывается туда '
        'же', () async {
      user();
      write(localFile(), 'skills:\n  extra_roots: [/opt/skills]\n');
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, rootsKey, '~/.claude/skills', present: true),
      );

      expect(result.layer, ConfigLayer.projectLocal);
      expect(result.edits, [
        const SetValue(rootsKey, ['/opt/skills', '~/.claude/skills']),
      ]);
    });
  });

  group('новое значение: порядок без дублей, пустой список — UnsetValue', () {
    test('сценарий «Последний элемент»: user [a], включается a — '
        'UnsetValue в user', () async {
      user(extra: 'skills:\n  disabled: [a]\n');
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, disabledKey, 'a', present: false),
      );

      expect(result.layer, ConfigLayer.user);
      expect(result.edits, [const UnsetValue(disabledKey)]);
    });

    test(
      'порядок сохраняется: удаление из середины, добавление в конец',
      () async {
        user(extra: 'skills:\n  disabled: [a, b, c]\n');
        final snapshot = await load();

        expect(
          plan(
            skillsListEdit(snapshot, disabledKey, 'b', present: false),
          ).edits,
          [
            const SetValue(disabledKey, ['a', 'c']),
          ],
        );
        expect(
          plan(skillsListEdit(snapshot, disabledKey, 'd', present: true)).edits,
          [
            const SetValue(disabledKey, ['a', 'b', 'c', 'd']),
          ],
        );
      },
    );

    test('дублей нет: элемент уже в списке — правок нет; удаление '
        'отсутствующего — правок нет', () async {
      user(extra: 'skills:\n  disabled: [a, b]\n');
      final snapshot = await load();

      final again = plan(
        skillsListEdit(snapshot, disabledKey, 'b', present: true),
      );
      final missing = plan(
        skillsListEdit(snapshot, disabledKey, 'zzz', present: false),
      );

      expect(again.edits, isEmpty);
      expect(missing.edits, isEmpty);
    });
  });

  group('отказ notEditable: действует слой, который страница не пишет', () {
    test('сценарий «Ключ из --config»: extra_roots в файле --config — '
        'отказ с путём файла, правок нет', () async {
      user();
      final extra = '${root.path}/team.yaml';
      write(extra, 'skills:\n  extra_roots: [/team/skills]\n');
      final snapshot = await load(extraConfig: extra);

      final result = skillsListEdit(
        snapshot,
        rootsKey,
        '.claude/skills',
        present: true,
      );

      final refused = refusal(result) as SkillsListNotEditable;
      expect(refused.source, extra);
      expect(result, isNot(isA<SkillsListPlan>()));
    });

    test('skills.disabled доверенного проекта в config.yaml (слой project): '
        'и выключение, и включение — отказ с путём файла', () async {
      user();
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final snapshot = await load();

      final off = refusal(
        skillsListEdit(snapshot, disabledKey, 'x', present: true),
      );
      final on = refusal(
        skillsListEdit(snapshot, disabledKey, 'p', present: false),
      );

      expect(off, isA<SkillsListNotEditable>());
      expect((off as SkillsListNotEditable).source, projectFile());
      expect((on as SkillsListNotEditable).source, projectFile());
    });

    test('значение из переменной окружения: отказ с именем источника', () {
      final snapshot = AgentConfigSnapshot.fromLayers(
        cwd: project,
        layers: {
          ConfigLayer.user: ConfigSnapshot(
            target: const ConfigTarget.user(),
            path: userFile(),
            fingerprint: 'fp',
            values: const {
              'skills': {
                'disabled': ['a'],
              },
            },
          ),
        },
        loaded: const ConfigLoadResult(
          values: {
            'skills.disabled': ['a', 'env'],
          },
        ),
        secrets: const SecretBackendInfo(id: 'file', writable: true),
        externalOrigin: (key) => key == disabledKey
            ? const ConfigSourceView(
                kind: ConfigSourceKind.environment,
                label: 'CODELAB_SKILLS_DISABLED',
              )
            : null,
      );

      final refused =
          refusal(skillsListEdit(snapshot, disabledKey, 'x', present: true))
              as SkillsListNotEditable;

      expect(refused.source, 'CODELAB_SKILLS_DISABLED');
    });
  });

  group('недоверенный проект: skills.disabled объединяется (Q43)', () {
    test('имя выключено проектом: включить нельзя — disabledByProject с '
        'файлом проекта', () async {
      user(trusted: false, extra: 'skills:\n  disabled: [u]\n');
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final snapshot = await load();

      final refused = refusal(
        skillsListEdit(snapshot, disabledKey, 'p', present: false),
      );

      expect(refused, isA<SkillsListDisabledByProject>());
      expect((refused as SkillsListDisabledByProject).source, projectFile());
    });

    test('выключить можно всегда: слой проекта при выборе цели не '
        'учитывается, пишется user с его списком', () async {
      user(trusted: false, extra: 'skills:\n  disabled: [u]\n');
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, disabledKey, 'x', present: true),
      );

      expect(result.layer, ConfigLayer.user);
      expect(result.edits, [
        const SetValue(disabledKey, ['u', 'x']),
      ]);
    });

    test('имя из списка user включается как обычно, даже когда проект '
        'выключает другие', () async {
      user(trusted: false, extra: 'skills:\n  disabled: [u]\n');
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, disabledKey, 'u', present: false),
      );

      expect(result.layer, ConfigLayer.user);
      expect(result.edits, [const UnsetValue(disabledKey)]);
    });
  });

  group('skills.extra_roots и слои проекта (SKL-2)', () {
    test('сценарий «extra_roots не уходит в проектный слой»: ключ только '
        'в config.yaml проекта (агент его отбрасывает) — правка в user, '
        'слой project не меняется', () async {
      user();
      write(projectFile(), 'skills:\n  extra_roots: [/from/project]\n');
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, rootsKey, '.claude/skills', present: true),
      );

      expect(result.layer, ConfigLayer.user);
      expect(result.base.target, const ConfigTarget.user());
      expect(result.edits, [
        const SetValue(rootsKey, ['.claude/skills']),
      ]);
      // Список проекта не стал источником и не слит в запись.
      expect(
        (result.edits.single as SetValue).value as List,
        isNot(contains('/from/project')),
      );
    });

    test('недоверенный проект: extra_roots из config.local.yaml агент '
        'отбрасывает — правка в user, не в projectLocal', () async {
      user(trusted: false);
      write(localFile(), 'skills:\n  extra_roots: [/from/local]\n');
      final snapshot = await load();

      final result = plan(
        skillsListEdit(snapshot, rootsKey, '/opt/skills', present: true),
      );

      expect(result.layer, ConfigLayer.user);
      expect(result.edits, [
        const SetValue(rootsKey, ['/opt/skills']),
      ]);
    });

    test('недоверенный проект и относительный элемент: untrustedProject, '
        'правок нет', () async {
      user(trusted: false);
      final snapshot = await load();

      final refused = refusal(
        skillsListEdit(snapshot, rootsKey, '.claude/skills', present: true),
      );

      expect(refused, isA<SkillsListUntrustedProject>());
    });

    test('недоверенный проект: домашний и абсолютный элементы — как обычно '
        '(читаются без доверия)', () async {
      user(trusted: false);
      final snapshot = await load();

      final home = plan(
        skillsListEdit(snapshot, rootsKey, '~/.claude/skills', present: true),
      );
      final absolute = plan(
        skillsListEdit(snapshot, rootsKey, '/opt/skills', present: true),
      );

      expect(home.layer, ConfigLayer.user);
      expect(absolute.layer, ConfigLayer.user);
    });
  });

  test('ключ вне skills.disabled и skills.extra_roots — ArgumentError '
      '(правило не общий редактор, D5)', () async {
    user();
    final snapshot = await load();

    expect(
      () => skillsListEdit(snapshot, 'skills.enabled', 'x', present: true),
      throwsArgumentError,
    );
  });

  group('применение правок через AgentConfigStore.apply', () {
    test('SetValue в user: ConfigSaved, файл и итог загрузки содержат '
        'список', () async {
      user();
      final store = await open();
      final snapshot = await store.snapshot(cwd: project);
      final result = plan(
        skillsListEdit(snapshot, disabledKey, 'x', present: true),
      );

      final outcome = await store.apply(result.base, result.edits);

      expect(outcome, isA<ConfigSaved>());
      final fresh = await store.snapshot(cwd: project);
      expect(fresh.loaded.config!.skills.disabled, ['x']);
      expect(fresh.originOf(disabledKey)!.kind, ConfigSourceKind.user);
    });

    test(
      'UnsetValue последнего элемента: ключ исчезает из файла слоя',
      () async {
        user(extra: 'skills:\n  disabled: [a]\n');
        final store = await open();
        final snapshot = await store.snapshot(cwd: project);
        final result = plan(
          skillsListEdit(snapshot, disabledKey, 'a', present: false),
        );

        final outcome = await store.apply(result.base, result.edits);

        expect(outcome, isA<ConfigSaved>());
        expect(
          File(userFile()).readAsStringSync(),
          isNot(contains('disabled')),
        );
        final fresh = await store.snapshot(cwd: project);
        expect(fresh.loaded.config!.skills.disabled, isEmpty);
      },
    );

    test('запись в projectLocal создаёт config.local.yaml со списком и не '
        'трогает user', () async {
      user(extra: 'skills:\n  disabled: [c]\n');
      write(localFile(), 'skills:\n  disabled: [a]\n');
      final store = await open();
      final snapshot = await store.snapshot(cwd: project);
      final before = File(userFile()).readAsStringSync();
      final result = plan(
        skillsListEdit(snapshot, disabledKey, 'b', present: true),
      );

      final outcome = await store.apply(result.base, result.edits);

      expect(outcome, isA<ConfigSaved>());
      expect(File(userFile()).readAsStringSync(), before);
      final fresh = await store.snapshot(cwd: project);
      expect(fresh.loaded.config!.skills.disabled, ['a', 'b']);
      expect(fresh.originOf(disabledKey)!.kind, ConfigSourceKind.projectLocal);
    });

    test('согласие на extra_roots, данное в user, действует в сессии: '
        'extraRoots в итоге загрузки', () async {
      user();
      final store = await open();
      final snapshot = await store.snapshot(cwd: project);
      final result = plan(
        skillsListEdit(snapshot, rootsKey, '~/.claude/skills', present: true),
      );

      final outcome = await store.apply(result.base, result.edits);

      expect(outcome, isA<ConfigSaved>());
      final fresh = await store.snapshot(cwd: project);
      expect(fresh.loaded.config!.skills.extraRoots, ['~/.claude/skills']);
    });

    test('чужая правка между чтением и записью: ConfigConflict, файл не '
        'перезаписан', () async {
      user();
      final store = await open();
      final snapshot = await store.snapshot(cwd: project);
      final result = plan(
        skillsListEdit(snapshot, disabledKey, 'x', present: true),
      );
      write(userFile(), '${File(userFile()).readAsStringSync()}# edited\n');

      final outcome = await store.apply(result.base, result.edits);

      expect(outcome, isA<ConfigConflict>());
      expect(File(userFile()).readAsStringSync(), contains('# edited'));
      expect(File(userFile()).readAsStringSync(), isNot(contains('disabled')));
    });
  });
}
