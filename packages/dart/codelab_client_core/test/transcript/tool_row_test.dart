// Строка инструмента без сырого JSON (spec acp-client-kit «Строка
// инструмента без сырого JSON»; `dart-agent-and-clients` §12.1.6; tasks 1.2,
// 1.3 change `redesign-transcript-rows`).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

ToolRowView _format(
  ToolKind kind, {
  String title = '',
  Map<String, Object?>? rawInput,
  List<String> paths = const [],
  List<String> textOutput = const [],
  ToolCallStatusView status = ToolCallStatusView.succeeded,
  String cwd = '/work/app',
}) => ToolRowFormatter.format(
  ToolCallItem(
    id: 'tool-1',
    toolCallId: const ToolCallId('call-1'),
    title: title,
    details: ToolCallView(
      kind: kind,
      status: status,
      rawInput: rawInput,
      paths: paths,
      textOutput: textOutput,
    ),
  ),
  cwd: cwd,
);

void main() {
  group('scenarios of the spec', () {
    test('a multi-line command collapses into one line', () {
      expect(
        _format(
          ToolKind.execute,
          rawInput: {'command': 'npm test --\n  --watch=false'},
        ),
        const ToolRowView(label: 'Run', detail: 'npm test -- --watch=false'),
      );
    });

    test('a read range inside the project is relative to cwd', () {
      expect(
        _format(
          ToolKind.read,
          rawInput: {'path': '/work/app/lib/a.dart', 'offset': 10, 'limit': 20},
        ),
        const ToolRowView(label: 'Read', detail: 'lib/a.dart:10-29'),
      );
    });

    test('a URL loses its scheme and query string', () {
      final row = _format(
        ToolKind.fetch,
        rawInput: {'url': 'https://example.com/docs?token=abc'},
      );

      expect(
        row,
        const ToolRowView(label: 'Fetch', detail: 'example.com/docs'),
      );
      expect(row.toString(), isNot(contains('token=abc')));
    });

    test('a URL loses its userinfo', () {
      final row = _format(
        ToolKind.fetch,
        rawInput: {'url': 'https://user:pass@example.com/x?t=1'},
      );

      expect(row, const ToolRowView(label: 'Fetch', detail: 'example.com/x'));
      expect(row.toString(), isNot(contains('user')));
      expect(row.toString(), isNot(contains('pass')));
    });

    test('a password with @ is dropped up to the last @', () {
      final row = _format(
        ToolKind.fetch,
        rawInput: {'url': 'https://user:p@ss@example.com/x'},
      );

      expect(row, const ToolRowView(label: 'Fetch', detail: 'example.com/x'));
      expect(row.toString(), isNot(contains('user')));
      expect(row.toString(), isNot(contains('p@ss')));
      expect(row.toString(), isNot(contains('ss@')));
    });

    test('an @ in the path is kept', () {
      expect(
        _format(ToolKind.fetch, rawInput: {'url': 'https://example.com/a@b'}),
        const ToolRowView(label: 'Fetch', detail: 'example.com/a@b'),
      );
    });

    test('a URL without a scheme loses its userinfo', () {
      final row = _format(
        ToolKind.fetch,
        rawInput: {'url': 'user:pass@example.com/x'},
      );

      expect(row, const ToolRowView(label: 'Fetch', detail: 'example.com/x'));
      expect(row.toString(), isNot(contains('pass')));
    });

    test('other URL shapes keep only host and path', () {
      const cases = {
        'https://ghp_token@github.com/org/repo': 'github.com/org/repo',
        'https://example.com?u=a@b': 'example.com',
        'ssh://git@host/repo': 'host/repo',
        'https://example.com#a@b': 'example.com',
        // Ведущие слэши снимаются, пустая authority не роняет форматирование.
        '/docs/a@b': 'docs/a@b',
        'https:///x': 'x',
        // `\` границей authority не считается: по RFC 3986 `h\a` — userinfo,
        // поэтому показываем меньше, а не больше (D2).
        r'https://h\a@b/x': 'b/x',
        // Двоеточие порта без слэша — не схема.
        'localhost:8080/x': 'localhost:8080/x',
      };
      for (final MapEntry(key: url, value: detail) in cases.entries) {
        expect(
          _format(ToolKind.fetch, rawInput: {'url': url}),
          ToolRowView(label: 'Fetch', detail: detail),
          reason: url,
        );
      }
    });

    test('unusual spellings of a URL do not leak userinfo', () {
      // Записи, которые парсер WHATWG (Node) или RFC 3986 (Python `urllib`,
      // `requests`) принимает за адрес с userinfo, и пробелы по краям —
      // юникодные и вперемешку с управляющими символами; design.md D2.
      const urls = [
        '//user:pass@host/x',
        ' https://user:pass@host/x',
        '\nhttps://user:pass@host/x',
        'ht\ttps://user:pass@host/x',
        'https:///user:pass@host/x',
        'https:/user:pass@host/x',
        r'https:/\user:pass@host/x',
        r'https:\\user:pass@host/x',
        'https:user:pass@host/x',
        r'https://h\user:pass@host/x',
        '\u00A0https://user:pass@host/x',
        '\uFEFFhttps://user:pass@host/x',
        '\u3000//user:pass@host/x',
        'https:// /user:pass@host/x',
        ' / /user:pass@host/x',
        '\x01\u00A0https://user:pass@host/x',
      ];
      for (final url in urls) {
        final row = _format(ToolKind.fetch, rawInput: {'url': url});
        expect(
          row,
          const ToolRowView(label: 'Fetch', detail: 'host/x'),
          reason: url,
        );
        expect(row.toString(), isNot(contains('pass')), reason: url);
      }
    });

    test('a tool without scalar fields shows no JSON', () {
      expect(
        _format(
          ToolKind.other,
          title: 'mcp__db__stats',
          rawInput: {
            'items': [1, 2],
          },
        ),
        const ToolRowView(label: 'mcp__db__stats'),
      );
    });
  });

  group('details by kind', () {
    test('a location wins over rawInput.path', () {
      expect(
        _format(
          ToolKind.read,
          paths: ['/work/app/lib/main.dart'],
          rawInput: {'path': 'other.dart'},
        ).detail,
        'lib/main.dart',
      );
    });

    test('a path outside cwd stays absolute', () {
      expect(
        _format(ToolKind.edit, paths: ['/etc/hosts']).detail,
        '/etc/hosts',
      );
    });

    test('several edited files show how many more', () {
      expect(
        _format(
          ToolKind.edit,
          paths: ['/work/app/a.dart', '/work/app/b.dart', '/work/app/c.dart'],
        ).detail,
        'a.dart +2',
      );
    });

    test('a move shows both ends', () {
      expect(
        _format(
          ToolKind.move,
          paths: ['/work/app/old.dart', '/work/app/new.dart'],
        ).detail,
        'old.dart → new.dart',
      );
    });

    test('a search shows the pattern, folder and glob', () {
      expect(
        _format(
          ToolKind.search,
          rawInput: {
            'pattern': 'login',
            'path': '/work/app/lib',
            'glob': '*.dart',
          },
        ).detail,
        '"login" in lib (*.dart)',
      );
    });

    test('a command given as a list is joined with spaces', () {
      expect(
        _format(
          ToolKind.execute,
          rawInput: {
            'command': ['git', 'status'],
          },
        ).detail,
        'git status',
      );
    });

    test('think shows the agent and the description', () {
      expect(
        _format(
          ToolKind.think,
          rawInput: {'agent': 'explore', 'description': 'Find auth code'},
        ),
        const ToolRowView(label: 'Think', detail: 'explore: Find auth code'),
      );
    });
  });

  group('safety and fallbacks', () {
    test('a secret in the command is masked', () {
      final detail = _format(
        ToolKind.execute,
        rawInput: {
          'command':
              'curl -H "Authorization: Bearer sk-abcdefghijklmnopqrstuvwx"',
        },
      ).detail;

      expect(detail, isNot(contains('sk-abcdefghijklmnopqrstuvwx')));
    });

    test('control characters become spaces', () {
      expect(
        _format(
          ToolKind.execute,
          rawInput: {'command': 'echo\u001b[31m red\u0007'},
        ).detail,
        'echo red',
      );
    });

    test('a long detail is cut to 160 characters with an ellipsis', () {
      final detail = _format(
        ToolKind.execute,
        rawInput: {'command': 'x' * 400},
      ).detail;

      expect(detail.length, ToolRowFormatter.maxDetailLength);
      expect(detail, endsWith('…'));
    });

    test('an empty detail falls back to the title without the label', () {
      expect(
        _format(ToolKind.read, title: 'Read lib/main.dart').detail,
        'lib/main.dart',
      );
    });

    test('a title repeating the label loses the repeated word', () {
      expect(_format(ToolKind.execute, title: 'Run build').detail, 'build');
    });

    test('a command without rawInput uses the title', () {
      expect(
        _format(ToolKind.execute, title: 'echo running tests').detail,
        'echo running tests',
      );
    });
  });

  group('secondary line', () {
    test('a failed call shows the first line of its text output', () {
      expect(
        _format(
          ToolKind.read,
          paths: ['/work/app/lib/main.dart'],
          status: ToolCallStatusView.failed,
          textOutput: ['\nFile not found: lib/main.dart\nmore'],
        ).secondary,
        'File not found: lib/main.dart',
      );
    });

    test('a completed call has no secondary line', () {
      expect(
        _format(ToolKind.read, textOutput: ['contents']).secondary,
        isNull,
      );
    });

    // change `redact-tool-row-text`, D1, D3.
    test('a failed fetch hides the credentials of an address in the error', () {
      final secondary = _format(
        ToolKind.fetch,
        status: ToolCallStatusView.failed,
        textOutput: [
          'Error: request to https://user:pass@host/x failed\n'
              '    at fetch (node:internal)',
        ],
      ).secondary;

      expect(secondary, 'Error: request to https://<redacted>@host/x failed');
      expect(secondary, isNot(contains('user:pass')));
      expect(secondary, isNot(contains('pass@')));
    });

    test('control characters of the second line become spaces', () {
      expect(
        _format(
          ToolKind.read,
          status: ToolCallStatusView.failed,
          textOutput: ['\u001b[31mError:\tboom\u001b[0m'],
        ).secondary,
        'Error: boom',
      );
    });

    test('a line of control characters only is skipped', () {
      expect(
        _format(
          ToolKind.read,
          status: ToolCallStatusView.failed,
          textOutput: ['\u001b[0m\nreal error'],
        ).secondary,
        'real error',
      );
      expect(
        _format(
          ToolKind.read,
          status: ToolCallStatusView.failed,
          textOutput: ['\u001b[0m'],
        ).secondary,
        isNull,
      );
    });

    test('a long second line is truncated after masking', () {
      final secondary = _format(
        ToolKind.fetch,
        status: ToolCallStatusView.failed,
        // Адрес целиком помещается до предела, усечение приходится на хвост
        // после него: маска уже наложена, `@` на месте.
        textOutput: ['${'a' * 130} https://user:password@host/x/${'b' * 40}'],
      ).secondary!;

      expect(secondary, hasLength(ToolRowFormatter.maxDetailLength));
      expect(secondary, endsWith('…'));
      expect(secondary, contains('https://<redacted>@'));
      expect(secondary, isNot(contains('user')));
      expect(secondary, isNot(contains('passw')));
    });

    test('the second line of a failed agent call is masked', () {
      final row = ToolRowFormatter.format(
        const ToolCallItem(
          id: 'tool-1',
          toolCallId: ToolCallId('call-1'),
          title: 'Subagent explore: Map callers',
          details: ToolCallView(
            kind: ToolKind.think,
            status: ToolCallStatusView.failed,
            subagentCall: SubagentCallView(id: 'sub_a1', type: 'explore'),
            textOutput: ['auth failed for https://user:pass@host/x'],
          ),
        ),
        cwd: '/work/app',
      );

      expect(row.secondary, 'auth failed for https://<redacted>@host/x');
    });
  });

  // Смена режима и вызов незнакомого вида (change `tolerate-unknown-tool-kind`,
  // D7; acp-client-kit «Строка инструмента без сырого JSON»).
  group('mode switch and unknown kind', () {
    test('a mode switch shows the Mode label and the title as detail', () {
      expect(
        _format(ToolKind.switchMode, title: 'Ready for implementation'),
        const ToolRowView(label: 'Mode', detail: 'Ready for implementation'),
      );
    });

    test('a call of kind other is labelled by its title with no detail', () {
      expect(
        _format(ToolKind.other, title: 'Plan sync'),
        const ToolRowView(label: 'Plan sync'),
      );
    });

    // change `redact-tool-row-text`, D2.
    test('the label of a call of kind other hides credentials', () {
      final row = _format(
        ToolKind.other,
        title: 'curl https://user:pass@host/x',
      );

      expect(row, const ToolRowView(label: 'curl https://<redacted>@host/x'));
      expect(row.label, isNot(contains('pass')));
    });

    test('the label of a call of kind other has no control characters', () {
      final row = _format(ToolKind.other, title: 'mcp\u001b[2J__db__stats');

      expect(row.label, isNot(contains('\u001b')));
      expect(row.detail, isEmpty);
    });

    test('a title with a secret of an unknown wire kind is masked', () {
      // Незнакомый wire-вид проекция читает как `other` (D7 change
      // `tolerate-unknown-tool-kind`).
      final row = _format(
        ToolKind.fromJson('future_kind'),
        title: 'sync Authorization: Bearer t0k3n-value',
      );

      expect(row.label, isNot(contains('t0k3n-value')));
      expect(row.detail, isEmpty);
    });

    test('no row exposes wire names of kinds', () {
      for (final row in [
        _format(ToolKind.switchMode, title: 'Ready for implementation'),
        _format(ToolKind.other, title: 'Plan sync'),
      ]) {
        final text = '${row.label} ${row.detail} ${row.secondary ?? ''}';
        expect(text, isNot(contains('switch_mode')));
        expect(text, isNot(contains('future_kind')));
      }
    });
  });

  // change `redact-tool-row-text`, D7; acp-client-kit «Хвост вывода строки
  // инструмента».
  group('output tail', () {
    ToolCallItem item({
      required List<String> textOutput,
      ToolCallStatusView status = ToolCallStatusView.succeeded,
      ToolKind kind = ToolKind.read,
      SubagentCallView? subagentCall,
    }) => ToolCallItem(
      id: 'tool-1',
      toolCallId: const ToolCallId('call-1'),
      title: 'x',
      details: ToolCallView(
        kind: kind,
        status: status,
        textOutput: textOutput,
        subagentCall: subagentCall,
      ),
    );

    test('secrets are masked and line breaks are kept', () {
      expect(
        ToolRowFormatter.outputTail(
          item(
            textOutput: [
              'line 1\nDATABASE_URL=postgres://user:pass@db/app\nline 3',
            ],
          ),
          maxLines: 20,
        ),
        'line 1\nDATABASE_URL=postgres://<redacted>@db/app\nline 3',
      );
    });

    // change `redact-tool-row-text`, D7: секрет, начавшийся выше границы
    // хвоста, не выходит в хвост открытой частью.
    test('a private key cut by the tail boundary is masked to its END', () {
      final key = [
        '-----BEGIN RSA PRIVATE KEY-----',
        for (var i = 1; i <= 25; i++) 'body-line-$i',
        '-----END RSA PRIVATE KEY-----',
      ];

      final tail = ToolRowFormatter.outputTail(
        item(textOutput: ['${key.join('\n')}\ndone']),
        maxLines: 20,
      )!;

      expect(tail, isNot(contains('body-line')));
      expect(tail, contains('<redacted>'));
      expect(tail, endsWith('done'));
    });

    test('a token on the next line after Bearer at the boundary is masked', () {
      final tail = ToolRowFormatter.outputTail(
        item(textOutput: ['l1\nAuthorization: Bearer\ntok3n-value\nl4\nl5']),
        maxLines: 3,
      )!;

      expect(tail, isNot(contains('tok3n-value')));
      expect(tail.split('\n'), hasLength(lessThanOrEqualTo(3)));
      expect(tail, endsWith('l4\nl5'));
    });

    test('a value on the line after "password:" at the boundary is masked', () {
      final tail = ToolRowFormatter.outputTail(
        item(textOutput: ['l1\npassword:\nhunter2\nl4\nl5']),
        maxLines: 3,
      )!;

      expect(tail, isNot(contains('hunter2')));
      expect(tail, endsWith('l4\nl5'));
    });

    // spec «Токен на границе хвоста».
    test('Bearer one line above the tail start masks the token', () {
      final tail = ToolRowFormatter.outputTail(
        item(
          textOutput: [
            'ok1\nok2\nok3\nok4\nAuthorization: Bearer\nt0k3n-value\n'
                'ok7\nok8\nok9\nok10',
          ],
        ),
        maxLines: 5,
      )!;

      expect(tail, isNot(contains('t0k3n-value')));
      expect(tail, contains('<redacted>'));
      expect(tail, endsWith('ok10'));
      expect(tail.split('\n'), hasLength(lessThanOrEqualTo(5)));
    });

    // spec «Приватный ключ длиннее хвоста».
    test('a private key longer than the tail leaves only the mask', () {
      final text = [
        '-----BEGIN RSA PRIVATE KEY-----',
        for (var i = 1; i <= 40; i++) 'MIIEow$i',
        '-----END RSA PRIVATE KEY-----',
        'done',
      ].join('\n');

      final tail = ToolRowFormatter.outputTail(
        item(textOutput: [text]),
        maxLines: 20,
      )!;

      expect(tail, isNot(contains('MIIEow')));
      expect(tail, contains('<redacted>'));
      expect(tail, endsWith('done'));
    });

    test('an END without BEGIN keeps the lines after it', () {
      final text = [
        for (var i = 1; i <= 30; i++) 'key-body-$i',
        '-----END RSA PRIVATE KEY-----',
        'after-1',
        'after-2',
      ].join('\n');

      final tail = ToolRowFormatter.outputTail(
        item(textOutput: [text]),
        maxLines: 10,
      )!;

      expect(tail, isNot(contains('key-body')));
      expect(tail, isNot(contains('PRIVATE KEY')));
      expect(tail, endsWith('after-1\nafter-2'));
    });

    // Незакрытый PEM: `head -n 10 ~/.ssh/id_rsa` или поток ещё идёт.
    test('a BEGIN without END masks everything to the end of the window', () {
      final tail = ToolRowFormatter.outputTail(
        item(
          textOutput: [
            'before\n-----BEGIN OPENSSH PRIVATE KEY-----\nbody-1\nbody-2',
          ],
        ),
        maxLines: 10,
      );

      expect(tail, 'before\n<redacted>');
    });

    test('a key that is still streaming is not shown', () {
      final tail = ToolRowFormatter.outputTail(
        item(
          textOutput: [
            'ok\n-----BEGIN RSA PRIVATE KEY-----\nMIIEow-1',
            'MIIEow-2\nMIIEow-3',
          ],
        ),
        maxLines: 10,
      )!;

      expect(tail, isNot(contains('MIIEow')));
      expect(tail, startsWith('ok\n'));
    });

    test('BEGIN and END both in the window are masked as a pair', () {
      final tail = ToolRowFormatter.outputTail(
        item(
          textOutput: [
            'before\n-----BEGIN PRIVATE KEY-----\nsecret-body\n'
                '-----END PRIVATE KEY-----\nafter',
          ],
        ),
        maxLines: 10,
      );

      expect(tail, 'before\n<redacted>\nafter');
    });

    test('a 5 MB output does not make the tail slow', () {
      final big = StringBuffer();
      for (var i = 0; i < 5 * 1024 * 1024 ~/ 4; i++) {
        big.write('row\n');
      }
      for (var i = 1; i <= 20; i++) {
        big.write('end $i\n');
      }
      final call = item(textOutput: [big.toString()]);

      final watch = Stopwatch()..start();
      final tail = ToolRowFormatter.outputTail(call, maxLines: 20);
      watch.stop();

      expect(tail, [for (var i = 1; i <= 20; i++) 'end $i'].join('\n'));
      // Бюджет — как у тестов линейности `secret_redaction_test.dart`; сам
      // вывод не разбивается и не копируется (D7, п. 2).
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('one huge element gives exactly its last lines', () {
      final big = [for (var i = 1; i <= 10000; i++) 'row $i'].join('\n');

      expect(
        ToolRowFormatter.outputTail(item(textOutput: [big]), maxLines: 2),
        'row 9999\nrow 10000',
      );
    });

    test('trailing blank space of the output is not part of the tail', () {
      expect(
        ToolRowFormatter.outputTail(
          item(textOutput: ['a\nb\n\n  \n', '', ' \n']),
          maxLines: 5,
        ),
        'a\nb',
      );
    });

    test('the last maxLines lines are taken', () {
      final lines = [for (var i = 1; i <= 30; i++) 'line $i'];

      final tail = ToolRowFormatter.outputTail(
        item(textOutput: [lines.join('\n')]),
        maxLines: 20,
      );

      expect(tail, [for (var i = 11; i <= 30; i++) 'line $i'].join('\n'));
    });

    test('the tail boundary may pass inside an element', () {
      final tail = ToolRowFormatter.outputTail(
        item(textOutput: ['a1\na2\na3', 'b1\nb2\nb3']),
        maxLines: 4,
      );

      expect(tail, 'a3\nb1\nb2\nb3');
    });

    test('a one-line error repeating the second line gives null', () {
      final call = item(
        status: ToolCallStatusView.failed,
        textOutput: ['Error:\tbad https://user:pass@host/x'],
      );

      expect(ToolRowFormatter.outputTail(call, maxLines: 20), isNull);
      expect(
        ToolRowFormatter.format(call, cwd: '/w').secondary,
        'Error: bad https://<redacted>@host/x',
      );
    });

    test('a multi-line error shows the whole output', () {
      expect(
        ToolRowFormatter.outputTail(
          item(
            status: ToolCallStatusView.failed,
            textOutput: ['Error: boom\n    at main (a.dart:1)'],
          ),
          maxLines: 20,
        ),
        'Error: boom\n    at main (a.dart:1)',
      );
    });

    test('a long single line is shown whole while the second is cut', () {
      final text = 'x' * 300;
      final call = item(status: ToolCallStatusView.failed, textOutput: [text]);

      expect(ToolRowFormatter.outputTail(call, maxLines: 20), text);
      expect(
        ToolRowFormatter.format(call, cwd: '/w').secondary,
        hasLength(ToolRowFormatter.maxDetailLength),
      );
    });

    test('an agent call and an empty output give null', () {
      expect(
        ToolRowFormatter.outputTail(
          item(
            kind: ToolKind.think,
            subagentCall: const SubagentCallView(id: 'sub_a1', type: 'explore'),
            textOutput: ['report'],
          ),
          maxLines: 20,
        ),
        isNull,
      );
      expect(
        ToolRowFormatter.outputTail(item(textOutput: []), maxLines: 20),
        isNull,
      );
      expect(
        ToolRowFormatter.outputTail(item(textOutput: ['\n  \n']), maxLines: 20),
        isNull,
      );
    });

    test('a successful call without a second line shows its single line', () {
      expect(
        ToolRowFormatter.outputTail(
          item(textOutput: ['contents']),
          maxLines: 20,
        ),
        'contents',
      );
    });
  });
}
