import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_setup/codelab_setup.dart';
// ignore: implementation_imports, шов тестов: функция не входит в публичный API.
import 'package:codelab_setup/src/io/extensions_host_paths.dart';
import 'package:test/test.dart';

/// Типизированные подписи вида навыков (spec `client-agent-setup`
/// «Типизированные подписи вида навыков»; design.md change
/// `add-desktop-localization`, D6 «Тексты моста настроек (итерация 5)»).
///
/// Почему: app строит «Overrides <область> skill» и «<элемент> (extra root)»
/// на своём языке по `overridesScope` и `extraEntry`, а прежние подписи
/// `overridesLabel` и `label` остаются для CLI. Тесты красные до 5.1b: поля
/// пока заглушки и всегда `null`. Данные — фейковые, файлов нет.
void main() {
  const roots = [
    SkillRootInfo(scope: ExtensionScope.project, path: '/r/p/.codelab/skills'),
    SkillRootInfo(scope: ExtensionScope.project, path: '/r/.agents/skills'),
    SkillRootInfo(scope: ExtensionScope.user, path: '/r/h/skills'),
    SkillRootInfo(
      scope: ExtensionScope.extra,
      path: '/r/u/.claude/skills',
      extraRoot: '~/.claude/skills',
    ),
    // Элемент extra_roots не записан: подпись строится по пути корня.
    SkillRootInfo(scope: ExtensionScope.extra, path: '/r/x/skills'),
  ];

  SkillFile skill(String dir, int root) => SkillFile(
    dir: '${roots[root].path}/$dir',
    scope: roots[root].scope,
    rootIndex: root,
    frontmatter: ConfigTree(
      kind: ConfigLayerKind.user,
      source: '${roots[root].path}/$dir/SKILL.md',
      values: {'name': dir, 'description': 'd'},
    ),
    body: 'b',
    bodyLine: 4,
  );

  /// Корень с индексом [root] — «неизвестный»: его нет в `skillRoots`.
  SkillFile orphan(String dir) => SkillFile(
    dir: '/r/lost/$dir',
    scope: ExtensionScope.extra,
    rootIndex: 9,
    frontmatter: ConfigTree(
      kind: ConfigLayerKind.user,
      source: '/r/lost/$dir/SKILL.md',
      values: {'name': dir, 'description': 'd'},
    ),
    body: 'b',
    bodyLine: 4,
  );

  AgentExtensionsView build(List<SkillFile> files) {
    final config = CoreConfig(
      defaultModel: ModelRef(
        provider: 'test',
        id: 'm',
        api: ProviderApi.openaiChat,
        baseUrl: Uri.parse('http://localhost/v1'),
        contextWindow: 32000,
        maxOutputTokens: 4096,
      ),
    );
    final snapshot = AgentConfigSnapshot.fromLayers(
      cwd: '/r/p',
      layers: {
        ConfigLayer.user: ConfigSnapshot(
          target: const ConfigTarget.user(),
          path: '/h/config.yaml',
          fingerprint: 'fp',
          values: const {},
        ),
      },
      loaded: ConfigLoadResult(config: config),
      secrets: const SecretBackendInfo(id: 'file', writable: true),
    );
    return agentExtensionsOf(
      snapshot,
      ProjectExtensions(
        cwd: '/r/p',
        trusted: true,
        contextRoot: '/r',
        codelabHome: '/r/h',
        projectFiles: PhaseLoaded(ProjectFiles.empty),
        skills: PhaseLoaded(SkillFiles(skills: files)),
        skillRoots: roots,
      ),
      userHome: '/r/u',
    );
  }

  SkillEntryView row(AgentExtensionsView view, String name, {int? root}) =>
      view.skills.entries.firstWhere(
        (e) =>
            e.name == name && (root == null || e.root.path == roots[root].path),
      );

  group('overridesScope (сценарий «Навык перекрывает пользовательский»)', () {
    test('проект перекрыл пользователя: подпись прежняя, область user', () {
      final view = build([skill('review', 0), skill('review', 2)]);

      final entry = row(view, 'review');
      expect(entry.overridesLabel, 'Overrides user skill');
      expect(entry.overridesScope, ExtensionScope.user);
    });

    test('проект перекрыл дополнительную папку: область extra', () {
      final view = build([skill('lint', 0), skill('lint', 3)]);

      final entry = row(view, 'lint');
      expect(entry.overridesLabel, 'Overrides extra skill');
      expect(entry.overridesScope, ExtensionScope.extra);
    });

    test('перекрыт навык той же области: «another skill», область null', () {
      final view = build([skill('zed', 0), skill('zed', 1)]);

      final entry = row(view, 'zed');
      expect(entry.overridesLabel, 'Overrides another skill');
      expect(entry.overridesScope, isNull);
    });

    test('без перекрытия подписи нет, область null', () {
      final view = build([skill('solo', 0)]);

      final entry = row(view, 'solo');
      expect(entry.overridesLabel, isNull);
      expect(entry.overridesScope, isNull);
    });

    test('текст подписи равен тексту, построенному по полю', () {
      final view = build([
        skill('a', 0),
        skill('a', 2),
        skill('b', 0),
        skill('b', 1),
        skill('c', 0),
        skill('d', 0),
        skill('d', 3),
      ]);

      for (final e in view.skills.entries) {
        final scope = e.overridesScope;
        if (scope != null) {
          expect(e.overridesLabel, 'Overrides ${scope.name} skill');
        } else {
          expect(
            e.overridesLabel,
            anyOf(isNull, 'Overrides another skill'),
            reason: e.name,
          );
        }
      }
      expect(
        view.skills.entries.where((e) => e.overridesScope != null),
        isNotEmpty,
      );
    });
  });

  group('extraEntry (сценарий «Дополнительная папка навыков»)', () {
    test('корень extra с элементом extra_roots: подпись прежняя, элемент как '
        'записан', () {
      final view = build([skill('delta', 3)]);

      final root = row(view, 'delta').root;
      expect(root.label, '~/.claude/skills (extra root)');
      expect(root.extraEntry, '~/.claude/skills');
    });

    test('корень extra без элемента: элемент — путь корня', () {
      final view = build([skill('echo', 4)]);

      final root = row(view, 'echo').root;
      expect(root.label, '/r/x/skills (extra root)');
      expect(root.extraEntry, '/r/x/skills');
    });

    test('project и user: extraEntry null, подписи прежние', () {
      final view = build([skill('p', 0), skill('u', 2)]);

      final project = row(view, 'p').root;
      final user = row(view, 'u').root;
      expect(project.label, '.codelab/skills');
      expect(project.extraEntry, isNull);
      expect(user.label, '/r/h/skills');
      expect(user.extraEntry, isNull);
    });

    test('неизвестный корень: «(unknown root)», extraEntry null', () {
      final view = build([orphan('ghost')]);

      final root = row(view, 'ghost').root;
      expect(root.scope, ExtensionScope.extra);
      expect(root.label, '(unknown root)');
      expect(root.extraEntry, isNull);
    });

    test('перевод путей в форму хоста переносит extraEntry без изменений', () {
      final view = build([skill('delta', 3), skill('p', 0)]);

      final host = extensionsInHostForm(view, windows: true);

      final root = row(host, 'delta').root;
      expect(root.path, isNot('/r/u/.claude/skills'));
      expect(root.extraEntry, '~/.claude/skills');
      expect(row(host, 'p').root.extraEntry, isNull);
    });
  });
}
