// Тесты `writeFileAtomically` (change `add-desktop-usage-pane`, D5, D13):
// запись через временный файл рядом и `rename`; при сбое временного файла не
// остаётся. Диалог `file_selector` без платформы не проверяется — его закрывает
// порт-двойник в тестах панели.

import 'dart:io';

import 'package:codelab_desktop/core/platform/usage_csv_saver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('usage_csv_saver_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('новый файл: содержимое записано, временного файла нет', () async {
    final path = '${dir.path}/out.csv';

    await writeFileAtomically(path, [0x61, 0x2c, 0x62]);

    expect(File(path).readAsStringSync(), 'a,b');
    expect(File('$path.tmp').existsSync(), isFalse);
  });

  test('существующий файл заменяется целиком', () async {
    final path = '${dir.path}/out.csv';
    File(path).writeAsStringSync('old content that is much longer');

    await writeFileAtomically(path, [0x6e]);

    expect(File(path).readAsStringSync(), 'n');
  });

  test('сбой переименования: исключение, временный файл удалён, цель '
      'не тронута', () async {
    // Цель — каталог: rename файла поверх каталога не удаётся.
    final target = Directory('${dir.path}/out.csv')..createSync();
    File('${target.path}/keep.txt').writeAsStringSync('keep');

    await expectLater(
      writeFileAtomically(target.path, [1, 2, 3]),
      throwsA(isA<FileSystemException>()),
    );

    expect(File('${target.path}.tmp').existsSync(), isFalse);
    expect(File('${target.path}/keep.txt').readAsStringSync(), 'keep');
  });

  test('каталога назначения нет: исключение без мусора', () async {
    final path = '${dir.path}/missing/out.csv';

    await expectLater(
      writeFileAtomically(path, [1]),
      throwsA(isA<FileSystemException>()),
    );

    expect(dir.listSync(), isEmpty);
  });
}
