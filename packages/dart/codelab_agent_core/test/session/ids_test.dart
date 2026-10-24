import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/ids.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

/// Id журнала (agent-sessions «Идентификаторы и дерево записей», §8.4).
void main() {
  group('newSessionId', () {
    test('is a ULID: 26 Crockford base32 characters', () {
      final id = newSessionId(FakeClock(), SequentialIdGenerator());

      expect(id.value, hasLength(26));
      expect(
        id.value.split('').every(crockfordAlphabet.contains),
        isTrue,
        reason: id.value,
      );
    });

    test('the first 10 characters are the time and sort by it', () async {
      final clock = FakeClock(start: DateTime.utc(2026, 10, 21, 8));
      final ids = SequentialIdGenerator();

      final earlier = newSessionId(clock, ids);
      await clock.elapse(const Duration(milliseconds: 1));
      final later = newSessionId(clock, ids);

      expect(earlier.value.compareTo(later.value), lessThan(0));
      expect(
        earlier.value.substring(0, 10),
        isNot(later.value.substring(0, 10)),
      );
    });

    test('the time part encodes milliseconds since the epoch', () {
      final clock = FakeClock(
        start: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

      final id = newSessionId(clock, SequentialIdGenerator());

      expect(id.value.substring(0, 10), '0000000000');
    });
  });

  group('newRecordId', () {
    test('is 8 characters of 0-9a-z', () {
      final id = newRecordId(SequentialIdGenerator(), (_) => false);

      expect(id, matches(RegExp(r'^[0-9a-z]{8}$')));
    });

    test('asks again while the id is taken', () {
      final ids = SequentialIdGenerator();
      final taken = {
        for (var i = 0; i < 3; i++) SequentialIdGenerator()._skip(i),
      };

      final id = newRecordId(ids, taken.contains);

      expect(taken, isNot(contains(id)));
      expect(id, hasLength(8));
    });

    test('gives 12 characters after 16 collisions', () {
      var asked = 0;
      final id = newRecordId(SequentialIdGenerator(), (candidate) {
        asked++;
        return candidate.length == 8;
      });

      expect(id, hasLength(12));
      // 1 + 16 eight-character attempts, then the free 12-character one.
      expect(asked, 18);
    });
  });
}

extension on SequentialIdGenerator {
  /// The [n]-th (from 0) 8-character id of a fresh generator.
  String _skip(int n) {
    for (var i = 0; i < n; i++) {
      nextChars(8, recordIdAlphabet);
    }
    return nextChars(8, recordIdAlphabet);
  }
}
