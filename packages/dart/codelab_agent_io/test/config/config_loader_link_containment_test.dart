import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Containment ссылок проектных слоёв при чтении (change
/// `add-config-writer-and-reload`, задача 8.5; ревью безопасности итерации 3,
/// L2; D5, D7). Репозиторий не должен ссылкой `.codelab/config.yaml` втянуть в
/// конфигурацию агента чужой файл; слой `user` (dotfiles) не ограничивается.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late String outside;

  const provider = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''';

  // Маркер: если слой прочитан, неизвестный ключ даст проблему с этим именем.
  const planted = 'planted_marker_key: 1\n';

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    final created = Directory.systemTemp.createTempSync('config_link_contain');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    outside = '${root.path}/other';
    Directory(home).createSync();
    Directory(cwd).createSync();
    write('$home/config.yaml', provider);
  });

  tearDown(() => root.deleteSync(recursive: true));

  ConfigLoadResult load() =>
      ConfigLoader().load(cwd: cwd, environment: {'CODELAB_HOME': home});

  /// Ровно одна проблема загрузки с путём слоя, без содержимого и цели.
  void expectRefused(ConfigLoadResult result, String layerFile) {
    expect(result.issues, hasLength(1), reason: result.issues.join('\n'));
    final issue = result.issues.single;
    expect(issue.source, layerFile);
    expect(issue.message, contains('resolves outside'));
    expect(issue.message, contains('${canonical(cwd)}/.codelab/'));
    final text = result.issues.join('\n');
    expect(text, isNot(contains('planted_marker_key')));
    expect(text, isNot(contains(outside)));
    expect(result.config, isNull);
  }

  group('project layers', () {
    test('relative link ../../other/.codelab/config.yaml is refused', () {
      write('$outside/.codelab/config.yaml', planted);
      Directory('$cwd/.codelab').createSync();
      Link(
        '$cwd/.codelab/config.yaml',
      ).createSync('../../other/.codelab/config.yaml');

      expectRefused(load(), '${canonical(cwd)}/.codelab/config.yaml');
    });

    test('absolute link outside is refused (projectLocal)', () {
      write('$outside/local.yaml', planted);
      Directory('$cwd/.codelab').createSync();
      Link('$cwd/.codelab/config.local.yaml').createSync('$outside/local.yaml');

      expectRefused(load(), '${canonical(cwd)}/.codelab/config.local.yaml');
    });

    test(
      '.codelab itself is a link outside: both existing layers are refused',
      () {
        write('$outside/config.yaml', planted);
        write('$outside/config.local.yaml', planted);
        Link('$cwd/.codelab').createSync(outside);

        final result = load();

        expect(result.issues.map((i) => i.source), [
          '${canonical(cwd)}/.codelab/config.yaml',
          '${canonical(cwd)}/.codelab/config.local.yaml',
        ]);
        expect(
          result.issues.map((i) => i.message),
          everyElement(contains('resolves outside')),
        );
        expect(result.issues.join('\n'), isNot(contains('planted_marker_key')));
        expect(result.config, isNull);
      },
    );

    test('a link inside .codelab is allowed', () {
      write('$cwd/.codelab/shared.yaml', 'budget:\n  max_steps: 7\n');
      Link('$cwd/.codelab/config.yaml').createSync('$cwd/.codelab/shared.yaml');

      final result = load();

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.config!.budget.maxSteps, 7);
    });

    test('a dangling link outside is a silently missing layer', () {
      Directory('$cwd/.codelab').createSync();
      Link('$cwd/.codelab/config.yaml').createSync('../../nowhere/x.yaml');

      final result = load();

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    });

    test('.codelab link outside without config files gives no issue', () {
      Directory('$outside/prompts').createSync(recursive: true);
      Link('$cwd/.codelab').createSync(outside);

      final result = load();

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.config, isNotNull);
    });

    test('a link cycle is a load problem "too many symbolic links"', () {
      Directory('$cwd/.codelab').createSync();
      Link('$cwd/.codelab/config.yaml').createSync('config.yaml');

      final result = load();

      expect(result.issues, hasLength(1), reason: result.issues.join('\n'));
      expect(
        result.issues.single.source,
        '${canonical(cwd)}/.codelab/config.yaml',
      );
      expect(
        result.issues.single.message,
        startsWith('too many symbolic links: '),
      );
      expect(result.config, isNull);
    });

    test('".." in a missing tail is a load problem "invalid path"', () {
      Directory('$cwd/.codelab').createSync();
      Link('$cwd/.codelab/config.yaml').createSync('nodir/../x.yaml');

      final result = load();

      expect(result.issues, hasLength(1), reason: result.issues.join('\n'));
      expect(result.issues.single.message, startsWith('invalid path: '));
      expect(result.config, isNull);
    });

    // POSIX: `\` — часть имени. Проверка, режущая путь по `\`, видит
    // внутренний `a/b`, а читается внешний файл по ссылке `a\b`.
    test('a backslash link name leading outside is refused', () {
      Directory('$cwd/.codelab/a').createSync(recursive: true);
      write('$cwd/.codelab/a/b', 'budget:\n  max_steps: 1\n');
      write('$outside/real.yaml', planted);
      Link('$cwd/.codelab/a\\b').createSync('$outside/real.yaml');
      Link('$cwd/.codelab/config.yaml').createSync('a\\b');

      expectRefused(load(), '${canonical(cwd)}/.codelab/config.yaml');
    }, skip: Platform.isWindows ? 'на Windows `\\` — разделитель' : null);

    test('a cwd with a backslash in the name keeps the protection', () {
      cwd = '${root.path}/pr\\oj';
      Directory(cwd).createSync();
      write('$outside/real.yaml', planted);
      Directory('$cwd/.codelab').createSync();
      Link('$cwd/.codelab/config.yaml').createSync('$outside/real.yaml');

      expectRefused(load(), '${canonical(cwd)}/.codelab/config.yaml');
    }, skip: Platform.isWindows ? 'на Windows `\\` недопустим в имени' : null);

    test('a cwd with a backslash reads an ordinary project file', () {
      cwd = '${root.path}/pr\\oj';
      write('$cwd/.codelab/config.yaml', 'budget:\n  max_steps: 4\n');

      final result = load();

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.config!.budget.maxSteps, 4);
    }, skip: Platform.isWindows ? 'на Windows `\\` недопустим в имени' : null);

    test('a dangling link inside .codelab is silently a missing layer', () {
      Directory('$cwd/.codelab').createSync();
      Link('$cwd/.codelab/config.yaml').createSync('missing.yaml');

      final result = load();

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    });
  });

  group('user layer', () {
    test('a link outside CODELAB_HOME is read', () {
      File('$home/config.yaml').deleteSync();
      write('${root.path}/dotfiles/codelab.yaml', provider);
      Link(
        '$home/config.yaml',
      ).createSync('${root.path}/dotfiles/codelab.yaml');

      final result = load();

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.config, isNotNull);
    });
  });

  group('file config source watching', () {
    test(
      'a file replaced by a link outside: load() is refused, no leak',
      () async {
        const marker = 'outside-marker-7f3a91';
        write('$cwd/.codelab/config.yaml', 'budget:\n  max_steps: 5\n');
        write('$outside/config.yaml', '$marker: 1\n');
        final environment = {'CODELAB_HOME': home};
        final initial = ConfigLoader().load(cwd: cwd, environment: environment);
        expect(initial.issues, isEmpty);
        final source = FileConfigSource(
          initial: initial,
          cwd: cwd,
          environment: environment,
          clock: FakeClock(),
          logger: RecordingLogger(),
          directoryEvents: (_) => const Stream.empty(),
        );
        addTearDown(source.close);
        File('$cwd/.codelab/config.yaml').deleteSync();
        Link('$cwd/.codelab/config.yaml').createSync('$outside/config.yaml');

        final result = await source.load();

        expect(result.config, isNull);
        expect(result.issues.single.message, contains('resolves outside'));
        final text = result.issues.join('\n');
        expect(text, isNot(contains(marker)));
        expect(text, isNot(contains(outside)));
        expect(source.initial.config!.budget.maxSteps, 5);
      },
    );

    test('.codelab that is a link outside is not subscribed', () {
      write('$outside/config.yaml', planted);
      Link('$cwd/.codelab').createSync(outside);
      final requested = <String>[];
      final environment = {'CODELAB_HOME': home};
      final source = FileConfigSource(
        initial: ConfigLoader().load(cwd: cwd, environment: environment),
        cwd: cwd,
        environment: environment,
        clock: FakeClock(),
        logger: RecordingLogger(),
        directoryEvents: (directory) {
          requested.add(directory.path);
          return const Stream.empty();
        },
      );
      addTearDown(source.close);

      expect(
        requested.where((d) => d.contains('.codelab') || d.startsWith(outside)),
        isEmpty,
        reason: 'the linked .codelab must not be watched',
      );
    });

    test('a refused project link target is not watched or hashed', () async {
      write('$outside/.codelab/config.yaml', planted);
      Directory('$cwd/.codelab').createSync();
      Link(
        '$cwd/.codelab/config.yaml',
      ).createSync('../../other/.codelab/config.yaml');
      final requested = <String>[];
      final environment = {'CODELAB_HOME': home};
      final source = FileConfigSource(
        initial: ConfigLoader().load(cwd: cwd, environment: environment),
        cwd: cwd,
        environment: environment,
        clock: FakeClock(),
        logger: RecordingLogger(),
        directoryEvents: (directory) {
          requested.add(directory.path);
          return const Stream.empty();
        },
      );
      addTearDown(source.close);

      expect(
        requested.where((d) => d.startsWith(outside)),
        isEmpty,
        reason: 'directories outside .codelab must not be watched',
      );
    });
  });
}

String canonical(String path) => Directory(path).resolveSymbolicLinksSync();
