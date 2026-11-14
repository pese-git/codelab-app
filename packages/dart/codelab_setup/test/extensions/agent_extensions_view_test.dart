import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

const _leak = 'sk-test-leak-0123456789';

const _cwd = '/repo/pkg';
const _repo = '/repo';
const _codelabHome = '/home/codelab';
const _userHome = '/uh';
const _configPath = '/h/config.yaml';

/// Корни навыков в порядке `rootIndex`, как их отдаёт `loadProjectExtensions`.
const _roots = [
  SkillRootInfo(
    scope: ExtensionScope.project,
    path: '/repo/pkg/.codelab/skills',
  ),
  SkillRootInfo(scope: ExtensionScope.project, path: '/repo/.agents/skills'),
  SkillRootInfo(scope: ExtensionScope.user, path: '/home/codelab/skills'),
  SkillRootInfo(scope: ExtensionScope.user, path: '/uh/.agents/skills'),
  SkillRootInfo(
    scope: ExtensionScope.extra,
    path: '/uh/.claude/skills',
    extraRoot: '~/.claude/skills',
  ),
];

CoreConfig _config({
  SkillsConfig skills = const SkillsConfig(),
  PermissionsConfig permissions = const PermissionsConfig(),
  int contextBytes = 32768,
}) => CoreConfig(
  defaultModel: ModelRef(
    provider: 'test',
    id: 'm',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost/v1'),
    contextWindow: 32000,
    maxOutputTokens: 4096,
  ),
  skills: skills,
  permissions: permissions,
  projectContextMaxBytes: contextBytes,
);

/// Снимок с единственным слоем `user`; [values] — значения слоя (ключи
/// `skills.*` для происхождения), [config] — итог загрузки.
AgentConfigSnapshot _snapshot(
  CoreConfig config, {
  Map<String, Object?> values = const {},
}) => AgentConfigSnapshot.fromLayers(
  cwd: _cwd,
  layers: {
    ConfigLayer.user: ConfigSnapshot(
      target: const ConfigTarget.user(),
      path: _configPath,
      fingerprint: 'fp',
      values: values,
    ),
  },
  loaded: ConfigLoadResult(config: config),
  secrets: const SecretBackendInfo(id: 'file', writable: true),
);

SkillFile _skill(
  String dirName, {
  required int root,
  bool noFrontmatter = false,
  String? name,
  String description = 'Does the thing',
  Map<String, Object?> extra = const {},
  String body = 'Do the thing.',
}) {
  final holder = _roots[root];
  return SkillFile(
    dir: '${holder.path}/$dirName',
    scope: holder.scope,
    rootIndex: root,
    frontmatter: noFrontmatter
        ? null
        : ConfigTree(
            kind: ConfigLayerKind.user,
            source: '${holder.path}/$dirName/SKILL.md',
            values: {
              'name': name ?? dirName,
              'description': description,
              ...extra,
            },
          ),
    body: body,
    bodyLine: 4,
  );
}

String _skillPath(String dirName, int root) =>
    '${_roots[root].path}/$dirName/SKILL.md';

ProjectExtensions _extensions({
  bool trusted = true,
  PhaseOutcome<ProjectFiles>? project,
  PhaseOutcome<SkillFiles>? skills,
  bool skillsOff = false,
}) => ProjectExtensions(
  cwd: _cwd,
  trusted: trusted,
  contextRoot: _repo,
  codelabHome: _codelabHome,
  projectFiles: project ?? PhaseLoaded(ProjectFiles.empty),
  skills: skillsOff ? null : (skills ?? PhaseLoaded(SkillFiles.empty)),
  skillRoots: _roots,
);

AgentExtensionsView _view(
  CoreConfig config,
  ProjectExtensions extensions, {
  Map<String, Object?> values = const {},
}) => agentExtensionsOf(
  _snapshot(config, values: values),
  extensions,
  userHome: _userHome,
);

SkillEntryView _row(AgentExtensionsView view, String name) =>
    view.skills.entries.singleWhere((e) => e.name == name);

