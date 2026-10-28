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
  });
}
