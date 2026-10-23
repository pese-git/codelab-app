/// Embeddable pure Dart CodeLab agent core.
///
/// Web-safe by construction: no `dart:io`, `dart:isolate`, `dart:ffi` or
/// Flutter imports (invariant PKG-1, checked by `melos run guard`).
library;

export 'src/cancel/cancel_token.dart';
export 'src/env/execution_env.dart';
export 'src/env/memory_env.dart'
    show MemoryExecutionEnv, decodeUtf8Strict, sliceLines;
export 'src/host/build_agent_core.dart';
export 'src/host/host_profile.dart';
export 'src/host/services.dart';
export 'src/llm/decorators/fallback.dart';
export 'src/llm/decorators/retry.dart' show RetryPolicy, withTransientRetry;
export 'src/llm/decorators/watchdog.dart';
export 'src/llm/errors.dart';
export 'src/llm/event_stream.dart';
export 'src/llm/events.dart';
export 'src/llm/messages.dart';
export 'src/llm/model_catalog.dart';
export 'src/llm/model_ref.dart';
export 'src/llm/overflow.dart' show isContextOverflow;
export 'src/llm/provider_config.dart';
export 'src/llm/provider_factory.dart';
export 'src/llm/stream_function.dart';
export 'src/llm/usage.dart';
export 'src/loop/agent_events.dart';
export 'src/loop/loop_config.dart'
    show
        AfterToolCallHook,
        AgentEventSink,
        BeforeToolCallHook,
        Block,
        ResultOverride,
        StepResult,
        StepUpdate;
export 'src/loop/turn_budget.dart';
export 'src/permissions/gate.dart';
export 'src/permissions/modes.dart';
export 'src/permissions/pattern.dart';
export 'src/permissions/policy.dart' show PolicyRules;
export 'src/runtime/agent_runtime.dart' show AgentRuntime;
export 'src/runtime/agent_session.dart';
export 'src/tools/agent_tool.dart';
export 'src/util/clock.dart' show Clock, ClockTimer, SystemClock;
export 'src/util/ids.dart';
export 'src/util/logger.dart';
export 'src/util/result.dart';

const codelabAgentCorePackageName = 'codelab_agent_core';
