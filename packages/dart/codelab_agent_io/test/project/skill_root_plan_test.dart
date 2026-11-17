import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/src/project/skill_roots.dart';
import 'package:test/test.dart';

/// `skillRootPlan`: один план корней навыков для загрузчика и для страницы
/// навыков (design.md change `add-app-skills-page`, D3; ревью итерации 1,
/// находка MAJOR «один план корней»).
///
/// Почему: `ProjectFilesLoader` читает корни, а `loadProjectExtensions` их
/// показывает; если список строится в двух местах, номер `rootIndex` навыка
/// указывает на чужой корень. Здесь проверяется чистая функция и то, что
/// загрузчик действительно обходит её план, в тех режимах, где расхождение
/// было возможно: недоверенный проект с `~`-элементом и пустой
/// `CODELAB_HOME`.
void main() {
  group('skillRootPlan', () {
    test('a trusted project: levels near-to-far, then home, ~/.agents, then '
        'extra_roots as written; areas bound the expansion', () {
      final plan = skillRootPlan(
        levels: const ['/repo', '/repo/pkg'],
        cwd: '/repo/pkg',
        trusted: true,
        home: '/h',
        userHome: '/u',
        extraRoots: const ['.claude/skills', '~/s', '/abs'],
      );

      expect(
        [for (final r in plan.roots) (r.scope, r.path, r.area, r.extraRoot)],
        [
          (
            ExtensionScope.project,
            '/repo/pkg/.codelab/skills',
            '/repo/pkg',
            null,
          ),
          (
            ExtensionScope.project,
            '/repo/pkg/.agents/skills',
            '/repo/pkg',
            null,
          ),
          (ExtensionScope.project, '/repo/.codelab/skills', '/repo', null),
          (ExtensionScope.project, '/repo/.agents/skills', '/repo', null),
          (ExtensionScope.user, '/h/skills', '/h', null),
          (ExtensionScope.user, '/u/.agents/skills', null, null),
          (
            ExtensionScope.extra,
            '/repo/pkg/.claude/skills',
            null,
            '.claude/skills',
          ),
          (ExtensionScope.extra, '/u/s', null, '~/s'),
          (ExtensionScope.extra, '/abs', null, '/abs'),
        ],
      );
      expect(plan.skipped, isEmpty);
    });

    test('an untrusted project: project levels and a relative extra root '
        'are skipped with a reason, a ~ element is a root', () {
      final plan = skillRootPlan(
        levels: const ['/repo/pkg'],
        cwd: '/repo/pkg',
        trusted: false,
        home: '/h',
        userHome: '/u',
        extraRoots: const ['.claude/skills', '~/s'],
      );

      expect(
        [for (final r in plan.roots) r.path],
        ['/h/skills', '/u/.agents/skills', '/u/s'],
      );
      expect(
        [for (final s in plan.skipped) (s.path, s.reason)],
        [
          (
            '/repo/pkg/.codelab/skills',
            SkippedSkillRootReason.untrustedProject,
          ),
          ('/repo/pkg/.agents/skills', SkippedSkillRootReason.untrustedProject),
          (
            '/repo/pkg/.claude/skills',
            SkippedSkillRootReason.untrustedRelativeExtra,
          ),
        ],
      );
    });

    test('an empty CODELAB_HOME or HOME is "no area", not the root of the '
        'disk (priority 1); a ~ element without HOME is skipped', () {
      final plan = skillRootPlan(
        levels: const ['/p'],
        cwd: '/p',
        trusted: true,
        home: '',
        userHome: '',
        extraRoots: const ['~/s'],
      );

      expect(
        [for (final r in plan.roots) r.path],
        ['/p/.codelab/skills', '/p/.agents/skills'],
      );
      expect(
        [for (final s in plan.skipped) (s.path, s.reason)],
        [('~/s', SkippedSkillRootReason.unresolvedHome)],
      );
    });

    test('~user and scheme elements are neither roots nor skipped (Q41)', () {
      final plan = skillRootPlan(
        levels: const ['/p'],
        cwd: '/p',
        trusted: true,
        home: null,
        userHome: '/u',
        extraRoots: const ['~bob/s', 'https://x/s'],
      );

      expect(
        plan.roots.map((r) => r.scope),
        everyElement(isNot(ExtensionScope.extra)),
      );
      expect(plan.skipped, isEmpty);
    });
  });

  group('the loader walks the plan: rootIndex points at the planned root', () {
    late Directory tmp;
    late String base;

    void skill(String root, String name) {
      File('$root/$name/SKILL.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('---\nname: $name\ndescription: D\n---\nBody\n');
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('skill_root_plan_');
      base = tmp.resolveSymbolicLinksSync();
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> expectIndexesMatchPlan({
      required String? home,
      required bool trusted,
      required List<String> extraRoots,
      required List<String> expectedNames,
    }) async {
      final cwd = '$base/proj';
      Directory('$cwd/.git').createSync(recursive: true);
      final userHome = '$base/uh';
      final loader = ProjectFilesLoader(
        home: home,
        userHome: userHome,
        local: LocalExecutionEnv(cwd: cwd),
      );
      final files = await loader.loadSkills(
        SkillFilesQuery(
          cwd: cwd,
          projectTrusted: trusted,
          extraRoots: extraRoots,
          cancel: CancelToken.none,
        ),
      );
      final plan = skillRootPlan(
        levels: projectLevels(cwd).levels,
        cwd: cwd,
        trusted: trusted,
        home: home,
        userHome: userHome,
        extraRoots: extraRoots,
      );

      expect(files.skills.map((s) => s.dir.split('/').last), expectedNames);
      for (final s in files.skills) {
        expect(
          s.dir.substring(0, s.dir.lastIndexOf('/')),
          plan.roots[s.rootIndex].path,
          reason: s.dir,
        );
      }
    }

    test('an untrusted project with a ~ element in extra_roots', () async {
      skill('$base/proj/.codelab/skills', 'project-skill');
      skill('$base/uh/.agents/skills', 'u');
      skill('$base/uh/shared', 'x');

      await expectIndexesMatchPlan(
        home: '$base/home',
        trusted: false,
        extraRoots: const ['.claude/skills', '~/shared'],
        expectedNames: ['u', 'x'],
      );
    });

    test('an empty CODELAB_HOME: no user root, indexes still match', () async {
      skill('$base/proj/.agents/skills', 'p');
      skill('$base/uh/.agents/skills', 'u');

      await expectIndexesMatchPlan(
        home: '',
        trusted: true,
        extraRoots: const [],
        expectedNames: ['p', 'u'],
      );
    });
  });
}
