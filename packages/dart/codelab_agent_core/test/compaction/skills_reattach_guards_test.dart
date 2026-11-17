import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/compactor.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/src/session/session_writer.dart';
import 'package:codelab_agent_core/src/skills/active_skills.dart';
import 'package:codelab_agent_core/src/skills/skill_block.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart' as j;
import '../session/recording_store.dart';
import '../skills/skills_support.dart';
import 'region.dart';

/// СТРАЖИ задачи 4.1 (change `add-agent-skills`): зелёные уже сейчас, на
/// существующем API, и обязаны остаться зелёными после 4.2. Красные тесты —
/// в `skills_reattach_test.dart` и `skills_reattach_active_test.dart`.
///
/// Что охраняют: совместимость вперёд (agent-compaction «Навыки после
/// сжатия», последний абзац; `agent-core-architecture` §8.2.2: неизвестное
/// поле записи не теряется), запись без поля `skills` ведёт себя как раньше
/// (D18 «Сжатие в итерации 3»), сжатие без навыков не меняет контекст
/// (сценарий «Сжатие без навыков»), шаблон сообщения после резюме уже есть.
void main() {
  const sid = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  Map<String, Object?> compactionLine({List<Object?>? skills}) {
    final line =
        jsonDecode(j.compaction('k1', 'a2', firstKept: 'u2', summary: 'S'))
            as Map<String, Object?>;
    if (skills != null) {
      line['skills'] = skills;
    }
    return line;
  }

  SessionSnapshot snapshot(Map<String, Object?> compaction) =>
      parseSessionLines(
        j.journal([
          j.header(),
          j.user('u1', null),
          j.answer('a1', 'u1'),
          j.user('u2', 'a1'),
          j.answer('a2', 'u2'),
          jsonEncode(compaction),
        ]),
        id: sid,
      ).snapshot;

  group('forward compatibility (§8.2.2)', () {
    test('a compaction line with the field skills survives parse and write '
        'byte for byte', () {
      final line = compactionLine(
        skills: [
          {'name': 'release-notes', 'fingerprint': 'ab' * 32},
          {'name': 'review', 'fingerprint': 'cd' * 32},
        ],
      );

      final record = SessionRecord.fromJson(line);

      expect(jsonEncode(record.toJson()), jsonEncode(line));
    });

    test('a core that does not know the field builds the previous context', () {
      final withField = snapshot(
        compactionLine(
          skills: [
            {'name': 'release-notes', 'fingerprint': 'ab' * 32},
          ],
        ),
      );
      final without = snapshot(compactionLine());

      final a = buildLlmContext(withField);
      final b = buildLlmContext(without);

      expect(
        jsonEncode([for (final m in a.messages) m.toJson()]),
        jsonEncode([for (final m in b.messages) m.toJson()]),
      );
      expect(a.messages, hasLength(3));
    });
  });

  group('a record without the field behaves as before (D18)', () {
    final catalog = parse([validSkill('notes', body: 'Plain notes.')]);

    test('the context is: the summary, then the kept tail; no extra '
        'message', () {
      final context = buildLlmContext(snapshot(compactionLine()));

      expect(context.messages, hasLength(3));
      expect(
        (context.messages.first as UserMessage).content.single,
        isA<TextContent>().having(
          (t) => t.text,
          'text',
          Prompts.compactionSummaryWrapper.render({'summary': 'S'}),
        ),
      );
    });

    test('a skill activated before firstKeptId is not active: its body went '
        'into the summary', () {
      final line = compactionLine();
      final snap = parseSessionLines(
        j.journal([
          j.header(),
          j.user('u1', null),
          j.answer(
            'a1',
            'u1',
            calls: [
              ('c1', 'skill', {'name': 'notes'}),
            ],
          ),
          j.toolResult(
            'r1',
            'a1',
            callId: 'c1',
            tool: 'skill',
            text: renderSkillBlock(catalog.skills.single),
          ),
          j.user('u2', 'r1'),
          j.answer('a2', 'u2'),
          jsonEncode(line),
        ]),
        id: sid,
      ).snapshot;

      expect(activeSkills(snap, catalog, const SkillsConfig()), isEmpty);
    });
  });

  group('compaction without activations (scenario "Сжатие без навыков")', () {
    test('no field in the record, tokensAfter is the estimate of the plain '
        'projection, no reattach log', () async {
      final store = RecordingStore();
      final logger = RecordingLogger();
      final header = SessionHeader(
        id: sid,
        cwd: '/proj',
        created: DateTime.utc(2026),
        agent: const AgentInfo(name: 'test', version: '0'),
      );
      await store.create(header);
      final writer = SessionWriter(
        store: store,
        snapshot: SessionSnapshot.empty(header),
        ids: SequentialIdGenerator(),
        clock: FakeClock(),
        logger: logger,
        onFailure: (_) {},
      );
      final r = RegionBuilder()
        ..user(40)
        ..assistant(2000)
        ..user(30)
        ..assistant(2500);
      for (final record in r.records) {
        await writer.appendBuilt(record);
      }

      final out =
          await compact(
                writer: writer,
                trigger: CompactionTrigger.manual,
                summarize: (request, cancel) async => 'S',
                settings: const CompactionSettings(
                  reserveTokens: 2048,
                  keepRecentTokens: 2048,
                  keepRecentUserTurns: 1,
                ),
                window: 100000,
                systemPrompt: 'You are CodeLab.',
                tools: const [],
                ids: SequentialIdGenerator(prefix: 'cmp'),
                clock: FakeClock(),
                cancel: CancelToken.none,
                emit: (_) {},
                logger: logger,
              )
              as Compacted;

      expect(out.record.toJson().containsKey('skills'), isFalse);
      expect(logger.eventsOf('skills.reattached'), isEmpty);
      expect(
        buildLlmContext(writer.snapshot).messages.map((m) => m.runtimeType),
        [UserMessage, UserMessage, AssistantMessage],
      );
    });
  });

  test('the template of the message after the summary exists and takes '
      '"blocks"', () {
    final text = Prompts.skillsReattached.render({'blocks': 'BLOCKS-HERE'});

    expect(text, contains('BLOCKS-HERE'));
    expect(text, contains('instructions are repeated here'));
  });
}
