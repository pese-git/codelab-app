import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Результат сохранения CSV панели Usage (design.md change
/// `add-desktop-usage-pane`, D5, D13).
///
/// Почему sealed-тип, а не enum и не исключение: сбой записи — штатный исход
/// порта, а журналу событий нужен класс ошибки (`error_class`), но ни текст
/// ошибки, ни путь в него попасть не должны. Для чего: `ActiveSessionCubit`
/// превращает результат в событие `usage_pane.export`, а виджет — в заметку.
/// Как использовать: порт возвращает один из трёх вариантов, `switch` по ним
/// исчерпывающий.
sealed class UsageCsvSaveResult {
  const UsageCsvSaveResult();

  /// Имя исхода для события `usage_pane.export` (`outcome`).
  String get outcome;
}

/// Файл записан.
final class UsageCsvSaved extends UsageCsvSaveResult {
  const UsageCsvSaved();

  @override
  String get outcome => 'saved';
}

/// Пользователь закрыл диалог без выбора: файла и заметки нет.
final class UsageCsvCancelled extends UsageCsvSaveResult {
  const UsageCsvCancelled();

  @override
  String get outcome => 'cancelled';
}

/// Запись не удалась: панель показывает `Couldn't save the file.`.
final class UsageCsvFailed extends UsageCsvSaveResult {
  const UsageCsvFailed(this.errorClass);

  /// `runtimeType` исключения: без сообщения и без пути (D13, `AGENTS.md`
  /// §16).
  final String errorClass;

  @override
  String get outcome => 'failed';
}

/// Порт сохранения CSV: системный диалог и запись файла (D5).
///
/// Почему порт: диалог и файловая система — infrastructure (`AGENTS.md`
/// §11), widgets и application до них не дотягиваются. Образец —
/// `ProjectFolderPicker`; шов тестов — `CodeLabTestBinding(usageCsvSaver:)`.
///
/// Как использовать: `save(suggestedName: …, csv: …)`; сбой записи —
/// [UsageCsvFailed], а не исключение.
abstract interface class UsageCsvSaver {
  Future<UsageCsvSaveResult> save({
    required String suggestedName,
    required String csv,
  });
}

/// Записывает [bytes] в [path] без риска оставить обрезанный файл.
///
/// Почему не `writeAsBytes` в сам [path]: он обрезает существующий файл до
/// записи, и обрыв посередине (диск, питание, kill) уничтожает прежнюю версию
/// отчёта (`AGENTS.md` §2, приоритет 3 — целостность данных пользователя).
/// Поэтому пишем во временный файл рядом (тот же каталог — `rename`
/// атомарен в пределах тома) и переименовываем; при любом сбое временный
/// файл удаляется, а [path] остаётся как был.
///
/// Как использовать: вызывает `FileSelectorUsageCsvSaver`; исключение
/// `FileSystemException` пробрасывается вызывающему.
Future<void> writeFileAtomically(String path, List<int> bytes) async {
  final temp = File('$path.tmp');
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
  } on Object {
    try {
      if (temp.existsSync()) {
        await temp.delete();
      }
    } on Object {
      // Убрать временный файл не вышло: исходная ошибка важнее.
    }
    rethrow;
  }
}

/// Настоящий адаптер на `file_selector` (`getSaveLocation`) и `dart:io`.
///
/// Почему так: диалог сохранения даёт `file_selector` (как выбор папки
/// проекта), а запись — `dart:io`: платформенная реализация `XFile.saveTo`
/// есть не везде. Путь выбирает пользователь, поэтому рабочей папкой сессии
/// он не ограничивается — это экспорт пользователя, а не операция агента
/// (design.md change `add-desktop-usage-pane`, D14).
///
/// Как использовать: привязан в `app_scope.dart`; тесты подменяют порт. Файл
/// пишется как UTF-8 без BOM через [writeFileAtomically]. Любой сбой записи —
/// [UsageCsvFailed] с классом исключения, без пути и текста ошибки (D13).
final class FileSelectorUsageCsvSaver implements UsageCsvSaver {
  const FileSelectorUsageCsvSaver();

  static const _csvType = XTypeGroup(label: 'CSV', extensions: ['csv']);

  @override
  Future<UsageCsvSaveResult> save({
    required String suggestedName,
    required String csv,
  }) async {
    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [_csvType],
      );
      if (location == null) {
        return const UsageCsvCancelled();
      }
      await writeFileAtomically(location.path, utf8.encode(csv));
      return const UsageCsvSaved();
    } on Object catch (error) {
      return UsageCsvFailed(error.runtimeType.toString());
    }
  }
}
