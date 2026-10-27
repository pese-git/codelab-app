// Точка входа `runCodelab` без агента (tasks 1.4, 1.5; spec codelab-cli
// «Команда codelab и разбор флагов»).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import 'support/fake_cli_io.dart';

void main() {
  test('--version prints one line and exits with 0', () async {
    final io = FakeCliIo();

    final code = await runCodelab(['--version'], environment: {}, io: io);

    expect(code, 0);
    expect(io.stdoutText, 'codelab $cliVersion\n');
    expect(io.stderrText, isEmpty);
  });

  test('--help prints the usage', () async {
    final io = FakeCliIo();

    final code = await runCodelab(['--help'], environment: {}, io: io);

    expect(code, 0);
    expect(io.stdoutText, contains('--agent'));
  });

  test('an unknown flag exits with 64, empty stdout and the error in '
      'stderr', () async {
    final io = FakeCliIo();

    final code = await runCodelab(
      ['--output-format', 'stream-json', '-p', 'hi'],
      environment: {},
      io: io,
    );

    expect(code, 64);
    expect(io.stdoutText, isEmpty);
    expect(io.stderrText, contains('Unknown flag --output-format'));
  });
}
