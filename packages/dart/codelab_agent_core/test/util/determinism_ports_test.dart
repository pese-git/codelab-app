import 'dart:async';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

void main() {
  group('FakeClock', () {
    test('does not move by itself', () async {
      final clock = FakeClock(start: DateTime.utc(2026, 1, 1));
      var done = false;
      unawaited(
        clock.delay(const Duration(seconds: 10)).then((_) => done = true),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(done, isFalse);
      expect(clock.now(), DateTime.utc(2026, 1, 1));
    });

    test('delay completes only after the clock is advanced', () async {
      final clock = FakeClock();
      var done = false;
      unawaited(
        clock.delay(const Duration(seconds: 10)).then((_) => done = true),
      );

      await clock.elapse(const Duration(seconds: 9));
      expect(done, isFalse);
      await clock.elapse(const Duration(seconds: 1));
      expect(done, isTrue);
    });

    test('timers fire in the order of their due time', () async {
      final clock = FakeClock();
      final fired = <String>[];
      clock.timer(const Duration(seconds: 3), () => fired.add('c'));
      clock.timer(const Duration(seconds: 1), () => fired.add('a'));
      clock.timer(const Duration(seconds: 2), () => fired.add('b'));
      clock.timer(const Duration(seconds: 2), () => fired.add('b2'));

      await clock.elapse(const Duration(seconds: 5));

      expect(fired, ['a', 'b', 'b2', 'c']);
    });

    test('the clock reads the due time inside a timer', () async {
      final start = DateTime.utc(2026);
      final clock = FakeClock(start: start);
      DateTime? seen;
      clock.timer(const Duration(seconds: 2), () => seen = clock.now());

      await clock.elapse(const Duration(seconds: 5));

      expect(seen, start.add(const Duration(seconds: 2)));
      expect(clock.now(), start.add(const Duration(seconds: 5)));
    });

    test('a cancelled timer does not fire', () async {
      final clock = FakeClock();
      var fired = false;
      final timer = clock.timer(const Duration(seconds: 1), () => fired = true);
      expect(timer.isActive, isTrue);

      timer.cancel();
      await clock.elapse(const Duration(seconds: 2));

      expect(fired, isFalse);
      expect(timer.isActive, isFalse);
    });

    test(
      'a timer scheduled after an awaited delay is seen by elapse',
      () async {
        final clock = FakeClock();
        final steps = <int>[];
        Future<void> work() async {
          await clock.delay(const Duration(seconds: 1));
          steps.add(1);
          await clock.delay(const Duration(seconds: 1));
          steps.add(2);
        }

        unawaited(work());
        await clock.elapse(const Duration(seconds: 2));

        expect(steps, [1, 2]);
      },
    );

    test('delay is cancelled by its token', () async {
      final clock = FakeClock();
      final source = CancelTokenSource();
      final delay = clock.delay(
        const Duration(seconds: 30),
        cancel: source.token,
      );

      source.cancel();

      await expectLater(delay, throwsA(isA<CancelledException>()));
      expect(clock.pendingTimers, 0);
    });
  });

  group('SequentialIdGenerator', () {
    test('two generators give the same sequence', () {
      final a = SequentialIdGenerator();
      final b = SequentialIdGenerator();

      final first = [a.nextId(), a.nextId(), a.nextId()];
      final second = [b.nextId(), b.nextId(), b.nextId()];

      expect(first, ['id-1', 'id-2', 'id-3']);
      expect(second, first);
    });

    test('nextChars is repeatable, in the alphabet and unique', () {
      const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
      final a = SequentialIdGenerator();
      final b = SequentialIdGenerator();

      final first = [for (var i = 0; i < 100; i++) a.nextChars(8, alphabet)];
      final second = [for (var i = 0; i < 100; i++) b.nextChars(8, alphabet)];

      expect(second, first);
      expect(first.toSet(), hasLength(100));
      for (final value in first) {
        expect(value, hasLength(8));
        expect(value.split('').every(alphabet.contains), isTrue, reason: value);
      }
    });

    test('nextChars does not disturb nextId', () {
      final ids = SequentialIdGenerator();

      ids.nextChars(8, '01');

      expect(ids.nextId(), 'id-1');
    });
  });

  group('RandomIdGenerator', () {
    test('is repeatable over Random(42)', () {
      final a = RandomIdGenerator(Random(42));
      final b = RandomIdGenerator(Random(42));

      expect(
        [a.nextId(), a.nextChars(16, 'abc')],
        [b.nextId(), b.nextChars(16, 'abc')],
      );
    });

    test('gives characters of the alphabet only', () {
      final ids = RandomIdGenerator(Random(7));

      final value = ids.nextChars(64, 'xyz');

      expect(value, hasLength(64));
      expect(value.split('').toSet().difference({'x', 'y', 'z'}), isEmpty);
    });
  });

  test('Random(42) is repeatable', () {
    final a = Random(42);
    final b = Random(42);

    expect(
      List.generate(10, (_) => a.nextInt(1000)),
      List.generate(10, (_) => b.nextInt(1000)),
    );
  });

  group('SystemClock', () {
    test('delays and reads the wall clock', () async {
      const clock = SystemClock();
      final before = clock.now();

      await clock.delay(const Duration(milliseconds: 5));

      expect(clock.now().isBefore(before), isFalse);
    });

    test('timer fires and can be cancelled', () async {
      const clock = SystemClock();
      var fired = 0;
      clock.timer(const Duration(milliseconds: 1), () => fired++);
      clock.timer(const Duration(milliseconds: 1), () => fired += 10).cancel();

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fired, 1);
    });
  });

  group('RecordingLogger', () {
    test('records events with fields at enabled levels', () {
      final logger = RecordingLogger(minLevel: LogLevel.info);

      logger.log(LogLevel.debug, 'llm.request.start');
      logger.log(
        LogLevel.info,
        'llm.retry',
        fields: {'attempt': 1, 'class': 'network', 'delay_ms': 500},
      );

      expect(logger.isEnabled(LogLevel.debug), isFalse);
      expect(logger.records.map((r) => r.event), ['llm.retry']);
      expect(logger.records.single.level, LogLevel.info);
      expect(logger.records.single.fields, containsPair('attempt', 1));
      expect(logger.eventsOf('llm.retry'), hasLength(1));
    });
  });
}
