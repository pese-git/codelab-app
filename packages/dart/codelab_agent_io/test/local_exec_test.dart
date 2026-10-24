import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

ExecResult _ok(Result<ExecResult, ExecError> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw StateError('expected Ok, got $error'),
};

ExecError _err(Result<ExecResult, ExecError> result) => switch (result) {
  Ok(:final value) => throw StateError('expected Err, got ${value.output}'),
  Err(:final error) => error,
};

Future<bool> _alive(String marker) async {
  final ps = await Process.run('ps', ['-A', '-o', 'args=']);
  return '${ps.stdout}'
      .split('\n')
      .any((line) => line.contains(marker) && !line.contains('ps -A'));
}

void main() {
  late Directory tmp;
  late LocalExecutionEnv env;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('local_exec_');
    env = LocalExecutionEnv(
      cwd: tmp.resolveSymbolicLinksSync(),
      hostEnvironment: {
        ...Platform.environment,
        'CODELAB_TEST_SECRET': 'leaked',
      },
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('a non-zero exit code is Ok with the output', () async {
    final result = _ok(
      await env.exec(
        'echo out; echo err >&2; exit 3',
        ExecOptions(cwd: env.cwd),
      ),
    );

    expect(result.exitCode, 3);
    expect(result.output, contains('out'));
    expect(result.output, contains('err'));
    expect(result.truncated, isFalse);
  });

  test('a missing working directory is spawnFailed', () async {
    final error = _err(
      await env.exec('true', ExecOptions(cwd: '${env.cwd}/none')),
    );

    expect(error.code, ExecErrorCode.spawnFailed);
    expect(error.message, 'working directory does not exist');
  });

  test(
    'a process ignoring SIGTERM ends by timeout within 6 s (ENV-5)',
    () async {
      final watch = Stopwatch()..start();

      final error = _err(
        await env.exec(
          'echo started; trap "" TERM; sleep 60',
          ExecOptions(cwd: env.cwd, timeout: const Duration(seconds: 1)),
        ),
      );

      expect(error.code, ExecErrorCode.timeout);
      expect(error.outputTail, contains('started'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('cancel kills the grandchildren (T-09)', () async {
    final source = CancelTokenSource();
    const marker = '60.4321';
    final running = env.exec(
      'sleep $marker & wait',
      ExecOptions(cwd: env.cwd, cancel: source.token),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await _alive(marker), isTrue);

    source.cancel();
    final error = _err(await running);

    expect(error.code, ExecErrorCode.aborted);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await _alive(marker), isFalse);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('output over the limit keeps the tail and says truncated', () async {
    final result = _ok(
      await env.exec(
        'i=0; while [ \$i -lt 2000 ]; do echo line\$i; i=\$((i+1)); done',
        ExecOptions(cwd: env.cwd, outputByteLimit: 1000),
      ),
    );

    expect(result.truncated, isTrue);
    expect(result.output.length, lessThanOrEqualTo(1000));
    expect(result.output, endsWith('line1999\n'));
  });

  test(
    'the environment is the allowlist plus explicit variables (ENV-6)',
    () async {
      final result = _ok(
        await env.exec('env', ExecOptions(cwd: env.cwd, env: {'EXTRA': 'yes'})),
      );

      expect(result.output, isNot(contains('CODELAB_TEST_SECRET')));
      expect(result.output, contains('GIT_TERMINAL_PROMPT=0'));
      expect(result.output, contains('TERM=dumb'));
      expect(result.output, contains('EXTRA=yes'));
      expect(result.output, contains('PATH='));
    },
  );

  test('stdin is closed: a reading command gets EOF', () async {
    final result = _ok(
      await env.exec(
        'read line; echo "got:\$line"',
        ExecOptions(cwd: env.cwd, timeout: const Duration(seconds: 5)),
      ),
    );

    expect(result.output, 'got:\n');
  });

  test('onOutput receives the chunks', () async {
    final chunks = <String>[];

    await env.exec(
      'echo one; echo two',
      ExecOptions(cwd: env.cwd, onOutput: chunks.add),
    );

    expect(chunks.join(), 'one\ntwo\n');
  });
}
