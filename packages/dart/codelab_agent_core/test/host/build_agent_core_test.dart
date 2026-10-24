import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../tools/fake_shell.dart';
import 'core_harness.dart';

void main() {
  test('agent-serve over the memory env without shell', () async {
    final h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      steps: [
        {
          ...textStep('ok'),
          'expect': {
            'tools': ['read', 'edit'],
          },
        },
      ],
    );

    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.prompt([const TextContent('hi')]);

    h.model.verify();
    expect(h.core.plan.toolNames, ['read', 'edit']);
    expect(h.core.plan.offReasons.keys, [HostCapability.shellExec]);
    expect(h.logger.eventsOf('host.plan'), hasLength(1));
  });

  test('exec is registered when shellExec is on', () {
    final h = CoreHarness.build(
      baseEnv: FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering('')),
      gate: FakeGate(),
      steps: const [],
    );

    expect(h.core.plan.toolNames, ['read', 'edit', 'exec']);
  });

  test('shellExec over the memory env is a wiring error (HOST-3)', () {
    expect(
      () => CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        gate: FakeGate(),
        steps: const [],
      ),
      throwsA(
        isA<HostWiringException>().having(
          (e) => e.message,
          'message',
          contains('shellExec'),
        ),
      ),
    );
  });

  test(
    'without a gate interactiveApproval is off and a write is denied (PERM-5)',
    () async {
      final memory = MemoryExecutionEnv(cwd: '/proj');
      await memory.writeText('/proj/a.txt', 'a\n');
      final h = CoreHarness.build(
        baseEnv: memory,
        narrow: noExec,
        steps: [
          callStep('c1', 'edit', {
            'path': 'a.txt',
            'oldText': 'a',
            'newText': 'b',
          }),
          textStep('could not'),
        ],
      );

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      final result = await session.prompt([const TextContent('edit')]);

      expect(
        h.core.plan.offReasons[HostCapability.interactiveApproval],
        'PermissionGate не передан',
      );
      expect(result.reason, TurnEndReason.completed);
      expect(
        await memory.readText('/proj/a.txt'),
        const Ok<String, FileError>('a\n'),
      );
      final request = h.model.requests[1].messages.last as ToolResultMessage;
      expect(
        (request.content.single as TextContent).text,
        contains('no approval interface is available'),
      );
    },
  );

  test('the policy is the first hook; host hooks come after it', () async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    await memory.writeText('/proj/a.txt', 'a\n');
    final seen = <String>[];
    final h = CoreHarness.build(
      baseEnv: memory,
      narrow: noExec,
      gate: gateAnswering(PermissionDecision.rejectOnce),
      steps: [
        callStep('c1', 'read', {'path': 'a.txt'}),
        callStep('c2', 'edit', {
          'path': 'a.txt',
          'oldText': 'a',
          'newText': 'b',
        }),
        textStep('done'),
      ],
    );

    final session = await h.core.runtime.createSession(
      SessionSpec(
        cwd: '/proj',
        extraBeforeToolCall: [
          (call, args, ctx) async {
            seen.add('before ${call.name}');
            return null;
          },
        ],
        extraAfterToolCall: [
          (call, result, isError) async {
            seen.add('after ${call.name}');
            return null;
          },
        ],
      ),
    );
    await session.prompt([const TextContent('go')]);

    expect(seen, ['before read', 'after read']);
  });

  test(
    'every session tool works on one bounded env of the session (ENV-2)',
    () async {
      final memory = MemoryExecutionEnv(cwd: '/proj');
      await memory.writeText('/other/x.txt', 'x\n');
      final h = CoreHarness.build(
        baseEnv: memory,
        narrow: noExec,
        gate: FakeGate(),
        steps: [
          callStep('c1', 'read', {'path': '/other/x.txt'}),
          textStep('no'),
        ],
      );

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.prompt([const TextContent('read')]);

      final result = h.model.requests[1].messages.last as ToolResultMessage;
      expect(
        (result.content.single as TextContent).text,
        'Path is outside the workspace: /other/x.txt',
      );
    },
  );
}
