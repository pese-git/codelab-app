import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:codelab_agent_core/src/skills/skill_block.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart' show callStep, inMemoryJournal, noExec;
import '../support/models.dart';
import 'skills_support.dart';

/// Ответ рантайма на один ход: события, текст сообщения агента и итог.
final class SkillTurn {
  SkillTurn(this.events, this.result);

  final List<AgentEvent> events;
  final TurnResult result;

  /// Текст сообщений агента, склеенный (ответ встроенной команды).
  String get text => [
    for (final e in events.whereType<MessageEnded>())
      for (final b in e.message.content.whereType<TextContent>()) b.text,
  ].join();
}

/// Сессия ядра с портом навыков, портом шаблонов и скриптованной моделью для
/// тестов команд `/skill:<name>` (design.md change `add-agent-skills`, D8,
/// D13, D16).
///
/// Почему отдельный стенд от `SkillSessionRig`: тестам команд нужны журнал
/// (`store`), события хода, шаблоны рядом с навыками и сужение capability, а
/// `SkillSessionRig` отдаёт только запросы модели. Образцы —
/// `test/skills/skill_session_rig.dart` и `test/runtime/command_expansion_test.dart`.
///
/// Как использовать: передать [skills] (и, при надобности, [templates],
/// [narrow], [settings]), затем `await rig.open()` и `await rig.ask('/skill:x')`.
/// Модель скриптована: [steps] по умолчанию — достаточно ответов `ok`.
final class SkillCommandRig {
  SkillCommandRig({
    List<SkillFile> skills = const [],
    List<MarkdownFile> templates = const [],
    Map<HostCapability, CapabilityState> narrow = const {},
    SkillsConfig settings = const SkillsConfig(),
    List<Map<String, Object?>>? steps,
  }) {
    port.files = SkillFiles(skills: skills);
    final scripted = ScriptedStreamFunction.fromJson({
      'steps':
          steps ??
          [
            for (var i = 0; i < 12; i++)
              {
                'reply': [
                  {'text': 'ok'},
                ],
              },
          ],
    }, clock: clock);
    core = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec, ...narrow}),
      services: AgentCoreServices(
        baseEnv: _Env(),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
        skillFiles: port,
        projectFiles: templates.isEmpty ? null : _Templates(templates),
      ),
      config: CoreConfig(defaultModel: testModel, skills: settings),
      streamFunction: (ref, context, {cancel}) {
        contexts.add(context);
        return scripted.call(ref, context, cancel: cancel);
      },
    );
  }

  final port = FakeSkillPort();
  final clock = FakeClock();
  final logger = RecordingLogger();
  final store = MemorySessionStore();
  final contexts = <LlmContext>[];
  late final BuiltAgentCore core;
  late AgentSession session;

  /// Открывает сессию в `/work/a`.
  Future<AgentSession> open() async =>
      session = await core.runtime.createSession(SessionSpec(cwd: '/work/a'));

  /// Число запросов к модели.
  int get streamCalls => contexts.length;

  /// Отправляет [text] первым блоком (и [more] следом) и собирает ход.
  Future<SkillTurn> ask(
    String text, {
    List<ContentBlock> more = const [],
  }) async {
    final events = <AgentEvent>[];
    final subscription = session.events.listen(events.add);
    final result = await session.prompt([TextContent(text), ...more]);
    await pumpEventQueue();
    await subscription.cancel();
    return SkillTurn(events, result);
  }

  /// Определение навыка из снимка каталога сессии.
  SkillDefinition definition(String name) =>
      session.skills.skills.firstWhere((s) => s.name == name);

  /// Последнее сообщение пользователя в последнем запросе модели.
  UserMessage get lastUserMessage =>
      contexts.last.messages.whereType<UserMessage>().last;

  /// Текст [lastUserMessage] (все текстовые блоки подряд).
  String get lastUserText => [
    for (final b in lastUserMessage.content.whereType<TextContent>()) b.text,
  ].join();

  /// Записи журнала сессии как JSON.
  List<Map<String, Object?>> journal() => [
    for (final line in const LineSplitter().convert(store.textOf(session.id)!))
      jsonDecode(line) as Map<String, Object?>,
  ];

  /// Текст всех логов одной строкой: для проверки «тела и аргументов нет».
  String get allLogs => [for (final r in logger.records) '$r'].join('\n');

  /// Ожидаемое сообщение пользователя для `/skill:<name>`: обёртка
  /// `prompts/skills/invoked.md` вокруг блока навыка с телом [body].
  String invoked(String name, {String? body}) => Prompts.skillsInvoked.render({
    'name': name,
    'block': renderSkillBlock(definition(name), body: body),
  });
}

/// Шаг модели: вызов инструмента `skill` с именем [name].
Map<String, Object?> loadSkillStep(String callId, String name) =>
    callStep(callId, 'skill', {'name': name});

/// Окружение сессии: `/work/a` существует (фаза навыков резолвит путь).
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

final class _Templates implements ProjectFilesSource {
  _Templates(this.files);

  final List<MarkdownFile> files;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(templates: files);
}

/// Шаблон команды пользователя `$CODELAB_HOME/prompts/<name>.md`.
MarkdownFile templateFile(String name, String body) => MarkdownFile(
  path: '/home/.codelab/prompts/$name.md',
  scope: ExtensionScope.user,
  body: body,
  bodyLine: 1,
);
