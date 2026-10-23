import '../../env/execution_env.dart';
import '../../llm/messages.dart';
import '../../util/result.dart';
import '../agent_tool.dart';
import '../fence.dart';
import '../truncate.dart';
import 'common.dart';

const _defaultTimeout = 120;
const _maxTimeout = 3600;

/// `exec` — a shell command (`agent-core-architecture` §6.4). A non-zero
/// exit code is an error result with the output: data for the model.
final class ExecTool extends AgentTool {
  @override
  String get name => 'exec';

  @override
  String get description =>
      'Run a non-interactive shell command in the workspace and return its '
      'output (the last lines of a long output).';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'command': {'type': 'string', 'description': 'Shell command to run.'},
      'timeout': {
        'type': 'integer',
        'description': 'Timeout in seconds. Default 120, maximum 3600.',
      },
      'cwd': {
        'type': 'string',
        'description':
            'Working directory, relative to the workspace root. Default: root.',
      },
    },
    'required': ['command'],
  };

  @override
  ToolTier get tier => ToolTier.exec;

  @override
  ToolKind get kind => ToolKind.execute;

  @override
  bool get truncatesOutput => true;

  /// A network command brings third-party text (§6.3.6, §10.6).
  @override
  ContentTrust outputTrust(Map<String, Object?> args) =>
      isNetworkCommand('${args['command']}')
      ? ContentTrust.untrusted
      : ContentTrust.trusted;

  @override
  String permissionPattern(Map<String, Object?> args, String cwd) =>
      '${args['command']}'.trim();

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolPresentation(title: '${args['command']}');

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final command = args['command']! as String;
    final cwd = args['cwd'] as String? ?? '.';
    final notes = <String>[];
    var timeout = args['timeout'] as int? ?? _defaultTimeout;
    if (timeout < 1 || timeout > _maxTimeout) {
      timeout = timeout < 1 ? 1 : _maxTimeout;
      notes.add(
        '[Note: timeout must be within 1..$_maxTimeout seconds; using $timeout.]',
      );
    }
    final result = await ctx.env.exec(
      command,
      ExecOptions(
        cwd: cwd,
        timeout: Duration(seconds: timeout),
        cancel: ctx.cancel,
        onOutput: (chunk) =>
            ctx.onUpdate(ToolExecutionResult([TextContent(chunk)])),
      ),
    );
    switch (result) {
      case Ok(:final value):
        final failed = value.exitCode != 0;
        final text = _join([
          if (value.output.isEmpty && !failed)
            '(no output)'
          else
            _tail(value.output),
          if (failed)
            '[Command exited with ${value.exitCode == null ? 'signal ${value.signal}' : 'code ${value.exitCode}'}]',
          ...notes,
        ]);
        return ToolExecutionResult([TextContent(text)], isError: failed);
      case Err(:final error):
        return _failure(error, cwd, ctx, notes);
    }
  }

  static ToolExecutionResult _failure(
    ExecError error,
    String cwd,
    ToolContext ctx,
    List<String> notes,
  ) {
    final seconds = ((error.duration ?? Duration.zero).inMilliseconds / 1000)
        .toStringAsFixed(1);
    final text = switch (error.code) {
      ExecErrorCode.timeout => _join([
        _tail(error.outputTail),
        '[Command timed out after $seconds s and was terminated]',
      ]),
      ExecErrorCode.aborted => _join([
        _tail(error.outputTail),
        '[Command was cancelled after $seconds s]',
      ]),
      ExecErrorCode.shellUnavailable =>
        'Shell commands are not available in this environment.',
      ExecErrorCode.outsideWorkspace => 'Path is outside the workspace: $cwd',
      ExecErrorCode.spawnFailed || ExecErrorCode.unknown =>
        'Command failed to start: ${error.message ?? error.code.name}',
    };
    if (error.code == ExecErrorCode.aborted) {
      throw ToolCancelled([
        TextContent(_join([text, ...notes])),
      ]);
    }
    return errorResult(_join([text, ...notes]));
  }

  static String _tail(String output) {
    final cut = truncateTail(output);
    return cut.truncated
        ? '${cut.text}\n${TruncationNotices.exec(kept: cut.keptLines, total: cut.totalLines)}'
        : cut.text;
  }

  static String _join(List<String> parts) {
    final kept = [
      for (final p in parts)
        if (p.isNotEmpty) p,
    ];
    return kept.join('\n');
  }
}
