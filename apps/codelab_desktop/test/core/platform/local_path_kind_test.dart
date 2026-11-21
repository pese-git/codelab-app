// Порт `LocalPathKindOf` и его реализация `ioLocalPathKind` (задача 3.1 change
// `add-empty-project-screen`; design.md D4): вид брошенного пути для решения
// «папка ли это». Обычный `test` на временном каталоге: реальная файловая
// система, без плагинов.
//
// Красный до задачи 3.2: файла `local_path_kind.dart` ещё нет, тест не
// компилируется.

import 'dart:io';

import 'package:codelab_desktop/core/platform/local_path_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('local_path_kind_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String path(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  test('папка — directory', () async {
    final dir = Directory(path('app'))..createSync();

    expect(await ioLocalPathKind(dir.path), LocalPathKind.directory);
  });

  test('обычный файл — file', () async {
    final file = File(path('README.md'))..writeAsStringSync('x');

    expect(await ioLocalPathKind(file.path), LocalPathKind.file);
  });

  test('несуществующий путь — missing', () async {
    expect(await ioLocalPathKind(path('gone')), LocalPathKind.missing);
  });

  test(
    'ссылка на папку — directory (ссылки раскрываются при проверке)',
    () async {
      final dir = Directory(path('real'))..createSync();
      final link = Link(path('link'))..createSync(dir.path);

      expect(await ioLocalPathKind(link.path), LocalPathKind.directory);
    },
    skip: Platform.isWindows ? 'ссылки на Windows требуют прав' : false,
  );

  test('битая ссылка — missing', () async {
    final link = Link(path('dangling'))..createSync(path('nowhere'));

    expect(await ioLocalPathKind(link.path), LocalPathKind.missing);
  }, skip: Platform.isWindows ? 'ссылки на Windows требуют прав' : false);

  test('ошибка проверки не бросается наружу: other (или missing, если ОС '
      'сама считает такой путь несуществующим)', () async {
    // Нулевой символ в пути — путь, который ОС не принимает. Какой именно
    // вид вернёт платформа, зависит от неё; важно, что исключения нет и
    // вид — не directory и не file (D4: ошибка проверки → other).
    final kind = await ioLocalPathKind('${tmp.path}/bad\u0000name');

    expect(kind, anyOf(LocalPathKind.other, LocalPathKind.missing));
  });
}
