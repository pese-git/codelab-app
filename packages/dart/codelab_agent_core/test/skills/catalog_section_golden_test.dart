import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart' show callStep, textStep;
import '../prompts/compose_test.dart' show allTools;
import '../support/package_dir.dart';
import 'skill_session_rig.dart';
import 'skills_support.dart';

/// Инструменты сессии с навыками: к встроенным добавлен `skill` (секция
/// `skills/catalog` объявляет `tools: [skill]`, PR-6).
final toolsWithSkill = {...allTools, 'skill'};

/// Промпт агента `agent-serve`, режим `standard`, с навыками [skills]
/// (`PromptInputs.skills` — навыки `modelVisible` снимка).
PromptInputs inputsWith(
  List<SkillDefinition> skills, {
  int? catalogMaxChars,
  Set<String>? tools,
  HostProfile? profile,
}) => PromptInputs(
  cwd: '/proj',
  platform: 'linux',
  today: DateTime.utc(2026, 1, 15, 23, 59),
  mode: ModeId.standard,
  profile: profile ?? HostProfile.of('agent-serve'),
  toolNames: tools ?? toolsWithSkill,
  skills: skills,
  skillsCatalogMaxChars: catalogMaxChars ?? 8000,
);

List<SkillDefinition> visible(
  Map<String, String> descriptions, {
  String body = 'Do it.',
}) => parse([
  for (final MapEntry(:key, :value) in descriptions.entries)
    validSkill(key, extra: {'description': value}, body: body),
]).modelVisible;

/// Строки каталога `- <name>: …` из текста промпта (без прозы секции).
///
/// Проза `skills/catalog.md` не должна содержать маркированных строк вида
/// `- слово: …` или `- слово`: тест отличает записи каталога по этой форме.
List<String> entryLines(String prompt) => [
  for (final line in prompt.split('\n'))
    if (RegExp(r'^- [A-Za-z0-9_-]+(: |$)').hasMatch(line) &&
        !line.contains('prefix mcp__') &&
        !line.contains(' tools, '))
      line,
];

final markerLine = RegExp(
  r'^\[(\d+) more skills not listed\]$',
  multiLine: true,
);

