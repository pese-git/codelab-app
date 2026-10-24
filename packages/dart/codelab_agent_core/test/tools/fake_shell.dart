import 'package:codelab_agent_core/codelab_agent_core.dart';

typedef ShellHandler =
    Future<Result<ExecResult, ExecError>> Function(
      String command,
      ExecOptions options,
    );

/// [MemoryExecutionEnv] with a scripted shell: [handler] answers every
/// `exec`; [commands] records them.
final class FakeShellEnv implements ExecutionEnv, DirectoryListing {
  FakeShellEnv(this.memory, this.handler);

  final MemoryExecutionEnv memory;
  final ShellHandler handler;
  final commands = <String>[];

  @override
  String get cwd => memory.cwd;

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) {
    commands.add(command);
    return handler(command, options);
  }

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => memory.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      memory.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => memory.stat(path);

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) =>
      memory.listDir(path);
}

/// A shell that prints [output] and exits with [exitCode].
ShellHandler answering(String output, {int exitCode = 0}) =>
    (command, options) async {
      options.onOutput?.call(output);
      return Ok(
        ExecResult(
          exitCode: exitCode,
          output: output,
          truncated: false,
          duration: const Duration(milliseconds: 1500),
        ),
      );
    };
