import '../cancel/cancel_token.dart';
import '../env/execution_env.dart';
import '../llm/messages.dart';
import '../llm/stream_function.dart';
import '../loop/agent_events.dart';
import '../util/canonical_json.dart';
import '../util/clock.dart';
import '../util/logger.dart';

/// Contract of a tool (`agent-core-architecture` §6.2): an object that
/// describes itself to the model and runs over [ExecutionEnv]. Built-in,
/// MCP and plugin tools share one registry and one execution point
/// (TOOL-1).

/// `exec` by default (TOOL-5); `network` — a model-chosen address (after
/// MVP).
enum ToolTier { read, write, network, exec }

enum ToolExecutionMode { parallel, sequential }

/// = ACP `ToolKind`.
enum ToolKind { read, edit, delete, move, search, execute, think, fetch, other }

enum ContentTrust { trusted, untrusted }

abstract base class AgentTool {
  String get name;
  String get description;

  /// JSON Schema of an object (subset of §6.3.2).
  Map<String, Object?> get parameters;

  ToolTier get tier => ToolTier.exec;
  ToolExecutionMode? get executionMode => null;
  ToolKind get kind => ToolKind.other;

  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.untrusted;

  /// Title, locations and diffs of the call for the client and for the
  /// approval request; may read the env of [ctx]. [args] may be raw (before
  /// validation), so a throwing implementation falls back to the name.
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolPresentation(title: name);

  /// The pattern of «allow always» (§7.5); by default the canonical JSON of
  /// the arguments. [cwd] is the session root: paths are relative to it.
  String permissionPattern(Map<String, Object?> args, String cwd) =>
      canonicalJson(args);

  /// A check of the arguments before permissions: an English error text
  /// for the model or `null`. Has no side effects (PERM-1).
  String? preflight(Map<String, Object?> args) => null;

  /// The tool truncates its output itself, with its own notice (§6.3.5);
  /// otherwise the execution point truncates the head with a generic
  /// notice (TOOL-9).
  bool get truncatesOutput => false;

  ToolTier tierOf(Map<String, Object?> args) => tier;
  ToolKind kindOf(Map<String, Object?> args) => kind;
  ToolExecutionMode? executionModeOf(Map<String, Object?> args) =>
      executionMode;
  bool offersAllowAlways(Map<String, Object?> args) => true;

  /// Runs with validated and coerced [args] (TOOL-2); called only by the
  /// single execution point (TOOL-1).
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  );

  ToolSchema toSchema() =>
      ToolSchema(name: name, description: description, parameters: parameters);
}

final class ToolContext {
  ToolContext({
    required this.env,
    required this.cancel,
    required this.onUpdate,
    required this.toolCallId,
    required this.services,
    List<String> stepTools = const [],
  }) : stepTools = List.unmodifiable(stepTools);

  /// Always the bounded env of the session (ENV-2).
  final ExecutionEnv env;
  final CancelToken cancel;
  final void Function(ToolExecutionResult partial) onUpdate;
  final String toolCallId;
  final ToolServices services;

  /// Tool names of the schemas of the current step: a text may mention
  /// only tools the model can call (§6.4).
  final List<String> stepTools;
}

/// Services of the session for tools; later stages add fields.
final class ToolServices {
  ToolServices({
    required this.clock,
    required this.logger,
    ApprovalWaitMeter? approvalWait,
  }) : approvalWait = approvalWait ?? ApprovalWaitMeter();

  final Clock clock;
  final Logger logger;

  /// Time spent waiting for the user: kept out of the turn time (§5.2).
  final ApprovalWaitMeter approvalWait;
}

/// Sum of the waits for `PermissionGate` in the current turn.
final class ApprovalWaitMeter {
  var _total = Duration.zero;

  Duration get total => _total;

  void add(Duration wait) => _total += wait;

  /// Called by the loop at the start of a turn.
  void reset() => _total = Duration.zero;
}

final class ToolExecutionResult {
  const ToolExecutionResult(
    this.content, {
    this.diffs = const [],
    this.isError = false,
  });

  /// [TextContent] and [ImageContent].
  final List<ContentBlock> content;

  /// One per changed file.
  final List<FileDiff> diffs;

  /// The tool reports an error without an exception.
  final bool isError;
}

final class ToolPresentation {
  const ToolPresentation({
    required this.title,
    this.locations = const [],
    this.diffs = const [],
  });

  final String title;
  final List<Location> locations;
  final List<FileDiff> diffs;
}

final class Location {
  const Location(this.path, {this.line});

  /// Absolute path.
  final String path;
  final int? line;

  @override
  bool operator ==(Object other) =>
      other is Location && other.path == path && other.line == line;

  @override
  int get hashCode => Object.hash(path, line);

  @override
  String toString() => 'Location($path${line == null ? '' : ':$line'})';
}

final class FileDiff {
  const FileDiff({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  /// Absolute path.
  final String path;

  /// `null` — a new file.
  final String? oldText;
  final String newText;

  @override
  bool operator ==(Object other) =>
      other is FileDiff &&
      other.path == path &&
      other.oldText == oldText &&
      other.newText == newText;

  @override
  int get hashCode => Object.hash(path, oldText, newText);

  @override
  String toString() => 'FileDiff($path)';
}

/// Content of a call update for the client (= ACP `ToolCallContent`).
sealed class ToolCallContent {
  const ToolCallContent();
}

final class ToolCallBlock extends ToolCallContent {
  const ToolCallBlock(this.block);

  final ContentBlock block;
}

final class ToolCallDiff extends ToolCallContent {
  const ToolCallDiff(this.diff);

  final FileDiff diff;
}

final class ToolCallTerminal extends ToolCallContent {
  const ToolCallTerminal(this.terminalId);

  final String terminalId;
}

/// Thrown by a tool that stopped on cancel and has its own text for the
/// model (`exec`: `[Command was cancelled after <t> s]`): outcome
/// `cancelled` with [content].
final class ToolCancelled implements Exception {
  const ToolCancelled(this.content);

  final List<ContentBlock> content;
}

final class ToolExecutionOutcome {
  ToolExecutionOutcome({
    required this.message,
    required this.outcome,
    List<FileDiff> diffs = const [],
  }) : diffs = List.unmodifiable(diffs);

  final ToolResultMessage message;
  final ToolOutcome outcome;
  final List<FileDiff> diffs;
}
