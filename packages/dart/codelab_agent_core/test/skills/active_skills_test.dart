import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
// Функция активных навыков — внутренняя (точка расширения K-06, D10); её
// путь фиксирует этот тест: lib/src/skills/active_skills.dart.
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:codelab_agent_core/src/skills/active_skills.dart';
import 'package:codelab_agent_core/src/skills/skill_block.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart';
import 'skills_support.dart';

/// Активные навыки (agent-skills «Активные навыки», «Повторная
/// активация»; design.md change `add-agent-skills`, D7, D8, D15, D10; решения
/// Q10, Q6; K-06). Сценарии со сжатием — итерация 4 (`4.1`).
///
/// Фиксируемый API (`lib/src/skills/active_skills.dart`): функция
/// `activeSkills(snapshot, catalog, settings)` возвращает список `ActiveSkill`
/// с полями `name` (строка), `full` (булево), `content` (строка); `content` —
/// SHA-256 в виде шестнадцатеричной строки (нижний регистр) от UTF-8 текста
/// содержимого активации. Функция чистая: только журнал, каталог и настройки.
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  String sha(String text) => sha256.convert(utf8.encode(text)).toString();

  SessionSnapshot snapshot(List<String> lines) =>
      parseSessionLines(journal([header(), ...lines]), id: id).snapshot;

  final catalog = parse([
    validSkill('notes', body: 'Plain notes.'),
    validSkill('review', body: r'Review $1 now.'),
    validSkill('other', body: 'Other body.'),
  ]);
  SkillDefinition def(String name) =>
      catalog.skills.firstWhere((s) => s.name == name);

  // Активация инструментом: сообщение модели с вызовом и результат с блоком.
  List<String> toolLoad(String n, String? parent, String name) => [
    answer(
      'a$n',
      parent,
      calls: [
        ('c$n', 'skill', {'name': name}),
      ],
    ),
    toolResult(
      'r$n',
      'a$n',
      callId: 'c$n',
      tool: 'skill',
      text: renderSkillBlock(def(name)),
    ),
  ];

  // Активация командой: сообщение пользователя с полем `command` и настоящим
  // текстом, какой дала бы команда по текущему снимку (D18, Q48 (б)): обёртка
  // `invoked.md` вокруг блока с подставленным телом, затем хвост `ARGUMENTS:`
  // для тела без плейсхолдеров (хвост стоит после блока, D18).
  String invokedText(String name, String args, {SkillCatalog? from}) {
    final skill = (from ?? catalog).skills.firstWhere((s) => s.name == name);
    final usesPlaceholders = skill.body.contains(r'$1');
    final text = usesPlaceholders
        ? substituteArguments(skill.body, args, splitArguments(args))
        : skill.body;
    return Prompts.skillsInvoked.render({
          'name': name,
          'block': renderSkillBlock(skill, body: text),
        }) +
        (!usesPlaceholders && args.isNotEmpty ? '\n\nARGUMENTS: $args' : '');
  }

  String commandLoad(
    String n,
    String? parent,
    String name,
    String args, {
    String? text,
  }) => user(
    'u$n',
    parent,
    text: text ?? invokedText(name, args),
    command: {'source': 'skill', 'name': name, 'args': args},
  );

  List<ActiveSkill> active(List<String> lines) =>
      activeSkills(snapshot(lines), catalog, const SkillsConfig());

  List<String> names(List<ActiveSkill> list) => [for (final s in list) s.name];

  test('an empty journal: no active skills', () {
    expect(active([]), isEmpty);
    expect(active([user('u1', null)]), isEmpty);
  });

  group('activation by the tool skill (D15, step 3)', () {
    test('a successful result with the block: full, content is the SHA-256 '
        'of the truncated body of the catalog', () {
      final list = active([user('u1', null), ...toolLoad('1', 'u1', 'notes')]);

      expect(list, hasLength(1));
      expect(list.single.name, 'notes');
      expect(list.single.full, isTrue);
      expect(list.single.content, sha('Plain notes.'));
      expect(list.single.content, sha(def('notes').body));
    });

    test('a failed result (isError) is not an activation', () {
      final list = active([
        user('u1', null),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'skill', {'name': 'notes'}),
          ],
        ),
        toolResult(
          'r1',
          'a1',
          callId: 'c1',
          tool: 'skill',
          isError: true,
          outcome: 'failed',
          text: renderSkillBlock(def('notes')),
        ),
      ]);

      expect(list, isEmpty);
    });

    test('the repeat mark is not an activation: it does not raise the skill '
        'and does not change content (scenario "Модель загружает навык '
        'дважды", D7)', () {
      final list = active([
        user('u1', null),
        ...toolLoad('1', 'u1', 'notes'),
        ...toolLoad('2', 'r1', 'other'),
        answer(
          'a3',
          'r2',
          calls: [
            ('c3', 'skill', {'name': 'notes'}),
          ],
        ),
        toolResult(
          'r3',
          'a3',
          callId: 'c3',
          tool: 'skill',
          text:
              'Skill "notes" is already loaded in this conversation; '
              'follow the instructions above.',
        ),
      ]);

      expect(names(list), ['other', 'notes']);
      expect(list.last.content, sha('Plain notes.'));
    });

    test('reading SKILL.md with the read tool is not an activation (D7)', () {
      final list = active([
        user('u1', null),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'read', {'path': '${def('notes').dir}/SKILL.md'}),
          ],
        ),
        toolResult(
          'r1',
          'a1',
          callId: 'c1',
          tool: 'read',
          text: '---\nname: notes\n---\nPlain notes.',
        ),
      ]);

      expect(list, isEmpty);
    });
  });

  group('activation by the command /skill: (D8, D15)', () {
    test('a message with command.source == skill: full, content is the '
        'SHA-256 of the body after substitution of command.args', () {
      final list = active([commandLoad('1', null, 'review', 'lib/x')]);

      expect(list.single.name, 'review');
      expect(list.single.full, isTrue);
      expect(list.single.content, sha('Review lib/x now.'));
    });

    test('the tail ARGUMENTS: is not in the content: a body without '
        'placeholders hashes like the tool activation', () {
      final byCommand = active([commandLoad('1', null, 'notes', 'draft')]);
      final byTool = active([
        user('u1', null),
        ...toolLoad('1', 'u1', 'notes'),
      ]);

      expect(byCommand.single.content, byTool.single.content);
      expect(byCommand.single.content, sha('Plain notes.'));
    });

    test('different arguments of a body with placeholders give different '
        'content', () {
      final a = active([commandLoad('1', null, 'review', 'v1.2')]);
      final b = active([commandLoad('1', null, 'review', 'v1.3')]);

      expect(a.single.content, isNot(b.single.content));
      expect(b.single.content, sha('Review v1.3 now.'));
    });

    test('a user message with another source or without command is not an '
        'activation', () {
      final list = active([
        user(
          'u1',
          null,
          command: {'source': 'template', 'name': 'notes', 'args': ''},
        ),
        user(
          'u2',
          'u1',
          command: {'source': 'plugin', 'name': 'notes', 'args': ''},
        ),
        user('u3', 'u2', text: '/skill:notes'),
      ]);

      expect(list, isEmpty);
    });
  });

  group('the order and replacement (D15, steps 3 and 4)', () {
    test('from a new activation to an old one', () {
      final list = active([
        user('u1', null),
        ...toolLoad('1', 'u1', 'notes'),
        commandLoad('2', 'r1', 'review', 'x'),
        ...toolLoad('3', 'u2', 'other'),
      ]);

      expect(names(list), ['other', 'review', 'notes']);
    });

    test('a newer record about a skill replaces the older one: one entry, '
        'at the front, with the new content', () {
      final list = active([
        commandLoad('1', null, 'review', 'v1.2'),
        ...toolLoad('2', 'u1', 'notes'),
        commandLoad('3', 'r2', 'review', 'v1.3'),
      ]);

      expect(names(list), ['review', 'notes']);
      expect(list.first.content, sha('Review v1.3 now.'));
    });

    test('a model-loaded skill and then the command: content of the '
        'latest activation wins', () {
      final list = active([
        user('u1', null),
        ...toolLoad('1', 'u1', 'review'),
        commandLoad('2', 'r1', 'review', 'v1.2'),
      ]);

      expect(list.single.content, sha('Review v1.2 now.'));
      // До команды содержимое было необработанным телом.
      expect(sha(def('review').body), isNot(list.single.content));
    });
  });

  group('the active branch only', () {
    test('an activation on an abandoned branch does not count', () {
      final list = active([
        user('u1', null),
        ...toolLoad('1', 'u1', 'notes'),
        // Новая ветка от u1: активный лист — на ней, активации notes нет.
        user('u2', 'u1', text: 'another branch'),
      ]);

      expect(list, isEmpty);
    });

    test('a leaf record switches the active branch', () {
      final lines = [
        user('u1', null),
        ...toolLoad('1', 'u1', 'notes'),
        user('u2', 'u1', text: 'another branch'),
      ];

      final onOld = active([...lines, leaf('l1', 'u2', target: 'r1')]);

      expect(names(onOld), ['notes']);
    });
  });

  group('the repeat message is not an activation (D18)', () {
    const repeat =
        'The user invoked the skill "notes" again; its instructions are '
        'already loaded above.';

    test('it neither raises the skill nor changes content', () {
      final list = active([
        commandLoad('1', null, 'notes', ''),
        commandLoad('2', 'u1', 'other', ''),
        commandLoad(
          '3',
          'u2',
          'notes',
          'draft',
          text: '$repeat\n\nARGUMENTS: draft',
        ),
      ]);

      expect(names(list), ['other', 'notes']);
    });

    test('a repeat message alone does not activate the skill', () {
      final list = active([commandLoad('1', null, 'notes', '', text: repeat)]);

      expect(list, isEmpty);
    });
  });

  group('the text must match the current snapshot (Q48 (б), D18)', () {
    // Каталог после правки SKILL.md между сессиями: журнал помнит прежнее тело.
    final old = parse([
      validSkill('notes', body: 'Old notes.'),
      validSkill('review', body: r'Old review $1.'),
    ]);

    test('a tool result with an outdated block is not an activation', () {
      final list = active([
        user('u1', null),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'skill', {'name': 'notes'}),
          ],
        ),
        toolResult(
          'r1',
          'a1',
          callId: 'c1',
          tool: 'skill',
          text: renderSkillBlock(
            old.skills.firstWhere((s) => s.name == 'notes'),
          ),
        ),
      ]);

      expect(list, isEmpty);
    });

    test('a command message with an outdated body is not an activation', () {
      final list = active([
        commandLoad(
          '1',
          null,
          'review',
          'v1',
          text: invokedText('review', 'v1', from: old),
        ),
      ]);

      expect(list, isEmpty);
    });

    test(
      'a changed dir in the block is not a match either (the safe side)',
      () {
        final moved = parse([
          validSkill('notes', body: 'Plain notes.', root: '/elsewhere/skills'),
        ]);
        final list = active([
          user('u1', null),
          answer(
            'a1',
            'u1',
            calls: [
              ('c1', 'skill', {'name': 'notes'}),
            ],
          ),
          toolResult(
            'r1',
            'a1',
            callId: 'c1',
            tool: 'skill',
            text: renderSkillBlock(moved.skills.single),
          ),
        ]);

        expect(list, isEmpty);
      },
    );

    test('an outdated record does not hide an older matching one', () {
      final list = active([
        commandLoad('1', null, 'review', 'v1'),
        commandLoad(
          '2',
          'u1',
          'review',
          'v2',
          text: invokedText('review', 'v2', from: old),
        ),
      ]);

      expect(names(list), ['review']);
      expect(list.single.content, sha('Review v1 now.'));
    });
  });

  group('a skill outside the catalog is skipped (D18)', () {
    final ghosts = parse([validSkill('ghost', body: 'Ghost.')]);

    test('by the tool and by the command', () {
      final list = active([
        user(
          'u1',
          null,
          text: invokedText('ghost', '', from: ghosts),
          command: {'source': 'skill', 'name': 'ghost', 'args': ''},
        ),
        answer(
          'a2',
          'u1',
          calls: [
            ('c2', 'skill', {'name': 'ghost'}),
          ],
        ),
        toolResult(
          'r2',
          'a2',
          callId: 'c2',
          tool: 'skill',
          text: renderSkillBlock(ghosts.skills.single),
        ),
        ...toolLoad('3', 'r2', 'notes'),
      ]);

      expect(names(list), ['notes']);
    });

    test('a non-string name argument is skipped', () {
      final list = active([
        user('u1', null),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'skill', {'name': 7}),
          ],
        ),
        toolResult(
          'r1',
          'a1',
          callId: 'c1',
          tool: 'skill',
          text: renderSkillBlock(def('notes')),
        ),
      ]);

      expect(list, isEmpty);
    });
  });

  group('purity (K-06)', () {
    test('the same input gives the same result and does not change the '
        'snapshot', () {
      final s = snapshot([
        user('u1', null),
        ...toolLoad('1', 'u1', 'notes'),
        commandLoad('2', 'r1', 'review', 'x'),
      ]);
      final before = s.records.length;

      final first = activeSkills(s, catalog, const SkillsConfig());
      final second = activeSkills(s, catalog, const SkillsConfig());

      expect(names(first), names(second));
      expect(
        [for (final a in first) a.content],
        [for (final a in second) a.content],
      );
      expect(s.records, hasLength(before));
    });

    test('no new record kinds are required: the journal has messages only', () {
      final s = snapshot([commandLoad('1', null, 'notes', '')]);

      expect(
        activeSkills(s, catalog, const SkillsConfig()).single.name,
        'notes',
      );
    });
  });
}
