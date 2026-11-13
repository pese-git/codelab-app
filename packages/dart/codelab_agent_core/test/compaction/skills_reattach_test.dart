import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/compactor.dart' as engine;
import 'package:codelab_agent_core/src/compaction/compactor.dart'
    show CompactionOutcome, CompactionTrigger, Compacted;
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/src/session/session_writer.dart';
import 'package:codelab_agent_core/src/session/tree.dart';
import 'package:codelab_agent_core/src/skills/active_skills.dart';
import 'package:codelab_agent_core/src/skills/skill_block.dart';
import 'package:codelab_agent_core/src/skills/skill_invocation.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart' as j;
import '../session/recording_store.dart';
import '../skills/skills_support.dart';
import '../support/models.dart';

/// Навыки после сжатия — красные тесты итерации 4, задача 4.1 (change
/// `add-agent-skills`: agent-compaction «Навыки после сжатия», agent-skills
/// «Активные навыки»; design.md D15, D18 «Сжатие в итерации 3»; решение Q6;
/// CMP-2, CMP-5).
///
/// Фиксируемые сигнатуры (реализует задача 4.2):
/// - запись `compaction` в журнале получает необязательное поле
///   `skills: [{"name": <имя>, "fingerprint": <SHA-256 hex тела снимка>}]`
///   (формат проводной, проверяется по `record.toJson()`; Dart-тип элемента
///   тестами не фиксируется); без активаций поля нет;
/// - `buildLlmContext(snapshot, {logger, SkillCatalog? skillCatalog,
///   SkillsConfig skillsConfig = const SkillsConfig()})`;
/// - `compact(..., SkillCatalog? skillCatalog, SkillsConfig skillsConfig =
///   const SkillsConfig())` — тот же каталог и бюджеты, что у проекции:
///   `tokensAfter` и CMP-5 считаются по проекции с приложенным сообщением;
/// - сообщение после резюме — `UserMessage` с одним `TextContent` по
///   `Prompts.skillsReattached` (переменная `blocks`); в журнал не пишется;
/// - логи `skills.reattached {session_id, names, dropped, truncated}` (info;
///   `names` — список приложенных, `dropped` и `truncated` — числа) пишет
///   `compact`, `skills.reattach.changed {session_id, name}` (warning) —
///   проекция.
///
/// Сценарии `core/skill-reattached-after-compaction` и соседние — прямой API
/// ядра без ACP (как остальные `core/*`: файла фикстуры в
/// `codelab_acp_testing` нет, 14-golden-fixtures §14.9).
///
/// Все тесты файла красные: файл не компилируется, пока у `compact` и
/// `buildLlmContext` нет параметров `skillCatalog`/`skillsConfig`; группы,
/// которые использовали бы только существующий API (`activeSkills`), красны по
/// существу и вынесены в `skills_reattach_active_test.dart`. Стражи — в
/// `skills_reattach_guards_test.dart`.
void main() {
  const sid = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0A');

  // Хвост и резерв как в compactor_test: хвост — последний ход пользователя.
  const settings = CompactionSettings(
    reserveTokens: 2048,
    keepRecentTokens: 2048,
    keepRecentUserTurns: 1,
  );
  // Окно, при котором сжатие не повторяется само: порог далеко от оценки.
  const bigWindow = 100000;
  // Окно, при котором приложенный навык перекрывает порог (CMP-5).
  const smallWindow = 8192;

  String sha(String text) => sha256.convert(utf8.encode(text)).toString();

  /// Тело навыка: [count] строк по 40 символов — длину в токенах считает тест.
  String rows(int count) => [
    for (var i = 0; i < count; i++)
      'row ${i.toString().padLeft(4, '0')} ${'-' * 31}',
  ].join('\n');

  SkillCatalog catalogOf(List<SkillFile> files) => parse(files);

  String textOf(Message message) =>
      message.content.whereType<TextContent>().map((b) => b.text).join();

  String summaryText(String summary) =>
      Prompts.compactionSummaryWrapper.render({'summary': summary});

  String messagesJson(LlmContextProjection p) =>
      jsonEncode([for (final m in p.messages) m.toJson()]);

  group('core/skill-reattached-after-compaction: the record (D15, '
      '"Запись сжатия")', () {
    late _Rig rig;
    setUp(() => rig = _Rig(sid, settings));

    test('a skill loaded by the tool and summarized: the field has the name '
        'and the fingerprint without a body; the next context repeats the '
        'block after the summary', () async {
      final catalog = catalogOf([
        validSkill(
          'release-notes',
          body: 'Write release notes.\nKeep it short.',
        ),
      ]);
      final def = catalog.skills.single;
      final chain = _Chain(catalog)
        ..user(40)
        ..load('release-notes')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);
      LlmContextProjection? rebuilt;

      final out =
          await rig.compact(catalog, bigWindow, onCompacted: (p) => rebuilt = p)
              as Compacted;

      final line = out.record.toJson();
      expect(line['skills'], [
        {'name': 'release-notes', 'fingerprint': sha(def.body)},
      ]);
      // Тело навыка в записи сжатия не дублируется (D15, альтернатива (в)).
      expect(jsonEncode(line), isNot(contains('Write release notes')));
      final context = rig.context(catalog);
      expect(context.messages, hasLength(4));
      expect(textOf(context.messages[0]), summaryText('S'));
      expect(context.messages[1], isA<UserMessage>());
      expect(
        textOf(context.messages[1]),
        Prompts.skillsReattached.render({'blocks': renderSkillBlock(def)}),
      );
      expect(messagesJson(rebuilt!), messagesJson(context));
      // Сообщение производное: в журнал не пишется (CMP-2).
      expect(rig.store.appended.single.record, isA<CompactionRecord>());
      expect(
        rig.store.inner.textOf(sid),
        isNot(contains('instructions are repeated here')),
      );
    });

    test('a command activation: the body is raw (no arguments), the record '
        'has no arguments', () async {
      final catalog = catalogOf([
        validSkill('review', body: r'Review $1 now.'),
      ]);
      final def = catalog.skills.single;
      final chain = _Chain(catalog)
        ..user(40)
        ..invoke('review', 'v1.2')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);

      final out = await rig.compact(catalog, bigWindow) as Compacted;

      expect(out.record.toJson()['skills'], [
        {'name': 'review', 'fingerprint': sha(def.body)},
      ]);
      expect(jsonEncode(out.record.toJson()), isNot(contains('v1.2')));
      final text = textOf(rig.context(catalog).messages[1]);
      // Аргументы относились к запросу, который ушёл в резюме (D15).
      expect(text, contains(r'Review $1 now.'));
      expect(text, isNot(contains('v1.2')));
    });

    test('the order of the record is the order of activeSkills: from the '
        'newest activation to the oldest; the blocks follow it', () async {
      final catalog = catalogOf([
        validSkill('alpha', body: 'Alpha.'),
        validSkill('bravo', body: 'Bravo.'),
        validSkill('charlie', body: 'Charlie.'),
      ]);
      final chain = _Chain(catalog)
        ..user(40)
        ..load('alpha')
        ..load('bravo')
        ..load('charlie')
        ..load('alpha')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);

      final out = await rig.compact(catalog, bigWindow) as Compacted;

      final names = [
        for (final s in out.record.toJson()['skills']! as List<Object?>)
          (s! as Map<String, Object?>)['name'],
      ];
      // Повторная активация alpha поднимает его в начало (D15, шаг 4).
      expect(names, ['alpha', 'charlie', 'bravo']);
      final text = textOf(rig.context(catalog).messages[1]);
      final at = [for (final n in names) text.indexOf('<skill name="$n" ')];
      expect(at, everyElement(greaterThanOrEqualTo(0)));
      expect(at, orderedEquals([...at]..sort()));
    });

    test('no activations: no field, the projection is byte-for-byte the '
        'previous one', () async {
      final catalog = catalogOf([validSkill('alpha', body: 'Alpha.')]);
      final chain = _Chain(catalog)
        ..user(40)
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);

      final out = await rig.compact(catalog, bigWindow) as Compacted;

      expect(out.record.toJson().containsKey('skills'), isFalse);
      final context = rig.context(catalog);
      expect(context.messages, hasLength(3));
      expect(messagesJson(context), messagesJson(rig.context(null)));
      expect(rig.logger.eventsOf('skills.reattached'), isEmpty);
    });

    test('a skill missing from the catalog is not recorded and not '
        'reattached', () async {
      final known = catalogOf([validSkill('alpha', body: 'Alpha.')]);
      final chain = _Chain(known)
        ..user(40)
        ..load('alpha')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);

      // Сессия закрыта и открыта без навыков (сессия загружена без каталога).
      final out = await rig.compact(SkillCatalog.empty, bigWindow) as Compacted;

      expect(out.record.toJson().containsKey('skills'), isFalse);
      expect(rig.context(SkillCatalog.empty).messages, hasLength(3));
    });
  });

  group('core/skill-in-tail-not-duplicated (agent-compaction "Навык в '
      'хвосте не дублируется")', () {
    late _Rig rig;
    setUp(() => rig = _Rig(sid, settings));

    test('activated in the last turn, which stays in the tail: not in the '
        'field, no block after the summary', () async {
      final catalog = catalogOf([validSkill('alpha', body: 'Alpha.')]);
      final chain = _Chain(catalog)
        ..user(40)
        ..say(2000)
        ..user(30)
        ..load('alpha')
        ..say(2500);
      await rig.open(chain.records);

      final out = await rig.compact(catalog, bigWindow) as Compacted;

      expect(out.record.toJson().containsKey('skills'), isFalse);
      final context = rig.context(catalog);
      // Резюме и три записи хвоста: слова, вызов с результатом, ответ.
      expect(context.messages.map((m) => m.runtimeType), [
        UserMessage,
        UserMessage,
        AssistantMessage,
        ToolResultMessage,
        AssistantMessage,
      ]);
      expect(
        context.messages.where((m) => textOf(m).contains('<skill name=')),
        hasLength(1), // только результат в хвосте
      );
    });

    test('activated before and again in the tail: only the tail copy, the '
        'record does not repeat it', () async {
      final catalog = catalogOf([
        validSkill('alpha', body: 'Alpha.'),
        validSkill('bravo', body: 'Bravo.'),
      ]);
      final chain = _Chain(catalog)
        ..user(40)
        ..load('alpha')
        ..load('bravo')
        ..say(2000)
        ..user(30)
        ..load('alpha')
        ..say(2500);
      await rig.open(chain.records);

      final out = await rig.compact(catalog, bigWindow) as Compacted;

      final names = [
        for (final s in out.record.toJson()['skills']! as List<Object?>)
          (s! as Map<String, Object?>)['name'],
      ];
      expect(names, ['bravo']);
      final text = textOf(rig.context(catalog).messages[1]);
      expect(text, contains('<skill name="bravo" '));
      expect(text, isNot(contains('<skill name="alpha" ')));
    });
  });

  group('budgets (D15, "Приложение"; agent-compaction "Общий бюджет")', () {
    /// Снимок с записью сжатия, у которой в `skills` — [skills] как записаны.
    SessionSnapshot snapshotWith(
      List<(String, String)> skills, {
      String summary = 'S',
    }) => _withCompactionSkills(sid, skills, summary: summary);

    test('per-skill: a longer body is cut at the last line boundary with the '
        'tool mark for a modelVisible skill', () {
      final catalog = catalogOf([validSkill('big', body: rows(1000))]);
      final def = catalog.skills.single;
      expect(catalog.modelVisible, contains(def));

      final context = buildLlmContext(
        snapshotWith([('big', sha(def.body))]),
        skillCatalog: catalog,
        skillsConfig: const SkillsConfig(reattachPerSkillTokens: 100),
      );

      final text = textOf(context.messages[1]);
      _expectCutAtLines(
        text,
        maxChars: 100 * 4,
        mark:
            '[skill truncated: load it again with the skill tool for the '
            'full text]',
      );
    });

    test('per-skill: not modelVisible but user-invocable -> the /skill: '
        'mark with the name', () {
      final catalog = catalogOf([
        validSkill(
          'big',
          body: rows(1000),
          extra: {'disable-model-invocation': true},
        ),
      ]);
      final def = catalog.skills.single;
      expect(catalog.modelVisible, isEmpty);
      expect(def.userInvocable, isTrue);

      final context = buildLlmContext(
        snapshotWith([('big', sha(def.body))]),
        skillCatalog: catalog,
        skillsConfig: const SkillsConfig(reattachPerSkillTokens: 100),
      );

      final text = textOf(context.messages[1]);
      _expectCutAtLines(
        text,
        maxChars: 100 * 4,
        mark:
            '[skill truncated: the user can run /skill:big for the full '
            'text]',
      );
      expect(text, isNot(contains('with the skill tool')));
    });

    test('per-skill: neither model-visible nor user-invocable -> the bare '
        'mark, no advice', () {
      final catalog = catalogOf([
        validSkill(
          'big',
          body: rows(1000),
          extra: {'disable-model-invocation': true, 'user-invocable': false},
        ),
      ]);
      final def = catalog.skill('big')!;
      expect(def.userInvocable, isFalse);
      expect(catalog.modelVisible, isEmpty);

      final context = buildLlmContext(
        snapshotWith([('big', sha(def.body))]),
        skillCatalog: catalog,
        skillsConfig: const SkillsConfig(reattachPerSkillTokens: 100),
      );

      final text = textOf(context.messages[1]);
      _expectCutAtLines(text, maxChars: 100 * 4, mark: '[skill truncated]');
      expect(text, isNot(contains('skill truncated:')));
    });

    test('a body within the per-skill budget is attached whole, no mark', () {
      final catalog = catalogOf([validSkill('small', body: rows(5))]);
      final def = catalog.skills.single;

      final context = buildLlmContext(
        snapshotWith([('small', sha(def.body))]),
        skillCatalog: catalog,
        skillsConfig: const SkillsConfig(reattachPerSkillTokens: 100),
      );

      expect(
        textOf(context.messages[1]),
        Prompts.skillsReattached.render({'blocks': renderSkillBlock(def)}),
      );
    });

    test('total: three skills of ~10 000 tokens, 25 000 in total: the two '
        'newest are attached, the oldest drops, the log says dropped: 1 '
        '(scenario "Общий бюджет")', () async {
      final catalog = catalogOf([
        validSkill('alpha', body: rows(1000)),
        validSkill('bravo', body: rows(1000)),
        validSkill('charlie', body: rows(1000)),
      ]);
      const config = SkillsConfig(
        reattachPerSkillTokens: 16384,
        reattachTotalTokens: 25000,
      );
      final rig = _Rig(sid, settings);
      final chain = _Chain(catalog)
        ..user(40)
        ..load('alpha')
        ..load('bravo')
        ..load('charlie')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);

      final out = await rig.compact(catalog, bigWindow, skills: config);

      expect(out, isA<Compacted>());
      final text = textOf(rig.context(catalog, skills: config).messages[1]);
      expect(text, contains('<skill name="charlie" '));
      expect(text, contains('<skill name="bravo" '));
      expect(text, isNot(contains('<skill name="alpha" ')));
      final log = rig.logger.eventsOf('skills.reattached').single;
      expect(log.level, LogLevel.info);
      expect(log.fields['session_id'], sid.value);
      expect(log.fields['names'], ['charlie', 'bravo']);
      expect(log.fields['dropped'], 1);
      expect(log.fields['truncated'], 0);
      // Тела в логе нет (D13).
      expect(jsonEncode(log.fields), isNot(contains('row 0000')));
      // Выпавший навык не активен (agent-skills "Активные навыки").
      expect(
        activeSkills(rig.writer.snapshot, catalog, config).map((s) => s.name),
        ['charlie', 'bravo'],
      );
    });

    test('0 in either key: no message, the context is the previous one', () {
      final catalog = catalogOf([validSkill('alpha', body: 'Alpha.')]);
      final def = catalog.skills.single;
      final snapshot = snapshotWith([('alpha', sha(def.body))]);
      final baseline = messagesJson(buildLlmContext(snapshot));

      for (final config in const [
        SkillsConfig(reattachPerSkillTokens: 0),
        SkillsConfig(reattachTotalTokens: 0),
      ]) {
        final context = buildLlmContext(
          snapshot,
          skillCatalog: catalog,
          skillsConfig: config,
        );
        expect(messagesJson(context), baseline);
        expect(context.messages, hasLength(3));
      }
    });

    test(
      '0 in either key, through compact: the record still has the field '
      '(D20), no message, no skills.reattached log, nothing carried',
      () async {
        final catalog = catalogOf([validSkill('alpha', body: 'Alpha.')]);
        final def = catalog.skills.single;
        for (final config in const [
          SkillsConfig(reattachPerSkillTokens: 0),
          SkillsConfig(reattachTotalTokens: 0),
        ]) {
          final rig = _Rig(sid, settings);
          await rig.open(
            (_Chain(catalog)
                  ..user(40)
                  ..load('alpha')
                  ..say(2000)
                  ..user(30)
                  ..say(2500))
                .records,
          );

          final out =
              await rig.compact(catalog, bigWindow, skills: config)
                  as Compacted;

          // Запись фиксирует, что было активно; бюджеты применяются при
          // приложении (D20, «Запись»).
          expect(out.record.toJson()['skills'], [
            {'name': 'alpha', 'fingerprint': sha(def.body)},
          ]);
          expect(rig.context(catalog, skills: config).messages, hasLength(3));
          expect(rig.logger.eventsOf('skills.reattached'), isEmpty);
          expect(activeSkills(rig.writer.snapshot, catalog, config), isEmpty);
        }
      },
    );

    test('several blocks are joined with a blank line, in the order of the '
        'record (D20, item 5)', () {
      final catalog = catalogOf([
        validSkill('alpha', body: 'Alpha.'),
        validSkill('bravo', body: 'Bravo.'),
      ]);
      final a = catalog.skill('alpha')!;
      final b = catalog.skill('bravo')!;

      final context = buildLlmContext(
        snapshotWith([('bravo', sha(b.body)), ('alpha', sha(a.body))]),
        skillCatalog: catalog,
      );

      expect(
        textOf(context.messages[1]),
        Prompts.skillsReattached.render({
          'blocks': '${renderSkillBlock(b)}\n\n${renderSkillBlock(a)}',
        }),
      );
      expect(context.messages[1].content, hasLength(1));
    });

    test('the per-skill budget counts the body: a body of exactly the budget '
        'is whole although its block is longer (D20, item 3)', () {
      final body = 'x' * 400; // ровно 100 токенов
      final catalog = catalogOf([validSkill('exact', body: body)]);
      final def = catalog.skills.single;

      final context = buildLlmContext(
        snapshotWith([('exact', sha(def.body))]),
        skillCatalog: catalog,
        skillsConfig: const SkillsConfig(reattachPerSkillTokens: 100),
      );

      expect(
        textOf(context.messages[1]),
        Prompts.skillsReattached.render({'blocks': renderSkillBlock(def)}),
      );
      expect(textOf(context.messages[1]), isNot(contains('skill truncated')));
    });

    test('the total budget counts the whole block (body, path line, '
        'files): it fits at the exact estimate and drops one token less '
        '(D20, item 4)', () {
      final catalog = catalogOf([validSkill('tiny', body: 'Hi.')]);
      final def = catalog.skills.single;
      final blockTokens = (renderSkillBlock(def).length / 4).ceil();
      // Тело — один токен: по телу оба бюджета были бы с огромным запасом.
      expect(blockTokens, greaterThan(20));

      LlmContextProjection build(int total) => buildLlmContext(
        snapshotWith([('tiny', sha(def.body))]),
        skillCatalog: catalog,
        skillsConfig: SkillsConfig(reattachTotalTokens: total),
      );

      expect(build(blockTokens).messages, hasLength(4));
      expect(build(blockTokens - 1).messages, hasLength(3));
    });
  });

  group('the log skills.reattached (D20, "Логи")', () {
    test('names are the attached skills including the truncated ones, in '
        'the order of the message; truncated counts the cut ones', () async {
      final catalog = catalogOf([
        validSkill('small', body: 'Small.'),
        validSkill('big', body: rows(1000)),
      ]);
      const config = SkillsConfig(reattachPerSkillTokens: 100);
      final rig = _Rig(sid, settings);
      await rig.open(
        (_Chain(catalog)
              ..user(40)
              ..load('small')
              ..load('big')
              ..say(2000)
              ..user(30)
              ..say(2500))
            .records,
      );

      await rig.compact(catalog, bigWindow, skills: config);

      final log = rig.logger.eventsOf('skills.reattached').single;
      expect(log.fields['names'], ['big', 'small']);
      expect(log.fields['dropped'], 0);
      expect(log.fields['truncated'], 1);
      final text = textOf(rig.context(catalog, skills: config).messages[1]);
      expect(
        text.indexOf('<skill name="big" '),
        lessThan(text.indexOf('<skill name="small" ')),
      );
    });

    test('a skill missing from the catalog at the application drops '
        'silently: no log at all', () {
      final catalog = catalogOf([validSkill('notes', body: 'Notes.')]);
      final logger = RecordingLogger();

      buildLlmContext(
        _withCompactionSkills(sid, [
          ('gone', sha('Gone.')),
          ('notes', sha(catalog.skills.single.body)),
        ]),
        skillCatalog: catalog,
        logger: logger,
      );

      expect(
        logger.records.where((r) => r.event.startsWith('skills.')),
        isEmpty,
      );
    });
  });

  group('carrying over (agent-compaction "Усечённый навык при следующем '
      'сжатии", "Выпавший навык не возвращается сам")', () {
    late _Rig rig;
    setUp(() => rig = _Rig(sid, settings));

    test('a truncated skill is in the next record and is reattached '
        'truncated again; activeSkills sees full: false', () async {
      final catalog = catalogOf([validSkill('big', body: rows(1000))]);
      final def = catalog.skills.single;
      const config = SkillsConfig(reattachPerSkillTokens: 100);
      final chain = _Chain(catalog)
        ..user(40)
        ..load('big')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);
      await rig.compact(catalog, bigWindow, skills: config);
      expect(
        activeSkills(rig.writer.snapshot, catalog, config).single.full,
        isFalse,
      );

      await rig.append(
        (c) => c
          ..user(30)
          ..say(2500),
        catalog,
      );
      final second =
          await rig.compact(catalog, bigWindow, skills: config) as Compacted;

      expect(second.record.toJson()['skills'], [
        {'name': 'big', 'fingerprint': sha(def.body)},
      ]);
      final text = textOf(rig.context(catalog, skills: config).messages[1]);
      expect(text, contains('[skill truncated'));
      expect(
        activeSkills(rig.writer.snapshot, catalog, config).single.full,
        isFalse,
      );
    });

    test('a skill dropped by the total budget does not come back in the '
        'next record', () async {
      final catalog = catalogOf([
        validSkill('alpha', body: rows(1000)),
        validSkill('bravo', body: rows(1000)),
        validSkill('charlie', body: rows(1000)),
      ]);
      const config = SkillsConfig(
        reattachPerSkillTokens: 16384,
        reattachTotalTokens: 25000,
      );
      final chain = _Chain(catalog)
        ..user(40)
        ..load('alpha')
        ..load('bravo')
        ..load('charlie')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);
      await rig.compact(catalog, bigWindow, skills: config);

      await rig.append(
        (c) => c
          ..user(30)
          ..say(2500),
        catalog,
      );
      final second =
          await rig.compact(catalog, bigWindow, skills: config) as Compacted;

      final names = [
        for (final s in second.record.toJson()['skills']! as List<Object?>)
          (s! as Map<String, Object?>)['name'],
      ];
      expect(names, ['charlie', 'bravo']);
      final text = textOf(rig.context(catalog, skills: config).messages[1]);
      expect(text, isNot(contains('<skill name="alpha" ')));
    });

    test('only a new activation brings a dropped skill back', () async {
      final catalog = catalogOf([
        validSkill('alpha', body: rows(1000)),
        validSkill('bravo', body: rows(1000)),
        validSkill('charlie', body: rows(1000)),
      ]);
      const config = SkillsConfig(
        reattachPerSkillTokens: 16384,
        reattachTotalTokens: 25000,
      );
      final chain = _Chain(catalog)
        ..user(40)
        ..load('alpha')
        ..load('bravo')
        ..load('charlie')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);
      await rig.compact(catalog, bigWindow, skills: config);

      await rig.append(
        (c) => c
          ..user(30)
          ..load('alpha')
          ..say(2500)
          ..user(30)
          ..say(2500),
        catalog,
      );
      final second =
          await rig.compact(catalog, bigWindow, skills: config) as Compacted;

      final names = [
        for (final s in second.record.toJson()['skills']! as List<Object?>)
          (s! as Map<String, Object?>)['name'],
      ];
      expect(names, ['alpha', 'charlie', 'bravo']);
    });
  });

  group('the catalog and the fingerprint at the application (D15)', () {
    test('a skill missing from the catalog drops, the others stay', () {
      final catalog = catalogOf([validSkill('notes', body: 'Notes.')]);
      final def = catalog.skills.single;

      final context = buildLlmContext(
        _withCompactionSkills(sid, [
          ('gone', sha('Gone.')),
          ('notes', sha(def.body)),
        ]),
        skillCatalog: catalog,
      );

      final text = textOf(context.messages[1]);
      expect(text, contains('<skill name="notes" '));
      expect(text, isNot(contains('gone')));
    });

    test('every skill missing: no message at all', () {
      final context = buildLlmContext(
        _withCompactionSkills(sid, [('gone', sha('Gone.'))]),
        skillCatalog: SkillCatalog.empty,
      );

      expect(context.messages, hasLength(3));
    });

    test('a changed file after session/load: the current body is attached '
        'and skills.reattach.changed (warning) is logged', () {
      final before = catalogOf([validSkill('notes', body: 'Old notes.')]);
      final now = catalogOf([validSkill('notes', body: 'New notes.')]);
      final logger = RecordingLogger();

      final context = buildLlmContext(
        _withCompactionSkills(sid, [('notes', sha(before.skills.single.body))]),
        skillCatalog: now,
        logger: logger,
      );

      final text = textOf(context.messages[1]);
      expect(text, contains('New notes.'));
      expect(text, isNot(contains('Old notes.')));
      final log = logger.eventsOf('skills.reattach.changed').single;
      expect(log.level, LogLevel.warning);
      expect(log.fields['session_id'], sid.value);
      expect(log.fields['name'], 'notes');
      // Тело и отпечаток в логе не нужны.
      expect(jsonEncode(log.fields), isNot(contains('notes.')));
    });

    test('a matching fingerprint: no warning', () {
      final catalog = catalogOf([validSkill('notes', body: 'Notes.')]);
      final logger = RecordingLogger();

      buildLlmContext(
        _withCompactionSkills(sid, [
          ('notes', sha(catalog.skills.single.body)),
        ]),
        skillCatalog: catalog,
        logger: logger,
      );

      expect(logger.eventsOf('skills.reattach.changed'), isEmpty);
    });
  });

  group('tokensAfter and CMP-5 count the message (agent-compaction '
      '"Навыки после сжатия", п. 5)', () {
    test('tokensAfter equals the estimate of the projection with the '
        'message and is above the estimate without it', () async {
      final catalog = catalogOf([validSkill('big', body: rows(300))]);
      final rig = _Rig(sid, settings);
      final chain = _Chain(catalog)
        ..user(40)
        ..load('big')
        ..say(2000)
        ..user(30)
        ..say(2500);
      await rig.open(chain.records);
      final before = rig.writer.snapshot;

      final out = await rig.compact(catalog, bigWindow) as Compacted;

      final withRecord = before.withRecord(out.record, leafAfter(out.record));
      int estimate(LlmContextProjection p) => estimateContextTokens(
        p.messages,
        systemPrompt: _systemPrompt,
        tools: const [],
      );
      final withMessage = buildLlmContext(withRecord, skillCatalog: catalog);
      final without = buildLlmContext(withRecord);
      expect(out.tokensAfter, estimate(withMessage));
      expect(out.record.tokensAfter, estimate(withMessage));
      expect(out.tokensAfter, greaterThan(estimate(without)));
      // Сообщение в оценке — это 300 строк навыка, а не символическая добавка.
      expect(out.tokensAfter - estimate(without), greaterThan(2900));
    });

    test(
      'CMP-5: a skill that lifts the estimate above the threshold '
      'triggers another pass; without the skill one pass is enough',
      () async {
        // Навык ~7000 токенов при пороге 6144 (окно 8192, запас 2048).
        final catalog = catalogOf([validSkill('big', body: rows(700))]);
        final threshold = compactionThreshold(smallWindow, settings);

        final withSkill = _Rig(sid, settings);
        await withSkill.open(
          (_Chain(catalog)
                ..user(40)
                ..load('big')
                ..say(2000)
                ..user(30)
                ..say(2500))
              .records,
        );
        await withSkill.compact(catalog, smallWindow);

        final plain = _Rig(sid, settings);
        await plain.open(
          (_Chain(catalog)
                ..user(40)
                ..say(2000)
                ..user(30)
                ..say(2500))
              .records,
        );
        await plain.compact(catalog, smallWindow);

        expect(plain.compactionRecords, hasLength(1));
        expect(
          plain.compactionRecords.single.tokensAfter,
          lessThanOrEqualTo(threshold),
        );
        // Первый проход с навыком остаётся выше порога только из-за сообщения.
        expect(
          withSkill.compactionRecords.first.tokensAfter,
          greaterThan(threshold),
        );
        expect(withSkill.summaries, greaterThanOrEqualTo(1));
      },
    );
  });

  group('determinism (D15: "кэш после сжатия стабилен")', () {
    test('the same snapshot and catalog give the same message, byte for '
        'byte, also across fresh instances', () {
      LlmContextProjection build() {
        final catalog = catalogOf([
          validSkill('alpha', body: rows(40)),
          validSkill('bravo', body: 'Bravo.'),
        ]);
        return buildLlmContext(
          _withCompactionSkills(sid, [
            ('bravo', sha('Bravo.')),
            ('alpha', sha(rows(40))),
          ]),
          skillCatalog: catalog,
          skillsConfig: const SkillsConfig(reattachPerSkillTokens: 50),
        );
      }

      final first = build();
      final second = build();

      expect(first.messages, hasLength(3));
      expect(textOf(first.messages[1]), contains('<skill name="bravo" '));
      expect(messagesJson(first), messagesJson(second));
    });

    test(
      'compaction of equal journals gives equal records and contexts',
      () async {
        Future<(String, String)> run() async {
          final catalog = catalogOf([validSkill('alpha', body: rows(40))]);
          final rig = _Rig(sid, settings);
          await rig.open(
            (_Chain(catalog)
                  ..user(40)
                  ..load('alpha')
                  ..say(2000)
                  ..user(30)
                  ..say(2500))
                .records,
          );
          final out = await rig.compact(catalog, bigWindow) as Compacted;
          return (
            jsonEncode(out.record.toJson()),
            messagesJson(rig.context(catalog)),
          );
        }

        final a = await run();
        final b = await run();

        expect(a.$1, contains('"skills"'));
        expect(a, b);
      },
    );
  });
}

