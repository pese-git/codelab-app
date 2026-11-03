import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
// ignore: implementation_imports
import 'package:codelab_agent_io/src/config/config_write_lock.dart';
import 'package:test/test.dart';

import '../support/config_writer_harness.dart';

/// Наблюдатель за файлами конфига (agent-configuration «Наблюдение за файлами
/// конфига»; design.md change `add-config-writer-and-reload`, D7).
///
/// События каталога подаются через шов-фабрику вручную, время — `FakeClock`:
/// ни ожидания настоящей файловой системы, ни `Future.delayed` для
/// синхронизации. Содержимое файлов — настоящее, во временном каталоге (по
/// нему считается sha256). Исключение — последний тест группы
/// «real watch»: настоящий `Directory.watch` с пределом «сигнал не позже 5 с».
///
/// Имена служебных файлов писателя берутся из констант `config_write_lock.dart`
/// (D5, «Где»), а не пишутся литералами.
void main() {
  late Directory root;
  late String home;
  late String project;
  late FakeClock clock;
  late RecordingLogger logger;
  late Map<String, StreamController<DirectoryChange>> controllers;
  late List<String> requestedDirectories;
  late int signals;
  late List<ConfigWatcher> watchers;

  String file(String path, [String text = 'a: 1\n']) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    return path;
  }

  setUp(() {
    final created = Directory.systemTemp.createTempSync('config_watcher_test');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    project = '${root.path}/proj';
    Directory(home).createSync();
    Directory('$project/.codelab').createSync(recursive: true);
    clock = FakeClock();
    logger = RecordingLogger();
    controllers = {};
    requestedDirectories = [];
    signals = 0;
    watchers = [];
  });

  tearDown(() async {
    for (final watcher in watchers) {
      await watcher.close();
    }
    for (final controller in controllers.values) {
      await controller.close();
    }
    root.deleteSync(recursive: true);
  });

  /// Шов: поток событий каталога — контроллер, которым управляет тест.
  Stream<DirectoryChange> fakeEvents(Directory directory) {
    requestedDirectories.add(directory.path);
    return controllers
        .putIfAbsent(
          directory.path,
          () => StreamController<DirectoryChange>(sync: true),
        )
        .stream;
  }

  ConfigWatcher watch(
    List<String> files, {
    Duration pollInterval = const Duration(seconds: 2),
    DirectoryEventsFactory? events,
    ConfigFileProbe? probe,
    String? Function(String file)? readablePath,
  }) {
    final watcher = ConfigWatcher(
      files: files,
      clock: clock,
      logger: logger,
      pollInterval: pollInterval,
      directoryEvents: events ?? fakeEvents,
      probe: probe,
      readablePath: readablePath,
    );
    watchers.add(watcher);
    watcher.changes.listen((_) => signals++);
    watcher.start();
    return watcher;
  }

  void emit(String directory, String name, {String? destination}) {
    controllers[directory]!.add(
      DirectoryChange(
        path: '$directory/$name',
        destination: destination == null ? null : '$directory/$destination',
      ),
    );
  }

  // Containment проектных слоёв (8.5): `readablePath` возвращает путь для
  // чтения или `null`, если загрузчик файл не читает.
  group('readablePath (project layer containment)', () {
    test('a redirect outside gives one signal, the target is neither read '
        'nor probed nor watched; a return inside gives a signal', () async {
      final inside = file('$project/.codelab/shared.yaml');
      final outsideFile = file('${root.path}/other/config.yaml', 'x: 1\n');
      final layer = '$project/.codelab/config.yaml';
      Link(layer).createSync(inside);
      var allowed = true;
      final probed = <String>[];
      watch(
        [layer],
        // Широковещательные потоки: после возврата внутрь наблюдатель
        // подписывается на каталог заново.
        events: (directory) {
          requestedDirectories.add(directory.path);
          return controllers
              .putIfAbsent(
                directory.path,
                () => StreamController<DirectoryChange>.broadcast(sync: true),
              )
              .stream;
        },
        readablePath: (f) => allowed ? f : null,
        probe: (path) {
          probed.add(path);
          return (exists: true, modified: DateTime(2020), size: 1);
        },
      );

      // Перенаправление наружу: ссылка меняется, загрузчик файл больше не читает.
      File(layer).deleteSync();
      Link(layer).createSync(outsideFile);
      allowed = false;
      emit('$project/.codelab', 'config.yaml');
      await clock.elapse(const Duration(milliseconds: 300));
      expect(signals, 1);

      // Правка цели снаружи: ни события каталога цели, ни второго сигнала.
      expect(
        requestedDirectories.where((d) => d.startsWith('${root.path}/other')),
        isEmpty,
      );
      File(outsideFile).writeAsStringSync('x: 2\n');
      await clock.elapse(const Duration(seconds: 5));
      expect(signals, 1);
      expect(probed.where((p) => p.contains('other')), isEmpty);

      // Возврат внутрь: опрос заметил смену и дал сигнал.
      File(layer).deleteSync();
      Link(layer).createSync(inside);
      allowed = true;
      await clock.elapse(const Duration(seconds: 5));
      expect(signals, 2);
    });

    test(
      'a file on error polling stays on polling after block and return',
      () async {
        final layer = file('$project/.codelab/config.yaml');
        var allowed = true;
        watch(
          [layer],
          events: (directory) {
            requestedDirectories.add(directory.path);
            return controllers
                .putIfAbsent(
                  directory.path,
                  () => StreamController<DirectoryChange>.broadcast(sync: true),
                )
                .stream;
          },
          readablePath: (f) => allowed ? f : null,
        );

        // Поток каталога упал: файл ушёл на опрос (D7).
        controllers['$project/.codelab']!.addError(StateError('stream died'));
        await pumpEventQueue();
        expect(logger.eventsOf('config.watch.fallback'), hasLength(1));

        allowed = false;
        await clock.elapse(const Duration(seconds: 5));
        expect(signals, 1);
        allowed = true;
        await clock.elapse(const Duration(seconds: 5));
        expect(signals, 2);

        File(layer).writeAsStringSync('a: 2222\n');
        await clock.elapse(const Duration(seconds: 5));

        expect(signals, 3, reason: 'the edit must still be seen by polling');
      },
    );

    test(
      'a blocked file stamp differs from a missing file in poll mode',
      () async {
        final layer = '$project/.codelab/config.yaml';
        var allowed = false;
        watch(
          [layer],
          readablePath: (f) => allowed ? f : null,
          probe: (_) => (exists: false, modified: null, size: 0),
        );

        await clock.elapse(const Duration(seconds: 5));
        expect(signals, 0);
        allowed = true;
        await clock.elapse(const Duration(seconds: 5));

        expect(signals, 1, reason: 'blocked is not the same as a missing file');
      },
    );
  });

  group('debounce and comparison', () {
    test(
      'three writes within 200 ms give exactly one signal after 300 ms',
      () async {
        final config = file('$home/config.yaml');
        watch([config]);

        File(config).writeAsStringSync('a: 2\n');
        emit(home, 'config.yaml');
        await clock.elapse(const Duration(milliseconds: 100));
        File(config).writeAsStringSync('a: 3\n');
        emit(home, 'config.yaml');
        await clock.elapse(const Duration(milliseconds: 100));
        File(config).writeAsStringSync('a: 4\n');
        emit(home, 'config.yaml');

        await clock.elapse(const Duration(milliseconds: 299));
        expect(signals, 0, reason: 'the timer restarts on every event');
        await clock.elapse(const Duration(milliseconds: 1));
        expect(signals, 1);
        await clock.elapse(const Duration(seconds: 5));
        expect(signals, 1);
      },
    );

    test('an observed edit logs config.watch.debounce at debug level', () {
      final config = file('$home/config.yaml');
      watch([config]);

      emit(home, 'config.yaml');

      final record = logger.eventsOf('config.watch.debounce').single;
      expect(record.level, LogLevel.debug);
      expect(record.fields['path'], '$home/config.yaml');
    });

    test('rewriting the same bytes gives no signal', () async {
      final config = file('$home/config.yaml', 'a: 1\n');
      watch([config]);

      File(config).writeAsStringSync('a: 1\n');
      emit(home, 'config.yaml');
      await clock.elapse(const Duration(seconds: 1));

      expect(signals, 0);
    });

    test(
      'the baseline moves after a signal: reverting the file signals again',
      () async {
        final config = file('$home/config.yaml', 'a: 1\n');
        watch([config]);

        File(config).writeAsStringSync('a: 2\n');
        emit(home, 'config.yaml');
        await clock.elapse(const Duration(milliseconds: 300));
        File(config).writeAsStringSync('a: 1\n');
        emit(home, 'config.yaml');
        await clock.elapse(const Duration(milliseconds: 300));

        expect(signals, 2);
      },
    );

    test('rebase() makes the current bytes the baseline', () async {
      final config = file('$home/config.yaml', 'a: 1\n');
      final watcher = watch([config]);

      File(config).writeAsStringSync('a: 2\n');
      watcher.rebase();
      emit(home, 'config.yaml');
      await clock.elapse(const Duration(seconds: 1));

      expect(signals, 0);
    });
  });

  group('oversized files', () {
    // Лимит загрузчика: больше него файл не читается ни загрузчиком, ни
    // наблюдателем (D7: отпечаток по размеру и mtime без чтения).
    String big(String path, int extra, {String fill = 'x'}) {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#${fill * (maxConfigBytes + extra)}\n');
      return path;
    }

    test('a change of size gives a signal without reading the file', () async {
      final config = big('$home/config.yaml', 10);
      watch([config]);

      big(config, 20);
      emit(home, 'config.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 1);
    });

    test('a change of mtime at the same size gives a signal', () async {
      final config = big('$home/config.yaml', 10);
      watch([config]);

      File(config).setLastModifiedSync(DateTime(2001, 2, 3));
      emit(home, 'config.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 1);
    });

    test('an untouched oversized file gives no signal', () async {
      final config = big('$home/config.yaml', 10);
      watch([config]);

      emit(home, 'config.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 0);
      expect(logger.eventsOf('config.watch.failed'), isEmpty);
    });
  });

  group('rename and new files', () {
    test('replacing config.yaml through rename gives a signal', () async {
      final config = file('$home/config.yaml', 'a: 1\n');
      watch([config]);

      final tmp = file('$home/config.yaml.swap', 'a: 2\n');
      File(tmp).renameSync(config);
      // Editor-style replacement: the event names the source, the target is
      // `destination` (Linux inotify) — both shapes must work.
      emit(home, 'config.yaml.swap', destination: 'config.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 1);
    });

    test(
      'a file that did not exist at start gives a signal when created',
      () async {
        final config = file('$home/config.yaml');
        final local = '$project/.codelab/config.local.yaml';
        watch([config, local]);

        file(local, 'budget:\n  max_steps: 5\n');
        emit('$project/.codelab', 'config.local.yaml');
        await clock.elapse(const Duration(milliseconds: 300));

        expect(signals, 1);
      },
    );

    test('deleting a watched file gives a signal', () async {
      final config = file('$home/config.yaml');
      watch([config]);

      File(config).deleteSync();
      emit(home, 'config.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 1);
    });

    test(
      'events of unrelated files in a watched directory are ignored',
      () async {
        final config = file('$home/config.yaml');
        watch([config]);

        file('$home/notes.txt');
        emit(home, 'notes.txt');

        expect(clock.pendingTimers, 0);
        await clock.elapse(const Duration(seconds: 1));
        expect(signals, 0);
      },
    );

    test('one subscription per parent directory', () {
      watch([
        file('$home/config.yaml'),
        '$home/secrets.yaml',
        '$project/.codelab/config.yaml',
        '$project/.codelab/config.local.yaml',
      ]);

      expect(requestedDirectories, [home, '$project/.codelab']);
    });
  });

  group('writer service files (D7, D5)', () {
    test('lock, stale lock and tmp events do not start a reload', () async {
      final config = file('$home/config.yaml');
      final local = file('$project/.codelab/config.local.yaml');
      watch([config, local]);

      // Содержимое изменено без события: если бы служебное событие запустило
      // debounce, сравнение sha256 дало бы сигнал.
      File(config).writeAsStringSync('a: 2\n');
      File(local).writeAsStringSync('a: 2\n');
      emit(home, 'config.yaml$configLockSuffix');
      emit(home, 'config.yaml${configTmpInfix}123-4');
      emit(home, 'config.yaml${configStaleLockInfix}abcd');
      emit(
        '$project/.codelab',
        'config.local.yaml$configStaleLockInfix'
            'abcd',
      );
      emit('$project/.codelab', 'config.local.yaml${configTmpInfix}9-9');

      expect(clock.pendingTimers, 0);
      await clock.elapse(const Duration(seconds: 1));
      expect(signals, 0);
    });

    test(
      'a ConfigWriter write gives exactly one signal, by the final rename',
      () async {
        final config = file('$home/config.yaml', 'a: 1\n');
        watch([config]);
        final lock = 'config.yaml$configLockSuffix';
        final tmp = 'config.yaml${configTmpInfix}77-5';

        emit(home, lock);
        await clock.elapse(const Duration(milliseconds: 10));
        emit(home, tmp);
        File('$home/$tmp').writeAsStringSync('a: 2\n');
        emit(home, tmp);
        await clock.elapse(const Duration(milliseconds: 10));
        expect(signals, 0);
        File('$home/$tmp').renameSync(config);
        emit(home, tmp, destination: 'config.yaml');
        emit(home, lock);
        await clock.elapse(const Duration(seconds: 1));

        expect(signals, 1);
      },
    );
  });

  group('symbolic links (dotfiles, PERM-11)', () {
    test('an event in the target directory gives a signal', () async {
      final real = file('${root.path}/dots/codelab/config.yaml', 'a: 1\n');
      Link('$home/config.yaml').createSync(real);
      watch(['$home/config.yaml']);
      expect(
        requestedDirectories,
        containsAll([home, '${root.path}/dots/codelab']),
      );

      File(real).writeAsStringSync('a: 2\n');
      emit('${root.path}/dots/codelab', 'config.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 1);
    });

    test('a chain of links is resolved to the final target', () async {
      final real = file('${root.path}/dots/real.yaml', 'a: 1\n');
      Link('${root.path}/mid.yaml').createSync(real);
      Link('$home/config.yaml').createSync('${root.path}/mid.yaml');
      watch(['$home/config.yaml']);

      File(real).writeAsStringSync('a: 2\n');
      emit('${root.path}/dots', 'real.yaml');
      await clock.elapse(const Duration(milliseconds: 300));

      expect(signals, 1);
    });

    test(
      'redirecting the link gives a signal and the new target is watched',
      () async {
        final first = file('${root.path}/one/config.yaml', 'a: 1\n');
        final second = file('${root.path}/two/config.yaml', 'a: 2\n');
        final link = Link('$home/config.yaml')..createSync(first);
        final watcher = watch(['$home/config.yaml']);

        link.updateSync(second);
        emit(home, 'config.yaml');
        await clock.elapse(const Duration(milliseconds: 300));
        expect(signals, 1);
        expect(requestedDirectories, contains('${root.path}/two'));

        File(second).writeAsStringSync('a: 3\n');
        emit('${root.path}/two', 'config.yaml');
        await clock.elapse(const Duration(milliseconds: 300));
        expect(signals, 2);

        // Старая цель больше не наблюдается.
        File(first).writeAsStringSync('a: 9\n');
        expect(controllers['${root.path}/one']!.hasListener, isFalse);
        watcher.rebase();
      },
    );

    test('rebase() re-resolves the target without a signal', () async {
      final first = file('${root.path}/one/config.yaml', 'a: 1\n');
      final second = file('${root.path}/two/config.yaml', 'a: 1\n');
      final link = Link('$home/config.yaml')..createSync(first);
      final watcher = watch(['$home/config.yaml']);

      link.updateSync(second);
      watcher.rebase();

      expect(requestedDirectories, contains('${root.path}/two'));
      expect(signals, 0);
    });
  });

  group('polling', () {
    test(
      'without directory events a change is seen within interval + 300 ms',
      () async {
        final config = file('$home/config.yaml');
        watch(
          [config],
          pollInterval: const Duration(seconds: 1),
          events: (_) => throw const FileSystemException('no watch'),
        );

        File(config).writeAsStringSync('a: 22222\n');
        await clock.elapse(const Duration(milliseconds: 1299));
        expect(signals, 0);
        await clock.elapse(const Duration(milliseconds: 1));

        expect(signals, 1);
      },
    );

    test(
      'a failed watch logs config.watch.fallback with the exception class',
      () {
        final config = file('$home/config.yaml');
        watch([
          config,
        ], events: (_) => throw const FileSystemException('no watch'));

        final record = logger.eventsOf('config.watch.fallback').single;
        expect(record.level, LogLevel.info);
        expect(record.fields['path'], config);
        expect(record.fields['reason'], 'FileSystemException');
      },
    );

    test('closing the directory stream moves the files to polling', () async {
      // Каталог удалили (inotify): поток закрывается без ошибки, и без
      // `onDone` файлы остались бы без наблюдения (D7).
      final config = file('$home/config.yaml');
      watch([config], pollInterval: const Duration(seconds: 1));

      await controllers[home]!.close();
      final record = logger.eventsOf('config.watch.fallback').single;
      expect(record.level, LogLevel.info);
      expect(record.fields['path'], config);
      expect(record.fields['reason'], '_StreamClosed');

      File(config).writeAsStringSync('a: 22222\n');
      await clock.elapse(const Duration(milliseconds: 1300));

      expect(signals, 1);
    });

    test('closing the watcher does not count as a stream closure', () async {
      final config = file('$home/config.yaml');
      final watcher = watch([config]);

      await watcher.close();

      expect(logger.eventsOf('config.watch.fallback'), isEmpty);
    });

    test('a stream error moves the files to polling', () async {
      final config = file('$home/config.yaml');
      watch([config], pollInterval: const Duration(seconds: 1));

      controllers[home]!.addError(StateError('watch died'));
      final record = logger.eventsOf('config.watch.fallback').single;
      expect(record.fields['reason'], 'StateError');
      expect(record.fields['path'], config);

      File(config).writeAsStringSync('a: 22222\n');
      await clock.elapse(const Duration(milliseconds: 1300));

      expect(signals, 1);
    });

    test(
      'a missing directory is polled; creating the file gives a signal',
      () async {
        final local = '$project/new/config.local.yaml';
        watch(
          [local],
          pollInterval: const Duration(seconds: 1),
          events: defaultDirectoryEvents,
        );
        expect(logger.eventsOf('config.watch.fallback'), hasLength(1));

        file(local, 'a: 1\n');
        await clock.elapse(const Duration(milliseconds: 1300));

        expect(signals, 1);
      },
    );

    test(
      'a poll exception logs config.watch.failed and polling goes on',
      () async {
        final config = file('$home/config.yaml');
        var failures = 1;
        watch(
          [config],
          pollInterval: const Duration(seconds: 1),
          events: (_) => throw const FileSystemException('no watch'),
          probe: (path) {
            if (failures > 0) {
              failures--;
              throw const FileSystemException('stat failed');
            }
            return defaultConfigFileProbe(path);
          },
        );

        await clock.elapse(const Duration(seconds: 1));
        final record = logger.eventsOf('config.watch.failed').single;
        expect(record.level, LogLevel.warning);
        expect(record.fields['path'], config);
        expect(record.fields['error_class'], 'FileSystemException');

        File(config).writeAsStringSync('a: 22222\n');
        await clock.elapse(const Duration(milliseconds: 1300));
        expect(signals, 1);
      },
    );
  });

  group('close', () {
    test('a pending debounce never signals after close()', () async {
      final config = file('$home/config.yaml');
      final watcher = watch([config]);

      File(config).writeAsStringSync('a: 2\n');
      emit(home, 'config.yaml');
      await watcher.close();
      await clock.elapse(const Duration(seconds: 5));

      expect(signals, 0);
      expect(clock.pendingTimers, 0);
    });

    test(
      'events and polls after close() are ignored; close() is idempotent',
      () async {
        final config = file('$home/config.yaml');
        final watcher = watch(
          [config],
          pollInterval: const Duration(seconds: 1),
          events: (_) => throw const FileSystemException('no watch'),
        );

        await watcher.close();
        await watcher.close();
        File(config).writeAsStringSync('a: 22222\n');
        await clock.elapse(const Duration(seconds: 5));

        expect(signals, 0);
        expect(clock.pendingTimers, 0);
      },
    );

    test('close() cancels the directory subscriptions', () async {
      final config = file('$home/config.yaml');
      final watcher = watch([config]);

      await watcher.close();

      expect(controllers[home]!.hasListener, isFalse);
    });
  });

  group('real watch', () {
    test('a real file change gives a signal within 5 seconds', () async {
      final config = file('$home/config.yaml', 'a: 0\n');
      final watcher = ConfigWatcher(
        files: [config],
        clock: const SystemClock(),
        logger: logger,
      );
      watchers.add(watcher);
      final signal = watcher.changes.first;
      watcher.start();

      // У настоящего `watch` есть задержка подписки (FSEvents/inotify):
      // запись повторяется с разным содержимым, пока сигнала нет. Интервал
      // больше debounce, иначе таймер перезапускался бы бесконечно.
      var done = false;
      unawaited(signal.then((_) => done = true));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      var n = 1;
      while (!done && DateTime.now().isBefore(deadline)) {
        File(config).writeAsStringSync('a: $n\n');
        n++;
        await Future.any([
          signal,
          Future<void>.delayed(const Duration(milliseconds: 700)),
        ]);
      }

      expect(done, isTrue, reason: 'signal expected within 5 s');
      expect(logger.eventsOf('config.watch.fallback'), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
      'a change of a symlink target in another directory gives a signal within 5 seconds',
      () async {
        final real = file('${root.path}/dots/config.yaml', 'a: 0\n');
        final link = '$home/config.yaml';
        Link(link).createSync(real);
        final watcher = ConfigWatcher(
          files: [link],
          clock: const SystemClock(),
          logger: logger,
        );
        watchers.add(watcher);
        var seen = 0;
        watcher.changes.listen((_) => seen++);
        watcher.start();

        var n = 1;
        while (!await _quietUntil(
          () => seen > 0,
          const Duration(milliseconds: 700),
        )) {
          File(real).writeAsStringSync('a: ${n++}\n');
          if (n > 8) {
            fail('no signal for the link target within 5 s');
          }
        }
        expect(logger.eventsOf('config.watch.fallback'), isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'a ConfigWriter write over real watch gives exactly one signal',
      () async {
        final h = ConfigWriterHarness.create();
        addTearDown(h.dispose);
        final config = '${h.home}/config.yaml';
        File(config).writeAsStringSync(baseConfig);
        final watcher = ConfigWatcher(
          files: [config],
          clock: const SystemClock(),
          logger: logger,
        );
        watchers.add(watcher);
        var seen = 0;
        watcher.changes.listen((_) => seen++);
        watcher.start();

        // Прогрев: пока первая запись не дала сигнал, подписка могла не
        // успеть встать (FSEvents/inotify). Дальше счёт идёт только по записи
        // писателя.
        var n = 0;
        while (!await _quietUntil(
          () => seen > 0,
          const Duration(milliseconds: 700),
        )) {
          File(config).writeAsStringSync('$baseConfig# warm-up ${n++}\n');
          if (n > 10) {
            fail('no signal from the real watch within 5 s');
          }
        }
        await _quietUntil(() => false, const Duration(milliseconds: 700));
        final before = seen;

        await h.writer.apply(await h.writer.read(const ConfigTarget.user()), [
          const SetValue('budget.max_steps', 40),
        ]);

        expect(
          await _quietUntil(() => seen > before, const Duration(seconds: 5)),
          isTrue,
          reason: 'the final rename must give a signal',
        );
        await _quietUntil(() => false, const Duration(seconds: 1));
        expect(
          seen,
          before + 1,
          reason: 'lock/tmp events must not give a second signal',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}

/// Ждёт [condition] не дольше [limit]; `true`, если условие выполнилось.
///
/// Настоящее время: тест настоящего `watch`, `FakeClock` здесь неприменим.
Future<bool> _quietUntil(bool Function() condition, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return condition();
}
