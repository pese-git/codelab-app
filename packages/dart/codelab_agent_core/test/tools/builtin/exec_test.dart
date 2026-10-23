import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:test/test.dart';

import '../executor_harness.dart';
import '../fake_shell.dart';

void main() {
  Future<(ExecutorHarness, FakeShellEnv)> harness(ShellHandler handler) async {
    final shell = FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), handler);
    await shell.writeText('/proj/sub/.keep', '');
    final h = await ExecutorHarness.create([ExecTool()], base: shell);
    return (h, shell);
  }

  test('schema, tier and kind of §6.4', () {
    final tool = ExecTool();

    expect(tool.tier, ToolTier.exec);
    expect(tool.kind, ToolKind.execute);
    expect(tool.parameters['required'], ['command']);
    expect(tool.truncatesOutput, isTrue);
  });

  test('exit code 0 completes with the output', () async {
    final (h, shell) = await harness(answering('ok\n'));

    final outcome = await h.run('exec', {'command': 'dart test'});

    expect(outcome.outcome, ToolOutcome.completed);
    expect(textOf(outcome), 'ok\n');
    expect(shell.commands, ['dart test']);
  });

  test('a non-zero code is an error with the code line', () async {
    final (h, _) = await harness(answering('1 failed\n', exitCode: 2));

    final outcome = await h.run('exec', {'command': 'dart test'});

    expect(outcome.outcome, ToolOutcome.failed);
    expect(textOf(outcome), '1 failed\n\n[Command exited with code 2]');
  });

  test('empty output is (no output)', () async {
    final (h, _) = await harness(answering(''));

    expect(textOf(await h.run('exec', {'command': 'true'})), '(no output)');
  });

  test(
    'timeout and cwd reach the shell; out-of-range timeout is clamped',
    () async {
      ExecOptions? seen;
      final (h, _) = await harness((command, options) async {
        seen = options;
        return answering('')(command, options);
      });

      final outcome = await h.run('exec', {
        'command': 'ls',
        'timeout': 99999,
        'cwd': 'sub',
      });

      expect(seen!.timeout, const Duration(seconds: 3600));
      expect(seen!.cwd, '/proj/sub');
      expect(
        textOf(outcome),
        '(no output)\n[Note: timeout must be within 1..3600 seconds; using 3600.]',
      );
    },
  );

  test('the default timeout is 120 s', () async {
    ExecOptions? seen;
    final (h, _) = await harness((command, options) async {
      seen = options;
      return answering('')(command, options);
    });

    await h.run('exec', {'command': 'ls'});

    expect(seen!.timeout, const Duration(seconds: 120));
  });

  test('a timeout keeps the tail and the duration', () async {
    final (h, _) = await harness(
      (command, options) async => const Err(
        ExecError(
          ExecErrorCode.timeout,
          outputTail: 'still running\n',
          duration: Duration(milliseconds: 1520),
        ),
      ),
    );

    final outcome = await h.run('exec', {'command': 'sleep 9'});

    expect(outcome.outcome, ToolOutcome.failed);
    expect(
      textOf(outcome),
      'still running\n\n[Command timed out after 1.5 s and was terminated]',
    );
  });

  test('a cancel is cancelled with the duration', () async {
    final (h, _) = await harness(
      (command, options) async => const Err(
        ExecError(
          ExecErrorCode.aborted,
          outputTail: '',
          duration: Duration(milliseconds: 2049),
        ),
      ),
    );

    final outcome = await h.run('exec', {'command': 'sleep 9'});

    expect(outcome.outcome, ToolOutcome.cancelled);
    expect(textOf(outcome), '[Command was cancelled after 2.0 s]');
  });

  test('no shell: the fixed text of §6.4', () async {
    final h = await ExecutorHarness.create([ExecTool()]);

    final outcome = await h.run('exec', {'command': 'ls'});

    expect(outcome.outcome, ToolOutcome.failed);
    expect(
      textOf(outcome),
      'Shell commands are not available in this environment.',
    );
  });

  test('a working directory outside the workspace is rejected', () async {
    final (h, shell) = await harness(answering(''));

    final outcome = await h.run('exec', {'command': 'ls', 'cwd': '../other'});

    expect(textOf(outcome), 'Path is outside the workspace: ../other');
    expect(shell.commands, isEmpty);
  });

  test('the tail of a long output with the notice', () async {
    final long = [for (var i = 1; i <= 2500; i++) 'l$i'].join('\n');
    final (h, _) = await harness(answering(long));

    final lines = textOf(await h.run('exec', {'command': 'seq'})).split('\n');

    expect(lines.first, 'l501');
    expect(
      lines.last,
      '[Output truncated: showing the last 2000 lines of 2500.]',
    );
  });

  test('output chunks become ToolCallProgress', () async {
    final (h, _) = await harness(answering('chunk'));

    await h.run('exec', {'command': 'echo chunk'});

    expect(h.events.map((e) => e.runtimeType), [
      ToolCallStarted,
      ToolCallProgress,
      ToolCallFinished,
    ]);
  });

  test('present: the command is the title', () async {
    final (h, _) = await harness(answering(''));

    await h.run('exec', {'command': 'dart test'});

    expect((h.events.first as ToolCallStarted).title, 'dart test');
  });
}
