import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Контекстная часть `ProjectFilesLoader` на реальных файлах во временных
/// каталогах (agent-project-context «Поиск инструкций проекта», «Граница
/// чтения файлов проекта»; design.md change `add-agent-project-files`, D2,
/// D4, D5, D6). Настоящий `~/.codelab` не читается: `home` задаётся явно.
void main() {
  late String base;
  late String repo;
  late String pkg;
  late String home;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('project_context_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    pkg = '$repo/pkg';
    home = '$base/home';
    Directory('$repo/.git').createSync(recursive: true);
    Directory(pkg).createSync();
    Directory(home).createSync();
  });

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  ProjectFilesLoader loader({String? withHome}) => ProjectFilesLoader(
    home: withHome,
    local: LocalExecutionEnv(cwd: base),
  );

  Future<ProjectFiles> load(
    String cwd, {
    String? withHome,
    bool trusted = false,
    int max = 32768,
  }) => loader(withHome: withHome).load(
    ProjectFilesQuery(
      cwd: cwd,
      projectTrusted: trusted,
      contextMaxBytes: max,
      cancel: CancelToken.none,
    ),
  );

  List<String> paths(ProjectFiles files) => [
    for (final f in files.context) f.path,
  ];

  List<String> codes(ProjectFiles files) => [
    for (final d in files.diagnostics) d.code,
  ];

  group('search from cwd up to the git root', () {
    // E-01: `core/project-context-agents-md-leaf-first`.
    test('core/project-context-agents-md-leaf-first: the root file comes '
        'before the file of cwd', () async {
      write('$repo/AGENTS.md', 'rule A');
      write('$pkg/AGENTS.md', 'rule B');

      final files = await load(pkg);

      expect(paths(files), ['AGENTS.md', 'pkg/AGENTS.md']);
      expect([for (final f in files.context) f.content], ['rule A', 'rule B']);
      expect(files.contextRoot, ContextRoot.git);
      expect(files.diagnostics, isEmpty);
    });

    test('the first model request has rule A before rule B (E-01, end to '
        'end over real files)', () async {
      write('$repo/AGENTS.md', 'rule A');
      write('$pkg/AGENTS.md', 'rule B');
      final prompts = <String>[];
      final model = ScriptedStreamFunction.fromJson({
        'steps': [
          {
            'reply': [
              {'text': 'ok'},
            ],
          },
        ],
      });
      final core = buildAgentCore(
        profile: HostProfile.of('agent-serve').narrowed(const {
          HostCapability.sessionPersistence: CapabilityOff('test'),
          HostCapability.shellExec: CapabilityOff('test'),
        }),
        services: AgentCoreServices(
          baseEnv: LocalExecutionEnv(cwd: pkg),
          logger: RecordingLogger(),
          clock: const SystemClock(),
          ids: SequentialIdGenerator(),
          sessions: MemorySessionStore(),
          projectFiles: loader(),
        ),
        config: CoreConfig(
          defaultModel: ModelRef(
            provider: 'test',
            id: 'm',
            api: ProviderApi.openaiChat,
            baseUrl: Uri.parse('http://localhost/v1'),
            contextWindow: 32000,
            maxOutputTokens: 4096,
          ),
        ),
        streamFunction: (ref, context, {cancel}) {
          prompts.add(context.systemPrompt);
          return model.call(ref, context, cancel: cancel);
        },
      );

      final session = await core.runtime.createSession(SessionSpec(cwd: pkg));
      await session.prompt([const TextContent('go')]);
      await core.runtime.dispose();

      final prompt = prompts.single;
      expect(prompt, contains('# Project instructions'));
      expect(prompt.indexOf('rule A'), lessThan(prompt.indexOf('rule B')));
    });

    test('cwd is the git root: one level', () async {
      write('$repo/AGENTS.md', 'rule A');
      write('$base/AGENTS.md', 'above the repository');

      final files = await load(repo);

      expect(paths(files), ['AGENTS.md']);
    });

    test('without .git only cwd is read', () async {
      final plain = '$base/plain/sub';
      write('$base/plain/AGENTS.md', 'parent');
      write('$plain/AGENTS.md', 'here');

      final files = await load(plain);

      expect(paths(files), ['AGENTS.md']);
      expect(files.context.single.content, 'here');
      expect(files.contextRoot, ContextRoot.cwd);
    });

    test('.git as a file (worktree, submodule) marks the root', () async {
      final tree = '$base/tree';
      write('$tree/.git', 'gitdir: /elsewhere/.git/worktrees/tree');
      write('$tree/AGENTS.md', 'root of the worktree');
      write('$tree/sub/AGENTS.md', 'leaf');

      final files = await load('$tree/sub');

      expect(paths(files), ['AGENTS.md', 'sub/AGENTS.md']);
      expect(files.contextRoot, ContextRoot.git);
    });

    test('the search stops after 64 levels: the root is cwd, with an info '
        'diagnostic', () async {
      var deep = repo;
      for (var i = 0; i < 64; i++) {
        deep = '$deep/d';
      }
      write('$repo/AGENTS.md', 'too far');
      write('$deep/AGENTS.md', 'here');

      final files = await load(deep);

      expect(files.context.map((f) => f.content), ['here']);
      expect(files.contextRoot, ContextRoot.cwd);
      final limit = files.diagnostics.single;
      expect(limit.code, 'limit_exceeded');
      expect(limit.level, DiagnosticLevel.info);
    });

    test('63 levels above cwd are still searched', () async {
      var deep = repo;
      for (var i = 0; i < 63; i++) {
        deep = '$deep/d';
      }
      write('$repo/AGENTS.md', 'far');

      final files = await load(deep);

      expect(paths(files), ['AGENTS.md']);
      expect(files.contextRoot, ContextRoot.git);
    });

    test('an untrusted project is read the same way (D4)', () async {
      write('$repo/AGENTS.md', 'rule A');

      final files = await load(repo, trusted: false);

      expect(paths(files), ['AGENTS.md']);
    });
  });

  group('CLAUDE.md is an alias', () {
    test('it is read at a level without AGENTS.md; with both the alias is '
        'shadowed (info)', () async {
      write('$repo/CLAUDE.md', 'claude root');
      write('$pkg/AGENTS.md', 'agents leaf');
      write('$pkg/CLAUDE.md', '@AGENTS.md');

      final files = await load(pkg);

      expect(paths(files), ['CLAUDE.md', 'pkg/AGENTS.md']);
      expect(codes(files), ['shadowed']);
      final shadowed = files.diagnostics.single;
      expect(shadowed.level, DiagnosticLevel.info);
      expect(shadowed.path, '$pkg/CLAUDE.md');
    });

    test('the user directory has no alias', () async {
      write('$home/CLAUDE.md', 'not ours');

      final files = await load(repo, withHome: home);

      expect(files.context, isEmpty);
    });
  });

  group('the user file', () {
    test(r'comes first and is named $CODELAB_HOME/AGENTS.md', () async {
      write('$home/AGENTS.md', 'user rule');
      write('$repo/AGENTS.md', 'rule A');

      final files = await load(repo, withHome: home);

      expect(paths(files), [r'$CODELAB_HOME/AGENTS.md', 'AGENTS.md']);
      expect(files.context.first.scope, ExtensionScope.user);
      expect(files.context.last.scope, ExtensionScope.project);
    });

    test('home: null does not read it (the script of --llm-script)', () async {
      write('$home/AGENTS.md', 'user rule');
      write('$repo/AGENTS.md', 'rule A');

      final files = await load(repo);

      expect(paths(files), ['AGENTS.md']);
    });

    test('a symlink out of CODELAB_HOME is rejected', () async {
      write('$base/dotfiles/AGENTS.md', 'dotfile');
      Link('$home/AGENTS.md').createSync('$base/dotfiles/AGENTS.md');

      final files = await load(repo, withHome: home);

      expect(files.context, isEmpty);
      expect(codes(files), ['outside_root']);
    });

    test('CODELAB_HOME itself may be a symlink', () async {
      write('$base/real_home/AGENTS.md', 'user rule');
      Link('$base/link_home').createSync('$base/real_home');

      final files = await load(repo, withHome: '$base/link_home');

      expect(files.context.single.content, 'user rule');
      expect(files.diagnostics, isEmpty);
    });
  });

  group('the boundary of reading (D2)', () {
    test('a symlink out of the root is not read: outside_root with the '
        'path', () async {
      write('$base/outside/secret.md', 'top secret');
      Link('$pkg/AGENTS.md').createSync('$base/outside/secret.md');
      write('$repo/AGENTS.md', 'rule A');

      final files = await load(pkg);

      expect(paths(files), ['AGENTS.md']);
      expect(
        files.context.map((f) => f.content).join(),
        isNot(contains('secret')),
      );
      final outside = files.diagnostics.single;
      expect(outside.code, 'outside_root');
      expect(outside.path, '$pkg/AGENTS.md');
      expect(outside.level, DiagnosticLevel.warning);
      expect(outside.message, isNot(contains('secret')));
    });

    test('a symlink inside the root is followed', () async {
      write('$repo/docs/rules.md', 'shared rules');
      Link('$pkg/AGENTS.md').createSync('$repo/docs/rules.md');

      final files = await load(pkg);

      expect(files.context.single.content, 'shared rules');
    });

    test('a dangling symlink is just an absent file', () async {
      Link('$pkg/AGENTS.md').createSync('$base/nowhere.md');

      final files = await load(pkg);

      expect(files.context, isEmpty);
      expect(files.diagnostics, isEmpty);
    });

    test('CLAUDE.md as a symlink out of the root without AGENTS.md is '
        'rejected: outside_root, nothing read', () async {
      write('$base/outside/secret.md', 'top secret');
      Link('$pkg/CLAUDE.md').createSync('$base/outside/secret.md');

      final files = await load(pkg);

      expect(files.context, isEmpty);
      final outside = files.diagnostics.single;
      expect(outside.code, 'outside_root');
      expect(outside.path, '$pkg/CLAUDE.md');
    });

    test('a symlink inside the root to /dev/zero is outside_root and does '
        'not hang', () async {
      Link('$pkg/AGENTS.md').createSync('/dev/zero');

      final files = await load(pkg);

      expect(files.context, isEmpty);
      expect(codes(files), ['outside_root']);
    }, skip: Platform.isWindows ? 'no /dev/zero' : false);

    test('a FIFO in place of AGENTS.md is not opened: unreadable, no '
        'block', () async {
      final made = await Process.run('mkfifo', ['$pkg/AGENTS.md']);
      expect(made.exitCode, 0, reason: '${made.stderr}');

      // Открытие FIFO на чтение блокируется до появления писателя: загрузчик
      // обязан отказать по `stat`, не вызывая `open`.
      final files = await load(pkg).timeout(const Duration(seconds: 10));

      expect(files.context, isEmpty);
      expect(codes(files), ['unreadable']);
    }, skip: Platform.isWindows ? 'no mkfifo' : false);

    test(
      '.git as a symlink is not a root marker and is not followed',
      () async {
        write('$base/elsewhere/marker.txt', 'x');
        write('$repo/AGENTS.md', 'rule A');
        write('$pkg/AGENTS.md', 'rule B');
        Link('$pkg/.git').createSync('$base/elsewhere');

        final files = await load(pkg);

        // Корень репозитория — настоящий `$repo`, а не каталог с symlink-ом.
        expect(paths(files), ['AGENTS.md', 'pkg/AGENTS.md']);
        expect(files.contextRoot, ContextRoot.git);
      },
    );

    test('a directory named AGENTS.md is a diagnostic, not a crash', () async {
      Directory('$pkg/AGENTS.md').createSync();

      final files = await load(pkg);

      expect(files.context, isEmpty);
      expect(codes(files), ['unreadable']);
    });
  });

  group('encoding and size', () {
    test('a file that is not UTF-8 is skipped with not_utf8', () async {
      File('$pkg/AGENTS.md').writeAsBytesSync([0x72, 0xFF, 0xFE, 0x75]);
      write('$repo/AGENTS.md', 'rule A');

      final files = await load(pkg);

      expect(paths(files), ['AGENTS.md']);
      expect(codes(files), ['not_utf8']);
      expect(files.diagnostics.single.path, '$pkg/AGENTS.md');
    });

    test('a BOM is removed', () async {
      File(
        '$pkg/AGENTS.md',
      ).writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode('rule')]);

      final files = await load(pkg);

      expect(files.context.single.content, 'rule');
    });

    test('at most max_bytes + 1 bytes are read; M comes from stat', () async {
      write('$pkg/AGENTS.md', 'a' * (1 << 20));

      final files = await load(pkg, max: 100);

      final file = files.context.single;
      expect(file.contentBytes, 101);
      expect(file.totalBytes, 1 << 20);
      expect(file.isPartial, isTrue);
    });

    test('a character cut by the limit is dropped, not reported as '
        'not_utf8', () async {
      write('$pkg/AGENTS.md', 'я' * 200);

      final files = await load(pkg, max: 100);

      expect(codes(files), isEmpty);
      final file = files.context.single;
      expect(file.contentBytes, 100);
      expect(file.totalBytes, 400);
    });

    test('a file within the limit is read whole', () async {
      write('$pkg/AGENTS.md', 'short');

      final file = (await load(pkg, max: 100)).context.single;

      expect(file.content, 'short');
      expect(file.isPartial, isFalse);
    });

    test('max_bytes 0 reads nothing and reports nothing', () async {
      write('$base/outside/secret.md', 'top secret');
      Link('$pkg/AGENTS.md').createSync('$base/outside/secret.md');
      write('$home/AGENTS.md', 'user rule');

      final files = await load(pkg, withHome: home, max: 0);

      expect(files.context, isEmpty);
      expect(files.diagnostics, isEmpty);
    });
  });

  test('a cancelled query returns what it has without failing', () async {
    write('$repo/AGENTS.md', 'rule A');
    final cancel = CancelTokenSource()..cancel();

    final files = await loader().load(
      ProjectFilesQuery(
        cwd: repo,
        projectTrusted: false,
        contextMaxBytes: 100,
        cancel: cancel.token,
      ),
    );

    expect(files.context, isEmpty);
  });
}
