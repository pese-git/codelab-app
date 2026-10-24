import 'dart:async';

import '../cancel/cancel_token.dart';
import '../env/bounded_env.dart';
import '../llm/messages.dart';
import '../llm/stream_function.dart';
import '../loop/agent.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../permissions/modes.dart';
import '../permissions/policy.dart';
import '../tools/agent_tool.dart';
import '../tools/executor.dart';
import '../tools/registry.dart';
import '../host/host_profile.dart';
import '../host/services.dart';
import 'agent_session.dart';

/// The runtime of the core (`agent-core-architecture` §5.6): creates and
/// keeps the sessions of this process. Stage 2 keeps sessions in memory;
/// the journal, `loadSession` and the list from the store arrive at stage
/// 3 (design.md, D4).
abstract interface class AgentRuntime {
  Future<AgentSession> createSession(SessionSpec spec);

  /// Sessions of this process in creation order.
  Future<List<SessionSummary>> listSessions();

  /// Cancels running turns and closes the event streams.
  Future<void> dispose();
}

/// Created only by `buildAgentCore` (HOST-6).
final class AgentRuntimeImpl implements AgentRuntime {
  AgentRuntimeImpl({
    required this.profile,
    required this.services,
    required this.config,
    required this.registry,
    required this.stream,
  });

  final HostProfile profile;
  final AgentCoreServices services;
  final CoreConfig config;
  final ToolRegistry registry;
  final StreamFunction stream;
  final _sessions = <_Session>[];

  @override
  Future<AgentSession> createSession(SessionSpec spec) async {
    final id = SessionId(services.ids.nextId());
    final env = await BoundedEnv.wrap(
      spec.ports.env ?? services.baseEnv,
      spec.cwd,
    );
    final logger = spec.ports.logger ?? services.logger;
    final tools = ToolServices(clock: services.clock, logger: logger);
    final plan = tools.plan;
    final gate = profile.isOn(HostCapability.interactiveApproval)
        ? spec.ports.gate ?? services.gate
        : null;
    final mode = spec.mode ?? config.permissions.mode ?? profile.defaultMode;
    final policy = PermissionPolicy(
      mode: mode,
      modeOverride: config.permissions.modeOverride,
      gate: gate,
      rules: config.permissions.rules,
      logger: logger,
    );
    final agent = Agent(
      config: AgentLoopConfig(
        sessionId: id,
        model: spec.model ?? config.defaultModel,
        stream: stream,
        executor: ToolCallExecutor(
          registry: registry,
          env: env,
          services: tools,
        ),
        clock: services.clock,
        ids: services.ids,
        budget: config.budget,
        beforeToolCall: [
          policy.asHook(registry.lookup),
          ...spec.extraBeforeToolCall,
        ],
        afterToolCall: spec.extraAfterToolCall,
        approvalWait: tools.approvalWait,
        logger: logger,
      ),
      // The system prompt is composed by composeSystemPrompt (tasks.md, 12.4).
      systemPrompt: '',
      tools: registry.tools,
    );
    // План эмитится через очередь агента: PlanUpdated приходит подписчикам
    // между ToolCallStarted и ToolCallFinished своего вызова (design.md, D5).
    plan.publish = (entries) => agent.emit(PlanUpdated(id, entries: entries));
    final session = _Session(
      id,
      spec.cwd,
      mode,
      agent,
      policy,
      tools,
      services,
    );
    _sessions.add(session);
    return session;
  }

  @override
  Future<List<SessionSummary>> listSessions() async => [
    for (final s in _sessions) SessionSummary(id: s.id, cwd: s.cwd),
  ];

  @override
  Future<void> dispose() async {
    for (final session in _sessions) {
      await session.close();
    }
    _sessions.clear();
  }
}

final class _Session implements AgentSession {
  _Session(
    this.id,
    this.cwd,
    this._mode,
    this._agent,
    this._policy,
    this._tools,
    this._services,
  ) {
    _agent.subscribe(_publish);
  }

  @override
  final SessionId id;
  final String cwd;
  ModeId _mode;
  final Agent _agent;
  final PermissionPolicy _policy;
  final ToolServices _tools;
  final AgentCoreServices _services;
  final _live = StreamController<AgentEvent>.broadcast(sync: true);
  final _turn = <AgentEvent>[];
  TurnEnded? _ended;

  @override
  ModeId get mode => _mode;

  @override
  Stream<AgentEvent> get events => Stream.multi((controller) {
    for (final event in _turn) {
      controller.add(event);
    }
    final subscription = _live.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  @override
  Future<TurnResult> prompt(
    List<ContentBlock> content, {
    CancelToken? cancel,
  }) async {
    if (_agent.isRunning) {
      throw StateError('a turn is already running');
    }
    _policy.clearTurnGrants();
    _tools.approvalWait.reset();
    _ended = null;
    cancel?.onCancel.then((_) => _agent.abort(cancel.reason));
    await _agent.prompt([
      UserMessage(content, timestamp: _services.clock.now()),
    ]);
    final ended = _ended!;
    return TurnResult(
      reason: ended.reason,
      usage: ended.usage,
      budgetExceeded: ended.budgetExceeded,
      held: ended.held,
    );
  }

  @override
  Future<void> cancel() async => _agent.abort(const UserCancel());

  @override
  Future<void> setMode(ModeId mode) async {
    _mode = mode;
    _policy.mode = mode;
    _publish(ModeChanged(id, mode: mode));
  }

  void _publish(AgentEvent event) {
    if (event is TurnStarted) {
      _turn.clear();
    }
    if (event is TurnEnded) {
      _ended = event;
    }
    _turn.add(event);
    _live.add(event);
  }

  Future<void> close() async {
    _agent.abort(const ShutdownCancel());
    await _agent.waitForIdle();
    await _live.close();
  }
}
