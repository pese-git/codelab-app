import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/dart_executable.dart';

/// `IoSecretProcessRunner` на настоящих дочерних процессах (design.md change
/// `add-agent-secret-store`, D5): stdin, таймаут с SIGKILL, пустое окружение
/// ребёнка и ошибка запуска. Дочерний `dart` — тот же, что в тестах MCP
/// (`dart_executable.dart`), эхо-скрипт — `line_echo.dart`.
void main() {
  const runner = IoSecretProcessRunner();
  final dart = dartExecutable();
  final posix = !Platform.isWindows;

  /// Дартовый скрипт с абсолютным путём: PATH ребёнку не передаётся.
  String script(String name) => File('test/support/$name').absolute.path;

  test('stdin reaches the child and the exit code is returned', () async {
    // line_echo завершает процесс командой `exit:N` со stdin.
    final result = await runner.run(dart, [
      script('line_echo.dart'),
    ], stdin: 'hello\nexit:7\n');

    expect(result.exitCode, 7);
    expect(result.timedOut, isFalse);
  });

  test(
    'EOF of stdin ends the child with code 0 when no stdin is given',
    () async {
      final result = await runner.run(dart, [script('line_echo.dart')]);

      expect(result.exitCode, 0);
      expect(result.timedOut, isFalse);
    },
  );

  test(
    'a child that outlives the timeout is killed (SIGKILL, timedOut)',
    () async {
      final stopwatch = Stopwatch()..start();

      final result = await runner.run('/bin/sleep', [
        '30',
      ], timeout: const Duration(milliseconds: 300));

      expect(result.timedOut, isTrue);
      expect(result.exitCode, -1);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    },
    skip: posix ? null : 'нужен /bin/sleep',
  );

  test('a fast child under a timeout is not timed out', () async {
    final result = await runner.run(
      dart,
      [script('line_echo.dart')],
      stdin: 'exit:0\n',
      timeout: const Duration(seconds: 60),
    );

    expect(result.timedOut, isFalse);
    expect(result.exitCode, 0);
  });

  test(
    'the child environment does not contain the parent environment',
    () async {
      final result = await runner.run(dart, [
        script('secret_runner_probe.dart'),
        'env',
      ]);

      // 0 — ни PATH, ни HOME, ни CODELAB_*, то есть и CODELAB_SECRET_* хоста.
      expect(result.exitCode, 0);
    },
  );

  test('a missing executable is an exception, not a result', () async {
    await expectLater(
      runner.run('/nonexistent/codelab-secret-tool', const []),
      throwsA(isA<ProcessException>()),
    );
  });

  test('writing stdin to a child that exits at once is not an error', () async {
    final result = await runner.run(
      '/usr/bin/true',
      const [],
      stdin: 'x' * (1024 * 1024),
    );

    expect(result.exitCode, 0);
  }, skip: File('/usr/bin/true').existsSync() ? null : 'нужен /usr/bin/true');
}