const _systemPrompt = 'You are CodeLab.';

/// Каждая строка `row NNNN ---…` в [text] — целая, нумерация с нуля подряд,
/// всего не больше [maxChars] символов тела (граница строки, D15).
void _expectCutAtLines(
  String text, {
  required int maxChars,
  required String mark,
}) {
  final whole = RegExp(
    r'^row (\d{4}) -{31}$',
    multiLine: true,
  ).allMatches(text).toList();
  final started = RegExp(r'^row ', multiLine: true).allMatches(text).length;
  expect(whole, isNotEmpty);
  expect(whole, hasLength(started), reason: 'a row cut in the middle');
  expect(
    [for (final m in whole) int.parse(m[1]!)],
    [for (var i = 0; i < whole.length; i++) i],
  );
  // Наибольший префикс целых строк, чья оценка ceil(символов / 4) не больше
  // бюджета (D20, п. 3): строка 40 символов + перевод строки.
  expect(whole.length, (maxChars + 1) ~/ 41);
  // Пометка — следующей строкой после усечённого тела, внутри блока, перед
  // `</skill>` (D20, п. 3).
  expect(text, contains('${whole.last[0]}\n$mark\n</skill>'));
  expect(text, isNot(contains('row 0999')));
}

/// Снимок: слова, ответ, слова (хвост), ответ и запись сжатия с полем
/// `skills`, записанным вручную: `firstKeptId` — вторые слова.
SessionSnapshot _withCompactionSkills(
  SessionId id,
  List<(String, String)> skills, {
  String summary = 'S',
}) {
  final line =
      jsonDecode(j.compaction('k1', 'a2', firstKept: 'u2', summary: summary))
          as Map<String, Object?>;
  line['skills'] = [
    for (final (name, fingerprint) in skills)
      {'name': name, 'fingerprint': fingerprint},
  ];
  return parseSessionLines(
    j.journal([
      j.header(id: id.value),
      j.user('u1', null),
      j.answer('a1', 'u1'),
      j.user('u2', 'a1'),
      j.answer('a2', 'u2'),
      jsonEncode(line),
    ]),
    id: id,
  ).snapshot;
}

