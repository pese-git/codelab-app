import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/misuse.dart';
import 'package:test/test.dart';

import '../loop/loop_harness.dart';
import 'executor_harness.dart';
import 'fake_tools.dart';

const _warn =
    'Do not repeat it: change the arguments or use another approach.]';

void main() {
  group('MisuseBreaker', () {
    test('the key is the tool and the canonical JSON of raw args', () {
      expect(
        MisuseBreaker.keyOf('read', {'path': 'a', 'limit': 'ten'}),
        MisuseBreaker.keyOf('read', {'limit': 'ten', 'path': 'a'}),
      );
      expect(
        MisuseBreaker.keyOf('read', {'limit': 'ten'}),
        isNot(MisuseBreaker.keyOf('read', {'limit': 10})),
      );
      expect(
        MisuseBreaker.keyOf('read', {}),
        isNot(MisuseBreaker.keyOf('edit', {})),
      );
    });

    test('warnings from warnAfter, block at blockAfter', () {
      final breaker = MisuseBreaker(const MisuseLimits());
      final key = MisuseBreaker.keyOf('read', {'limit': 'ten'});

      final texts = [for (var i = 0; i < 6; i++) breaker.recordInvalid(key)];

      expect(texts.take(2), [null, null]);
      expect(
        texts[2],
        '[Warning: this exact call has failed 3 times in this turn. $_warn',
      );
      expect(texts[4], contains('failed 5 times'));
      expect(
        texts[5],
        '[Warning: this exact call has failed 6 times in this turn and is now '
        'blocked until the turn ends.]',
      );
      expect(breaker.isBlocked(key), isTrue);
      expect(breaker.count(key), 6);
    });

    test('a disabled breaker counts nothing and never blocks', () {
      final breaker = MisuseBreaker(const MisuseLimits(enabled: false));
      final key = MisuseBreaker.keyOf('read', {});

      for (var i = 0; i < 10; i++) {
        expect(breaker.recordInvalid(key), isNull);
      }
      expect(breaker.isBlocked(key), isFalse);
    });

    test('limits outside 1 ≤ warnAfter ≤ blockAfter ≤ 50 are rejected', () {
      expect(() => MisuseLimits(warnAfter: 0), throwsA(isA<AssertionError>()));
      expect(
        () => MisuseLimits(warnAfter: 4, blockAfter: 3),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => MisuseLimits(blockAfter: 51),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('the execution point (steps 1a and 9a)', () {
    test(
      'seven read {"limit":"ten"} — core/misuse-breaker-blocks-repeat',
      () async {
        final hookCalls = <String>[];
        final h = await LoopHarness.create(
          tools: [ReadTool()],
          llm: script([
            for (var i = 1; i <= 7; i++)
              callStep([
                ('c$i', 'read', {'limit': 'ten'}),
              ]),
            textStep('giving up'),
          ]),
        );

        await h.run(
          [user('go')],
          config: h.config(
            beforeToolCall: [
              (call, args, ctx) async {
                hookCalls.add(call.id);
                return null;
              },
            ],
          ),
        );

        final texts = [
          for (final e in h.events.whereType<ToolCallFinished>())
            (e.content.single as TextContent).text,
        ];
        expect(texts, hasLength(7));
        for (final text in texts.take(6)) {
          expect(text, startsWith('Invalid arguments for tool "read":'));
        }
        expect(texts[0], isNot(contains('[Warning')));
        expect(texts[1], isNot(contains('[Warning')));
        for (final text in texts.sublist(2, 5)) {
          expect(text, endsWith(_warn));
        }
        expect(texts[5], endsWith('is now blocked until the turn ends.]'));
        expect(
          texts[6],
          'Blocked: this exact call to read has already failed 6 times in this '
          'turn and will not be run again until the turn ends. Change the '
          'arguments or use another approach.',
        );
        expect(
          h.events.whereType<ToolCallFinished>().map((e) => e.outcome),
          everyElement(ToolOutcome.failed),
        );
        // Валидация не прошла ни разу, поэтому хуки не вызывались вовсе.
        expect(hookCalls, isEmpty);
        final logger = h.logger;
        expect(
          logger.records.where((r) => r.event == 'tool.misuse.blocked'),
          hasLength(1),
        );
      },
    );

    test('fixed arguments are another key and run', () async {
      final h = await ExecutorHarness.create([ReadTool()]);
      final breaker = MisuseBreaker(const MisuseLimits());
      final invocation = h.invocation(misuse: breaker);
      for (var i = 0; i < 6; i++) {
        await h.run(
          'read',
          {'path': 'a.txt', 'limit': 'ten'},
          id: 'c$i',
          invocation: invocation,
        );
      }

      final swapped = await h.run(
        'read',
        {'limit': 'ten', 'path': 'a.txt'},
        id: 'c7',
        invocation: invocation,
      );
      final fixed = await h.run(
        'read',
        {'path': 'a.txt', 'limit': 10},
        id: 'c8',
        invocation: invocation,
      );

      expect(textOf(swapped), startsWith('Blocked: '));
      expect(textOf(fixed), 'File not found: a.txt');
    });

    test('an unavailable tool and a preflight error are counted', () async {
      final h = await ExecutorHarness.create([
        FakeTool('checked', preflightText: 'bad input'),
      ]);
      final breaker = MisuseBreaker(
        const MisuseLimits(warnAfter: 2, blockAfter: 3),
      );
      final invocation = h.invocation(misuse: breaker);

      final missing = [
        for (var i = 0; i < 2; i++)
          textOf(await h.run('nope', {}, id: 'm$i', invocation: invocation)),
      ];
      final preflight = [
        for (var i = 0; i < 4; i++)
          textOf(await h.run('checked', {}, id: 'p$i', invocation: invocation)),
      ];

      expect(
        missing[1],
        contains('[Warning: this exact call has failed 2 times'),
      );
      expect(preflight[0], 'bad input');
      expect(preflight[2], endsWith('is now blocked until the turn ends.]'));
      expect(preflight[3], startsWith('Blocked: this exact call to checked'));
    });

    test('denials, failed executions and cancels are not counted', () async {
      final denied = FakeTool('denied');
      final failing = FakeTool(
        'failing',
        onExecute: (args, ctx) =>
            const ToolExecutionResult([TextContent('exit 1')], isError: true),
      );
      final h = await ExecutorHarness.create([denied, failing]);
      final breaker = MisuseBreaker(
        const MisuseLimits(warnAfter: 1, blockAfter: 2),
      );
      final invocation = h.invocation(
        misuse: breaker,
        before: [
          (call, args, ctx) async =>
              call.name == 'denied' ? const Block('no') : null,
        ],
      );

      for (var i = 0; i < 5; i++) {
        expect(
          textOf(await h.run('denied', {}, id: 'd$i', invocation: invocation)),
          'no',
        );
        expect(
          textOf(await h.run('failing', {}, id: 'f$i', invocation: invocation)),
          'exit 1',
        );
      }
      expect(failing.executed, hasLength(5));
    });
  });

  group('the loop (LOOP-16)', () {
    test('a new turn starts with an empty counter', () async {
      final h = await LoopHarness.create(
        tools: [ReadTool()],
        llm: script([
          for (var i = 1; i <= 6; i++)
            callStep([
              ('a$i', 'read', {'limit': 'ten'}),
            ]),
          textStep('turn 1'),
          callStep([
            ('b1', 'read', {'limit': 'ten'}),
          ]),
          textStep('turn 2'),
        ]),
      );

      await h.run([user('one')]);
      final firstTurn = h.events.whereType<ToolCallFinished>().length;
      await h.run([user('two')]);

      final last = h.events.whereType<ToolCallFinished>().last;
      expect(firstTurn, 6);
      expect(
        (last.content.single as TextContent).text,
        startsWith('Invalid arguments for tool "read":'),
      );
      expect(
        (last.content.single as TextContent).text,
        isNot(contains('[Warning')),
      );
    });

    test('two identical calls of one batch are both counted', () async {
      final h = await LoopHarness.create(
        tools: [ReadTool()],
        llm: script([
          for (var i = 1; i <= 3; i++)
            callStep([
              ('x$i', 'read', {'limit': 'ten'}),
              ('y$i', 'read', {'limit': 'ten'}),
            ]),
          callStep([
            ('z', 'read', {'limit': 'ten'}),
          ]),
          textStep('done'),
        ]),
      );

      await h.run([user('go')]);

      final last = h.events.whereType<ToolCallFinished>().last;
      expect(
        (last.content.single as TextContent).text,
        startsWith('Blocked: this exact call to read has already failed 6 '),
      );
    });

    test('loop config misuse: enabled false turns the breaker off', () async {
      final h = await LoopHarness.create(
        tools: [ReadTool()],
        llm: script([
          for (var i = 1; i <= 7; i++)
            callStep([
              ('c$i', 'read', {'limit': 'ten'}),
            ]),
          textStep('done'),
        ]),
      );

      await h.run([
        user('go'),
      ], config: h.config(misuse: const MisuseLimits(enabled: false)));

      for (final e in h.events.whereType<ToolCallFinished>()) {
        final text = (e.content.single as TextContent).text;
        expect(text, startsWith('Invalid arguments'));
        expect(text, isNot(contains('[Warning')));
      }
    });
  });
}
