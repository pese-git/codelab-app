import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../skills/skills_support.dart';
import '../support/project_config_rig.dart';

/// Навыки сессии вне корня запуска (agent-runtime «Конфигурация сессии вне
/// корня запуска», сценарии «Навыки сессии вне корня запуска», «Навыки
/// выключены только в сессиях папки», «Недоверенный проект сессии не
/// расширяет навыки», «Навыки выключены в корне запуска»; design.md change
/// `add-agent-skills`, D11, D16, решения Q40, Q43, Q44, Q45).
///
/// Почему: `skills.*` — настройки папки сессии, а не корня запуска; корни
/// навыков и `projectTrusted` считаются по каноническому cwd сессии. Корень
/// `/A` не должен ни включать, ни выключать навыки сессиям `/B` (Q44, Q45).
void main() {
  late FakeSkillPort port;

  setUp(() => port = FakeSkillPort());

  ProjectConfigRig rig({Map<String, Object?> rootProject = const {}}) =>
      ProjectConfigRig.create(rootProject: rootProject, skillFiles: port);

  /// Пользовательский слой со своими `skills.*`.
  Map<String, Object?> userWith(Map<String, Object?> skills) =>
      norm({...baseUser(), 'skills': skills});

  List<String> names(AgentSession session) => [
    for (final k in session.skills.skills) k.name,
  ];

  List<String?> untrustedKeys(ConfigLoadResult result) => [
    for (final w in result.warnings)
      if (w.event == 'config.project.untrusted_key') w.key,
  ];

  test('scenario "Навыки сессии вне корня запуска" (Q44): extra_roots, '
      'disabled and trust come from the folder of the session, not from the '
      'root /A', () async {
    port.files = SkillFiles(
      skills: [validSkill('a'), validSkill('b'), validSkill('c')],
    );
    // Корень /A отключает `b`; у /B своё `disabled: [a]`.
    final r = rig(
      rootProject: {
        'skills': {
          'disabled': ['b'],
        },
      },
    );
    // `extra_roots` проекта допустимы только из `config.local.yaml`
    // доверенной папки; из `config.yaml` они отбрасываются.
    final folder = folderResult(
      '/B',
      project: {
        'skills': {
          'extra_roots': ['/dropped'],
          'disabled': ['a'],
        },
      },
      local: {
        'skills': {
          'extra_roots': ['/opt/b-skills'],
        },
      },
    );
    r.loader.results['/B'] = () => folder;

    final outside = await r.session('/B');
    final root = await r.session('/A');

    final query = port.queries.first;
    expect(query.cwd, '/B');
    expect(query.projectTrusted, isTrue);
    expect(query.extraRoots, ['/opt/b-skills']);
    expect(names(outside), ['b', 'c']);
    expect(port.queries.last.cwd, '/A');
    expect(names(root), ['a', 'c']);
  });

  test('scenario "Навыки выключены только в сессиях папки": '
      'skills.enabled: false of /B silences /B only, no offReasons and no '
      'process-key warning', () async {
    port.files = SkillFiles(skills: [validSkill('notes')]);
    final r = rig();
    r.loader.results['/B'] = () =>
        folderResult('/B', user: userWith({'enabled': false}));

    final outside = await r.session('/B');
    final queriesAfterB = port.queries.length;
    final root = await r.session('/A');

    expect(queriesAfterB, 0);
    expect(outside.skills, same(SkillCatalog.empty));
    expect(port.queries.single.cwd, '/A');
    expect([for (final k in root.skills.skills) k.name], ['notes']);
    expect(r.core.plan.offReasons, isNot(contains(HostCapability.skills)));
    expect(r.logger.eventsOf('config.session.process_keys_ignored'), isEmpty);
  });

  test(
    'scenario "Недоверенный проект сессии не расширяет навыки" (Q40, '
    'Q43): limits only go down, roots are dropped, bans are merged',
    () async {
      port.files = SkillFiles(
        skills: [
          validSkill('notes'),
          validSkill('pdf'),
          validSkill('x'),
          validSkill('y'),
          validSkill('z'),
        ],
      );
      final r = rig();
      final folder = folderResult(
        '/C',
        user: userWith({
          'max_skills': 2,
          'disabled': ['pdf'],
        }),
        project: {
          'skills': {
            'max_skills': 500,
            'disabled': ['notes'],
          },
        },
        local: {
          'skills': {
            'extra_roots': ['/evil'],
          },
        },
        trusted: false,
      );
      r.loader.results['/C'] = () => folder;

      final session = await r.session('/C');

      final query = port.queries.single;
      expect(query.cwd, '/C');
      expect(query.projectTrusted, isFalse);
      expect(query.extraRoots, isNot(contains('/evil')));
      // Запреты слоёв объединены, предел остался пользовательским.
      expect(names(session), ['x', 'y']);
      expect(
        untrustedKeys(folder),
        containsAll(['skills.max_skills', 'skills.extra_roots']),
      );
    },
  );

  test('Q43: skills.enabled: true of an untrusted project does not undo the '
      'user ban', () async {
    port.files = SkillFiles(skills: [validSkill('notes')]);
    final r = rig();
    final folder = folderResult(
      '/B',
      user: userWith({'enabled': false}),
      project: {
        'skills': {'enabled': true},
      },
      trusted: false,
    );
    r.loader.results['/B'] = () => folder;

    final session = await r.session('/B');

    expect(session.skills, same(SkillCatalog.empty));
    expect(port.queries, isEmpty);
    expect(untrustedKeys(folder), contains('skills.enabled'));
  });

  test('scenario "Навыки выключены в корне запуска" (Q45): false of /A '
      'silences /A sessions, a trusted /B with true gets skills, offReasons '
      'has no skills', () async {
    port.files = SkillFiles(skills: [validSkill('notes')]);
    final r = rig(
      rootProject: {
        'skills': {'enabled': false},
      },
    );
    r.setFolder(
      '/B',
      project: {
        'skills': {'enabled': true},
      },
    );

    final root = await r.session('/A');
    expect(root.skills, same(SkillCatalog.empty));
    expect(port.queries, isEmpty);

    final outside = await r.session('/B');

    expect(port.queries.single.cwd, '/B');
    expect([for (final k in outside.skills.skills) k.name], ['notes']);
    expect(r.core.plan.offReasons, isNot(contains(HostCapability.skills)));
    expect(r.core.plan.profile.isOn(HostCapability.skills), isTrue);
  });
}