/// Записи для журнала: ход пользователя, ответы и активации навыков.
final class _Chain {
  _Chain(this.catalog, {this.prefix = 'r', String? parent}) : _last = parent;

  final SkillCatalog catalog;
  final String prefix;
  final records = <SessionRecord>[];
  String? _last;
  var _n = 0;
  final _at = DateTime.utc(2026);

  String _id() => '$prefix${(_n++).toString().padLeft(7, '0')}';

  void _add(Message message, {CommandRef? command, String? outcome}) {
    final record = MessageRecord(
      id: _id(),
      parentId: _last,
      timestamp: _at,
      message: message,
      command: command,
      outcome: outcome,
    );
    _last = record.id;
    records.add(record);
  }

  /// Слова пользователя размером в [tokens] по оценке §9.3.
  void user(int tokens) => _add(
    UserMessage([TextContent('u' * ((tokens - 4) * 4))], timestamp: _at),
  );

  /// Ответ модели размером в [tokens].
  void say(int tokens) => _add(
    AssistantMessage(
      content: [TextContent('a' * ((tokens - 4) * 4))],
      model: testModel,
      usage: Usage.zero,
      stopReason: StopReason.stop,
      timestamp: _at,
    ),
  );

  /// Активация инструментом `skill`: вызов и результат с блоком каталога.
  void load(String name) {
    final callId = 'k${_n}x';
    _add(
      AssistantMessage(
        content: [
          ToolCall(id: callId, name: 'skill', arguments: {'name': name}),
        ],
        model: testModel,
        usage: Usage.zero,
        stopReason: StopReason.toolUse,
        timestamp: _at,
      ),
    );
    _add(
      ToolResultMessage(
        toolCallId: callId,
        toolName: 'skill',
        content: [TextContent(renderSkillBlock(catalog.skill(name)!))],
        isError: false,
        timestamp: _at,
      ),
      outcome: 'completed',
    );
  }

