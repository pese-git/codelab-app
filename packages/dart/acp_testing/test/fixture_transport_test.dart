import 'dart:convert';

import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

/// Транспортные фикстуры (acp-golden-fixtures «Формат golden-фикстуры
/// ACP»; design.md change `add-codelab-agent-binary`, D8): блок
/// `setup.transport` и генератор строки `$repeat`.
void main() {
  Map<String, Object?> fixture(Map<String, Object?> setup) => {
    'id': 'acp/transport',
    'spec': ['16-Transports.md#stdio'],
    'description': 'Транспортная фикстура для теста загрузчика.',
    'roles': ['agent'],
    'setup': {'cwd': '/work/demo', ...setup},
    'frames': <Object?>[],
  };

  AcpFixture parse(Map<String, Object?> json) =>
      AcpFixture.fromJson(json, fileName: 'transport.json');

  group('setup.transport', () {
    test('stdio', () {
      final transport = parse(
        fixture({
          'transport': {'kind': 'stdio'},
        }),
      ).setup.transport!;
      expect(transport.kind, FixtureTransportKind.stdio);
      expect(transport.attempts, isEmpty);
    });

    test('ws with attempts in order', () {
      final transport = parse(
        fixture({
          'transport': {
            'kind': 'ws',
            'attempts': [
              {'authorization': 'none', 'expectStatus': 401},
              {'authorization': 'wrong', 'expectStatus': 401},
            ],
          },
        }),
      ).setup.transport!;
      expect(transport.kind, FixtureTransportKind.ws);
      expect(
        [for (final a in transport.attempts) (a.authorization, a.expectStatus)],
        [(FixtureAuthorization.none, 401), (FixtureAuthorization.wrong, 401)],
      );
    });

    test('no transport block — in-memory run', () {
      expect(parse(fixture(const {})).setup.transport, isNull);
    });

    test('an unknown kind fails loudly with the field path', () {
      expect(
        () => parse(
          fixture({
            'transport': {'kind': 'pipe'},
          }),
        ),
        throwsA(
          isA<FixtureFormatException>().having(
            (e) => e.path,
            'path',
            r'$.setup.transport.kind',
          ),
        ),
      );
    });

    test('attempts only with ws', () {
      expect(
        () => parse(
          fixture({
            'transport': {
              'kind': 'stdio',
              'attempts': [
                {'authorization': 'none', 'expectStatus': 401},
              ],
            },
          }),
        ),
        throwsA(isA<FixtureFormatException>()),
      );
    });

    test('an unknown attempt key fails loudly', () {
      expect(
        () => parse(
          fixture({
            'transport': {
              'kind': 'ws',
              'attempts': [
                {'authorization': 'none', 'status': 401},
              ],
            },
          }),
        ),
        throwsA(isA<FixtureFormatException>()),
      );
    });
  });

  group(r'$repeat', () {
    late FrameMatcher matcher;

    setUp(() {
      matcher = FrameMatcher(cwd: '/work/demo');
    });

    const repeat = {
      r'$repeat': {'text': 'ab', 'times': 3},
    };

    test('materializes in a c2a frame', () {
      expect(matcher.materialize({'text': repeat}), {'text': 'ababab'});
    });

    test('matches the exact string in an a2c frame', () {
      expect(matcher.match({'text': repeat}, {'text': 'ababab'}), isEmpty);
      final mismatches = matcher.match({'text': repeat}, {'text': 'abab'});
      expect(mismatches.single.path, r'$.text');
      // Мегабайтная строка не печатается в отчёт целиком.
      expect(mismatches.single.toString().length, lessThan(200));
    });

    test('a malformed generator is a fixture error', () {
      expect(
        () => matcher.materialize({
          r'$repeat': {'text': 'a'},
        }),
        throwsA(isA<FixtureMatchException>()),
      );
    });

    test('expandRepeat expands only generators in an llm block', () {
      final llm = {
        'steps': [
          {
            'reply': [
              {'text': r'in ${cwd}'},
              {
                'toolCall': {
                  'arguments': {'content': repeat},
                },
              },
            ],
          },
        ],
      };
      expect(
        jsonEncode(expandRepeat(llm)),
        jsonEncode({
          'steps': [
            {
              'reply': [
                {'text': r'in ${cwd}'},
                {
                  'toolCall': {
                    'arguments': {'content': 'ababab'},
                  },
                },
              ],
            },
          ],
        }),
      );
    });
  });
}
