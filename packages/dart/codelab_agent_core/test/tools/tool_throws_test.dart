import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/misuse.dart';
import 'package:test/test.dart';

import 'executor_harness.dart';
import 'fake_tools.dart';

void main() {
  for (final (thrown, text) in [
    (StateError('x'), 'x'),
    (ArgumentError('bad'), 'bad'),
    (Exception('Bad state: nested'), 'nested'),
    (const FormatException('broken json'), 'FormatException: broken json'),
  ]) {
    test(
      '${thrown.runtimeType} → "$text" without Dart prefixes (TOOL-3)',
      () async {
        final h = await ExecutorHarness.create([
          FakeTool('boom', onExecute: (args, ctx) => throw thrown),
        ]);

        final outcome = await h.run('boom', const {});

        expect(outcome.outcome, ToolOutcome.failed);
        expect(outcome.message.isError, isTrue);
        expect(textOf(outcome), text);
      },
    );
  }

  test('a throwing schema is a tool error with a terminal status', () async {
    final h = await ExecutorHarness.create([_BrokenSchemaTool()]);

    final outcome = await h.run('broken', const {});

    expect(outcome.outcome, ToolOutcome.failed);
    expect(outcome.message.isError, isTrue);
    expect(textOf(outcome), 'schema is broken');
    expect((h.events.last as ToolCallFinished).outcome, ToolOutcome.failed);
  });

  test('a validation exception is logged as tool.validate.error', () async {
    final h = await ExecutorHarness.create([_BrokenSchemaTool()]);

    await h.run('broken', const {}, id: 'call_7');

    final record = h.logger.eventsOf('tool.validate.error').single;
    expect(record.level, LogLevel.debug);
    expect(record.fields['tool'], 'broken');
    expect(record.fields['tool_call_id'], 'call_7');
    expect(record.error, contains('schema is broken'));
  });

  test('a validation exception does not count in the MisuseBreaker', () async {
    final h = await ExecutorHarness.create([_BrokenSchemaTool()]);
    final breaker = MisuseBreaker(const MisuseLimits());

    await h.run('broken', const {}, invocation: h.invocation(misuse: breaker));

    expect(breaker.count(MisuseBreaker.keyOf('broken', const {})), 0);
  });

  test('a schema keyword violation counts like any step 3 error', () async {
    final h = await ExecutorHarness.create([
      FakeTool(
        'badschema',
        parameters: const {'type': 'object', 'required': 'x'},
      ),
    ]);
    final breaker = MisuseBreaker(const MisuseLimits());

    final outcome = await h.run(
      'badschema',
      const {},
      invocation: h.invocation(misuse: breaker),
    );

    expect(textOf(outcome), contains('schema: "required" must be'));
    expect(breaker.count(MisuseBreaker.keyOf('badschema', const {})), 1);
  });
}

/// Инструмент, чья схема бросает при чтении: валидатор не должен ронять цикл.
final class _BrokenSchemaTool extends AgentTool {
  @override
  String get name => 'broken';

  @override
  String get description => 'Broken schema.';

  @override
  Map<String, Object?> get parameters => throw StateError('schema is broken');

  @override
  ToolTier get tier => ToolTier.read;

  @override
  ToolKind get kind => ToolKind.other;

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.trusted;

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolExecutionResult([TextContent('never')]);
}