  /// Активация командой `/skill:<name> <args>` с настоящим текстом (D18).
  void invoke(String name, String args) => _add(
    UserMessage([
      TextContent(invokeSkill(catalog.skill(name)!, args).full),
    ], timestamp: _at),
    command: CommandRef(source: 'skill', name: name, args: args),
  );
}

/// Писатель журнала, вызов `compact` и проекции с одним набором параметров.
final class _Rig {
  _Rig(this.sid, this.settings);

  final SessionId sid;
  final CompactionSettings settings;
  late final RecordingStore store;
  late final SessionWriter writer;
  final logger = RecordingLogger();
  final events = <AgentEvent>[];
  var summaries = 0;
  var _pass = 0;

  List<CompactionRecord> get compactionRecords => [
    for (final a in store.appended)
      if (a.record case final CompactionRecord r) r,
  ];

  Future<void> open(List<SessionRecord> records) async {
    store = RecordingStore();
    final header = SessionHeader(
      id: sid,
      cwd: '/proj',
      created: DateTime.utc(2026),
      agent: const AgentInfo(name: 'test', version: '0'),
    );
    await store.create(header);
    writer = SessionWriter(
      store: store,
      snapshot: SessionSnapshot.empty(header),
      ids: SequentialIdGenerator(),
      clock: FakeClock(),
      logger: logger,
      onFailure: (_) {},
    );
    for (final record in records) {
      await writer.appendBuilt(record);
    }
    store.appended.clear();
  }

