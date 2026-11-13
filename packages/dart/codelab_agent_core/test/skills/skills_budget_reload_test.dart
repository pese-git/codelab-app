import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' show baseValues, layer;
import '../host/core_harness.dart' show inMemoryJournal, noExec, textStep;
import 'skill_command_rig.dart' show loadSkillStep;
import 'skills_support.dart';

/// Бюджеты приложения закреплены за сессией (задача 4.3, M1 ревью
/// безопасности итерации 4; design.md change `add-agent-skills`, D11, D20
/// «M1»; agent-compaction «Навыки после сжатия», п. 7, сценарий
/// «Перезагрузка не меняет бюджеты живой сессии»).
///
/// Почему: ключи `skills.reattach.*` не `restartRequired`, и `reloadConfig`
/// меняет настройки, но транскрипт живой сессии собран со старыми бюджетами.
/// Если `activeSkills` и `compact` читают бюджеты в момент вызова, усечённый
/// навык после перезагрузки становится «активным» и `skill` отвечает
/// «already loaded», хотя модель видит только обрезок. Снимок `SkillsConfig`
/// берётся при `createSession`/`loadSession`, как каталог.
void main() {
  String rows(int count) => [
    for (var i = 0; i < count; i++)
      'row ${i.toString().padLeft(4, '0')} ${'-' * 31}',
  ].join('\n');

  group('a reload does not change the budgets of a live session', () {
    test('per_skill 100 -> 16384: the truncated skill stays full: false, '
        '/skill: gives the full block', () async {
      final rig = await _Rig.create(
        perSkill: 100,
        skills: [validSkill('big', body: rows(100))],
      );
      await rig.compacted('big');

      await rig.raiseBudgets(perSkill: 16384);
      await rig.ask('/skill:big', steps: [textStep('r1')]);

      expect(rig.lastUserText, contains('row 0000'));
      expect(rig.lastUserText, isNot(contains('already loaded')));
    });

    test('per_skill 100 -> 16384: the skill tool gives the full block, not '
        '"already loaded"', () async {
      final rig = await _Rig.create(
        perSkill: 100,
        skills: [validSkill('big', body: rows(100))],
      );
      await rig.compacted('big');

      await rig.raiseBudgets(perSkill: 16384);
      await rig.ask(
        'again',
        steps: [loadSkillStep('c9', 'big'), textStep('x')],
      );

      expect(rig.lastToolResultText, contains('<skill name="big"'));
      expect(rig.lastToolResultText, isNot(contains('already loaded')));
    });

    test(
      'total_tokens 50 -> 25000: the dropped skill stays inactive',
      () async {
        final rig = await _Rig.create(
          total: 50,
          skills: [validSkill('tiny', body: 'Hi.')],
        );
        await rig.compacted('tiny');

        await rig.raiseBudgets(total: 25000);
        await rig.ask('/skill:tiny', steps: [textStep('r1')]);

        expect(rig.lastUserText, contains('Hi.'));
        expect(rig.lastUserText, isNot(contains('already loaded')));
      },
    );

    test(
      'a second compaction after the reload: the restored transcript and '
      'the log still use the old budgets (the block stays truncated)',
      () async {
        final rig = await _Rig.create(
          perSkill: 100,
          skills: [validSkill('big', body: rows(100))],
        );
        await rig.compacted('big');
        await rig.raiseBudgets(perSkill: 16384);

        await rig.ask('c' * 16000, steps: [textStep('ok')]);
        await rig.ask('/compact', steps: [textStep('summary two')]);
        await rig.ask('next', steps: [textStep('fin')]);

        // Транскрипт после сжатия (`_restoreHistory`) собран со старым
        // бюджетом: в сообщении после резюме обрезок с пометкой.
        final reattached = [
          for (final m in rig.contexts.last.messages.whereType<UserMessage>())
            m.content.whereType<TextContent>().map((b) => b.text).join(),
        ].firstWhere((t) => t.contains('stay in force'));
        expect(reattached, contains('[skill truncated'));
        expect(reattached, isNot(contains('row 0099')));
        // `compact` считает усечение по тому же снимку.
        final log = rig.logger.eventsOf('skills.reattached').last;
        expect(log.fields['truncated'], 1);
      },
    );

    test(
      'a reload during session/load: the transcript of the loaded session '
      'is built with the budgets of the snapshot taken at its start',
      () async {
        final big = validSkill('big', body: rows(100));
        final rig = await _Rig.create(perSkill: 100, skills: [big]);
        await rig.compacted('big');
        final id = rig.session.id;
        await rig.session.close();

        // Загрузка стоит на порту навыков, пока приходит перезагрузка.
        final gate = Completer<SkillFiles>();
        rig.port.gate = gate.future;
        final loading = rig.runtime.loadSession(
          id,
          const SessionHostPorts(),
          cwd: '/proj',
        );
        await pumpEventQueue();
        await rig.raiseBudgets(perSkill: 16384);
        gate.complete(SkillFiles(skills: [big]));
        rig.session = await loading;
        await rig.ask('next', steps: [textStep('fin')]);

        final reattached = [
          for (final m in rig.contexts.last.messages.whereType<UserMessage>())
            m.content.whereType<TextContent>().map((b) => b.text).join(),
        ].firstWhere((t) => t.contains('stay in force'));
        expect(reattached, contains('[skill truncated'));
      },
    );

    test(
      'a session loaded after the reload gets the new budgets '
      'consistently (the skill is attached whole, so it is active)',
      () async {
        final rig = await _Rig.create(
          perSkill: 100,
          skills: [validSkill('big', body: rows(100))],
        );
        await rig.compacted('big');
        await rig.raiseBudgets(perSkill: 16384);
        final id = rig.session.id;
        await rig.session.close();

        rig.session = await rig.runtime.loadSession(
          id,
          const SessionHostPorts(),
          cwd: '/proj',
        );
        await rig.ask('/skill:big', steps: [textStep('r1')]);

        expect(rig.lastUserText, contains('already loaded'));
      },
    );
  });
}