/// Каталог навыков в системном промпте (agent-skills «Секция каталога в
/// системном промпте», все сценарии; agent-prompts «Детерминированная сборка
/// системного промпта»; design.md change `add-agent-skills`, D6; решение
/// Q18; SKL-4, SKL-5, PR-3, PR-6).
///
/// Фиксируемый API: `PromptInputs` получает именованные параметры `skills`
/// (список `SkillDefinition`, навыки `modelVisible` снимка, по умолчанию
/// пуст) и `skillsCatalogMaxChars` (`int`, `skills.catalog_max_chars`, по
/// умолчанию 8000); шаг 9a `composeSystemPrompt`; id секции
/// `skills.catalog`. Лог `skills.catalog.truncated` пишет рантайм один раз на
/// сессию при её открытии (секция одинакова на каждом шаге, SKL-4) —
/// проверяется сквозь `SkillSessionRig`.
void main() {
  final update = Platform.environment['UPDATE_GOLDEN'] == '1';

  group('golden', () {
    test('scenario "Golden секции": two skills, after mcp and before '
        'project_context', () {
      final text = composeSystemPrompt(
        inputsWith(
          visible({
            'release-notes': 'Writes release notes from merged pull requests.',
            'flutter-golden': 'Updates golden images of Flutter widget tests.',
          }),
        ),
      );

      // Образец получения: после задачи 2.2
      //   UPDATE_GOLDEN=1 fvm dart test test/skills/catalog_section_golden_test.dart
      // и просмотр diff файла глазами: golden не создаётся вслепую.
      final file = File(
        corePath('test/prompts/golden/agent-serve-standard-skills.txt'),
      );
      if (update) {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      }
      expect(file.existsSync(), isTrue, reason: 'запустите с UPDATE_GOLDEN=1');
      expect(text, file.readAsStringSync());
    });

    test('the section starts with "## Skills" and has no available_skills '
        'wrapper (D17)', () {
      final text = composeSystemPrompt(inputsWith(visible({'a': 'x.'})));

      expect(text, contains('\n## Skills\n'));
      expect(text, isNot(contains('available_skills')));
    });

    test(
      'the lines go by name, one per skill, as "- <name>: <description>"',
      () {
        final text = composeSystemPrompt(
          inputsWith(
            visible({
              'release-notes': 'Writes release notes.',
              'flutter-golden': 'Updates golden images.',
            }),
          ),
        );

        expect(entryLines(text), [
          '- flutter-golden: Updates golden images.',
          '- release-notes: Writes release notes.',
        ]);
      },
    );
  });

  group('descriptions', () {
    test('scenario "Описание целиком": 900 characters stay whole, no '
        'warning', () async {
      final description = 'd' * 900;
      final text = composeSystemPrompt(
        inputsWith(visible({'one': description})),
      );

      expect(entryLines(text), ['- one: $description']);
      expect(entryLines(text).any((l) => l.contains('…')), isFalse);
      expect(markerLine.hasMatch(text), isFalse);
    });

    test('a description longer than 1024 is cut to 1024 characters and "…" '
        'even when the budget allows more', () {
      final long = 'a' * 1500;
      final text = composeSystemPrompt(
        inputsWith(visible({'one': long}), catalogMaxChars: 100000),
      );

      expect(entryLines(text), ['- one: ${'a' * 1024}…']);
    });

    test('a description of exactly 1024 characters is whole', () {
      final exact = 'b' * 1024;
      final text = composeSystemPrompt(
        inputsWith(visible({'one': exact}), catalogMaxChars: 100000),
      );

      expect(entryLines(text), ['- one: $exact']);
    });
  });

  group('the budget (Q18)', () {
    test('scenario "Описания делятся поровну": equal shares of the rest, '
        'the short one is whole', () {
      final descriptions = {
        for (var i = 0; i < 40; i++)
          'long-${i.toString().padLeft(2, '0')}': 'x' * 1000,
        'short': 's' * 50,
      };
      final text = composeSystemPrompt(inputsWith(visible(descriptions)));

      final lines = entryLines(text);
      expect(lines, hasLength(41));
      final total = lines.fold<int>(0, (sum, l) => sum + l.length + 1);
      expect(total, lessThanOrEqualTo(8000));
      expect(
        lines.singleWhere((l) => l.startsWith('- short: ')),
        '- short: ${'s' * 50}',
      );
      final longs = [
        for (final l in lines)
          if (l.startsWith('- long-')) l.substring(l.indexOf(': ') + 2),
      ];
      expect(longs, hasLength(40));
      expect(
        {for (final d in longs) d.length},
        hasLength(1),
        reason: 'одинаковая доля у всех длинных',
      );
      expect(longs.every((d) => d.endsWith('…')), isTrue);
      expect(longs.first.length, allOf(lessThan(1000), greaterThan(100)));
      expect(markerLine.hasMatch(text), isFalse);
    });

    test('a medium description under the share stays whole while the long '
        'ones are cut to one length', () {
      final text = composeSystemPrompt(
        inputsWith(
          visible({
            'a-medium': 'm' * 120,
            'b-long': 'x' * 1000,
            'c-long': 'y' * 1000,
          }),
          catalogMaxChars: 700,
        ),
      );

      final lines = entryLines(text);
      expect(lines[0], '- a-medium: ${'m' * 120}');
      expect(lines[1].length, lines[2].length);
      expect(lines[1], endsWith('…'));
      expect(
        lines.fold<int>(0, (s, l) => s + l.length + 1),
        lessThanOrEqualTo(700),
      );
    });

    test('when even names do not fit, lines are removed from the end and the '
        'last line counts them', () {
      final names = [for (var i = 0; i < 10; i++) 'skill-0$i'];
      final text = composeSystemPrompt(
        inputsWith(
          visible({for (final n in names) n: 'About $n.'}),
          catalogMaxChars: 60,
        ),
      );

      final lines = entryLines(text);
      expect(lines, isNotEmpty);
      expect(lines.length, lessThan(10));
      // Остались первые по имени, порядок сохранён.
      for (final (i, line) in lines.indexed) {
        expect(line, startsWith('- ${names[i]}'));
      }
      expect(
        lines.fold<int>(0, (s, l) => s + l.length + 1),
        lessThanOrEqualTo(60),
      );
      final marker = markerLine.allMatches(text).single;
      // A3: строка об опущенных с переводом входит в бюджет.
      expect(
        lines.fold<int>(0, (s, l) => s + l.length + 1) + marker[0]!.length + 1,
        lessThanOrEqualTo(60),
      );
      expect(int.parse(marker[1]!), 10 - lines.length);
      expect(text.indexOf(marker[0]!), greaterThan(text.indexOf(lines.last)));
    });

    test('a catalog that fits has neither shortening nor marker', () {
      final text = composeSystemPrompt(
        inputsWith(visible({'a': 'one.', 'b': 'two.'})),
      );

      expect(entryLines(text), ['- a: one.', '- b: two.']);
      expect(entryLines(text).any((l) => l.contains('…')), isFalse);
      expect(markerLine.hasMatch(text), isFalse);
    });
  });

  group('the log skills.catalog.truncated (runtime)', () {
    Future<SkillSessionRig> open(Map<String, String> descriptions) async {
      final rig = SkillSessionRig(
        steps: [
          callStep('c1', 'skill', {'name': 'a'}),
          textStep('ok'),
        ],
      );
      rig.port.files = SkillFiles(
        skills: [
          for (final MapEntry(:key, :value) in descriptions.entries)
            validSkill(key, extra: {'description': value}),
        ],
      );
      await rig.open();
      return rig;
    }

    test('scenario "Описания делятся поровну": one warning for the session, '
        'not one per step', () async {
      final rig = await open({
        for (var i = 0; i < 40; i++)
          'long-${i.toString().padLeft(2, '0')}': 'x' * 1000,
        'a': 's' * 50,
      });

      await rig.run();

      expect(rig.contexts, hasLength(2));
      final log = rig.logger.eventsOf('skills.catalog.truncated').single;
      expect(log.level, LogLevel.warning);
      expect(log.fields['session_id'], rig.session.id.value);
      expect(log.fields['shortened'], 40);
      expect(log.fields['omitted'], 0);
      expect(rig.contexts[0].systemPrompt, rig.contexts[1].systemPrompt);
    });

    test('A4: session/load logs it once more for the loaded session, and '
        'a mode change does not log', () async {
      final rig = await open({
        for (var i = 0; i < 40; i++)
          'long-${i.toString().padLeft(2, '0')}': 'x' * 1000,
        'a': 's' * 50,
      });
      await rig.run();
      expect(rig.logger.eventsOf('skills.catalog.truncated'), hasLength(1));

      await rig.core.runtime.loadSession(
        rig.session.id,
        const SessionHostPorts(),
        cwd: '/work/a',
      );

      final logs = rig.logger.eventsOf('skills.catalog.truncated');
      expect(logs, hasLength(2));
      expect(logs.last.fields['session_id'], rig.session.id.value);
    });

    test('no truncation: no log', () async {
      final rig = await open({'a': 'short.'});

      await rig.run();

      expect(rig.logger.eventsOf('skills.catalog.truncated'), isEmpty);
    });
  });

  group('stability (SKL-4, PR-3)', () {
    test('the same snapshot gives the same bytes; no paths, dates or counts '
        'in the section', () {
      final skills = visible({'a-skill': 'Does a.', 'b-skill': 'Does b.'});

      final first = composeSystemPrompt(inputsWith(skills));
      final second = composeSystemPrompt(inputsWith(skills));

      expect(first, second);
      for (final skill in skills) {
        expect(first, isNot(contains(skill.dir)));
      }
      expect(first, isNot(contains('SKILL.md')));
    });

    test('the order of the input does not matter: the lines go by name', () {
      final forward = visible({'a': 'x.', 'b': 'y.'});

      expect(
        composeSystemPrompt(inputsWith(forward.reversed.toList())),
        composeSystemPrompt(inputsWith(forward)),
      );
    });
  });

  group('without a section', () {
    test('scenario "Навык только для команды": skills are not in the '
        'prompt', () {
      final catalog = parse([
        validSkill('only-command', extra: {'disable-model-invocation': true}),
      ]);

      final text = composeSystemPrompt(inputsWith(catalog.modelVisible));

      expect(catalog.skills, hasLength(1));
      expect(
        systemPromptSections(inputsWith(catalog.modelVisible)),
        isNot(contains('skills.catalog')),
      );
      expect(text, isNot(contains('only-command')));
    });

    test('a profile with skills off: no section even with skills', () {
      final profile = HostProfile.of(
        'agent-serve',
      ).narrowed({HostCapability.skills: const CapabilityOff('test')});

      final text = composeSystemPrompt(
        inputsWith(visible({'a': 'x.'}), profile: profile),
      );

      expect(text, isNot(contains('- a: x.')));
      expect(
        systemPromptSections(
          inputsWith(visible({'a': 'x.'}), profile: profile),
        ),
        isNot(contains('skills.catalog')),
      );
    });

    test('no skill tool among the tools: no section (PR-6)', () {
      final text = composeSystemPrompt(
        inputsWith(visible({'a': 'x.'}), tools: allTools),
      );

      expect(text, isNot(contains('- a: x.')));
    });
  });
}
