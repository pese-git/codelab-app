// Источники промпта headless (tasks 4.5; spec cli-headless «Источники
// промпта headless»; H-01).

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_cli_io.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('codelab_prompt_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> read(List<String> args, {String? stdin}) =>
      readPrompt(parseCliArgs(args), FakeCliIo(stdin: stdin));

  test('-p is the text as is, even when a file has that name', () async {
    File('${tmp.path}/task.md').writeAsStringSync('from the file');

    expect(await read(['-p', '${tmp.path}/task.md']), '${tmp.path}/task.md');
  });

  test('-f reads the file as UTF-8', () async {
    File('${tmp.path}/task.md').writeAsStringSync('Исправь тесты\n');

    expect(await read(['-f', '${tmp.path}/task.md']), 'Исправь тесты\n');
  });

  test('-f - reads stdin', () async {
    expect(await read(['-f', '-'], stdin: 'from stdin'), 'from stdin');
  });

  test('without -p and -f the prompt is stdin', () async {
    expect(await read([], stdin: 'piped prompt\n'), 'piped prompt\n');
  });

  test('an unreadable file is a usage error naming the path', () async {
    await expectLater(
      read(['-f', '${tmp.path}/missing.md']),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          contains('missing.md'),
        ),
      ),
    );
  });

  test('an empty prompt is a usage error', () async {
    for (final (args, stdin) in [
      (['-p', ''], null),
      (['-p', '  \n'], null),
      (['-f', '-'], ''),
      (<String>[], '   '),
    ]) {
      await expectLater(
        read(args, stdin: stdin),
        throwsA(
          isA<UsageError>().having((e) => e.message, 'message', 'No prompt.'),
        ),
        reason: '$args',
      );
    }
  });
}
