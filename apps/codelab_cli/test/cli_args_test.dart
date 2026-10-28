// Разбор флагов `codelab` (tasks 1.4; spec codelab-cli «Команда codelab и
// разбор флагов»; design.md change `add-codelab-cli`, D1, D2).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  test('without -p or a subcommand the mode is the REPL', () {
    final options = parseCliArgs([]);

    expect(options.command, CliCommand.repl);
    expect(options.prompt, isNull);
    expect(options.approve, ApprovePolicy.reject);
  });

  test('positional arguments are the first REPL message', () {
    final options = parseCliArgs(['fix', 'the', 'bug']);

    expect(options.command, CliCommand.repl);
    expect(options.positional, ['fix', 'the', 'bug']);
  });

  test('-p selects the headless mode with the text as is', () {
    final options = parseCliArgs(['-p', 'hello world', '-a', 'py']);

    expect(options.command, CliCommand.headless);
    expect(options.prompt, 'hello world');
    expect(options.agent, 'py');
  });

  test('-f selects the headless mode with a prompt file', () {
    expect(parseCliArgs(['-f', 'task.md']).promptFile, 'task.md');
    expect(parseCliArgs(['-f', '-']).command, CliCommand.headless);
  });

  test('connection and session flags', () {
    final options = parseCliArgs([
      '--agent',
      'stdio:codelab-agent serve --stdio',
      '-C',
      '/work',
      '-m',
      'gpt',
      '--mode',
      'ask',
      '-r',
      'session-1',
      '--no-color',
      '-v',
    ]);

    expect(options.agent, 'stdio:codelab-agent serve --stdio');
    expect(options.cwd, '/work');
    expect(options.model, 'gpt');
    expect(options.configMode, 'ask');
    expect(options.resume, 'session-1');
    expect(options.noColor, isTrue);
    expect(options.verbose, isTrue);
  });

  test('--approve accepts the three policies', () {
    expect(
      parseCliArgs(['-p', 'x', '--approve', 'read-only']).approve,
      ApprovePolicy.readOnly,
    );
    expect(
      parseCliArgs(['-p', 'x', '--approve', 'allow-all']).approve,
      ApprovePolicy.allowAll,
    );
    expect(
      () => parseCliArgs(['-p', 'x', '--approve', 'maybe']),
      throwsA(isA<UsageError>()),
    );
  });

  test('--timeout parses durations', () {
    expect(
      parseCliArgs(['-p', 'x', '--timeout', '90s']).timeout,
      const Duration(seconds: 90),
    );
    expect(
      parseCliArgs(['-p', 'x', '--timeout', '10m']).timeout,
      const Duration(minutes: 10),
    );
    expect(
      parseCliArgs(['-p', 'x', '--timeout', '1h30m']).timeout,
      const Duration(hours: 1, minutes: 30),
    );
    for (final bad in ['soon', '10', '0s', '-5s']) {
      expect(
        () => parseCliArgs(['-p', 'x', '--timeout', bad]),
        throwsA(isA<UsageError>()),
        reason: bad,
      );
    }
  });

  test('--resume together with --continue is a usage error', () {
    expect(
      () => parseCliArgs(['-r', 'a', '-c']),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          contains('--continue'),
        ),
      ),
    );
  });

  test('-p together with -f is a usage error', () {
    expect(
      () => parseCliArgs(['-p', 'x', '-f', 'y']),
      throwsA(isA<UsageError>()),
    );
  });

  test('positional arguments together with -p are a usage error', () {
    expect(
      () => parseCliArgs(['-p', 'x', 'extra']),
      throwsA(isA<UsageError>()),
    );
  });

  test('flags of later changes are not registered', () {
    for (final flag in [
      ['--output-format', 'stream-json'],
      ['--include-thoughts'],
      ['--include-acp'],
      ['--input-format', 'text'],
      ['--trace-file', 'x'],
      ['--ui', 'tui'],
      ['--session', 'x'],
      ['--permission-mode', 'ask'],
      ['--config', 'x.yaml'],
    ]) {
      expect(
        () => parseCliArgs(['-p', 'hi', ...flag]),
        throwsA(
          isA<UsageError>().having(
            (e) => e.message,
            'message',
            startsWith('Unknown flag ${flag.first}'),
          ),
        ),
        reason: flag.first,
      );
    }
  });

  test('subcommands of later stages are unknown commands', () {
    for (final command in [
      'config',
      'provider',
      'mcp',
      'secret',
      'sessions',
      'update',
      'login',
      'logout',
      'trajectory',
    ]) {
      expect(
        () => parseCliArgs([command, 'x']),
        throwsA(
          isA<UsageError>().having(
            (e) => e.message,
            'message',
            'Unknown command $command',
          ),
        ),
        reason: command,
      );
    }
  });

  test('profiles is a subcommand with its own arguments', () {
    final options = parseCliArgs(['profiles', 'add', 'py', 'stdio:python']);

    expect(options.command, CliCommand.profiles);
    expect(options.positional, ['add', 'py', 'stdio:python']);
  });

  test('--version and --help', () {
    expect(parseCliArgs(['--version']).command, CliCommand.version);
    expect(parseCliArgs(['--help']).command, CliCommand.help);
    expect(parseCliArgs(['-h']).command, CliCommand.help);
  });

  test('the usage text lists the MVP flags and no later ones', () {
    final text = cliUsage();

    expect(text, contains('--agent'));
    expect(text, contains('--print'));
    expect(text, contains('--approve'));
    expect(text, isNot(contains('--output-format')));
  });

  test('test-scenario takes paths, --agent, --filter and --timeout', () {
    final options = parseCliArgs([
      'test-scenario',
      'fixtures/acp',
      'one.json',
      '--agent',
      'stdio:agent',
      '--filter',
      'acp/session-*',
      '--timeout',
      '10s',
    ]);

    expect(options.command, CliCommand.testScenario);
    expect(options.positional, ['fixtures/acp', 'one.json']);
    expect(options.agent, 'stdio:agent');
    expect(options.filter, 'acp/session-*');
    expect(options.timeout, const Duration(seconds: 10));
  });

  test('test-scenario without --timeout waits 30s for a frame', () {
    final options = parseCliArgs(['test-scenario', 'x', '-a', 'stdio:agent']);

    expect(options.timeout, const Duration(seconds: 30));
  });
}
