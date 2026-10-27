// История ввода и файл `cli_history` (tasks 6.3; spec codelab-cli «Редактор
// строки и клавиши», U-07; design.md change `add-codelab-cli`, D4, D5).

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('History', () {
    test('a repeat of the last entry is not added', () {
      final history = History(const [])
        ..add('a')
        ..add('a')
        ..add('b')
        ..add('a');

      expect(history.entries, ['a', 'b', 'a']);
    });

    test('only the last entries within the limit are kept', () {
      final history = History([for (var i = 0; i < 5; i++) '$i'], limit: 3);
      expect(history.entries, ['2', '3', '4']);

      history.add('5');
      expect(history.entries, ['3', '4', '5']);
    });

    test('the default limit is 1000', () {
      final history = History([for (var i = 0; i < 1005; i++) '$i']);

      expect(history.entries, hasLength(1000));
      expect(history.entries.first, '5');
    });
  });

  group('HistoryFile', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cli_history_test');
      path = p.join(dir.path, 'cli_history');
    });
    tearDown(() => dir.delete(recursive: true));

    test('a missing file is an empty history', () async {
      expect(await HistoryFile(path).load(), isEmpty);
    });

    test('multi-line entries survive a round trip', () async {
      final file = HistoryFile(path);
      await file.save(['one', 'two\nlines', r'back\slash']);

      expect(await HistoryFile(path).load(), [
        'one',
        'two\nlines',
        r'back\slash',
      ]);
      expect(await File(path).readAsLines(), hasLength(3));
    });

    test('a damaged line is skipped', () async {
      await File(path).writeAsString('"ok"\nnot json\n"fine"\n');

      expect(await HistoryFile(path).load(), ['ok', 'fine']);
    });

    test('the file is readable only by its owner', () async {
      await HistoryFile(path).save(['secret prompt']);

      final mode = (await File(path).stat()).mode & 0x1ff;
      expect(mode.toRadixString(8), '600');
    }, testOn: '!windows');
  });
}
