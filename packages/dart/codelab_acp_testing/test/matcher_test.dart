import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

Map<String, Object?> _toolUpdate({
  String status = 'completed',
  Map<String, Object?> extra = const {},
}) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': 'sess-1',
    'update': {
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'call_1',
      'status': status,
      ...extra,
    },
  },
};

List<String> _paths(List<FrameMismatch> mismatches) =>
    mismatches.map((m) => m.path).toList();

void main() {
  late FrameMatcher matcher;

  setUp(() {
    matcher = FrameMatcher(cwd: '/work/demo')
      ..variables['sessionId'] = 'sess-1';
  });

  group('exact comparison: frame mutations are caught', () {
    test('identical frames match', () {
      expect(matcher.match(_toolUpdate(), _toolUpdate()), isEmpty);
    });

    test('extra key in the actual frame', () {
      final mismatches = matcher.match(
        _toolUpdate(),
        _toolUpdate(extra: {'rawOutput': 'x'}),
      );
      expect(_paths(mismatches), [r'$.params.update.rawOutput']);
      expect(mismatches.single.message, contains('unexpected key'));
    });

    test('different status reports path, expected and actual', () {
      final mismatches = matcher.match(
        _toolUpdate(),
        _toolUpdate(status: 'failed'),
      );
      expect(
        mismatches.single.toString(),
        r'$.params.update.status: expected "completed", got "failed"',
      );
    });

    test('different array order', () {
      final mismatches = matcher.match(
        {
          'items': ['a', 'b'],
        },
        {
          'items': ['b', 'a'],
        },
      );
      expect(_paths(mismatches), [r'$.items[0]', r'$.items[1]']);
    });

    test('different array length', () {
      final mismatches = matcher.match(
        {
          'items': ['a'],
        },
        {
          'items': ['a', 'b'],
        },
      );
      expect(mismatches.single.path, r'$.items');
      expect(mismatches.single.message, contains('1 items, got 2'));
    });

    test('missing key', () {
      final actual = _toolUpdate();
      ((actual['params']! as Map)['update']! as Map).remove('status');
      final mismatches = matcher.match(_toolUpdate(), actual);
      expect(_paths(mismatches), [r'$.params.update.status']);
      expect(mismatches.single.message, contains('missing key'));
    });

    test('key order does not matter; int and double compare by value', () {
      expect(matcher.match({'a': 1, 'b': 2}, {'b': 2.0, 'a': 1}), isEmpty);
    });

    test('type mismatch', () {
      expect(
        matcher.match({'a': '1'}, {'a': 1}).single.toString(),
        r'$.a: expected "1", got 1',
      );
    });
  });

  group('matchers', () {
    test(r'$any requires the key with any value', () {
      expect(
        matcher.match(
          {
            'a': {r'$any': true},
          },
          {'a': null},
        ),
        isEmpty,
      );
      expect(
        matcher.match({
          'a': {r'$any': true},
        }, <String, Object?>{}),
        hasLength(1),
      );
    });

    test(r'$absent forbids the key', () {
      expect(
        matcher.match(
          {
            'a': 1,
            'b': {r'$absent': true},
          },
          {'a': 1},
        ),
        isEmpty,
      );
      expect(
        _paths(
          matcher.match(
            {
              'b': {r'$absent': true},
            },
            {'b': 2},
          ),
        ),
        [r'$.b'],
      );
    });

    test(r'$regex and $contains', () {
      expect(
        matcher.match(
          {
            'a': {r'$regex': r'^call_\d+$'},
          },
          {'a': 'call_7'},
        ),
        isEmpty,
      );
      expect(
        matcher.match(
          {
            'a': {r'$regex': r'^call_\d+$'},
          },
          {'a': 'x'},
        ),
        hasLength(1),
      );
      expect(
        matcher.match(
          {
            'a': {r'$contains': 'README'},
          },
          {'a': 'Edit README.md'},
        ),
        isEmpty,
      );
      expect(
        matcher.match(
          {
            'a': {r'$contains': 'README'},
          },
          {'a': 1},
        ),
        hasLength(1),
      );
    });

    test(r'$partial allows extra keys but not missing ones', () {
      final expected = {
        'a': {
          r'$partial': {'x': 1},
        },
      };
      expect(
        matcher.match(expected, {
          'a': {'x': 1, 'y': 2},
        }),
        isEmpty,
      );
      expect(
        _paths(
          matcher.match(expected, {
            'a': {'y': 2},
          }),
        ),
        [r'$.a.x'],
      );
    });

    test(r'$oneOf', () {
      final expected = {
        'kind': {
          r'$oneOf': ['allow_once', 'allow_always'],
        },
      };
      expect(matcher.match(expected, {'kind': 'allow_always'}), isEmpty);
      expect(
        matcher.match(expected, {'kind': 'reject_once'}).single.message,
        contains('one of'),
      );
    });

    test('_meta is always compared as partial', () {
      expect(
        matcher.match(
          {'a': 1},
          {
            'a': 1,
            '_meta': {
              'codelab': {'outcome': 'ok'},
            },
          },
        ),
        isEmpty,
      );
      expect(
        matcher.match(
          {
            '_meta': {'x': 1},
          },
          {
            '_meta': {'x': 1, 'y': 2},
          },
        ),
        isEmpty,
      );
      expect(
        _paths(
          matcher.match(
            {
              '_meta': {'x': 1},
            },
            {
              '_meta': {'y': 2},
            },
          ),
        ),
        [r'$._meta.x'],
      );
    });

    test('unknown matcher is a fixture error', () {
      expect(
        () => matcher.match(
          {
            'a': {r'$exists': true},
          },
          {'a': 1},
        ),
        throwsA(isA<FixtureMatchException>()),
      );
    });

    test(r'$text: concatenated content.text of repeated frames', () {
      Map<String, Object?> chunk(String text) => {
        'params': {
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': text},
          },
        },
      };
      expect(
        matcher.matchText('Заменю слово.', [chunk('Заменю '), chunk('слово.')]),
        isEmpty,
      );
      expect(
        matcher.matchText('Заменю слово.', [chunk('Заменю')]).single.message,
        contains('"Заменю"'),
      );
    });

    test('unordered: any assignment of actual to expected frames', () {
      expect(
        matcher.matchUnordered(
          [
            {'id': 1},
            {'id': 2},
          ],
          [
            {'id': 2},
            {'id': 1},
          ],
        ),
        isEmpty,
      );
      expect(
        matcher.matchUnordered(
          [
            {'id': 1},
            {'id': 2},
          ],
          [
            {'id': 2},
            {'id': 3},
          ],
        ),
        isNotEmpty,
      );
    });
  });

  group(r'$capture: agent request id', () {
    test('captured id is used for the client answer, not a literal', () {
      final request = {
        'jsonrpc': '2.0',
        'id': {r'$capture': 'permId'},
        'method': 'session/request_permission',
      };
      expect(
        matcher.match(request, {
          'jsonrpc': '2.0',
          'id': 'perm-7',
          'method': 'session/request_permission',
        }),
        isEmpty,
      );
      expect(matcher.variables['permId'], 'perm-7');

      final answer = {
        'jsonrpc': '2.0',
        'id': r'${permId}',
        'result': {
          'outcome': {'outcome': 'cancelled'},
        },
      };
      expect(
        matcher.match(answer, {
          'jsonrpc': '2.0',
          'id': 'perm-7',
          'result': {
            'outcome': {'outcome': 'cancelled'},
          },
        }),
        isEmpty,
      );
      expect(
        matcher
            .match(answer, {
              'jsonrpc': '2.0',
              'id': 'perm-8',
              'result': {
                'outcome': {'outcome': 'cancelled'},
              },
            })
            .single
            .path,
        r'$.id',
      );
    });

    test('a whole-string variable keeps its JSON type', () {
      matcher.match(
        {
          'id': {r'$capture': 'req'},
        },
        {'id': 3},
      );
      expect(matcher.match({'id': r'${req}'}, {'id': 3}), isEmpty);
    });

    test('a failed match does not commit captures', () {
      matcher.match(
        {
          'id': {r'$capture': 'x'},
          'method': 'a',
        },
        {'id': 5, 'method': 'b'},
      );
      expect(matcher.variables.containsKey('x'), isFalse);
    });

    test('unknown variable is a fixture error', () {
      expect(
        () => matcher.match({'id': r'${nope}'}, {'id': 1}),
        throwsA(isA<FixtureMatchException>()),
      );
    });
  });

  group('normalization', () {
    test(r'${sessionId} is substituted in expected frames', () {
      expect(
        matcher.match({'sessionId': r'${sessionId}'}, {'sessionId': 'sess-1'}),
        isEmpty,
      );
      expect(
        matcher.match({'sessionId': r'${sessionId}'}, {'sessionId': 'sess-2'}),
        hasLength(1),
      );
    });

    test(r'${cwd} matches the absolute cwd prefix of actual paths', () {
      expect(
        matcher.match(
          {'path': r'${cwd}/README.md'},
          {'path': '/work/demo/README.md'},
        ),
        isEmpty,
      );
      expect(
        matcher
            .match({'path': r'${cwd}/README.md'}, {'path': '/other/README.md'})
            .single
            .toString(),
        contains('/other/README.md'),
      );
    });

    test('path separators are normalized to "/"', () {
      final windows = FrameMatcher(cwd: r'C:\work\demo');
      expect(
        windows.match(
          {'path': r'${cwd}/src/main.dart'},
          {'path': r'C:\work\demo\src\main.dart'},
        ),
        isEmpty,
      );
    });

    test('<ts> accepts ISO-8601 strings and time fields', () {
      expect(
        matcher.match(
          {'updatedAt': '<ts>', 'at': '<ts>'},
          {'updatedAt': 'yesterday', 'at': '2026-10-23T08:00:00Z'},
        ),
        isEmpty,
      );
      expect(matcher.match({'at': '<ts>'}, {'at': 'not a time'}), hasLength(1));
    });

    test('normalize.replace applies to both sides at its path', () {
      final withRule = FrameMatcher(
        cwd: '/work/demo',
        replace: [
          FixtureReplaceRule(
            path: r'$.params.text',
            regex: RegExp(r'\d+ мс'),
            replacement: '<N> мс',
          ),
        ],
      );
      expect(
        withRule.match(
          {
            'params': {'text': 'Готово за <N> мс'},
          },
          {
            'params': {'text': 'Готово за 42 мс'},
          },
        ),
        isEmpty,
      );
      expect(
        withRule.match({'other': 'за <N> мс'}, {'other': 'за 42 мс'}),
        hasLength(1),
      );
    });
  });

  group('materialize: a2c template to a concrete frame', () {
    test('matchers give concrete values', () {
      final frame = matcher.materialize({
        'id': {r'$capture': 'permId'},
        'path': r'${cwd}/README.md',
        'sessionId': r'${sessionId}',
        'title': {r'$contains': 'README.md'},
        'kind': {
          r'$oneOf': ['edit', 'read'],
        },
        'name': {r'$any': true},
        'availableCommands': {r'$any': <Object?>[]},
        'meta': {
          r'$partial': {'a': 1},
        },
        'gone': {r'$absent': true},
        'updatedAt': '<ts>',
      });

      expect(frame, {
        'id': 'fixture-permId',
        'path': '/work/demo/README.md',
        'sessionId': 'sess-1',
        'title': 'README.md',
        'kind': 'edit',
        'name': 'fixture-any',
        'availableCommands': <Object?>[],
        'meta': {'a': 1},
        'updatedAt': fixtureTimestamp,
      });
      expect(matcher.variables['permId'], 'fixture-permId');
    });

    test(r'the $any sample is materialized with variables', () {
      expect(
        matcher.materialize({
          'content': {
            r'$any': [
              {'terminalId': r'${sessionId}'},
            ],
          },
        }),
        {
          'content': [
            {'terminalId': 'sess-1'},
          ],
        },
      );
    });

    test(r'$any with a sample still matches any value', () {
      expect(
        matcher.match(
          {
            'list': {r'$any': <Object?>[]},
          },
          {
            'list': ['x'],
          },
        ),
        isEmpty,
      );
    });

    test(r'$regex cannot be materialized', () {
      expect(
        () => matcher.materialize({
          'a': {r'$regex': 'x'},
        }),
        throwsA(isA<FixtureMatchException>()),
      );
    });
  });
}
