import 'package:structured_log/structured_log.dart' as structured_log;

import '../domain/logger.dart';
import '../domain/secret_redaction.dart';

/// Context key used to route an entry to a sink by category
/// (see `structured_log`'s `LogSink.categories`).
const logCategoryKey = 'category';

/// Context key identifying which architectural layer produced an entry —
/// see `docs/architecture/observability.md` §3 (logging ownership).
const logComponentKey = 'component';

/// Category routing an entry to the human-readable application sink.
const applicationLogCategory = 'application';

/// Category routing an entry to the developer-only protocol-trace sink.
const protocolTraceLogCategory = 'protocol';

/// Name of the protocol-trace file sink, for [setProtocolTracingEnabled].
const protocolTraceSinkName = 'protocol';

const _applicationSinkName = 'application';

/// Name of the optional in-app log viewer sink, for reference in tests.
const inAppViewerSinkName = 'debug-panel';

/// Component tag for events originating in `acp_transports`.
const transportComponent = 'transport';

/// Component tag for events originating in `acp_protocol`.
const protocolComponent = 'protocol';

/// Component tag for events originating in `acp_client_core`'s own
/// application-lifecycle logic (session/request/reconnect/cancellation/
/// permission).
const clientComponent = 'client';

/// Component tag for presentation-layer events (significant user intents,
/// UI-level failures).
const presentationComponent = 'presentation';

/// [structured_log]-backed [Logger] adapter. Wraps a `BoundLogger` obtained
/// through the package's global `getLogger()`/`StructlogConfiguration`
/// singleton — a deliberate exception to the project's general
/// no-global-service-locator rule, see `design.md` Decision 7.
final class StructuredLogLogger implements Logger {
  StructuredLogLogger._(this._delegate);

  /// Creates a logger bound to [name] (stored under the `logger` context
  /// key), reading the current global `StructlogConfiguration`.
  factory StructuredLogLogger([String? name]) =>
      StructuredLogLogger._(structured_log.getLogger(name));

  final structured_log.BoundLogger _delegate;

  @override
  Logger bind(Map<String, Object?> context) =>
      StructuredLogLogger._(_delegate.bind(context));

  @override
  Logger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  }) => StructuredLogLogger._(
    _delegate.withCorrelation(
      sessionId: sessionId,
      requestId: requestId,
      connectionGeneration: connectionGeneration,
      toolCallId: toolCallId,
      messageId: messageId,
      operationId: operationId,
    ),
  );

  @override
  void trace(String? event, {Map<String, Object?>? context}) =>
      _delegate.trace(event, context: context);

  @override
  void debug(String? event, {Map<String, Object?>? context}) =>
      _delegate.debug(event, context: context);

  @override
  void info(String? event, {Map<String, Object?>? context}) =>
      _delegate.info(event, context: context);

  @override
  void warning(String? event, {Map<String, Object?>? context}) =>
      _delegate.warning(event, context: context);

  @override
  void error(String? event, {Map<String, Object?>? context}) =>
      _delegate.error(event, context: context);

  @override
  void critical(String? event, {Map<String, Object?>? context}) =>
      _delegate.critical(event, context: context);
}

/// [structured_log] `Processor` that redacts secrets from every log entry
/// using the project's existing [SecretRedactor] — the single source of
/// truth for masking (`docs/architecture/observability.md` §12-14), reused
/// rather than duplicated as a separate redaction ruleset.
Map<String, dynamic>? secretRedactionProcessor(Map<String, dynamic> entry) {
  return const SecretRedactor().redactMap(entry);
}

/// Configures the global `structured_log` singleton for CodeLab
/// (`design.md` Decision 6/7): an [applicationOutput] sink for
/// human-readable/application-level events, a developer-only,
/// off-by-default [protocolTraceOutput] sink for full ACP payload tracing,
/// and an optional [inAppViewerOutput] sink feeding the in-app log viewer
/// (`replace-debug-log-panel-with-fluent` `design.md` Decision 3).
///
/// [inAppViewerOutput] always receives both `category=application` and
/// `category=protocol` events, unconditionally — [protocolTraceOutput]'s
/// file sink keeps its own independent, off-by-default toggle
/// ([setProtocolTracingEnabled]), but the in-app viewer's `LogBuffer` is
/// bounded/in-memory and redacted like every other sink, so there is no
/// capture-side reason to gate it too; which events are actually shown is a
/// view concern, left to `LogViewerController.categoryFilter` in the UI
/// (`design.md` Decision 5, revised) rather than an enable/disable toggle.
///
/// The composition root supplies concrete outputs (console vs file per
/// build mode, platform-specific paths) — this pure-Dart function only
/// wires sinks/processors/filtering, since `acp_client_core` must not
/// depend on Flutter to detect debug/release builds itself
/// (`layers-and-dependencies.md` §7).
void configureCodeLabLogging({
  required structured_log.OutputFunction applicationOutput,
  required structured_log.OutputFunction protocolTraceOutput,
  structured_log.OutputFunction? inAppViewerOutput,
  bool protocolTracingEnabledByDefault = false,
}) {
  structured_log.StructlogConfiguration.configure(
    processors: [secretRedactionProcessor, structured_log.dropNullValues],
    sinks: [
      structured_log.LogSink(
        name: _applicationSinkName,
        output: applicationOutput,
        categories: const {applicationLogCategory},
      ),
      if (inAppViewerOutput != null)
        structured_log.LogSink(
          name: inAppViewerSinkName,
          output: inAppViewerOutput,
          minLevel: structured_log.LogLevel.trace,
          categories: const {applicationLogCategory, protocolTraceLogCategory},
        ),
      structured_log.LogSink(
        name: protocolTraceSinkName,
        output: protocolTraceOutput,
        minLevel: structured_log.LogLevel.trace,
        categories: const {protocolTraceLogCategory},
        enabled: protocolTracingEnabledByDefault,
      ),
    ],
  );
}

/// Toggles the developer-only `protocol.log` file sink at runtime
/// (`design.md` Decision 4) — callers must never invoke this automatically
/// on error, only on explicit debug/developer action. Does not affect the
/// in-app viewer, which always captures protocol-trace events (see
/// [configureCodeLabLogging]) — filtering what's shown there is a UI
/// concern (`LogViewerController.categoryFilter`), not a capture toggle.
void setProtocolTracingEnabled(bool enabled) {
  structured_log.StructlogConfiguration.setSinkEnabled(
    protocolTraceSinkName,
    enabled: enabled,
  );
}

/// Whether the `protocol.log` file sink is currently enabled — reflects the
/// state [setProtocolTracingEnabled] last set (or [configureCodeLabLogging]'s
/// `protocolTracingEnabledByDefault`).
bool isProtocolTracingEnabled() {
  return structured_log.StructlogConfiguration.current.sinks
      .firstWhere((sink) => sink.name == protocolTraceSinkName)
      .enabled;
}
