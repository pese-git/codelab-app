import '../env/execution_env.dart';
import '../env/memory_env.dart';
import '../llm/stream_function.dart';
import '../runtime/agent_runtime.dart';
import '../tools/builtin/edit.dart';
import '../tools/builtin/exec.dart';
import '../tools/builtin/read.dart';
import '../tools/registry.dart';
import '../util/logger.dart';
import 'host_profile.dart';
import 'services.dart';

/// What is on and why (`agent-core-architecture` §10.3).
final class CorePlan {
  CorePlan({
    required this.profile,
    required List<String> toolNames,
    required List<String> promptSections,
    required Map<HostCapability, String> offReasons,
  }) : toolNames = List.unmodifiable(toolNames),
       promptSections = List.unmodifiable(promptSections),
       offReasons = Map.unmodifiable(offReasons);

  /// Already narrowed.
  final HostProfile profile;

  /// In registration order.
  final List<String> toolNames;

  /// In assembly order; filled by `composeSystemPrompt` (tasks.md, 12.4).
  final List<String> promptSections;
  final Map<HostCapability, String> offReasons;
}

final class BuiltAgentCore {
  const BuiltAgentCore({required this.plan, required this.runtime});

  final CorePlan plan;
  final AgentRuntime runtime;
}

/// The single way to assemble the core (HOST-6; §10.7 in the scope of stage
/// 2 — design.md, D12): narrowing by the services, the tool registry by
/// capability, the policy as the first hook of every session, the plan.
/// [streamFunction] comes from the host — the factory of stage 1 or a
/// scripted model in tests.
BuiltAgentCore buildAgentCore({
  required HostProfile profile,
  required AgentCoreServices services,
  required CoreConfig config,
  required StreamFunction streamFunction,
}) {
  final narrowed = profile.narrowed({
    if (services.gate == null)
      HostCapability.interactiveApproval: const CapabilityOff(
        'PermissionGate не передан',
      ),
    if (services.baseEnv is! DirectoryListing)
      HostCapability.fileListing: const CapabilityOff(
        'env без листинга каталога',
      ),
  });
  if (narrowed.isOn(HostCapability.shellExec) &&
      services.baseEnv is MemoryExecutionEnv) {
    throw const HostWiringException(
      'capability shellExec требует сервис baseEnv с настоящим Shell.exec: '
      'у MemoryExecutionEnv его нет',
    );
  }
  final registry = ToolRegistry();
  void register(String name, void Function() add) {
    if (registry.lookup(name) != null) {
      throw HostWiringException('два встроенных инструмента с именем $name');
    }
    add();
  }

  register('read', () => registry.register(ReadTool()));
  register('edit', () => registry.register(EditTool()));
  if (narrowed.isOn(HostCapability.shellExec)) {
    register('exec', () => registry.register(ExecTool()));
  }
  final plan = CorePlan(
    profile: narrowed,
    toolNames: [for (final t in registry.tools) t.name],
    promptSections: const [],
    offReasons: {
      for (final MapEntry(key: capability, value: state)
          in narrowed.states.entries)
        if (state case CapabilityOff(:final reason)) capability: reason,
    },
  );
  services.logger.log(
    LogLevel.info,
    'host.plan',
    fields: {
      'profile': narrowed.name,
      'tools': plan.toolNames,
      'off': {for (final e in plan.offReasons.entries) e.key.name: e.value},
    },
  );
  return BuiltAgentCore(
    plan: plan,
    runtime: AgentRuntimeImpl(
      profile: narrowed,
      services: services,
      config: config,
      registry: registry,
      stream: streamFunction,
    ),
  );
}
