import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/skills/active_skills.dart';
import 'package:codelab_agent_core/src/skills/skill_block.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart' as j;
import '../skills/skills_support.dart';

/// `activeSkills` после сжатия — шаг 2 D15 (`carried`): задачи 4.1 и 4.2
/// change `add-agent-skills` (agent-skills «Активные навыки», сценарии
/// «Активация ушла в резюме и приложена», «Приложен усечённым»; D15, D18,
/// D20; решение Q6).
///
/// Тесты используют сигнатуру `activeSkills(snapshot, catalog, settings)` и
/// поле `skills` записи `compaction`, записанное вручную, то есть проверяют
/// функцию отдельно от `compact`: перенос читает `last.skills` и применяет
/// бюджеты `settings` тем же расчётом, что и проекция (`reattachSkills`).
///
/// Правила: `carried` = записи `last.skills`, приложенные целиком
/// (`full: true`, `content` — SHA-256 текущего тела снимка) или усечённые
/// по `reattachPerSkillTokens` (`full: false`); выпавшие по общему бюджету
/// `reattachTotalTokens` и отсутствующие в каталоге не входят; `0` в любом
/// из двух ключей — ничего; активации в хвосте после `firstKeptId`
/// (`full: true`) идут раньше `carried`, а повтора имён нет.
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  String sha(String text) => sha256.convert(utf8.encode(text)).toString();

  String rows(int count) => [
    for (var i = 0; i < count; i++)
      'row ${i.toString().padLeft(4, '0')} ${'-' * 31}',
  ].join('\n');

  final catalog = parse([
    validSkill('notes', body: 'Plain notes.'),
    validSkill('other', body: 'Other body.'),
    validSkill('big', body: rows(1000)),
    validSkill('alpha', body: rows(1000)),
    validSkill('bravo', body: rows(1000)),
    validSkill('charlie', body: rows(1000)),
  ]);
  SkillDefinition def(String name) => catalog.skill(name)!;

  /// Журнал: слова, ответ, слова (хвост), ответ, запись сжатия с [skills]
  /// и [tail] — записи после неё (родитель первой — `k1`).
  SessionSnapshot snapshot(
    List<(String, String)> skills, {
    List<String> Function(String parent)? tail,
  }) {
    final line =
        jsonDecode(j.compaction('k1', 'a2', firstKept: 'u2'))
            as Map<String, Object?>;
    line['skills'] = [
      for (final (name, fingerprint) in skills)
        {'name': name, 'fingerprint': fingerprint},
    ];
    return parseSessionLines(
      j.journal([
        j.header(),
        j.user('u1', null),
        j.answer('a1', 'u1'),
        j.user('u2', 'a1'),
        j.answer('a2', 'u2'),
        jsonEncode(line),
        ...?tail?.call('k1'),
      ]),
      id: id,
    ).snapshot;
  }

  List<String> toolLoad(String n, String parent, String name) => [
    j.answer(
      'a$n',
      parent,
      calls: [
        ('c$n', 'skill', {'name': name}),
      ],
    ),
    j.toolResult(
      'r$n',
      'a$n',
      callId: 'c$n',
      tool: 'skill',
      text: renderSkillBlock(def(name)),
    ),
  ];

  List<ActiveSkill> active(
    List<(String, String)> skills, {
    SkillsConfig config = const SkillsConfig(),
    List<String> Function(String parent)? tail,
    SkillCatalog? from,
  }) => activeSkills(snapshot(skills, tail: tail), from ?? catalog, config);

  List<String> names(List<ActiveSkill> list) => [for (final s in list) s.name];

  group('carried: the skills attached after the compaction (D15, step 2)', () {
    test('attached whole: full true, content is the SHA-256 of the body of '
        'the catalog (scenario "Активация ушла в резюме и приложена")', () {
      final list = active([('notes', sha(def('notes').body))]);

      expect(list, hasLength(1));
      expect(list.single.name, 'notes');
      expect(list.single.full, isTrue);
      expect(list.single.content, sha('Plain notes.'));
    });

    test('attached truncated by the per-skill budget: full false '
        '(scenario "Приложен усечённым")', () {
      final list = active([
        ('big', sha(def('big').body)),
      ], config: const SkillsConfig(reattachPerSkillTokens: 100));

      expect(names(list), ['big']);
      expect(list.single.full, isFalse);
      // content — SHA-256 текущего тела и при усечении (D20).
      expect(list.single.content, sha(def('big').body));
    });

    test('a body within the per-skill budget stays full', () {
      final list = active([
        ('big', sha(def('big').body)),
      ], config: const SkillsConfig(reattachPerSkillTokens: 16384));

      expect(list.single.full, isTrue);
    });

    test('the order of the record is kept', () {
      final list = active([
        ('other', sha(def('other').body)),
        ('notes', sha(def('notes').body)),
      ]);

      expect(names(list), ['other', 'notes']);
    });

    test('a skill missing from the catalog is not carried', () {
      final list = active([
        ('gone', sha('Gone.')),
        ('notes', sha(def('notes').body)),
      ]);

      expect(names(list), ['notes']);
    });

    test('a changed fingerprint: the current body is attached, so full '
        'and the content of the current body', () {
      final list = active([('notes', sha('Older notes.'))]);

      expect(list.single.full, isTrue);
      expect(list.single.content, sha(def('notes').body));
    });

    test('over the total budget the oldest drop and are not active '
        '(scenario "Выпавший навык не возвращается сам")', () {
      final list = active(
        [
          ('charlie', sha(def('charlie').body)),
          ('bravo', sha(def('bravo').body)),
          ('alpha', sha(def('alpha').body)),
        ],
        config: const SkillsConfig(
          reattachPerSkillTokens: 16384,
          reattachTotalTokens: 25000,
        ),
      );

      expect(names(list), ['charlie', 'bravo']);
      expect(list.every((s) => s.full), isTrue);
    });

    // СТРАЖ: зелёный и до 4.2 (ничего не переносится), после неё нельзя сломать.
    test('0 in either key: nothing is carried', () {
      final skills = [('notes', sha(def('notes').body))];

      expect(
        active(skills, config: const SkillsConfig(reattachPerSkillTokens: 0)),
        isEmpty,
      );
      expect(
        active(skills, config: const SkillsConfig(reattachTotalTokens: 0)),
        isEmpty,
      );
    });
  });

  group('the tail and carried together (D15, steps 3 and 4)', () {
    test('an activation in the tail goes first and is full; carried skills '
        'follow', () {
      final list = active(
        [('notes', sha(def('notes').body))],
        tail: (parent) => [
          j.user('u3', parent),
          ...toolLoad('9', 'u3', 'other'),
        ],
      );

      expect(names(list), ['other', 'notes']);
      expect(list.map((s) => s.full), [true, true]);
    });

    test('a carried skill activated again in the tail: once, at the front', () {
      final list = active(
        [('other', sha(def('other').body)), ('notes', sha(def('notes').body))],
        tail: (parent) => [
          j.user('u3', parent),
          ...toolLoad('9', 'u3', 'notes'),
        ],
      );

      expect(names(list), ['notes', 'other']);
    });

    test('a truncated skill activated again in the tail becomes full: the '
        'new activation replaces the old record', () {
      final list = active(
        [('big', sha(def('big').body))],
        config: const SkillsConfig(reattachPerSkillTokens: 100),
        tail: (parent) => [j.user('u3', parent), ...toolLoad('9', 'u3', 'big')],
      );

      expect(names(list), ['big']);
      expect(list.single.full, isTrue);
      expect(list.single.content, sha(def('big').body));
    });
  });

  test('purity: the same inputs, the same result; the snapshot is not '
      'changed', () {
    final snap = snapshot([('notes', sha(def('notes').body))]);

    final first = activeSkills(snap, catalog, const SkillsConfig());
    final second = activeSkills(snap, catalog, const SkillsConfig());

    expect(
      [for (final s in first) (s.name, s.full, s.content)],
      [for (final s in second) (s.name, s.full, s.content)],
    );
    expect(first, isNotEmpty);
    expect(snap.records, hasLength(5));
  });
}
