import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

import '../host/core_harness.dart' show inMemoryJournal, noExec;
import '../support/models.dart';
import 'skills_support.dart';

/// Сессия ядра с фейковым портом навыков и скриптованной моделью
/// (design.md change `add-agent-skills`, D1, D7, D16).
///
/// Почему отдельный стенд: инструмент `skill` и секция каталога собираются
/// рантаймом при открытии сессии из снимка каталога, поэтому «регистрация
/// только при `modelVisible`» и «тело из снимка» проверяются сквозь
/// `createSession` + `prompt`, а не на голом инструменте. Образец —
/// `test/runtime/skills_load_phase_test.dart`.
///
/// Как использовать: задать [steps] модели и положить навыки в [port], затем
/// `await rig.open()` и `await rig.session.prompt(...)`; запросы модели лежат
/// в [contexts].
final class SkillSessionRig {
  SkillSessionRig({
    required List<Map<String, Object?>> steps,
    SkillsConfig skills = const SkillsConfig(),
    PermissionsConfig? permissions,
  }) {
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': steps,
    }, clock: clock);
    core = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: _Env(),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
        skillFiles: port,
      ),
      config: CoreConfig(
        defaultModel: testModel,
        skills: skills,
        permissions: permissions ?? PermissionsConfig(),
      ),
      streamFunction: (ref, context, {cancel}) {
        contexts.add(context);
        return scripted.call(ref, context, cancel: cancel);
      },
    );
  }

  final port = FakeSkillPort();
  final clock = FakeClock();
  final logger = RecordingLogger();
  final contexts = <LlmContext>[];
  late final BuiltAgentCore core;
  late AgentSession session;

  /// Открывает сессию в `/work/a` (фаза навыков отрабатывает на порту).
  Future<AgentSession> open() async =>
      session = await core.runtime.createSession(SessionSpec(cwd: '/work/a'));

  /// Один ход пользователя `go`.
  Future<TurnResult> run() => session.prompt([const TextContent('go')]);

  /// Имена схем инструментов первого запроса модели.
  List<String> get firstToolNames => [
    for (final t in contexts.first.tools) t.name,
  ];

  /// Текст всех логов одной строкой: для проверки «тело не в логах».
  String get allLogs => [for (final r in logger.records) '$r'].join('\n');
}

/// Окружение сессии: `/work/a` существует, больше путей нет.
final class _Env implements ExecutionEnv, PathResolver {
  final _inner = MemoryExecutionEnv(cwd: '/work/a');

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async =>
      path == '/work/a'
      ? Ok(path)
      : Err(FileError(FileErrorCode.notFound, path));

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => _inner.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      _inner.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => _inner.stat(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}
