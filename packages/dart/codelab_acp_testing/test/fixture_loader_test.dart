import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

Map<String, Object?> _minimalFixture({String id = 'acp/minimal'}) => {
  'id': id,
  'spec': ['05-Prompt Turn.md#1-user-message'],
  'description': 'Минимальная фикстура для теста загрузчика.',
  'setup': {'cwd': '/work/demo'},
  'frames': [
    {
      'dir': 'c2a',
      'frame': {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'session/prompt',
        'params': {
          'sessionId': r'${sessionId}',
          'prompt': [
            {'type': 'text', 'text': 'Привет'},
          ],
        },
      },
    },
    {
      'dir': 'a2c',
      'frame': {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'stopReason': 'end_turn'},
      },
    },
  ],
};

Map<String, Object?> _deepCopy(Map<String, Object?> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, Object?>;

Matcher _formatError({required String path, String? message}) =>
    isA<FixtureFormatException>()
        .having((e) => e.path, 'path', path)
        .having(
          (e) => e.message,
          'message',
          message == null ? anything : contains(message),
        );

void main() {
  group('AcpFixture.fromJson rejects an incomplete fixture loudly', () {
    AcpFixture parse(Map<String, Object?> json, {String file = 'minimal'}) =>
        AcpFixture.fromJson(json, fileName: '$file.json');

    for (final field in ['id', 'spec', 'description', 'setup', 'frames']) {
      test('missing required field "$field"', () {
        final json = _minimalFixture()..remove(field);
        expect(
          () => parse(json),
          throwsA(_formatError(path: '\$.$field', message: 'required')),
        );
      });
    }

    test('empty spec', () {
      final json = _minimalFixture()..['spec'] = <Object?>[];
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.spec', message: 'non-empty')),
      );
    });

    test('id does not match the file name', () {
      expect(
        () => parse(_minimalFixture(), file: 'other'),
        throwsA(_formatError(path: r'$.id', message: 'acp/other')),
      );
    });

    test('unknown top-level key', () {
      final json = _minimalFixture()..['comment'] = 'x';
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.comment', message: 'unknown key')),
      );
    });

    test('unknown setup key', () {
      final json = _deepCopy(_minimalFixture());
      (json['setup']! as Map<String, Object?>)['workdir'] = '/x';
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.setup.workdir', message: 'unknown key')),
      );
    });

    test('invalid frame dir', () {
      final json = _deepCopy(_minimalFixture());
      ((json['frames']! as List)[1] as Map<String, Object?>)['dir'] = 'up';
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.frames[1].dir', message: '"up"')),
      );
    });

    test('frame with both frame and unordered', () {
      final json = _deepCopy(_minimalFixture());
      ((json['frames']! as List)[0] as Map<String, Object?>)['unordered'] = [
        <String, Object?>{},
      ];
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.frames[0]', message: 'exactly one')),
      );
    });

    test('match without repeat', () {
      final json = _deepCopy(_minimalFixture());
      ((json['frames']! as List)[1] as Map<String, Object?>)['match'] = {
        r'$text': 'x',
      };
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.frames[1].match', message: 'repeat')),
      );
    });

    test('invalid roles value', () {
      final json = _minimalFixture()..['roles'] = ['server'];
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.roles[0]', message: '"server"')),
      );
    });

    test('empty roles', () {
      final json = _minimalFixture()..['roles'] = <Object?>[];
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.roles', message: 'non-empty')),
      );
    });

    test('duplicate roles', () {
      final json = _minimalFixture()..['roles'] = ['client', 'client'];
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.roles', message: 'duplicate')),
      );
    });

    test('invalid llm step stopReason', () {
      final json = _minimalFixture()
        ..['llm'] = {
          'steps': [
            {
              'reply': [
                {'text': 'ok'},
              ],
              'stopReason': 'end_turn',
            },
          ],
        };
      expect(
        () => parse(json),
        throwsA(
          _formatError(
            path: r'$.llm.steps[0].stopReason',
            message: '"end_turn"',
          ),
        ),
      );
    });

    test('unknown llm step key', () {
      final json = _minimalFixture()
        ..['llm'] = {
          'steps': [
            {'answer': 'ok', 'stopReason': 'stop'},
          ],
        };
      expect(
        () => parse(json),
        throwsA(
          _formatError(path: r'$.llm.steps[0].answer', message: 'unknown key'),
        ),
      );
    });

    test('llm reply block with two kinds', () {
      final json = _minimalFixture()
        ..['llm'] = {
          'steps': [
            {
              'reply': [
                {'text': 'a', 'thinking': 'b'},
              ],
              'stopReason': 'stop',
            },
          ],
        };
      expect(
        () => parse(json),
        throwsA(
          _formatError(
            path: r'$.llm.steps[0].reply[0]',
            message: 'exactly one',
          ),
        ),
      );
    });

    test('llm step with both reply and error', () {
      final json = _minimalFixture()
        ..['llm'] = {
          'steps': [
            {
              'reply': [
                {'text': 'a'},
              ],
              'error': {'class': 'auth', 'message': '401'},
              'stopReason': 'error',
            },
          ],
        };
      expect(
        () => parse(json),
        throwsA(_formatError(path: r'$.llm.steps[0]', message: 'reply')),
      );
    });

    test('error message names the file and the field path', () {
      final json = _minimalFixture()..remove('description');
      expect(
        () => parse(json),
        throwsA(
          isA<FixtureFormatException>().having(
            (e) => e.toString(),
            'toString',
            allOf(contains('minimal.json'), contains(r'$.description')),
          ),
        ),
      );
    });
  });

  group('AcpFixture.fromJson loads a complete fixture', () {
    test('typed model with default roles', () {
      final fixture = AcpFixture.fromJson(
        _minimalFixture(),
        fileName: 'minimal.json',
      );

      expect(fixture.id, 'acp/minimal');
      expect(fixture.spec, ['05-Prompt Turn.md#1-user-message']);
      expect(fixture.roles, {FixtureRole.agent, FixtureRole.client});
      expect(fixture.goals, isEmpty);
      expect(fixture.extensions, isEmpty);
      expect(fixture.setup.cwd, '/work/demo');
      expect(fixture.setup.skipInitialize, isFalse);
      expect(fixture.frames, hasLength(2));
      expect(fixture.frames[0].direction, FrameDirection.c2a);
      expect(fixture.frames[0].index, 0);
      expect(fixture.frames[1].direction, FrameDirection.a2c);
      expect(fixture.frames[1].frame, containsPair('id', 2));
      expect(fixture.llm, isNull);
      expect(fixture.after, isNull);
    });

    test('optional blocks are parsed', () {
      final json = _minimalFixture()
        ..['goals'] = ['C-01']
        ..['extensions'] = ['outcome']
        ..['roles'] = ['client']
        ..['setup'] = {
          'cwd': '/work/demo',
          'files': {'README.md': '# foo\n'},
          'mode': 'standard',
          'terminal': {
            'ls -la': {'output': 'README.md\n', 'exitCode': 0},
          },
          'skipInitialize': true,
        }
        ..['llm'] = {
          'model': {'provider': 'scripted', 'modelId': 'scripted-1'},
          'steps': [
            {
              'expect': {
                'lastMessage': {'role': 'user', r'$textContains': 'README'},
              },
              'reply': [
                {'text': 'ok'},
                {
                  'toolCall': {
                    'id': 'call_1',
                    'name': 'read',
                    'arguments': {'path': 'README.md'},
                  },
                },
              ],
              'stopReason': 'toolUse',
            },
          ],
        }
        ..['normalize'] = {
          'replace': [
            {
              'path': r'$.params.update.content.text',
              'regex': r'\d+ мс',
              'with': '<N> мс',
            },
          ],
        }
        ..['after'] = {
          'files': {'README.md': '# bar\n'},
        };

      final fixture = AcpFixture.fromJson(json, fileName: 'minimal.json');

      expect(fixture.goals, ['C-01']);
      expect(fixture.extensions, ['outcome']);
      expect(fixture.roles, {FixtureRole.client});
      expect(fixture.setup.files, {'README.md': '# foo\n'});
      expect(fixture.setup.mode, 'standard');
      expect(fixture.setup.skipInitialize, isTrue);
      expect(fixture.setup.terminal['ls -la']?.output, 'README.md\n');
      expect(fixture.setup.terminal['ls -la']?.exitCode, 0);
      expect(fixture.llm?.steps.single.stopReason, 'toolUse');
      expect(fixture.normalize.replace.single.replacement, '<N> мс');
      expect(fixture.after?.files, {'README.md': '# bar\n'});
    });
  });

  group('loadFixtureCorpus', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('acp_fixture_corpus_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('loads every fixture file sorted by id and skips _schema.json', () {
      File(
        '${dir.path}/b-second.json',
      ).writeAsStringSync(jsonEncode(_minimalFixture(id: 'acp/b-second')));
      File(
        '${dir.path}/a-first.json',
      ).writeAsStringSync(jsonEncode(_minimalFixture(id: 'acp/a-first')));
      File('${dir.path}/_schema.json').writeAsStringSync('{}');

      final corpus = loadFixtureCorpus(directory: dir.path);

      expect(corpus.map((f) => f.id), ['acp/a-first', 'acp/b-second']);
      expect(corpus.first.sourcePath, endsWith('a-first.json'));
    });

    test('invalid JSON fails with the file name', () {
      File('${dir.path}/broken.json').writeAsStringSync('{');

      expect(
        () => loadFixtureCorpus(directory: dir.path),
        throwsA(
          isA<FixtureFormatException>().having(
            (e) => e.toString(),
            'toString',
            contains('broken.json'),
          ),
        ),
      );
    });

    test('subdirectories are rejected: the corpus is flat', () {
      Directory('${dir.path}/group').createSync();

      expect(
        () => loadFixtureCorpus(directory: dir.path),
        throwsA(isA<FixtureFormatException>()),
      );
    });

    test('default directory is the package corpus', () {
      expect(
        defaultFixtureCorpusDirectory(),
        endsWith('codelab_acp_testing/fixtures/acp'),
      );
    });
  });
}
