import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'executor_harness.dart';

/// Ограда `untrusted-content` не имеет лазеек (TOOL-10): результат любого
/// инструмента с `outputTrust` `untrusted` — успех и ошибка — огораживается
/// единой точкой исполнения (design.md change `add-subagents-and-tasks`:
/// ошибки проверки `agent` идут исключением, а не флагом результата).
final class _Untrusted extends AgentTool {
  _Untrusted(this.result);

  final ToolExecutionResult result;

  @override
  String get name => 'u';

  @override
  String get description => 'u';

  @override
  Map<String, Object?> get parameters => const {'type': 'object'};

  @override
  ToolTier get tier => ToolTier.read;

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => result;
}

void main() {
  for (final isError in [false, true]) {
    test('untrusted result (isError: $isError) is fenced', () async {
      final h = await ExecutorHarness.create([
        _Untrusted(
          ToolExecutionResult([TextContent('data')], isError: isError),
        ),
      ]);

      final outcome = await h.run('u', const {});

      expect(textOf(outcome), startsWith('<untrusted-content source="u">'));
    });
  }
}
