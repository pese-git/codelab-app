import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

import '../support/models.dart';

/// Builds the core over [baseEnv] with a scripted model.
final class CoreHarness {
  CoreHarness._(this.core, this.model, this.clock, this.logger, this.sessions);

  static CoreHarness build({
    required ExecutionEnv baseEnv,
    required List<Map<String, Object?>> steps,
    String profile = 'agent-serve',
    Map<HostCapability, CapabilityState> narrow = const {},
    PermissionGate? gate,
    PermissionMode? modeOverride,
    FakeClock? clock,
    SessionStore? sessions,
  }) {
    final c = clock ?? FakeClock();
    final logger = RecordingLogger();
    final model = ScriptedStreamFunction.fromJson({'steps': steps}, clock: c);
    final store = sessions ?? MemorySessionStore();
    final core = buildAgentCore(
      profile: HostProfile.of(profile).narrowed({
        // Журнал теста — в памяти: постоянного носителя нет (design.md, D12).
        if (store is MemorySessionStore) ...inMemoryJournal,
        ...narrow,
      }),
      services: AgentCoreServices(
        baseEnv: baseEnv,
        gate: gate,
        logger: logger,
        clock: c,
        ids: SequentialIdGenerator(),
        sessions: store,
      ),
      config: CoreConfig(
        defaultModel: testModel,
        permissions: PermissionsConfig(modeOverride: modeOverride),
      ),
      streamFunction: model.call,
    );
    return CoreHarness._(core, model, c, logger, store);
  }

  final BuiltAgentCore core;
  final ScriptedStreamFunction model;
  final FakeClock clock;
  final RecordingLogger logger;
  final SessionStore sessions;
}

const inMemoryJournal = {
  HostCapability.sessionPersistence: CapabilityOff('журнал теста в памяти'),
};

const noExec = {HostCapability.shellExec: CapabilityOff('тест без shell')};

Map<String, Object?> callStep(
  String id,
  String name,
  Map<String, Object?> args,
) => {
  'reply': [
    {
      'toolCall': {'id': id, 'name': name, 'arguments': args},
    },
  ],
};

Map<String, Object?> textStep(String text) => {
  'reply': [
    {'text': text},
  ],
};
