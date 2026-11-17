/// Исход сохранения CSV панели Usage (design.md change
/// `add-desktop-usage-pane`, D5, D13).
enum UsageCsvSaveOutcome {
  /// Файл записан.
  saved,

  /// Пользователь закрыл диалог без выбора: файла и заметки нет.
  cancelled,

  /// Запись не удалась: панель показывает `Couldn't save the file.`.
  failed,
}

/// Порт сохранения CSV: системный диалог и запись файла (D5).
///
/// Почему порт: диалог и файловая система — infrastructure (`AGENTS.md`
/// §11), widgets и application до них не дотягиваются. Образец —
/// `ProjectFolderPicker`; шов тестов — `CodeLabTestBinding(usageCsvSaver:)`.
///
/// Как использовать: `save(suggestedName: …, csv: …)`; сбой записи — исход
/// [UsageCsvSaveOutcome.failed], а не исключение.
abstract interface class UsageCsvSaver {
  Future<UsageCsvSaveOutcome> save({
    required String suggestedName,
    required String csv,
  });
}

/// Настоящий адаптер на `file_selector` (`getSaveLocation`) и `dart:io`.
///
/// Заглушка задачи 1.4: реализация — задача 1.7.
final class FileSelectorUsageCsvSaver implements UsageCsvSaver {
  const FileSelectorUsageCsvSaver();

  @override
  Future<UsageCsvSaveOutcome> save({
    required String suggestedName,
    required String csv,
  }) => throw UnimplementedError();
}
