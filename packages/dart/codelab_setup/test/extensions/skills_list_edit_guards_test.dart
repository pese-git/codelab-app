import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:codelab_setup/src/config/project_trust.dart';
import 'package:test/test.dart';

/// Защитные ветки `skillsListEdit` и расчёта доверия (мутационная проверка
/// итерации 2; design.md change `add-app-skills-page`, D5, Q43, SKL-2).
///
/// Почему отдельно: эти ветки не видны на «счастливом» пути — доверенный
/// проект не должен получать отказ Q43, порядок причин отказа определяет, что
/// увидит пользователь, доверие без итога загрузки обязано быть fail-closed, а
/// слои проекта, которые ядро уже отбросило, не должны становиться целью
/// записи, даже если в снимке нет предупреждения `untrusted_key`.
///
/// Порядок причин (D5), зафиксированный тестом: источник не редактируется
/// (`NotEditable`) → имя выключено проектом (`DisabledByProject`) → выдача
/// относительного корня (`UntrustedProject`) → слой цели не прочитан
/// (`LayerUnreadable`). design порядок явно не называет.
void main() {
  const disabledKey = 'skills.disabled';
  const rootsKey = 'skills.extra_roots';

  CoreConfig config({
    String? projectRoot,
    List<String> trusted = const [],
    Map<String, Object?>? below,
  }) => CoreConfig(
    defaultModel: ModelRef(
      provider: 'test',
      id: 'm',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost/v1'),
      contextWindow: 32000,
      maxOutputTokens: 4096,
    ),
    projectRoot: projectRoot,
    trustedProjects: trusted,
    withoutProjectValues: below,
  );

  ConfigSnapshot layer(
    ConfigTarget target,
    String path,
    Map<String, Object?> values,
  ) => ConfigSnapshot(
    target: target,
    path: path,
    fingerprint: 'fp',
    values: values,
  );

  AgentConfigSnapshot snapshot({
    required Map<ConfigLayer, ConfigSnapshot> layers,
    ConfigLoadResult loaded = const ConfigLoadResult(),
  }) => AgentConfigSnapshot.fromLayers(
    cwd: '/work',
    layers: layers,
    loaded: loaded,
    secrets: const SecretBackendInfo(id: 'file', writable: true),
  );

  group('доверие по итогу загрузки (fail-closed)', () {
    test('нет итога загрузки или корня проектных слоёв — недоверенный', () {
      expect(projectTrustedIn(null), isFalse);
      // Список доверия не пуст, но корень проектных слоёв не задан.
      expect(projectTrustedIn(config(trusted: ['/work'])), isFalse);
    });

    test('корень в trusted_projects — доверенный; чужой — нет', () {
      expect(
        projectTrustedIn(config(projectRoot: '/work', trusted: ['/work'])),
        isTrue,
      );
      expect(
        projectTrustedIn(config(projectRoot: '/work', trusted: ['/other'])),
        isFalse,
      );
    });

    test(r'разделители Windows: `C:\p` и `C:/p` — один и тот же корень', () {
      expect(
        projectTrustedIn(config(projectRoot: r'C:\p', trusted: [r'C:\p'])),
        isTrue,
      );
      expect(
        projectTrustedIn(config(projectRoot: r'C:\p', trusted: ['C:/p'])),
        isTrue,
      );
      expect(
        projectTrustedIn(config(projectRoot: 'C:/p', trusted: [r'C:\p'])),
        isTrue,
      );
      expect(
        projectTrustedIn(config(projectRoot: r'C:\p', trusted: ['C:/q'])),
        isFalse,
      );
    });

    test('снимок без итога загрузки: выдача относительного корня — '
        'untrustedProject', () {
      final result = skillsListEdit(
        snapshot(
          layers: {
            ConfigLayer.user: layer(
              const ConfigTarget.user(),
              '/h/config.yaml',
              const {},
            ),
          },
        ),
        rootsKey,
        '.claude/skills',
        present: true,
      );

      expect(
        (result as SkillsListRefused).refusal,
        isA<SkillsListUntrustedProject>(),
      );
    });
  });

  group('порядок причин отказа (D5)', () {
    // Недоверенный проект: ядро заполнило `withoutProjectValues` (пусто),
    // слоя user в снимке нет (файл не прочитан), проект выключает `p`.
    AgentConfigSnapshot untrustedWithoutUser() => snapshot(
      layers: {
        ConfigLayer.project: layer(
          const ConfigTarget.project('/work'),
          '/work/.codelab/config.yaml',
          const {
            'skills': {
              'disabled': ['p'],
            },
          },
        ),
      },
      loaded: ConfigLoadResult(
        config: config(projectRoot: '/work', below: const {}),
        values: const {
          'skills.disabled': ['p'],
        },
      ),
    );

    test('включение имени, выключенного проектом, — disabledByProject, '
        'а не layerUnreadable слоя user', () {
      final result = skillsListEdit(
        untrustedWithoutUser(),
        disabledKey,
        'p',
        present: false,
      );

      final refusal = (result as SkillsListRefused).refusal;
      expect(refusal, isA<SkillsListDisabledByProject>());
      expect(
        (refusal as SkillsListDisabledByProject).source,
        '/work/.codelab/config.yaml',
      );
    });

    test('выдача относительного корня — untrustedProject, а не '
        'layerUnreadable', () {
      final result = skillsListEdit(
        untrustedWithoutUser(),
        rootsKey,
        '.claude/skills',
        present: true,
      );

      expect(
        (result as SkillsListRefused).refusal,
        isA<SkillsListUntrustedProject>(),
      );
    });

    test(
      'остальные действия при том же снимке — layerUnreadable слоя user',
      () {
        final result = skillsListEdit(
          untrustedWithoutUser(),
          disabledKey,
          'x',
          present: true,
        );

        expect(
          (result as SkillsListRefused).refusal,
          isA<SkillsListLayerUnreadable>(),
        );
      },
    );
  });

  group('защита от слоёв проекта, которые ядро отбросило', () {
    test('extra_roots в слое project без предупреждения untrusted_key: не '
        'источник, правка идёт в user', () {
      final result = skillsListEdit(
        snapshot(
          layers: {
            ConfigLayer.user: layer(
              const ConfigTarget.user(),
              '/h/config.yaml',
              const {},
            ),
            ConfigLayer.project: layer(
              const ConfigTarget.project('/work'),
              '/work/.codelab/config.yaml',
              const {
                'skills': {
                  'extra_roots': ['/from/project'],
                },
              },
            ),
          },
        ),
        rootsKey,
        '/opt/skills',
        present: true,
      );

      expect(result, isA<SkillsListPlan>(), reason: '$result');
      final plan = result as SkillsListPlan;
      expect(plan.layer, ConfigLayer.user);
      expect(plan.edits, [
        const SetValue(rootsKey, ['/opt/skills']),
      ]);
    });

    test('extra_roots в projectLocal недоверенного проекта без '
        'предупреждения: правка идёт в user, не в projectLocal', () {
      final result = skillsListEdit(
        snapshot(
          layers: {
            ConfigLayer.user: layer(
              const ConfigTarget.user(),
              '/h/config.yaml',
              const {},
            ),
            ConfigLayer.projectLocal: layer(
              const ConfigTarget.projectLocal('/work'),
              '/work/.codelab/config.local.yaml',
              const {
                'skills': {
                  'extra_roots': ['/from/local'],
                },
              },
            ),
          },
          loaded: ConfigLoadResult(config: config(projectRoot: '/work')),
        ),
        rootsKey,
        '/opt/skills',
        present: true,
      );

      expect(result, isA<SkillsListPlan>(), reason: '$result');
      final plan = result as SkillsListPlan;
      expect(plan.layer, ConfigLayer.user);
      expect(plan.base.target, const ConfigTarget.user());
    });
  });

  group('доверенный проект: отказ Q43 не применяется', () {
    late Directory root;
    late String home;
    late String project;

    void write(String path, String text) => File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

    setUp(() {
      root = Directory.systemTemp.createTempSync('skills_list_guards_');
      home = '${root.path}/home';
      project = '${root.path}/project';
      Directory(home).createSync();
      Directory(project).createSync();
      Process.runSync('/bin/chmod', ['700', home]);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('disabled в config.local.yaml доверенного проекта: источник '
        'projectLocal, включение — план UnsetValue в projectLocal', () async {
      final canonical = Directory(project).resolveSymbolicLinksSync();
      write(
        '$home/config.yaml',
        'agent:\n  default_model: p/m\nproviders:\n  p:\n'
            '    kind: openai-compatible\n    base_url: https://llm.test/v1\n'
            '    models:\n      m:\n        context_window: 32000\n'
            'trusted_projects: [$canonical]\n',
      );
      write(
        '$project/.codelab/config.local.yaml',
        'skills:\n  disabled: [a]\n',
      );
      final environment = {'HOME': root.path, 'CODELAB_HOME': home};
      final store = FileAgentConfigStore(
        paths: ConfigPaths(codelabHome: home, projectDir: project),
        environment: environment,
        secrets: await ClientSecretAccess.open(
          codelabHome: home,
          environment: environment,
          logger: RecordingLogger(),
        ),
        logger: RecordingLogger(),
      );
      final snap = await store.snapshot(cwd: project);

      final result = skillsListEdit(snap, disabledKey, 'a', present: false);

      expect(result, isA<SkillsListPlan>(), reason: '$result');
      final plan = result as SkillsListPlan;
      expect(plan.layer, ConfigLayer.projectLocal);
      expect(plan.edits, [const UnsetValue(disabledKey)]);
    });
  });
}
