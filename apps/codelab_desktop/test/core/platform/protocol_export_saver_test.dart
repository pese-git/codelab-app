// Порт сохранения экспорта панели Protocol (задача 4.7 change
// `redesign-protocol-pane`; spec agent-workbench-ui «Pause, Clear и Export
// панели Protocol» — «Сбой записи»; design.md D10).
//
// Красный до задачи 4.8: нет `lib/core/platform/protocol_export_saver.dart`.
// Ожидаемый API по образцу `UsageCsvSaver` (`usage_csv_saver_test.dart`):
//
// * sealed `ProtocolExportSaveResult` с `outcome` (`saved`, `cancelled`,
//   `failed`): `ProtocolExportSaved`, `ProtocolExportCancelled`,
//   `ProtocolExportFailed(errorClass)`;
// * `ProtocolExportSaver.save({suggestedName, text})`;
// * `FileSelectorProtocolExportSaver({pickPath})`: `pickPath` — шов диалога
//   сохранения (по умолчанию `file_selector.getSaveLocation`); в тесте
//   подставляется функция, возвращающая путь или `null` (отказ). Запись — общая
//   `writeFileAtomically`, поэтому сбой не оставляет обрезанного файла.
//
// Диалог `file_selector` без платформы не проверяется.

import 'dart:convert';
import 'dart:io';

import 'package:codelab_desktop/core/platform/protocol_export_saver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('protocol_export_'));
  tearDown(() => dir.deleteSync(recursive: true));

  FileSelectorProtocolExportSaver saverTo(String? path) =>
      FileSelectorProtocolExportSaver(pickPath: (_) async => path);

  test('исходы называются saved, cancelled, failed', () {
    expect(const ProtocolExportSaved().outcome, 'saved');
    expect(const ProtocolExportCancelled().outcome, 'cancelled');
    expect(const ProtocolExportFailed('X').outcome, 'failed');
    expect(const ProtocolExportFailed('X').errorClass, 'X');
  });

  test(
    'сохранение: UTF-8 без BOM, LF сохранён, временного файла нет',
    () async {
      final path = '${dir.path}/out.jsonl';
      const text = '{"type":"codelab.protocol_export"}\n{"a":"привет"}\n';

      final result = await saverTo(path).save(
        suggestedName: 'codelab-protocol-frames-20261122-140241.jsonl',
        text: text,
      );

      expect(result, isA<ProtocolExportSaved>());
      final bytes = File(path).readAsBytesSync();
      expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
      expect(utf8.decode(bytes), text);
      expect(File('$path.tmp').existsSync(), isFalse);
    },
  );

  test('предложенное имя передаётся в диалог как есть', () async {
    String? asked;
    final saver = FileSelectorProtocolExportSaver(
      pickPath: (name) async {
        asked = name;
        return null;
      },
    );

    await saver.save(suggestedName: 'codelab-protocol-log-1.jsonl', text: 'x');

    expect(asked, 'codelab-protocol-log-1.jsonl');
  });

  test('отказ в диалоге — Cancelled, файл не создан', () async {
    final result = await saverTo(null).save(suggestedName: 'a', text: 'x');

    expect(result, isA<ProtocolExportCancelled>());
    expect(dir.listSync(), isEmpty);
  });

  test(
    'сбой записи — Failed с классом исключения, без пути и текста',
    () async {
      final result = await saverTo(
        '${dir.path}/missing/out.jsonl',
      ).save(suggestedName: 'a', text: 'x');

      expect(result, isA<ProtocolExportFailed>());
      final failed = result as ProtocolExportFailed;
      expect(failed.errorClass, isNot(contains(dir.path)));
      // Класс ошибки, а не её текст: имя исключения без пути (на Dart VM запись
      // в несуществующий каталог — `PathNotFoundException`).
      expect(failed.errorClass, 'PathNotFoundException');
    },
  );

  test('сбой не трогает существующий файл по этому пути', () async {
    // Цель — каталог с файлом: rename поверх него не удаётся.
    final target = Directory('${dir.path}/out.jsonl')..createSync();
    File('${target.path}/keep.txt').writeAsStringSync('keep');

    final result = await saverTo(
      target.path,
    ).save(suggestedName: 'a', text: 'x');

    expect(result, isA<ProtocolExportFailed>());
    expect(File('${target.path}/keep.txt').readAsStringSync(), 'keep');
    expect(File('${target.path}.tmp').existsSync(), isFalse);
  });

  test('исключение диалога тоже даёт Failed, а не падение', () async {
    final saver = FileSelectorProtocolExportSaver(
      pickPath: (_) async => throw StateError('no dialog'),
    );

    final result = await saver.save(suggestedName: 'a', text: 'x');

    expect(result, isA<ProtocolExportFailed>());
    expect((result as ProtocolExportFailed).errorClass, 'StateError');
  });
}
