import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'executor_harness.dart';
import 'fake_tools.dart';

const _pathSchema = {
  'type': 'object',
  'properties': {
    'path': {'type': 'string'},
    'limit': {'type': 'integer'},
  },
  'required': ['path'],
};

void main() {
  test('a successful call: started, executed, finished, completed', () async {
    final tool = FakeTool('probe', parameters: _pathSchema);
    final h = await ExecutorHarness.create([tool]);

    final outcome = await h.run('probe', {'path': 'a', 'limit': '3'});

    expect(outcome.outcome, ToolOutcome.completed);
    expect(outcome.message.toolCallId, 'call_1');
    expect(outcome.message.toolName, 'probe');
    expect(outcome.message.isError, isFalse);
    expect(textOf(outcome), 'probe ok');
    expect(tool.executed, [
      {'path': 'a', 'limit': 3},
    ]);
    expect(h.events.map((e) => e.runtimeType), [
      ToolCallStarted,
      ToolCallFinished,
    ]);
    final started = h.events.first as ToolCallStarted;
    expect(started.toolCallId, 'call_1');
    expect(started.tool, 'probe');
    expect(started.title, 'probe');
    expect(started.input, {'path': 'a', 'limit': '3'});
    final finished = h.events.last as ToolCallFinished;
    expect(finished.outcome, ToolOutcome.completed);
    expect(finished.content, [const TextContent('probe ok')]);
  });

  test('a tool not in the schemas of the step is not available', () async {
    final h = await ExecutorHarness.create([FakeTool('read'), FakeTool('ls')]);

    final outcome = await h.run(
      'ls',
      const {},
      invocation: h.invocation(stepTools: ['read']),
    );
    final unknown = await h.run('exce', const {}, id: 'call_2');

    expect(outcome.outcome, ToolOutcome.failed);
    expect(outcome.message.isError, isTrue);
    expect(
      textOf(outcome),
      'Tool "ls" is not available. Available tools: read.',
    );
    expect(
      textOf(unknown),
      'Tool "exce" is not available. Available tools: read, ls.',
    );
    expect((h.events.first as ToolCallStarted).title, 'ls');
  });

  test('invalid arguments are reported and the tool does not run', () async {
    final tool = FakeTool('read', parameters: _pathSchema);
    final h = await ExecutorHarness.create([tool]);

    final outcome = await h.run('read', {'limit': 'ten'});

    expect(outcome.outcome, ToolOutcome.failed);
    expect(
      textOf(outcome),
      'Invalid arguments for tool "read":\n'
      '  - path: missing required property\n'
      '  - limit: expected integer, got string "ten"\n'
      'Received arguments: {"limit":"ten"}',
    );
    expect(tool.executed, isEmpty);
  });

  test('preflight text stops the call before the hooks', () async {
    final hooks = <String>[];
    final tool = FakeTool('fetch', preflightText: 'Invalid URL: x');
    final h = await ExecutorHarness.create([tool]);

    final outcome = await h.run(
      'fetch',
      const {},
      invocation: h.invocation(
        before: [
          (call, args, ctx) async {
            hooks.add('before');
            return null;
          },
        ],
      ),
    );

    expect(outcome.outcome, ToolOutcome.failed);
    expect(textOf(outcome), 'Invalid URL: x');
    expect(hooks, isEmpty);
    expect(tool.executed, isEmpty);
  });

  test('the first Block stops the chain; after hooks do not run', () async {
    final calls = <String>[];
    final tool = FakeTool('edit');
    final h = await ExecutorHarness.create([tool]);

    final outcome = await h.run(
      'edit',
      const {'x': 1},
      invocation: h.invocation(
        before: [
          (call, args, ctx) async {
            calls.add('first ${args['x']}');
            return const Block('no');
          },
          (call, args, ctx) async {
            calls.add('second');
            return null;
          },
        ],
        after: [
          (call, result, isError) async {
            calls.add('after');
            return null;
          },
        ],
      ),
    );

    expect(calls, ['first 1']);
    expect(outcome.outcome, ToolOutcome.rejected);
    expect(textOf(outcome), 'no');
    expect(tool.executed, isEmpty);
  });

  test('a throwing before hook rejects the call, not the turn', () async {
    final h = await ExecutorHarness.create([FakeTool('edit')]);

    final outcome = await h.run(
      'edit',
      const {},
      invocation: h.invocation(
        before: [(call, args, ctx) async => throw StateError('hook broke')],
      ),
    );

    expect(outcome.outcome, ToolOutcome.failed);
    expect(textOf(outcome), 'hook broke');
  });

  test('a cancelled turn does not execute', () async {
    final source = CancelTokenSource()..cancel();
    final tool = FakeTool('edit');
    final h = await ExecutorHarness.create([tool]);

    final outcome = await h.run(
      'edit',
      const {},
      invocation: h.invocation(cancel: source.token),
    );

    expect(outcome.outcome, ToolOutcome.cancelled);
    expect(textOf(outcome), 'Tool call was cancelled');
    expect(tool.executed, isEmpty);
  });

  test('after hooks override fields in order', () async {
    final h = await ExecutorHarness.create([FakeTool('read')]);

    final outcome = await h.run(
      'read',
      const {},
      invocation: h.invocation(
        after: [
          (call, result, isError) async =>
              const ResultOverride(content: [TextContent('first')]),
          (call, result, isError) async {
            expect((result.content.single as TextContent).text, 'first');
            return const ResultOverride(isError: true);
          },
        ],
      ),
    );

    expect(textOf(outcome), 'first');
    expect(outcome.message.isError, isTrue);
    expect(outcome.outcome, ToolOutcome.failed);
  });

  test('a throwing after hook makes the result an error', () async {
    final h = await ExecutorHarness.create([FakeTool('read')]);

    final outcome = await h.run(
      'read',
      const {},
      invocation: h.invocation(
        after: [(call, result, isError) async => throw Exception('late')],
      ),
    );

    expect(outcome.outcome, ToolOutcome.failed);
    expect(textOf(outcome), 'late');
  });

  test('isError of the tool fails the call', () async {
    final h = await ExecutorHarness.create([
      FakeTool(
        'exec',
        onExecute: (args, ctx) =>
            const ToolExecutionResult([TextContent('exit 1')], isError: true),
      ),
    ]);

    final outcome = await h.run('exec', const {});

    expect(outcome.outcome, ToolOutcome.failed);
    expect(outcome.message.isError, isTrue);
  });

  test('a CancelledException of the tool is cancelled', () async {
    final h = await ExecutorHarness.create([
      FakeTool(
        'exec',
        onExecute: (args, ctx) => throw const CancelledException(UserCancel()),
      ),
    ]);

    final outcome = await h.run('exec', const {});

    expect(outcome.outcome, ToolOutcome.cancelled);
    expect(textOf(outcome), 'Tool call was cancelled');
  });

  test('progress is delivered before the finish', () async {
    final h = await ExecutorHarness.create([
      FakeTool(
        'exec',
        onExecute: (args, ctx) {
          ctx.onUpdate(const ToolExecutionResult([TextContent('half')]));
          return const ToolExecutionResult([TextContent('done')]);
        },
      ),
    ]);

    await h.run('exec', const {});

    expect(h.events.map((e) => e.runtimeType), [
      ToolCallStarted,
      ToolCallProgress,
      ToolCallFinished,
    ]);
  });

  test('a tool result is truncated to the limits with a notice', () async {
    final h = await ExecutorHarness.create([
      FakeTool(
        'dump',
        onExecute: (args, ctx) => ToolExecutionResult([
          TextContent([for (var i = 1; i <= 2500; i++) 'l$i'].join('\n')),
        ]),
      ),
    ]);

    final outcome = await h.run('dump', const {});

    final lines = textOf(outcome).split('\n');
    expect(lines, hasLength(2001));
    expect(
      lines.last,
      '[Output truncated: showing the first 2000 lines of 2500.]',
    );
  });

  test('the context of the tool is the bounded env', () async {
    ExecutionEnv? seen;
    final h = await ExecutorHarness.create([
      FakeTool(
        'probe',
        onExecute: (args, ctx) {
          seen = ctx.env;
          return const ToolExecutionResult([]);
        },
      ),
    ]);

    await h.run('probe', const {});

    expect(seen, same(h.env));
  });

  test('abandon gives cancelled with the not-started text', () async {
    final h = await ExecutorHarness.create([FakeTool('exec')]);
    final handle = await h.executor.announce(
      ToolCall(id: 'call_3', name: 'exec', arguments: const {}),
      h.invocation(),
    );

    final outcome = await h.executor.abandon(handle);

    expect(outcome.outcome, ToolOutcome.cancelled);
    expect(textOf(outcome), 'Tool call was cancelled before it started');
    expect(h.events.last, isA<ToolCallFinished>());
  });
}