/// Рантайм с источником конфигурации в памяти, портом навыков и скриптованной
/// моделью; `raiseBudgets` правит слой пользователя и вызывает
/// `reloadConfig`.
final class _Rig {
  _Rig._(
    this.user,
    this.runtime,
    this.store,
    this.contexts,
    this.script,
    this.logger,
    this.port,
  );

  static Future<_Rig> create({
    int? perSkill,
    int? total,
    required List<SkillFile> skills,
  }) async {
    final user = <String, Object?>{
      ...baseValues(),
      'providers': {
        'a': {
          'kind': 'openai-compatible',
          'base_url': 'https://a.test/v1',
          'models': {
            'm1': {'context_window': 32000},
          },
        },
      },
      'agent': {'default_model': 'a/m1'},
      'compaction': {'keep_recent_tokens': 2048},
      'skills': {
        'reattach': {'per_skill_tokens': ?perSkill, 'total_tokens': ?total},
      },
    };
    final clock = FakeClock();
    final logger = RecordingLogger(clock: clock);
    final script = <Map<String, Object?>>[];
    final scripted = _Steps(script, clock);
    final contexts = <LlmContext>[];
    AssistantMessageEventStream stream(
      ModelRef ref,
      LlmContext context, {
      CancelToken? cancel,
    }) {
      contexts.add(context);
      return scripted.call(ref, context, cancel: cancel);
    }

    final source = _Source(
      () => CoreConfig.fromLayers(
        [layer(user)],
        environment: const {},
        projectRoot: '/proj',
      ),
    );
    ModelCatalog catalogOf(CoreConfig config) =>
        StaticModelCatalog(config.providers, logger: logger);
    final port = FakeSkillPort()..files = SkillFiles(skills: skills);
    final store = MemorySessionStore();
    final initial = source.initial.config!;
    final built = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: _Env(),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
        models: catalogOf(initial),
        config: source,
        skillFiles: port,
      ),
      config: initial,
      streamFunction: stream,
      modelsFor: (config) => (stream: stream, catalog: catalogOf(config)),
    );
    return _Rig._(user, built.runtime, store, contexts, script, logger, port);
  }

  final Map<String, Object?> user;
  final AgentRuntime runtime;
  final MemorySessionStore store;
  final List<LlmContext> contexts;
  final List<Map<String, Object?>> script;
  final RecordingLogger logger;
  final FakeSkillPort port;
  late AgentSession session;

  /// Два хода (первый загружает навык [name] инструментом) и `/compact`:
  /// активация уходит в резюме, запись получает `skills`.
  Future<void> compacted(String name) async {
    session = await runtime.createSession(SessionSpec(cwd: '/proj'));
    await ask('a' * 8000, steps: [loadSkillStep('c1', name), textStep('done')]);
    await ask('b' * 16000, steps: [textStep('ok')]);
    await ask('/compact', steps: [textStep('summary')]);
    expect(store.textOf(session.id), contains('"skills"'));
  }

  Future<void> raiseBudgets({int? perSkill, int? total}) async {
    final reattach =
        (user['skills']! as Map<String, Object?>)['reattach']!
            as Map<String, Object?>;
    if (perSkill != null) reattach['per_skill_tokens'] = perSkill;
    if (total != null) reattach['total_tokens'] = total;
    await runtime.reloadConfig();
    await pumpEventQueue();
  }

  Future<void> ask(
    String text, {
    required List<Map<String, Object?>> steps,
  }) async {
    script.addAll(steps);
    await session.prompt([TextContent(text)]);
    await pumpEventQueue();
  }

  String get lastUserText => [
    for (final b
        in contexts.last.messages
            .whereType<UserMessage>()
            .last
            .content
            .whereType<TextContent>())
      b.text,
  ].join();

  String get lastToolResultText => [
    for (final b
        in contexts.last.messages
            .whereType<ToolResultMessage>()
            .last
            .content
            .whereType<TextContent>())
      b.text,
  ].join();
}

/// Скриптованная модель, шаги которой дописываются по ходу теста.
final class _Steps {
  _Steps(this.steps, this.clock);

  final List<Map<String, Object?>> steps;
  final Clock clock;
  var _next = 0;

  AssistantMessageEventStream call(
    ModelRef ref,
    LlmContext context, {
    CancelToken? cancel,
  }) {
    // Шаги читаются лениво: тест дописывает их перед каждым ходом.
    final single = ScriptedStreamFunction.fromJson({
      'steps': [steps[_next++]],
    }, clock: clock);
    return single.call(ref, context, cancel: cancel);
  }
}

final class _Source implements ConfigSource {
  _Source(this._build) {
    _initial = _build();
    expect(_initial.issues, isEmpty, reason: _initial.issues.join('\n'));
  }

  final ConfigLoadResult Function() _build;
  late final ConfigLoadResult _initial;

  @override
  ConfigLoadResult get initial => _initial;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async => _build();

  @override
  Stream<void> get changes => const Stream.empty();
}

final class _Env implements ExecutionEnv, PathResolver {
  final _inner = MemoryExecutionEnv(cwd: '/proj');

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async =>
      path == '/proj' ? Ok(path) : Err(FileError(FileErrorCode.notFound, path));

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
