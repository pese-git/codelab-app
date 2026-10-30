import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/src/project/frontmatter.dart';
import 'package:test/test.dart';

/// Отделение frontmatter и разбор в строгом профиле CFG-21 (design.md change
/// `add-agent-project-files`, D3; `agent-core-architecture` §15.5).
void main() {
  const path = '/h/prompts/review.md';

  MarkdownRead read(String text) =>
      readMarkdownFile(text, path: path, scope: ExtensionScope.user);

  ExtensionDiagnostic only(MarkdownRead r) {
    expect(r.file, isNull);
    return r.diagnostics.single;
  }

  group('a file without frontmatter', () {
    test('is the body as a whole', () {
      final r = read('Just a body\nsecond line\n');

      expect(r.diagnostics, isEmpty);
      expect(r.file!.frontmatter, isNull);
      expect(r.file!.body, 'Just a body\nsecond line\n');
      expect(r.file!.bodyLine, 1);
      expect(r.file!.path, path);
      expect(r.file!.scope, ExtensionScope.user);
    });

    test('a --- that is not on the first line is just text', () {
      final r = read('\n---\na: 1\n---\nbody');

      expect(r.file!.frontmatter, isNull);
      expect(r.file!.body, '\n---\na: 1\n---\nbody');
    });

    test('an empty file is an empty body', () {
      expect(read('').file!.body, '');
    });
  });

  group('frontmatter', () {
    test('is separated from the body, with positions in file lines', () {
      final r = read('---\ndescription: Hi\nargument-hint: <x>\n---\nBody\n');

      final file = r.file!;
      expect(r.diagnostics, isEmpty);
      expect(file.frontmatter!.values, {
        'description': 'Hi',
        'argument-hint': '<x>',
      });
      expect(
        file.frontmatter!.positions['description'],
        const ConfigPosition(2, 1),
      );
      expect(
        file.frontmatter!.positions['"argument-hint"'] ??
            file.frontmatter!.positions['argument-hint'],
        const ConfigPosition(3, 1),
      );
      expect(file.frontmatter!.source, path);
      expect(file.body, 'Body\n');
      expect(file.bodyLine, 5);
    });

    test('an empty frontmatter is an empty tree', () {
      final r = read('---\n---\nBody');

      expect(r.file!.frontmatter!.values, isEmpty);
      expect(r.file!.body, 'Body');
      expect(r.file!.bodyLine, 3);
    });

    test('a closing --- at the end of the file leaves an empty body', () {
      final r = read('---\na: 1\n---');

      expect(r.file!.frontmatter!.values, {'a': 1});
      expect(r.file!.body, '');
    });

    test('--- after a BOM opens the frontmatter', () {
      final r = read('\u{FEFF}---\na: 1\n---\nBody');

      expect(r.file!.frontmatter!.values, {'a': 1});
      expect(r.file!.frontmatter!.positions['a'], const ConfigPosition(2, 1));
    });

    test('a BOM before a plain body is dropped', () {
      expect(read('\u{FEFF}Body').file!.body, 'Body');
    });

    test('CRLF is read as LF, in the body too', () {
      final r = read('---\r\na: 1\r\nb: 2\r\n---\r\nline1\r\nline2\r\n');

      expect(r.diagnostics, isEmpty);
      expect(r.file!.frontmatter!.values, {'a': 1, 'b': 2});
      expect(r.file!.frontmatter!.positions['b'], const ConfigPosition(3, 1));
      expect(r.file!.body, 'line1\nline2\n');
      expect(r.file!.bodyLine, 5);
    });

    test('--- with trailing spaces still delimits', () {
      final r = read('---  \na: 1\n--- \nBody');

      expect(r.file!.frontmatter!.values, {'a': 1});
      expect(r.file!.body, 'Body');
    });
  });

  group('errors are diagnostics with file coordinates', () {
    test('an unclosed --- is a syntax error at the opening line', () {
      final d = only(read('---\na: 1\nBody never closed\n'));

      expect(d.code, 'syntax');
      expect(d.level, DiagnosticLevel.error);
      expect(d.path, path);
      expect(d.line, 1);
    });

    test('invalid YAML is a syntax error with a shifted line', () {
      final d = only(read('---\na: 1\nb: [1, 2\n---\nBody'));

      expect(d.code, 'syntax');
      expect(d.line, greaterThanOrEqualTo(3));
    });

    test('an anchor is a profile error at its file line', () {
      final d = only(read('---\nname: &a value\n---\nBody'));

      expect(d.code, 'profile');
      expect(d.level, DiagnosticLevel.error);
      expect(d.line, 2);
      expect(d.column, 7);
    });

    test('a tag is a profile error at its file line', () {
      final d = only(read('---\na: 1\nb: !!str x\n---\nBody'));

      expect(d.code, 'profile');
      expect(d.line, 3);
    });

    test('a duplicate key names both positions in file lines', () {
      final d = only(
        read(
          '---\ndescription: one\nargument-hint: x\ndescription: two\n---\nB',
        ),
      );

      expect(d.code, 'profile');
      expect([d.line, d.column], [4, 1]);
      expect(d.message, contains('first defined at 2:1'));
    });

    test('a frontmatter that is not a mapping is a profile error', () {
      final d = only(read('---\n- a\n- b\n---\nBody'));

      expect(d.code, 'profile');
      expect(d.line, 2);
    });

    test('a message never repeats the file text', () {
      final r = read('---\nsecret-key-xyz: &a sk-test-secret\n---\nBody');

      for (final d in r.diagnostics) {
        expect(d.message, isNot(contains('sk-test-secret')));
        expect(d.message, isNot(contains('secret-key-xyz')));
      }
      expect(r.file, isNull);
    });
  });
}