  /// Дописывает записи после текущего листа (после сжатия).
  Future<void> append(
    void Function(_Chain chain) build,
    SkillCatalog catalog,
  ) async {
    final chain = _Chain(
      catalog,
      prefix: 's${_pass++}',
      parent: writer.snapshot.leafId,
    );
    build(chain);
    for (final record in chain.records) {
      await writer.appendBuilt(record);
    }
  }

  Future<CompactionOutcome> compact(
    SkillCatalog? catalog,
    int window, {
    SkillsConfig skills = const SkillsConfig(),
    void Function(LlmContextProjection)? onCompacted,
  }) => engine.compact(
    writer: writer,
    trigger: CompactionTrigger.manual,
    summarize: (request, cancel) async {
      summaries++;
      return 'S';
    },
    settings: settings,
    window: window,
    systemPrompt: _systemPrompt,
    tools: const [],
    ids: SequentialIdGenerator(prefix: 'cmp'),
    clock: FakeClock(),
    cancel: CancelToken.none,
    emit: events.add,
    onCompacted: onCompacted,
    logger: logger,
    skillCatalog: catalog,
    skillsConfig: skills,
  );

  LlmContextProjection context(
    SkillCatalog? catalog, {
    SkillsConfig skills = const SkillsConfig(),
  }) => buildLlmContext(
    writer.snapshot,
    skillCatalog: catalog,
    skillsConfig: skills,
  );
}
