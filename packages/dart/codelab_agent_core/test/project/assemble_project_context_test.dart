import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Сборка контекста проекта: порядок, бюджет, усечение (agent-project-context
/// «Бюджет и усечение контекста проекта»; design.md change
/// `add-agent-project-files`, D5; E-01).
void main() {
  ContextFile file(String path, String content) =>
      ContextFile(path: path, content: content);

  int bytes(String text) => utf8.encode(text).length;

  test('files keep the order of the input: general first (E-01)', () {
    final context = assembleProjectContext([
      file(r'$CODELAB_HOME/AGENTS.md', 'user'),
      file('AGENTS.md', 'root'),
      file('pkg/AGENTS.md', 'leaf'),
    ], 1000)!;

    expect(
      [for (final f in context.files) f.path],
      [r'$CODELAB_HOME/AGENTS.md', 'AGENTS.md', 'pkg/AGENTS.md'],
    );
    expect(context.omitted, 0);
    expect(context.truncated, 0);
    expect(context.bytes, bytes('user') + bytes('root') + bytes('leaf'));
  });

  test('a file that fits stays as it is, without a marker', () {
    final text = 'a\nb\nc';

    final context = assembleProjectContext([
      file('AGENTS.md', text),
    ], bytes(text))!;

    expect(context.files.single.text, text);
    expect(context.files.single.truncated, isFalse);
  });

  test('the nearest file takes the budget first; a farther file is cut at a '
      'line boundary with a marker', () {
    // Бюджет 100: файл cwd — 60 байт, файл корня — 79 байт, остаётся 40.
    final leaf = '${List.filled(5, '123456789').join('\n')}\n1234567890'; // 60
    final root = List.filled(8, '123456789').join('\n'); // 79
    expect(bytes(leaf), 60);
    expect(bytes(root), 79);

    final context = assembleProjectContext([
      file('AGENTS.md', root),
      file('pkg/AGENTS.md', leaf),
    ], 100)!;

    expect(context.files.last.text, leaf);
    final cut = context.files.first;
    expect(cut.truncated, isTrue);
    expect(cut.shownBytes, 39);
    expect(cut.totalBytes, 79);
    expect(
      cut.text,
      '${List.filled(4, '123456789').join('\n')}\n'
      '[file truncated: showing 39 of 79 bytes]',
    );
    expect(context.truncated, 1);
    // Пометка в бюджет не входит.
    expect(context.bytes, 60 + 39);
  });

  test('when the nearest file takes the whole budget, farther files are '
      'omitted and counted', () {
    final leaf = 'x' * 50;

    final context = assembleProjectContext([
      file(r'$CODELAB_HOME/AGENTS.md', 'user'),
      file('AGENTS.md', 'root'),
      file('pkg/AGENTS.md', leaf),
    ], 50)!;

    expect([for (final f in context.files) f.path], ['pkg/AGENTS.md']);
    expect(context.omitted, 2);
  });

  test(
    'a truncated file exhausts the budget: no fragments of farther files',
    () {
      final context = assembleProjectContext([
        file(r'$CODELAB_HOME/AGENTS.md', 'user rule'),
        file('AGENTS.md', 'line one\nline two\nline three'),
      ], 20)!;

      expect([for (final f in context.files) f.path], ['AGENTS.md']);
      expect(context.files.single.truncated, isTrue);
      expect(context.omitted, 1);
    },
  );

  test('an empty or blank file is skipped and is not counted as omitted', () {
    final context = assembleProjectContext([
      file('AGENTS.md', '  \n\n\t'),
      file('pkg/AGENTS.md', 'rule'),
    ], 100)!;

    expect([for (final f in context.files) f.path], ['pkg/AGENTS.md']);
    expect(context.omitted, 0);
  });

  test('maxBytes 0 or only empty files give no context', () {
    expect(assembleProjectContext([file('AGENTS.md', 'rule')], 0), isNull);
    expect(assembleProjectContext([file('AGENTS.md', '  ')], 100), isNull);
    expect(assembleProjectContext(const [], 100), isNull);
  });

  group('multi-byte characters are never cut in the middle', () {
    test('a line boundary is preferred', () {
      // «ααα» — 6 байт, перевод строки — седьмой байт, «ββββ» — 8 байт.
      final context = assembleProjectContext([
        file('AGENTS.md', 'ααα\nββββ'),
      ], 7)!;

      expect(context.files.single.shownBytes, 6);
      expect(context.files.single.text, startsWith('ααα\n[file truncated'));
    });

    test('a first line longer than the budget is cut at a character', () {
      // Бюджет 7 байт: три буквы «При» (6 байт), четвёртая не помещается.
      final context = assembleProjectContext([
        file('AGENTS.md', 'Привет\nМир'),
      ], 7)!;

      final entry = context.files.single;
      expect(entry.shownBytes, 6);
      expect(entry.text, startsWith('При\n[file truncated: showing 6 of '));
      expect(utf8.decode(utf8.encode(entry.text)), entry.text);
    });
  });

  test('M is the size of the file given by the host, not of the part read', () {
    // Загрузчик читает не больше maxBytes + 1 байт; размер берёт из stat.
    final context = assembleProjectContext([
      ContextFile(
        path: 'AGENTS.md',
        content: 'line one\nline two\npartial',
        totalBytes: 5000,
      ),
    ], 12)!;

    expect(context.files.single.totalBytes, 5000);
    expect(
      context.files.single.text,
      endsWith('[file truncated: showing 8 of 5000 bytes]'),
    );
  });

  test('the same input gives the same result', () {
    final input = [file('a', 'x\ny'), file('b', 'z')];

    expect(
      [for (final f in assembleProjectContext(input, 3)!.files) f.text],
      [for (final f in assembleProjectContext(input, 3)!.files) f.text],
    );
  });
}
