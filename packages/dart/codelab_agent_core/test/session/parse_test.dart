import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'journal_lines.dart';

/// Разбор журнала в памяти (agent-sessions «Открытие и ремонт журнала»,
/// «Идентификаторы и дерево записей»; §8.4, §8.6, шаги 1–4 и 6–8).
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  ParsedJournal parse(String text, {Logger? logger}) =>
      parseSessionLines(text, id: id, logger: logger);

  test('a clean journal: header, records in file order, the leaf', () {
    final parsed = parse(
      journal([header(), user('a', null), answer('b', 'a')]),
    );

    expect(parsed.snapshot.header.id, id);
    expect(parsed.snapshot.records.map((r) => r.id), ['a', 'b']);
    expect(parsed.snapshot.byId.keys, ['a', 'b']);
    expect(parsed.snapshot.leafId, 'b');
    expect(parsed.snapshot.repair.isClean, isTrue);
    expect(parsed.quarantine, isEmpty);
  });

  test('an empty journal body has no leaf', () {
    final parsed = parse(journal([header()]));

    expect(parsed.snapshot.records, isEmpty);
    expect(parsed.snapshot.leafId, isNull);
  });

  test('empty lines are skipped', () {
    final parsed = parse('${header()}\n\n${user('a', null)}\n\n');

    expect(parsed.snapshot.records.map((r) => r.id), ['a']);
    expect(parsed.quarantine, isEmpty);
  });

  test('an unknown version is SessionOpenException(unsupportedVersion)', () {
    expect(
      () => parse(journal([header(version: 2), user('a', null)])),
      throwsA(
        isA<SessionOpenException>()
            .having(
              (e) => e.error,
              'error',
              SessionOpenError.unsupportedVersion,
            )
            .having((e) => e.version, 'version', 2),
      ),
    );
  });

  test('a missing header is synthesized in memory', () {
    final parsed = parseSessionLines(
      journal([user('a', null)]),
      id: id,
      cwd: '/work/demo',
      created: DateTime.utc(2026, 10, 21),
    );

    expect(parsed.snapshot.repair.headerMissing, isTrue);
    expect(parsed.snapshot.header.id, id);
    expect(parsed.snapshot.header.cwd, '/work/demo');
    expect(parsed.snapshot.header.created, DateTime.utc(2026, 10, 21));
    expect(parsed.snapshot.records.map((r) => r.id), ['a']);
  });

  test('a cut last line goes to quarantine as truncated', () {
    final whole = journal([header(), user('a', null), answer('b', 'a')]);
    final cut = whole.substring(0, whole.length - 20);

    final parsed = parse(cut);

    expect(parsed.snapshot.records.map((r) => r.id), ['a']);
    expect(parsed.snapshot.leafId, 'a');
    expect(parsed.quarantine.single.line, 3);
    expect(parsed.quarantine.single.reason, 'truncated');
    expect(parsed.onlyTailBroken, isTrue);
    expect(parsed.snapshot.repair.quarantinedLines, 1);
  });

  test('garbage in the middle goes to quarantine as invalid', () {
    final parsed = parse(
      '${header()}\n${user('a', null)}\n{oops\n${answer('b', 'a')}\n',
    );

    expect(parsed.snapshot.records.map((r) => r.id), ['a', 'b']);
    expect(parsed.quarantine.single.line, 3);
    expect(parsed.quarantine.single.text, '{oops');
    expect(parsed.quarantine.single.reason, 'invalid');
    expect(parsed.onlyTailBroken, isFalse);
  });

  test('not an object and a record without id are invalid', () {
    final parsed = parse(
      '${header()}\n[1,2]\n{"type":"leaf","parentId":null,'
      '"timestamp":"2026-10-21T08:00:00.000Z","targetId":"x"}\n',
    );

    expect(parsed.quarantine.map((q) => q.line), [2, 3]);
    expect(parsed.snapshot.records, isEmpty);
  });

  test('a duplicate id keeps the first copy', () {
    final parsed = parse(
      journal([header(), user('a', null), user('a', null, text: 'again')]),
    );

    expect(parsed.snapshot.records, hasLength(1));
    final kept = parsed.snapshot.byId['a']! as MessageRecord;
    expect((kept.message.content.single as TextContent).text, 'hello');
    expect(parsed.quarantine.single.reason, 'duplicate id');
  });

  test('a whole last line without newline is kept', () {
    final parsed = parse('${header()}\n${user('a', null)}');

    expect(parsed.snapshot.records.map((r) => r.id), ['a']);
    expect(parsed.quarantine, isEmpty);
    expect(parsed.missingFinalNewline, isTrue);
  });

  test('a leaf record moves the leaf to its target (rule 2)', () {
    final parsed = parse(
      journal([
        header(),
        user('a', null),
        answer('b', 'a'),
        leaf('l', 'b', target: 'a'),
      ]),
    );

    expect(parsed.snapshot.leafId, 'a');
  });

  test('a dangling leaf heals to the last surviving record', () {
    final logger = RecordingLogger();
    final parsed = parse(
      journal([
        header(),
        user('a', null),
        answer('b', 'a'),
        leaf('l', 'b', target: 'gone'),
      ]),
      logger: logger,
    );

    expect(parsed.snapshot.leafId, 'b');
    expect(parsed.snapshot.repair.healedLeafFrom, 'gone');
    expect(logger.eventsOf('session.leaf.healed'), hasLength(1));
  });

  test('broken links are counted', () {
    final parsed = parse(
      journal([header(), user('a', null), answer('b', 'missing')]),
    );

    expect(parsed.snapshot.repair.brokenLinks, 1);
    expect(parsed.snapshot.repair.isClean, isFalse);
  });

  test('an unknown record type does not break the leaf', () {
    final parsed = parse(
      '${journal([header(), user('a', null)])}'
      '{"type":"branch","id":"x","parentId":"a",'
      '"timestamp":"2026-10-21T08:00:00.000Z","targetId":"a"}\n',
    );

    expect(parsed.snapshot.records.last, isA<CustomRecord>());
    expect(parsed.snapshot.leafId, 'x');
  });
}
