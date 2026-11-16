import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Общая загрузка определений агентов (agent-configuration «config check
/// показывает диагностику файлов проекта»; client-agent-setup «Строки
/// определений агентов в мосте»; design.md change `add-settings-agents-modes`,
/// D7, D11): определения и диагностика во временном `CODELAB_HOME`, проект с
/// доверием и без, без папки, тайм-аут и отмена. Настоящий `~/.codelab` не
/// читается: `home` задан явно.
///
/// Красные до задачи 2.3: `loadAgentDefinitions` — заглушка.
void main() {
  late String base;
  late String repo;
  late String home;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('load_agent_defs_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    home = '$base/home';
    Directory('$repo/.git').createSync(recursive: true);
    Directory('$home/agents').createSync(recursive: true);
  });

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  String agent(String name, {String extra = ''}) =>
      '---\nname: $name\ndescription: Agent $name\n$extra---\nBody of $name\n';

  CoreConfig config() => CoreConfig(
    defaultModel: ModelRef(
      provider: 'test',
      id: 'model-1',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost:8080/v1'),
      contextWindow: 32000,
      maxOutputTokens: 4096,
    ),
  );

  ProjectFilesLoader realSource() => ProjectFilesLoader(
    home: home,
    local: LocalExecutionEnv(cwd: base),
  );

  group('определения и диагностика', () {
    test('пользовательский и доверенный проектный каталоги', () async {
      write('$home/agents/user-one.md', agent('user-one'));
      write('$repo/.codelab/agents/proj-one.md', agent('proj-one'));

      final report = await loadAgentDefinitions(
        config: config(),
        cwd: repo,
        projectTrusted: true,
        source: realSource(),
      );

      expect(
        [for (final d in report.definitions) d.name],
        ['proj-one', 'user-one'],
      );
      expect(report.timedOut, isFalse);
    });

    test(
      'недоверенный проект: файлов проекта нет, есть untrusted_project',
      () async {
        write('$repo/.codelab/agents/proj-one.md', agent('proj-one'));

        final report = await loadAgentDefinitions(
          config: config(),
          cwd: repo,
          projectTrusted: false,
          source: realSource(),
        );

        expect(report.definitions, isEmpty);
        expect(
          [for (final d in report.diagnostics) d.code],
          ['untrusted_project'],
        );
      },
    );

    test('без папки читается только каталог CODELAB_HOME', () async {
      write('$home/agents/user-one.md', agent('user-one'));
      write('$repo/.codelab/agents/proj-one.md', agent('proj-one'));

      final report = await loadAgentDefinitions(
        config: config(),
        cwd: null,
        projectTrusted: false,
        source: realSource(),
      );

      expect([for (final d in report.definitions) d.name], ['user-one']);
      expect(report.diagnostics, isEmpty);
    });

    test('диагностика разбора: модель вне каталога даёт код model', () async {
      write(
        '$home/agents/broken.md',
        agent('broken', extra: 'model: nope/missing\n'),
      );

      final report = await loadAgentDefinitions(
        config: config(),
        cwd: null,
        projectTrusted: false,
        source: realSource(),
      );

      expect(report.definitions, isEmpty);
      final diagnostic = report.diagnostics.single;
      expect(diagnostic.code, 'model');
      expect(diagnostic.path, '$home/agents/broken.md');
    });
  });

  group('тайм-аут и отмена', () {
    test(
      'источник не ответил за timeout: timedOut и отменённый токен',
      () async {
        final source = _HangingSource();

        final report = await loadAgentDefinitions(
          config: config(),
          cwd: repo,
          projectTrusted: true,
          source: source,
          timeout: const Duration(milliseconds: 20),
        );

        expect(report.timedOut, isTrue);
        expect(report.definitions, isEmpty);
        expect(source.lastCancel!.isCancelled, isTrue);
      },
    );

    test('отмена снаружи отменяет токен источника', () async {
      final source = _HangingSource();
      final outer = CancelTokenSource();
      addTearDown(outer.dispose);

      final pending = loadAgentDefinitions(
        config: config(),
        cwd: repo,
        projectTrusted: true,
        source: source,
        cancel: outer.token,
      );
      await source.started.future;
      outer.cancel();
      await source.lastCancel!.onCancel;

      expect(source.lastCancel!.isCancelled, isTrue);
      source.release();
      await pending;
    });
  });
}

/// Источник, который не отвечает, пока его не отпустят: проверяет тайм-аут и
/// отмену без реальных задержек.
final class _HangingSource implements ProjectFilesSource {
  final started = Completer<void>();
  final _release = Completer<ProjectFiles>();
  CancelToken? lastCancel;

  void release() {
    if (!_release.isCompleted) {
      _release.complete(ProjectFiles.empty);
    }
  }

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) {
    lastCancel = query.cancel;
    started.complete();
    return _release.future;
  }
}
