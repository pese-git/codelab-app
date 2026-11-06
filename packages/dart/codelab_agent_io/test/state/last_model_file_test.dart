import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Файловая память последней модели `$CODELAB_HOME/state/last-model.json`
/// (agent-runtime «Последняя выбранная модель»; design.md change
/// `optional-default-model`, D7; задача 3.1). Всё идёт во временном
/// `CODELAB_HOME`, настоящий `~/.codelab` не читается.
void main() {
  late Directory tmp;
  late String home;
  late RecordingLogger logger;
  late FileLastModelStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('last_model_file_');
    home = tmp.path;
    logger = RecordingLogger();
    store = FileLastModelStore(codelabHome: home, logger: logger);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  File fileOf() => File('$home/state/last-model.json');

  Map<String, Object?> contentOf() =>
      jsonDecode(fileOf().readAsStringSync()) as Map<String, Object?>;

  List<String> tmpFiles() => [
    for (final entity in Directory('$home/state').listSync())
      if (entity.uri.pathSegments.last.contains('.tmp-'))
        entity.uri.pathSegments.last,
  ];

  group('write and read', () {
    test('the path is state/last-model.json under CODELAB_HOME', () {
      expect(store.path, '$home/state/last-model.json');
    });

    test('write creates state/ and the file {"v":1,"model":…}; read returns '
        'the model', () async {
      expect(Directory('$home/state').existsSync(), isFalse);

      await store.write(const ModelId('b/y'));

      expect(contentOf(), {'v': 1, 'model': 'b/y'});
      expect(await store.read(), const ModelId('b/y'));
      expect(logger.records, isEmpty);
    });

    test('a model id may contain a slash in the model part', () async {
      await store.write(const ModelId('or/anthropic/claude'));

      expect(await store.read(), const ModelId('or/anthropic/claude'));
    });

    test(
      'a later write replaces the earlier one; no *.tmp-* is left',
      () async {
        await store.write(const ModelId('a/x'));
        await store.write(const ModelId('b/y'));

        expect(contentOf(), {'v': 1, 'model': 'b/y'});
        expect(tmpFiles(), isEmpty);
      },
    );

    test('writes of one process go through a queue: the last queued wins and '
        'the file is never torn', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++) store.write(ModelId('p/m$i')),
      ]);

      expect(contentOf(), {'v': 1, 'model': 'p/m19'});
      expect(tmpFiles(), isEmpty);
    });

    test('two stores over one home: the last rename wins, the file stays '
        'valid', () async {
      final other = FileLastModelStore(codelabHome: home, logger: logger);

      await store.write(const ModelId('a/x'));
      await other.write(const ModelId('b/y'));

      expect(await store.read(), const ModelId('b/y'));
      expect(tmpFiles(), isEmpty);
    });

    test('a missing CODELAB_HOME is created with 0700, then state/ '
        '(as ConfigWriter does)', () async {
      final fresh = '${tmp.path}/fresh/home';
      final other = FileLastModelStore(codelabHome: fresh, logger: logger);

      await other.write(const ModelId('a/x'));

      expect(File('$fresh/state/last-model.json').existsSync(), isTrue);
      expect(Directory(fresh).statSync().mode & 0x1FF, 0x1C0); // 0700
    }, skip: Platform.isWindows ? 'POSIX modes only' : false);

    test('unknown fields are ignored on read (forward compatibility of the '
        'own format)', () async {
      Directory('$home/state').createSync();
      fileOf().writeAsStringSync(
        jsonEncode({
          'v': 1,
          'model': 'a/x',
          'projects': {'/p': 'b/y'},
        }),
      );

      expect(await store.read(), const ModelId('a/x'));
      expect(logger.records, isEmpty);
    });

    test('no file: null without an event', () async {
      expect(await store.read(), isNull);
      expect(logger.eventsOf('model.last_used.ignored'), isEmpty);
      expect(Directory('$home/state').existsSync(), isFalse);
    });
  });

  group('a damaged state file (scenario "Повреждённый файл состояния")', () {
    const reasons = {
      'too large',
      'invalid json',
      'unknown version',
      'invalid model',
    };

    /// Содержимое → ожидаемая категория (`null` — любая из [reasons]).
    final cases = <String, (String, String?)>{
      'model is not a string': ('{"v": 1, "model": 42}', 'invalid model'),
      'truncated json': ('{"v": 1, "model": "a/x', 'invalid json'),
      'unknown version': ('{"v": 9, "model": "a/x"}', 'unknown version'),
      'not an object': ('["a/x"]', null),
      'a bare string': ('"a/x"', null),
      'no slash': ('{"v": 1, "model": "abc"}', 'invalid model'),
      'empty provider': ('{"v": 1, "model": "/x"}', 'invalid model'),
      'empty model': ('{"v": 1, "model": "a/"}', 'invalid model'),
      'no model': ('{"v": 1}', 'invalid model'),
      'larger than 4 KiB': (
        jsonEncode({'v': 1, 'model': 'a/x', 'pad': 'z' * 5000}),
        'too large',
      ),
    };

    for (final MapEntry(key: name, value: (content, reason)) in cases.entries) {
      test('$name: null, the event has a category without the content, the '
          'file is untouched', () async {
        // Секретоподобная строка внутри файла не должна попасть в лог.
        final text = content.replaceFirst('a/x', 'a/x-sk-test-leak-0123456789');
        Directory('$home/state').createSync();
        fileOf().writeAsStringSync(text);
        final before = fileOf().readAsBytesSync();

        final result = await store.read();

        expect(result, isNull);
        final event = logger.eventsOf('model.last_used.ignored').single;
        expect(event.level, LogLevel.warning);
        expect(event.fields['path'], store.path);
        expect(event.fields['reason'], isA<String>());
        expect(
          reason == null
              ? reasons.contains(event.fields['reason'])
              : event.fields['reason'] == reason,
          isTrue,
          reason: 'reason: ${event.fields['reason']}',
        );
        expect(event.fields.toString(), isNot(contains('sk-test-leak')));
        expect(fileOf().readAsBytesSync(), before);
        expect(tmpFiles(), isEmpty);
      });
    }

    test('a link to a file larger than 4 KiB: too large, the target is not '
        'read to the end', () async {
      Directory('$home/state').createSync();
      final target = File('${tmp.path}/big.json')
        ..writeAsStringSync('{"v": 1, "model": "a/x", "pad": "${'z' * 9000}"}');
      Link(store.path).createSync(target.path);

      expect(await store.read(), isNull);

      final event = logger.eventsOf('model.last_used.ignored').single;
      expect(event.fields['reason'], 'too large');
    });

    test('a directory in place of the file: not a file', () async {
      Directory(store.path).createSync(recursive: true);

      expect(await store.read(), isNull);

      final event = logger.eventsOf('model.last_used.ignored').single;
      expect(event.fields['reason'], 'not a file');
    });

    test('a FIFO in place of the file does not block: not a file', () async {
      Directory('$home/state').createSync();
      final made = Process.runSync('/usr/bin/mkfifo', [store.path]);
      if (made.exitCode != 0) {
        markTestSkipped('mkfifo is not available');
        return;
      }

      expect(await store.read(), isNull);

      final event = logger.eventsOf('model.last_used.ignored').single;
      expect(event.fields['reason'], 'not a file');
    }, skip: Platform.isWindows ? 'no FIFO on Windows' : false);

    test('an explicit write replaces a damaged file', () async {
      Directory('$home/state').createSync();
      fileOf().writeAsStringSync('{"v": 9, "model": "a/x"}');

      await store.write(const ModelId('b/y'));

      expect(contentOf(), {'v': 1, 'model': 'b/y'});
      expect(await store.read(), const ModelId('b/y'));
    });
  });

  group('no secrets (scenario "Секретов нет в файле и логе")', () {
    test('the file has only v and model; neither it nor the log has the key, '
        'the address or the headers', () async {
      logger = RecordingLogger();
      store = FileLastModelStore(codelabHome: home, logger: logger);

      await store.write(const ModelId('gw/m'));
      await store.read();

      expect(contentOf().keys.toSet(), {'v', 'model'});
      final text = fileOf().readAsStringSync() + logger.records.join('\n');
      expect(text, isNot(contains('sk-test-leak-0123456789')));
      expect(text, isNot(contains('https://')));
      expect(text, isNot(contains('Authorization')));
    });
  });
}
