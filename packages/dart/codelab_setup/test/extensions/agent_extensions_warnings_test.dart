import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

/// Предупреждения разделов вида (ревью итерации 1, находка MINOR 6; design.md
/// change `add-app-skills-page`, D4 «Предупреждения»).
///
/// Почему: диагностики файлов проекта одним списком смешивают файлы цепочки
/// (`AGENTS.md`, `CLAUDE.md`), шаблоны и определения агентов. Страница
/// показывает цепочку и шаблоны, поэтому диагностики файлов цепочки идут в
/// `ContextChainView.warnings`, шаблонов — в `TemplatesSectionView.warnings`,
/// а `.codelab/agents` не показывается вовсе (агентов на странице нет).
void main() {
  ExtensionDiagnostic diag(
    String path,
    String code, {
    DiagnosticLevel level = DiagnosticLevel.warning,
  }) => ExtensionDiagnostic(
    path: path,
    level: level,
    code: code,
    message: 'fixed text',
  );

  AgentExtensionsView build(ProjectFiles files) => agentExtensionsOf(
    AgentConfigSnapshot.fromLayers(
      cwd: '/repo',
      layers: {
        ConfigLayer.user: ConfigSnapshot(
          target: const ConfigTarget.user(),
          path: '/h/config.yaml',
          fingerprint: 'fp',
          values: const {},
        ),
      },
      loaded: ConfigLoadResult(
        config: CoreConfig(
          defaultModel: ModelRef(
            provider: 'test',
            id: 'm',
            api: ProviderApi.openaiChat,
            baseUrl: Uri.parse('http://localhost/v1'),
            contextWindow: 32000,
            maxOutputTokens: 4096,
          ),
        ),
      ),
      secrets: const SecretBackendInfo(id: 'file', writable: true),
    ),
    ProjectExtensions(
      cwd: '/repo',
      trusted: true,
      contextRoot: '/repo',
      codelabHome: '/home/codelab',
      projectFiles: PhaseLoaded(files),
      skills: null,
      skillRoots: const [],
    ),
    userHome: '/uh',
  );

  test('diagnostics of AGENTS.md and CLAUDE.md go to the chain, of prompts '
      'to the templates, of agents nowhere; info is dropped', () {
    final files = ProjectFiles(
      diagnostics: [
        diag('/repo/AGENTS.md', 'too_large'),
        diag('/repo/pkg/CLAUDE.md', 'not_utf8', level: DiagnosticLevel.error),
        diag('/repo/agents/AGENTS.md', 'unreadable'),
        diag('/repo/.codelab/prompts', 'unreadable'),
        diag('/repo/.codelab/prompts/big.md', 'too_large'),
        diag('/repo/.codelab/agents/x.md', 'too_large'),
        diag('/repo/pkg/CLAUDE.md', 'shadowed', level: DiagnosticLevel.info),
      ],
      templates: [
        MarkdownFile(
          path: '/repo/.codelab/prompts/Bad Name.md',
          scope: ExtensionScope.project,
          body: 'b',
          bodyLine: 1,
        ),
      ],
    );

    final view = build(files);

    expect(view.context.warnings.map((d) => d.code), [
      'too_large',
      'not_utf8',
      'unreadable',
    ]);
    expect(view.context.warnings.map((d) => d.path), [
      '/repo/AGENTS.md',
      '/repo/pkg/CLAUDE.md',
      '/repo/agents/AGENTS.md',
    ]);
    // Каталог prompts и файл в нём, затем диагностика самого шаблона.
    expect(view.templates.warnings.map((d) => d.code), [
      'unreadable',
      'too_large',
      'invalid_name',
    ]);
    expect(
      [...view.context.warnings, ...view.templates.warnings].map((d) => d.path),
      isNot(contains('/repo/.codelab/agents/x.md')),
    );
  });

  test('a project under a directory named agents or prompts: only the '
      'directory of the file decides, not the parents of the project', () {
    final files = ProjectFiles(
      diagnostics: [
        // Проект под `/work/prompts/…`: определения агентов не в шаблоны.
        diag('/work/prompts/repo/.codelab/agents/x.md', 'too_large'),
        diag('/work/prompts/repo/.codelab/prompts/big.md', 'too_large'),
        diag('/work/prompts/repo/.codelab/prompts', 'unreadable'),
        // Проект под `/work/agents/…`: диагностика цепочки не пропадает.
        diag('/work/agents/repo/pkg/notes.txt', 'outside_root'),
        diag('/work/agents/repo/.codelab/agents/y.md', 'too_large'),
      ],
    );

    final view = build(files);

    expect(view.templates.warnings.map((d) => d.path), [
      '/work/prompts/repo/.codelab/prompts/big.md',
      '/work/prompts/repo/.codelab/prompts',
    ]);
    expect(view.context.warnings.map((d) => d.path), [
      '/work/agents/repo/pkg/notes.txt',
    ]);
  });
}
