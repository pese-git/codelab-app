import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_setup/codelab_setup.dart';
// ignore: implementation_imports, шов тестов: функция не входит в публичный API.
import 'package:codelab_setup/src/io/extensions_host_paths.dart';
import 'package:test/test.dart';

/// `extensionsInHostForm`: перевод всех путей вида из формы ядра (`/c/p`) в
/// форму хоста (`C:\p`) одним проходом (design.md change
/// `add-app-skills-page`, D8 «Форма путей вида»). На POSIX хост тождественен,
/// поэтому Windows-форма проверяется параметром `windows: true`.
void main() {
  const roots = [
    SkillRootInfo(scope: ExtensionScope.project, path: '/c/p/.codelab/skills'),
    SkillRootInfo(scope: ExtensionScope.user, path: '/c/u/.agents/skills'),
  ];

  ExtensionDiagnostic warn(String path) => ExtensionDiagnostic(
    path: path,
    level: DiagnosticLevel.warning,
    code: 'some_warning',
    message: 'text with /c/p inside stays',
  );

  AgentExtensionsView build({bool diagnostics = false}) {
    SkillFile file(String dir, int root) => SkillFile(
      dir: dir,
      scope: roots[root].scope,
      rootIndex: root,
      frontmatter: ConfigTree(
        kind: ConfigLayerKind.user,
        source: '$dir/SKILL.md',
        values: {'name': dir.split('/').last, 'description': 'd'},
      ),
      body: 'b',
      bodyLine: 4,
    );
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
      cwd: '/c/p',
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
        cwd: '/c/p',
        trusted: true,
        contextRoot: '/c/p',
        codelabHome: '/c/h',
        projectFiles: PhaseLoaded(
          ProjectFiles(
            context: [
              ContextFile(
                path: 'AGENTS.md',
                content: 'rules',
                scope: ExtensionScope.project,
              ),
              if (diagnostics) ...[
                ContextFile(path: 'packages/x/AGENTS.md', content: 'x'),
                ContextFile(path: r'$CODELAB_HOME/AGENTS.md', content: 'h'),
                // Абсолютный путь в `path` недостижим для загрузчика, но
                // правило «путь для промпта не переводится» не зависит от вида.
                ContextFile(path: '/c/odd/AGENTS.md', content: 'o'),
              ],
            ],
            diagnostics: [
              if (diagnostics) ...[
                warn('/c/p/AGENTS.md'),
                warn('a/AGENTS.md'),
                warn('/c/p/.codelab/prompts/bad.md'),
              ],
            ],
            templates: [
              MarkdownFile(
                path: '/c/p/.codelab/prompts/review.md',
                scope: ExtensionScope.project,
                body: 'Review it',
                bodyLine: 1,
              ),
            ],
          ),
        ),
        skills: PhaseLoaded(
          SkillFiles(
            skills: [
              file('/c/p/.codelab/skills/alpha', 0),
              file('/c/u/.agents/skills/alpha', 1),
            ],
            diagnostics: [
              if (diagnostics) ...[
                warn('/c/p/.codelab/skills/alpha/SKILL.md'),
                warn('/c/u/.agents/skills/broken'),
              ],
            ],
          ),
        ),
        skillRoots: roots,
      ),
      userHome: '/c/u',
      consents: [
        if (diagnostics)
          const SkillConsentView(
            entry: '~/.claude/skills',
            path: '/c/u/.claude/skills',
            skillDirs: 1,
            granted: false,
            toggle: SkillToggle.available(),
          ),
      ],
    );
  }

  test('корни, overrides, каталог навыка, openDir, шаблон и папка — в форме '
      'хоста Windows; путь для промпта и подписи не трогаются', () {
    final view = extensionsInHostForm(build(), windows: true);

    expect(view.folder, r'C:\p');
    expect(view.context.files.single.openDir, r'C:\p');
    expect(view.context.files.single.path, 'AGENTS.md');
    final alpha = view.skills.entries.single;
    expect(alpha.root.path, r'C:\p\.codelab\skills');
    expect(alpha.root.label, '.codelab/skills');
    expect(alpha.directory, r'C:\p\.codelab\skills\alpha');
    expect([for (final o in alpha.overrides) o.path], [r'C:\u\.agents\skills']);
    expect(
      view.templates.entries.single.sourcePath,
      r'C:\p\.codelab\prompts\review.md',
    );
  });

  test('согласие и пути диагностик во всех четырёх списках — в форме хоста; '
      'тексты, относительные пути и путь для промпта не трогаются', () {
    final view = extensionsInHostForm(build(diagnostics: true), windows: true);

    expect(view.skills.consents.single.path, r'C:\u\.claude\skills');
    expect(
      [for (final d in view.context.warnings) d.path],
      [r'C:\p\AGENTS.md', 'a/AGENTS.md'],
    );
    expect(
      [for (final d in view.templates.warnings) d.path],
      [r'C:\p\.codelab\prompts\bad.md'],
    );
    expect(
      [for (final d in view.skills.entries.single.warnings) d.path],
      [r'C:\p\.codelab\skills\alpha\SKILL.md'],
    );
    expect(
      [for (final d in view.skills.warnings) d.path],
      // Вторым идёт `shadowed` перекрытого навыка (диагностика ядра).
      [r'C:\u\.agents\skills\broken', r'C:\u\.agents\skills\alpha\SKILL.md'],
    );
    expect(view.context.warnings.first.message, 'text with /c/p inside stays');
    expect(
      [for (final f in view.context.files) f.path],
      containsAll([
        'AGENTS.md',
        'packages/x/AGENTS.md',
        r'$CODELAB_HOME/AGENTS.md',
        '/c/odd/AGENTS.md',
      ]),
    );
  });

  test('на POSIX перевод тождественен', () {
    final view = extensionsInHostForm(build(), windows: false);

    expect(view.folder, '/c/p');
    expect(view.skills.entries.single.directory, '/c/p/.codelab/skills/alpha');
  });
}
