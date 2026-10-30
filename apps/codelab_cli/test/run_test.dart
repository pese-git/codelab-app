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

  test('--ui tui without a terminal exits with 64 and does not start the '
      'agent', () async {
    for (final io in [
      FakeCliIo(stdinIsTerminal: true),
      FakeCliIo(stdoutIsTerminal: true),
    ]) {
      final code = await runCodelab(
        ['--ui', 'tui', '--agent', 'stdio:/nonexistent/agent'],
        environment: {'HOME': '/nonexistent'},
        io: io,
      );

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        contains('--ui tui needs a terminal on stdin and stdout'),
      );
    }
  });

  // D17, 10.5: `CODELAB_HOME=~bob/cl` — ошибка использования до запуска
  // агента: команда агента несуществующая, и если бы CLI дошёл до запуска,
  // текст ошибки был бы другим.
  test('CODELAB_HOME=~user/cl exits with 64 before the agent starts', () async {
    final io = FakeCliIo();

    final code = await runCodelab(
      ['--agent', 'stdio:/no/such/agent', '-p', 'hi'],
      environment: {'CODELAB_HOME': '~bob/cl', 'HOME': '/Users/me'},
      io: io,
    );

    expect(code, 64);
    expect(io.stdoutText, isEmpty);
    expect(
      io.stderrText,
      contains('CODELAB_HOME: ~user is not supported, use an absolute path'),
    );
  });
}
