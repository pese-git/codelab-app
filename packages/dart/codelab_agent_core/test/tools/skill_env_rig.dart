import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:codelab_agent_core/src/tools/registry.dart';
import 'package:codelab_agent_core/testing.dart';

import 'executor_harness.dart' show session;

/// Стенд инструментов над env с корнями только для чтения (design.md change
/// `add-agent-skills`, D5, D9).
///
/// Почему отдельный стенд, а не `ExecutorHarness`: тот оборачивает env как
/// `BoundedEnv.wrap(base, base.cwd)` без корней, а тесты `exec` с `cwd` в
/// каталоге навыка и `read` файлов навыка вне рабочей папки требуют
/// `readOnlyRoots`/`readOnlyFs` — их рантайм передаёт при открытии сессии.
///
/// Как использовать: `await SkillToolRig.create([...tools], base: shell,
/// hostFs: files, readOnlyRoots: [dir])`, затем `rig.run('read', {...})`.
final class SkillToolRig {
  SkillToolRig._(this.env, this.executor, this.registry, this.logger);

  static Future<SkillToolRig> create(
    List<AgentTool> tools, {
    required ExecutionEnv base,
    ExecutionEnv? hostFs,
    List<String> readOnlyRoots = const [],
    bool execInReadOnlyRoots = false,
  }) async {
    final clock = FakeClock();
    final env = await BoundedEnv.wrap(
      base,
      base.cwd,
      readOnlyRoots: readOnlyRoots,
      readOnlyFs: hostFs,
      execInReadOnlyRoots: execInReadOnlyRoots,
    );
    final registry = ToolRegistry();
    tools.forEach(registry.register);
    final logger = RecordingLogger();
    return SkillToolRig._(
      env,
      ToolCallExecutor(
        registry: registry,
        env: env,
        services: ToolServices(clock: clock, logger: logger),
      ),
      registry,
      logger,
    );
  }

  final ExecutionEnv env;
  final ToolCallExecutor executor;
  final ToolRegistry registry;
  final RecordingLogger logger;
  final events = <AgentEvent>[];

  Future<ToolExecutionOutcome> run(
    String name,
    Map<String, Object?> args,
  ) async {
    final handle = await executor.announce(
      ToolCall(id: 'call_1', name: name, arguments: args),
      ToolInvocation(
        sessionId: session,
        cancel: CancelToken.none,
        stepTools: [for (final t in registry.tools) t.name],
        emit: events.add,
      ),
    );
    return executor.complete(handle);
  }
}

String textOfOutcome(ToolExecutionOutcome outcome) => outcome.message.content
    .whereType<TextContent>()
    .map((b) => b.text)
    .join('\n');
