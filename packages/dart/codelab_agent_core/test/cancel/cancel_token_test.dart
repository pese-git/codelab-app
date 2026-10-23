import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CancelTokenSource', () {
    test('CAN-1: listeners run in a microtask, not inside cancel()', () async {
      final source = CancelTokenSource();
      var calls = 0;
      unawaited(source.token.onCancel.then((_) => calls++));

      source.cancel();
      expect(calls, 0);
      expect(source.token.isCancelled, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    });

    test('the first reason wins; the token stays cancelled (CAN-2)', () {
      final source = CancelTokenSource();

      source.cancel(const WatchdogFired('idle'));
      source.cancel(const UserCancel());

      expect(source.isCancelled, isTrue);
      expect(source.token.reason, isA<WatchdogFired>());
      expect((source.token.reason! as WatchdogFired).kind, 'idle');
    });

    test('cancel without a reason is a user cancel', () {
      final source = CancelTokenSource()..cancel();

      expect(source.token.reason, isA<UserCancel>());
    });

    test('throwIfCancelled throws CancelledException with the reason', () {
      final source = CancelTokenSource();
      source.token.throwIfCancelled();

      source.cancel(const ShutdownCancel());

      expect(
        source.token.throwIfCancelled,
        throwsA(
          isA<CancelledException>().having(
            (e) => e.reason,
            'reason',
            isA<ShutdownCancel>(),
          ),
        ),
      );
    });

    test('a token that is not cancelled has no reason', () {
      final source = CancelTokenSource();

      expect(source.token.isCancelled, isFalse);
      expect(source.token.reason, isNull);
    });

    test('CancelToken.none is never cancelled', () async {
      expect(CancelToken.none.isCancelled, isFalse);
      var fired = false;
      unawaited(CancelToken.none.onCancel.then((_) => fired = true));
      await Future<void>.delayed(Duration.zero);
      expect(fired, isFalse);
    });
  });

  group('hierarchy (CAN-3)', () {
    test(
      'cancelling the parent reaches the grandchild with its reason',
      () async {
        final turn = CancelTokenSource();
        final attempt = CancelTokenSource(parent: turn.token);
        final operation = CancelTokenSource(parent: attempt.token);

        turn.cancel(const UserCancel());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(attempt.token.isCancelled, isTrue);
        expect(operation.token.isCancelled, isTrue);
        expect(operation.token.reason, isA<UserCancel>());
      },
    );

    test('cancelling a child does not touch the parent', () {
      final turn = CancelTokenSource();
      final attempt = CancelTokenSource(parent: turn.token);

      attempt.cancel(const WatchdogFired('connect'));

      expect(turn.token.isCancelled, isFalse);
      expect(CancelTokenSource(parent: turn.token).token.isCancelled, isFalse);
    });

    test('a child of a cancelled parent is cancelled at once', () {
      final turn = CancelTokenSource()..cancel(const ShutdownCancel());

      final child = CancelTokenSource(parent: turn.token);

      expect(child.token.isCancelled, isTrue);
      expect(child.token.reason, isA<ShutdownCancel>());
    });

    test('a disposed child is no longer cancelled by the parent', () async {
      final turn = CancelTokenSource();
      final attempt = CancelTokenSource(parent: turn.token)..dispose();

      turn.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(attempt.token.isCancelled, isFalse);
    });
  });

  group('raceCancel', () {
    test('work that finishes first wins', () async {
      final source = CancelTokenSource();

      expect(await raceCancel(Future.value(42), source.token), 42);
    });

    test(
      'cancel first throws; the late error of work is not unhandled',
      () async {
        final errors = <Object>[];
        await runZonedGuarded(() async {
          final source = CancelTokenSource();
          final work = Completer<int>();
          final race = raceCancel(work.future, source.token);

          source.cancel();
          await expectLater(race, throwsA(isA<CancelledException>()));
          work.completeError(StateError('late'));
          await Future<void>.delayed(Duration.zero);
        }, (error, _) => errors.add(error));

        expect(errors, isEmpty);
      },
    );
  });

  group('delayCancellable', () {
    test('completes after the delay on the clock', () async {
      final clock = FakeClock();
      var done = false;
      unawaited(
        delayCancellable(
          clock,
          const Duration(seconds: 2),
          CancelToken.none,
        ).then((_) => done = true),
      );

      await clock.elapse(const Duration(seconds: 2));

      expect(done, isTrue);
    });

    test('is interrupted by cancel without advancing the clock', () async {
      final clock = FakeClock();
      final source = CancelTokenSource();
      final delay = delayCancellable(
        clock,
        const Duration(seconds: 30),
        source.token,
      );

      await clock.elapse(const Duration(seconds: 1));
      source.cancel();

      await expectLater(delay, throwsA(isA<CancelledException>()));
      expect(clock.elapsed, const Duration(seconds: 1));
    });
  });
}