/// `agentExtensionsOf` и `AgentExtensionsView`: вид страницы навыков и
/// расширений по снимку конфигурации и прочитанным файлам (client-agent-setup
/// «Обзор расширений агента»; app-settings сценарии данных «…контекстные
/// файлы и шаблоны», «…навыки»; design.md change `add-app-skills-page`, D4,
/// D15; задача 1.3).
///
/// Почему на фейковых данных: построитель — чистая функция основного бареля
/// (web-безопасно, без `dart:io`), поэтому тесту не нужны ни файлы, ни
/// загрузчик: `ProjectExtensions` собирается руками, снимок — из слоёв
/// `AgentConfigSnapshot.fromLayers`. Чтение настоящих файлов проверяет
/// `test/io/read_agent_extensions_test.dart`.
///
/// Фиксируемый API (design.md D4; решения, которых design не задаёт, отмечены
/// в отчёте итерации): `agentExtensionsOf(snapshot, extensions, {userHome})`;
/// `AgentExtensionsView(folder, trusted, context, skills, templates)`;
/// `ContextChainView(outcome, files, shownBytes, omittedCount,
/// truncatedCount)`; `ContextFileView(path, openDir, bytes, shownBytes,
/// scope, isClaudeAlias, omitted)`; `SkillsSectionView(outcome, entries,
/// warnings)`; `SkillEntryView(name, description, argumentHint, invokeAs,
/// availability, modelVisible, userInvocable, root, overrides,
/// overridesLabel, warnings)`; `SkillRootView(scope, label, path)`;
/// `TemplatesSectionView(outcome, entries, warnings)`;
/// `TemplateEntryView(command, argumentHint, description, sourcePath,
/// scope)`; исходы раздела `SectionRead | SectionTimedOut |
/// SectionFailed(errorType) | SectionOff(source)`.
void main() {
  group('цепочка AGENTS.md (E-01; D4 «Цепочка»)', () {
    test('порядок цепочки — порядок загрузчика, пути на диске: '
        '\$CODELAB_HOME и корень обхода', () {
      final files = ProjectFiles(
        context: [
          ContextFile(
            path: r'$CODELAB_HOME/AGENTS.md',
            content: 'user rules',
            scope: ExtensionScope.user,
          ),
          ContextFile(path: 'AGENTS.md', content: 'repo rules'),
          ContextFile(path: 'pkg/AGENTS.md', content: 'pkg rules'),
        ],
        contextRoot: ContextRoot.git,
      );

      final view = _view(_config(), _extensions(project: PhaseLoaded(files)));

      final chain = view.context.files;
      expect(
        [for (final f in chain) f.path],
        [r'$CODELAB_HOME/AGENTS.md', 'AGENTS.md', 'pkg/AGENTS.md'],
      );
      // Каталог для «Open» — каталог файла на диске (решение Q5).
      expect(
        [for (final f in chain) f.openDir],
        [_codelabHome, _repo, '$_repo/pkg'],
      );
      expect(chain.first.scope, ExtensionScope.user);
      expect(chain.last.scope, ExtensionScope.project);
      expect(chain.last.bytes, 'pkg rules'.length);
      expect(view.context.outcome, isA<SectionRead>());
    });

    test('CLAUDE.md помечен как замена AGENTS.md (Q6)', () {
      final files = ProjectFiles(
        context: [
          ContextFile(path: 'CLAUDE.md', content: 'claude rules'),
          ContextFile(path: 'pkg/AGENTS.md', content: 'pkg rules'),
        ],
      );

      final view = _view(_config(), _extensions(project: PhaseLoaded(files)));

      expect(view.context.files[0].isClaudeAlias, isTrue);
      expect(view.context.files[1].isClaudeAlias, isFalse);
    });

    test('усечение и пропуск по бюджету считает assembleProjectContext '
        'ядра, мост их не пересчитывает', () {
      // Бюджет 30 байт раздаётся от ближайшего файла: pkg — целиком (20),
      // корень — обрывок 10 из 20, пользовательский — пропущен.
      final files = ProjectFiles(
        context: [
          ContextFile(
            path: r'$CODELAB_HOME/AGENTS.md',
            content: 'u' * 20,
            scope: ExtensionScope.user,
          ),
          ContextFile(path: 'AGENTS.md', content: 'r' * 20),
          ContextFile(path: 'pkg/AGENTS.md', content: 'p' * 20),
        ],
      );
      final expected = assembleProjectContext(files.context, 30)!;

      final view = _view(
        _config(contextBytes: 30),
        _extensions(project: PhaseLoaded(files)),
      );

      final chain = view.context;
      expect(chain.files[0].omitted, isTrue);
      expect(chain.files[0].shownBytes, 0);
      expect(chain.files[1].omitted, isFalse);
      expect(chain.files[1].shownBytes, 10);
      expect(chain.files[1].bytes, 20);
      expect(chain.files[2].shownBytes, 20);
      expect(chain.shownBytes, expected.bytes);
      expect(chain.omittedCount, expected.omitted);
      expect(chain.truncatedCount, expected.truncated);
    });
  });

  group('навыки: строки совпадают с каталогом сессии (D4 «Навыки»)', () {
    late SkillFiles files;
    late CoreConfig config;

    setUp(() {
      files = SkillFiles(
        skills: [
          _skill('alpha', root: 0, extra: {'argument-hint': 'file'}),
          _skill('alpha', root: 2),
          _skill('beta', root: 1, extra: {'disable-model-invocation': true}),
          _skill('gamma', root: 3, extra: {'user-invocable': false}),
          _skill('eps', root: 3),
          _skill('delta', root: 4),
          _skill('notes', root: 3, name: 'Notes'),
          _skill('kappa', root: 0),
          _skill('kappa', root: 3),
          _skill('zed', root: 0),
          _skill('zed', root: 1),
          _skill('broken', root: 1, noFrontmatter: true),
        ],
        diagnostics: [
          const ExtensionDiagnostic(
            path: '/uh/.agents/skills/x',
            level: DiagnosticLevel.warning,
            code: 'outside_root',
            message: 'the skill directory is outside its root',
          ),
          const ExtensionDiagnostic(
            path: '/repo/pkg/.codelab/skills',
            level: DiagnosticLevel.info,
            code: 'some_info',
            message: 'a hint that is not shown',
          ),
        ],
      );
      config = _config(
        skills: const SkillsConfig(disabled: ['kappa']),
        permissions: PermissionsConfig(
          rules: PolicyRules(
            denyPatterns: {const PermissionKey('skill', 'eps')},
          ),
        ),
      );
    });

    AgentExtensionsView build() => _view(
      config,
      _extensions(skills: PhaseLoaded(files)),
      values: {
        'skills': {
          'disabled': ['kappa'],
        },
      },
    );

    test('включённые строки совпадают по именам с parseSkills, выключенный '
        'skills.disabled навык — победитель без признака disabled', () {
      final view = build();

      final catalog = parseSkills(
        files,
        config.skills,
        rules: config.permissions.rules,
      );
      final enabled = [
        for (final e in view.skills.entries)
          if (e.availability == SkillAvailability.enabled) e.name,
      ];
      expect(enabled, [for (final s in catalog.skills) s.name]);
      expect(enabled, isNot(contains('kappa')));

      final kappa = _row(view, 'kappa');
      expect(kappa.availability, SkillAvailability.disabled);
      // Победитель второго вызова — тот, кого включит выключатель: ближний.
      expect(kappa.root.scope, ExtensionScope.project);
      expect(kappa.root.path, _roots[0].path);
      // Порядок строк — по имени, как в каталоге.
      final names = [for (final e in view.skills.entries) e.name];
      expect(names, [...names]..sort());
    });

    test('команда и подсказка: /skill:<name> <argument-hint>; без '
        'user-invocable — invokeAs null (Model only)', () {
      final view = build();

      expect(_row(view, 'alpha').invokeAs, '/skill:alpha file');
      expect(_row(view, 'alpha').argumentHint, 'file');
      expect(_row(view, 'beta').invokeAs, '/skill:beta');
      expect(_row(view, 'gamma').invokeAs, isNull);
      expect(_row(view, 'gamma').userInvocable, isFalse);
      expect(_row(view, 'gamma').modelVisible, isTrue);
    });

    test('Command only: disable-model-invocation и запрет skill:<name> '
        'правилами разрешений дают modelVisible == false', () {
      final view = build();

      final catalog = parseSkills(
        files,
        config.skills,
        rules: config.permissions.rules,
      );
      expect(_row(view, 'beta').modelVisible, isFalse);
      expect(_row(view, 'eps').modelVisible, isFalse);
      expect(_row(view, 'eps').userInvocable, isTrue);
      expect(_row(view, 'alpha').modelVisible, isTrue);
      // Признак совпадает с SkillCatalog.modelVisible сессии.
      expect(
        {
          for (final e in view.skills.entries)
            if (e.availability == SkillAvailability.enabled && e.modelVisible)
              e.name,
        },
        {for (final s in catalog.modelVisible) s.name},
      );
    });

    test('источник строки: корень по rootIndex, подпись по виду корня', () {
      final view = build();

      expect(_row(view, 'alpha').root.label, '.codelab/skills');
      expect(_row(view, 'beta').root.label, '../.agents/skills');
      expect(_row(view, 'gamma').root.label, '~/.agents/skills');
      expect(_row(view, 'delta').root.label, '~/.claude/skills (extra root)');
      expect(_row(view, 'delta').root.scope, ExtensionScope.extra);
      expect(_row(view, 'delta').root.path, '/uh/.claude/skills');
      final user = _row(view, 'Notes');
      expect(user.root.scope, ExtensionScope.user);
    });

    test(r'Overrides user/project/extra skill: по диагностике shadowed, без '
        'разбора её текста', () {
      final view = build();

      final alpha = _row(view, 'alpha');
      expect(alpha.overrides.map((r) => r.scope), [ExtensionScope.user]);
      expect(alpha.overridesLabel, 'Overrides user skill');
      // Тот же уровень (проект перекрыл проект) — без названия уровня.
      expect(_row(view, 'zed').overridesLabel, 'Overrides another skill');
      expect(_row(view, 'beta').overrides, isEmpty);
      expect(_row(view, 'beta').overridesLabel, isNull);
    });

    test('предупреждения: error/warning загруженного навыка — в его строке, '
        'остальные — в разделе, info отброшены', () {
      final view = build();

      final notesPath = _skillPath('notes', 3);
      final notes = _row(view, 'Notes');
      expect(notes.warnings, isNotEmpty);
      expect(notes.warnings.map((d) => d.path), everyElement(notesPath));
      expect(
        notes.warnings.map((d) => d.level),
        everyElement(isNot(DiagnosticLevel.info)),
      );
      expect(_row(view, 'alpha').warnings, isEmpty);

      final section = view.skills.warnings;
      // Пропущенный навык, перекрытый навык и диагностика корня — в разделе.
      expect(
        section.map((d) => (d.code, d.path)),
        containsAll([
          ('missing_frontmatter', _skillPath('broken', 1)),
          ('shadowed', _skillPath('alpha', 2)),
          ('outside_root', '/uh/.agents/skills/x'),
        ]),
      );
      // Строка и раздел не дублируют друг друга.
      expect(section.map((d) => d.path), isNot(contains(notesPath)));
      // info (`disabled`, `some_info`) не показываются.
      expect(
        section.map((d) => d.level),
        everyElement(isNot(DiagnosticLevel.info)),
      );
      expect(section.map((d) => d.code), isNot(contains('some_info')));
      expect(section.map((d) => d.code), isNot(contains('disabled')));
    });
  });

  group('исходы фаз и состояния раздела (D4 «Фазы»)', () {
    test('таймаут фазы навыков: раздел навыков пуст с исходом «не прочитано», '
        'цепочка и шаблоны целы', () {
      final files = ProjectFiles(
        context: [ContextFile(path: 'AGENTS.md', content: 'rules')],
        templates: [_template('/repo/pkg/.codelab/prompts/review.md')],
      );

      final view = _view(
        _config(),
        _extensions(project: PhaseLoaded(files), skills: const PhaseTimedOut()),
      );

      expect(view.skills.outcome, isA<SectionTimedOut>());
      expect(view.skills.entries, isEmpty);
      expect(view.context.outcome, isA<SectionRead>());
      expect(view.context.files, hasLength(1));
      expect(view.templates.outcome, isA<SectionRead>());
      expect(view.templates.entries, hasLength(1));
    });

    test('исключение порта навыков — исход с именем типа, не исключение', () {
      final view = _view(
        _config(),
        _extensions(skills: const PhaseFailed('StateError')),
      );

      final outcome = view.skills.outcome as SectionFailed;
      expect(outcome.errorType, 'StateError');
      expect(view.skills.entries, isEmpty);
    });

    test('сбой фазы файлов проекта: цепочка и шаблоны с исходом, навыки '
        'прочитаны', () {
      final skills = SkillFiles(skills: [_skill('alpha', root: 0)]);

      final view = _view(
        _config(),
        _extensions(
          project: const PhaseFailed('FileSystemException'),
          skills: PhaseLoaded(skills),
        ),
      );

      expect(
        (view.context.outcome as SectionFailed).errorType,
        'FileSystemException',
      );
      expect(view.context.files, isEmpty);
      expect(view.templates.outcome, isA<SectionFailed>());
      expect(view.skills.outcome, isA<SectionRead>());
      expect(view.skills.entries.single.name, 'alpha');
    });

    test('skills.enabled: false — исход «выключено» с файлом-источником '
        'ключа из origins', () {
      final view = _view(
        _config(skills: const SkillsConfig(enabled: false)),
        _extensions(skillsOff: true),
        values: {
          'skills': {'enabled': false},
        },
      );

      final outcome = view.skills.outcome as SectionOff;
      expect(outcome.source, _configPath);
      expect(view.skills.entries, isEmpty);
    });

    test('недоверенный проект: trusted == false, цепочка проекта показана', () {
      final files = ProjectFiles(
        context: [ContextFile(path: 'pkg/AGENTS.md', content: 'pkg rules')],
      );

      final view = _view(
        _config(),
        _extensions(trusted: false, project: PhaseLoaded(files)),
      );

      expect(view.trusted, isFalse);
      expect(view.folder, _cwd);
      expect(view.context.files.single.path, 'pkg/AGENTS.md');
    });
  });

  group('шаблоны команд (E-07; D4 «Шаблоны»)', () {
    test('строки — parseCommandTemplates ядра: проект заменяет пользователя '
        'с тем же именем, перекрытие — info и не показывается', () {
      final files = ProjectFiles(
        templates: [
          _template(
            '/home/codelab/prompts/review.md',
            scope: ExtensionScope.user,
            description: 'User review',
          ),
          _template(
            '/repo/pkg/.codelab/prompts/review.md',
            description: 'Project review',
            hint: '<file>',
          ),
          _template(
            '/home/codelab/prompts/fix.md',
            scope: ExtensionScope.user,
            description: 'Fix it',
          ),
        ],
      );

      final view = _view(_config(), _extensions(project: PhaseLoaded(files)));

      expect(
        [for (final t in view.templates.entries) t.command],
        ['/fix', '/review'],
      );
      final review = view.templates.entries.last;
      expect(review.description, 'Project review');
      expect(review.argumentHint, '<file>');
      expect(review.sourcePath, '/repo/pkg/.codelab/prompts/review.md');
      expect(review.scope, ExtensionScope.project);
      expect(view.templates.warnings, isEmpty);
    });

    test('шаблон с негодным именем файла — предупреждение раздела', () {
      final files = ProjectFiles(
        templates: [_template('/repo/pkg/.codelab/prompts/Bad Name.md')],
      );

      final view = _view(_config(), _extensions(project: PhaseLoaded(files)));

      expect(view.templates.entries, isEmpty);
      expect(view.templates.warnings.single.code, 'invalid_name');
    });
  });

  group('SkillEntryView.toggle: одно правило с записью (D4, D5; задача '
      '2.2)', () {
    SkillFiles twoSkills() => SkillFiles(
      skills: [_skill('alpha', root: 0), _skill('kappa', root: 0)],
    );

    AgentExtensionsView build({
      Map<String, Object?>? projectValues,
      Map<String, Object?> userValues = const {
        'skills': {
          'disabled': ['kappa'],
        },
      },
    }) {
      final config = _config(skills: const SkillsConfig(disabled: ['kappa']));
      final snapshot = AgentConfigSnapshot.fromLayers(
        cwd: _cwd,
        layers: {
          ConfigLayer.user: ConfigSnapshot(
            target: const ConfigTarget.user(),
            path: _configPath,
            fingerprint: 'fp',
            values: userValues,
          ),
          if (projectValues != null)
            ConfigLayer.project: ConfigSnapshot(
              target: const ConfigTarget.project(_cwd),
              path: '$_cwd/.codelab/config.yaml',
              fingerprint: 'fp-p',
              values: projectValues,
            ),
        },
        loaded: ConfigLoadResult(config: config),
        secrets: const SecretBackendInfo(id: 'file', writable: true),
      );
      return agentExtensionsOf(
        snapshot,
        _extensions(skills: PhaseLoaded(twoSkills())),
        userHome: _userHome,
      );
    }

    test('список действует из слоя user: переключатель доступен у '
        'включённого и у выключенного навыка', () {
      final view = build();

      expect(_row(view, 'alpha').toggle.isAvailable, isTrue);
      expect(_row(view, 'alpha').toggle.refusal, isNull);
      expect(_row(view, 'kappa').availability, SkillAvailability.disabled);
      expect(_row(view, 'kappa').toggle.isAvailable, isTrue);
    });

    test('список действует из слоя project: у всех строк отказ '
        'notEditable с файлом (подсказка «Set in <файл>»)', () {
      final view = build(
        projectValues: const {
          'skills': {
            'disabled': ['kappa'],
          },
        },
      );

      for (final name in ['alpha', 'kappa']) {
        final refusal = _row(view, name).toggle.refusal;
        expect(refusal, isA<SkillsListNotEditable>(), reason: name);
        expect(
          (refusal as SkillsListNotEditable).source,
          '$_cwd/.codelab/config.yaml',
        );
        expect(_row(view, name).toggle.isAvailable, isFalse);
      }
    });
  });

  group('SETUP-25: тела не попадают в вид', () {
    test('маркер в телах AGENTS.md, SKILL.md и шаблона не виден в '
        'toString() вида и всех строк', () {
      final files = ProjectFiles(
        context: [ContextFile(path: 'pkg/AGENTS.md', content: 'rules $_leak')],
        templates: [
          _template('/repo/pkg/.codelab/prompts/review.md', body: 'Do $_leak'),
        ],
      );
      final skills = SkillFiles(
        skills: [
          _skill('alpha', root: 0, body: 'Secret $_leak'),
          _skill('gamma', root: 3, body: 'Secret $_leak'),
        ],
      );

      final view = _view(
        _config(),
        _extensions(project: PhaseLoaded(files), skills: PhaseLoaded(skills)),
      );

      // Вид не пуст: тест не тавтологичен.
      expect(view.context.files, hasLength(1));
      expect(view.skills.entries, hasLength(2));
      expect(view.templates.entries, hasLength(1));
      final texts = [
        view.toString(),
        view.context.toString(),
        view.skills.toString(),
        view.templates.toString(),
        for (final f in view.context.files) f.toString(),
        for (final e in view.skills.entries) e.toString(),
        for (final e in view.skills.entries) e.root.toString(),
        for (final t in view.templates.entries) t.toString(),
      ];
      for (final text in texts) {
        expect(text, isNot(contains(_leak)));
      }
    });
  });
}

/// Файл шаблона: имя команды — имя файла (D3 `add-agent-project-files`).
MarkdownFile _template(
  String path, {
  ExtensionScope scope = ExtensionScope.project,
  String description = 'A template',
  String? hint,
  String body = 'Run it',
}) => MarkdownFile(
  path: path,
  scope: scope,
  frontmatter: ConfigTree(
    kind: ConfigLayerKind.user,
    source: path,
    values: {'description': description, 'argument-hint': ?hint},
  ),
  body: body,
  bodyLine: 4,
);
