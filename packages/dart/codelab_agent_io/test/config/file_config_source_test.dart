import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// `FileConfigSource` — источник конфига живого агента (agent-configuration
/// «Наблюдение за файлами конфига», «Ключи config.watch и config.poll_interval»;
/// design.md change `add-config-writer-and-reload`, D7, D8).
///
/// События каталога — вручную через шов-фабрику, время — `FakeClock`. Файлы —
/// во временных `CODELAB_HOME` и `cwd`; окружение передаётся явно.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late FakeClock clock;
  late RecordingLogger logger;
  late Map<String, StreamController<DirectoryChange>> controllers;
  late List<String> requestedDirectories;
  late List<FileConfigSource> sources;

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

  const mcpServers = '''
mcp:
  servers:
    - name: github
      type: stdio
      command: /bin/true
''';

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    final created = Directory.systemTemp.createTempSync('file_config_source');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory('$cwd/.codelab').createSync(recursive: true);
    clock = FakeClock();
    logger = RecordingLogger();
    controllers = {};
    requestedDirectories = [];
    sources = [];
  });

  tearDown(() async {
    for (final source in sources) {
      await source.close();
    }
    for (final controller in controllers.values) {
      await controller.close();
    }
    root.deleteSync(recursive: true);
  });

  Stream<DirectoryChange> fakeEvents(Directory directory) {
    requestedDirectories.add(directory.path);
    return controllers
        .putIfAbsent(
          directory.path,
          () => StreamController<DirectoryChange>(sync: true),
        )
        .stream;
  }

  Map<String, String> environment() => {'CODELAB_HOME': home};

  /// Стартовая загрузка и источник поверх неё, как это делает хост.
  FileConfigSource open({DirectoryEventsFactory? events}) {
    final initial = ConfigLoader().load(cwd: cwd, environment: environment());
    expect(initial.issues, isEmpty, reason: 'start config must be valid');
    final source = FileConfigSource(
      initial: initial,
      cwd: cwd,
      environment: environment(),
      clock: clock,
      logger: logger,
      directoryEvents: events ?? fakeEvents,
    );
    sources.add(source);
    return source;
  }

  void emit(String directory, String name) =>
      controllers[directory]!.add(DirectoryChange(path: '$directory/$name'));

  group('changes', () {
    test('an edit of config.yaml gives a signal and load() sees it', () async {
      write('$home/config.yaml', provider);
      final source = open();
      var signals = 0;
      source.changes.listen((_) => signals++);

      write('$home/config.yaml', '${provider}budget:\n  max_steps: 40\n');
      emit(home, 'config.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 1);
      final loaded = await source.load();
      expect(loaded.issues, isEmpty);
      expect(loaded.values['budget.max_steps'], 40);
      expect(source.initial.values.containsKey('budget.max_steps'), isFalse);
    });

    test('load() rebases the watcher: its own read is not a change', () async {
      write('$home/config.yaml', provider);
      final source = open();
      var signals = 0;
      source.changes.listen((_) => signals++);

      write('$home/config.yaml', '${provider}budget:\n  max_steps: 40\n');
      await source.load();
      emit(home, 'config.yaml');
      await clock.elapse(const Duration(seconds: 1));

      expect(signals, 0);
    });

    test(
      'load(rebase: false) during the debounce does not swallow the signal',
      () async {
        // `/config check` вызывает тот же `load()`: перенос базы в окне debounce
        // давал те же sha256 и терял сигнал, правка не применялась (D7, D8).
        write('$home/config.yaml', provider);
        final source = open();
        var signals = 0;
        source.changes.listen((_) => signals++);

        write('$home/config.yaml', '${provider}budget:\n  max_steps: 40\n');
        emit(home, 'config.yaml');
        await clock.elapse(const Duration(milliseconds: 100));
        await source.load(rebase: false);
        await clock.elapse(const Duration(milliseconds: 200));

        expect(signals, 1);
      },
    );

    test('watches the files of watchedConfigFiles', () {
      write('$home/config.yaml', provider);
      open();

      expect(requestedDirectories, [home, '$cwd/.codelab']);
    });

    test('close() stops the signals', () async {
      write('$home/config.yaml', provider);
      final source = open();
      var signals = 0;
      source.changes.listen((_) => signals++);

      write('$home/config.yaml', '${provider}budget:\n  max_steps: 40\n');
      emit(home, 'config.yaml');
      await source.close();
      await clock.elapse(const Duration(seconds: 5));

      expect(signals, 0);
    });
  });

  group('config.watch and config.poll_interval', () {
    test(
      'config.watch: false creates no watcher; load() still works',
      () async {
        write('$home/config.yaml', '${provider}config:\n  watch: false\n');
        final source = open();
        var signals = 0;
        source.changes.listen((_) => signals++);

        write(
          '$home/config.yaml',
          '${provider}config:\n  watch: false\nbudget:\n  max_steps: 7\n',
        );
        await clock.elapse(const Duration(seconds: 10));

        expect(requestedDirectories, isEmpty);
        expect(clock.pendingTimers, 0);
        expect(signals, 0);
        expect((await source.load()).values['budget.max_steps'], 7);
      },
    );

    test('config.watch defaults to true', () {
      write('$home/config.yaml', provider);
      expect(
        ConfigLoader()
            .load(cwd: cwd, environment: environment())
            .host
            ?.configWatch,
        isNull,
      );
      open();

      expect(requestedDirectories, isNotEmpty);
    });

    test(
      'config.poll_interval sets the poll period where there are no events',
      () async {
        write('$home/config.yaml', '${provider}config:\n  poll_interval: 5s\n');
        final source = open(
          events: (_) => throw const FileSystemException('no watch'),
        );
        var signals = 0;
        source.changes.listen((_) => signals++);

        write(
          '$home/config.yaml',
          '${provider}config:\n  poll_interval: 5s\nbudget:\n  max_steps: 7\n',
        );
        await clock.elapse(const Duration(milliseconds: 5299));
        expect(signals, 0);
        await clock.elapse(const Duration(milliseconds: 1));

        expect(signals, 1);
      },
    );

    test(
      'config.* in config.local.yaml of an untrusted project is ignored with config.project.untrusted_key',
      () async {
        write('$home/config.yaml', provider);
        write('$cwd/.codelab/config.local.yaml', 'config:\n  watch: false\n');
        final source = open();

        final loaded = await source.load();

        expect(loaded.issues, isEmpty);
        final warning = loaded.warnings.singleWhere(
          (w) => w.event == 'config.project.untrusted_key',
        );
        expect(warning.key, 'config');
        expect(warning.source, '$cwd/.codelab/config.local.yaml');
        expect(loaded.host?.configWatch, isNull);
        expect(
          requestedDirectories,
          isNotEmpty,
          reason: 'the ignored key must not switch the watcher off',
        );
      },
    );
  });

  group('secrets.yaml', () {
    test('is watched with secrets.backend: file', () async {
      write('$home/config.yaml', '${provider}secrets:\n  backend: file\n');
      final source = open();
      var signals = 0;
      source.changes.listen((_) => signals++);

      write('$home/secrets.yaml', 'codelab/key: replaced\n');
      emit(home, 'secrets.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 1);
    });

    test('is not watched with another backend', () async {
      write('$home/config.yaml', provider);
      final source = open();
      var signals = 0;
      source.changes.listen((_) => signals++);

      write('$home/secrets.yaml', 'codelab/key: replaced\n');
      emit(home, 'secrets.yaml');

      expect(clock.pendingTimers, 0);
      await clock.elapse(const Duration(seconds: 1));
      expect(signals, 0);
    });
  });

  group('trust is pinned to initial (D8)', () {
    test(
      'trust granted after start does not apply to project layers',
      () async {
        write('$home/config.yaml', provider);
        write('$cwd/.codelab/config.yaml', mcpServers);
        final source = open();
        expect(source.initial.config!.trustedProjects, isEmpty);

        write('$home/config.yaml', '${provider}trusted_projects: [$cwd]\n');
        final loaded = await source.load();

        expect(loaded.issues, isEmpty);
        expect(
          loaded.config!.trustedProjects,
          isEmpty,
          reason: 'trust is pinned to initial until restart',
        );
        expect(
          loaded.warnings.where(
            (w) =>
                w.event == 'config.project.untrusted_key' &&
                w.key == 'mcp.servers',
          ),
          isNotEmpty,
          reason: 'project mcp.servers stay untrusted',
        );
        expect(loaded.config!.mcpServers, isEmpty);
        // Новое значение ключа видно рантайму только через `values` (D8).
        expect(loaded.values.containsKey('trusted_projects'), isTrue);
      },
    );

    test('trust revoked after start keeps project layers trusted', () async {
      write('$home/config.yaml', '${provider}trusted_projects: [$cwd]\n');
      write('$cwd/.codelab/config.yaml', mcpServers);
      final source = open();
      expect(source.initial.config!.trustedProjects, [cwd]);
      expect(source.initial.config!.mcpServers, isNotEmpty);

      write('$home/config.yaml', provider);
      final loaded = await source.load();

      expect(loaded.issues, isEmpty);
      expect(loaded.config!.trustedProjects, [cwd]);
      expect(loaded.config!.mcpServers, isNotEmpty);
      expect(
        loaded.warnings.where((w) => w.event == 'config.project.untrusted_key'),
        isEmpty,
      );
    });
  });
}
