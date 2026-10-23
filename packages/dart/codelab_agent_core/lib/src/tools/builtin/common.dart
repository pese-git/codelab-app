import '../../env/execution_env.dart';
import '../../llm/messages.dart';
import '../../util/posix_path.dart';
import '../agent_tool.dart';

/// Shared helpers of the built-in tools (`agent-core-architecture` §6.4):
/// paths in output are relative to the workspace, env errors become fixed
/// texts for the model.

/// The absolute path of [raw] in the env of [ctx]; `null` for `~`.
String? absolutePath(ToolContext ctx, String raw) =>
    normalizePath(ctx.env.cwd, raw);

/// [raw] as the model should see it: relative to the workspace when it is
/// inside, otherwise as given.
String displayPath(ToolContext ctx, String raw) {
  final abs = absolutePath(ctx, raw);
  return abs != null && isInside(ctx.env.cwd, abs)
      ? relativeTo(ctx.env.cwd, abs)
      : raw;
}

String fileErrorText(FileError error, ToolContext ctx, String raw) {
  final path = displayPath(ctx, raw);
  return switch (error.code) {
    FileErrorCode.notFound => 'File not found: $path',
    FileErrorCode.isDirectory =>
      '$path is a directory.'
          '${ctx.stepTools.contains('ls') ? ' Use ls to list it.' : ''}',
    FileErrorCode.outsideWorkspace => 'Path is outside the workspace: $raw',
    FileErrorCode.permissionDenied => 'Permission denied: $path',
    FileErrorCode.notText => '$path is not a UTF-8 text file.',
    FileErrorCode.unsupported =>
      'This operation is not supported in the current environment.',
    FileErrorCode.notDirectory => '$path is not a directory.',
    FileErrorCode.tooLarge => '$path is too large.',
    FileErrorCode.io => 'Cannot access $path: ${error.message ?? 'I/O error'}',
  };
}

/// The pattern of a path for «allow always» (§7.5): normalized and
/// relative to [cwd] when inside it; `.` for the root. Without [cwd] the
/// path is normalized as relative.
String pathPattern(String raw, String cwd) {
  final root = cwd.isEmpty ? '/' : cwd;
  final abs = normalizePath(root, raw);
  if (abs == null) {
    return raw;
  }
  return isInside(root, abs) ? relativeTo(root, abs) : abs;
}

ToolExecutionResult errorResult(String text) =>
    ToolExecutionResult([TextContent(text)], isError: true);

/// Lines of a `readText` result: the terminator of the last line does not
/// make an extra empty line.
List<String> splitLines(String text) {
  if (text.isEmpty) {
    return const [];
  }
  final body = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return body.split('\n');
}
