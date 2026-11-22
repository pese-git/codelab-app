import 'dart:convert';

import 'package:file_selector/file_selector.dart';

import 'usage_csv_saver.dart' show writeFileAtomically;

/// Результат сохранения экспорта панели Protocol (design.md change
/// `redesign-protocol-pane`, D10).
///
/// Почему sealed-тип: сбой записи — штатный исход порта, а журналу событий
/// нужен класс ошибки (`error_class`) без текста и пути. Для чего: Cubit
/// превращает результат в событие `protocol_pane.export` и заметку панели.
/// Как использовать: `switch` по трём вариантам исчерпывающий.
sealed class ProtocolExportSaveResult {
  const ProtocolExportSaveResult();

  /// Имя исхода для события `protocol_pane.export` (`outcome`).
  String get outcome;
}

/// Файл записан.
final class ProtocolExportSaved extends ProtocolExportSaveResult {
  const ProtocolExportSaved();

  @override
  String get outcome => 'saved';
}

/// Пользователь закрыл диалог без выбора: файла и заметки нет.
final class ProtocolExportCancelled extends ProtocolExportSaveResult {
  const ProtocolExportCancelled();

  @override
  String get outcome => 'cancelled';
}

/// Запись не удалась: панель показывает `Couldn't save the file.`.
final class ProtocolExportFailed extends ProtocolExportSaveResult {
  const ProtocolExportFailed(this.errorClass);

  /// `runtimeType` исключения: без сообщения и без пути (`AGENTS.md` §16).
  final String errorClass;

  @override
  String get outcome => 'failed';
}

/// Порт сохранения экспорта: системный диалог и запись файла.
///
/// Почему порт: диалог и файловая система — infrastructure (`AGENTS.md`
/// §11), application и виджеты до них не дотягиваются. Образец —
/// `UsageCsvSaver`. Как использовать: `save(suggestedName: …, text: …)`;
/// сбой записи — [ProtocolExportFailed], а не исключение.
abstract interface class ProtocolExportSaver {
  Future<ProtocolExportSaveResult> save({
    required String suggestedName,
    required String text,
  });
}

/// Диалог сохранения: возвращает путь или `null`, если пользователь отказался.
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

Future<String?> _pickWithFileSelector(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON Lines', extensions: ['jsonl']),
    ],
  );
  return location?.path;
}

/// Настоящий адаптер на `file_selector` (`getSaveLocation`) и `dart:io`.
///
/// Почему так: диалог даёт `file_selector`, запись — общая
/// `writeFileAtomically` (UTF-8 без BOM; сбой не оставляет обрезанный файл
/// на месте существующего). Путь выбирает пользователь, поэтому рабочей
/// папкой сессии он не ограничивается: это экспорт пользователя, а не
/// операция агента (как `FileSelectorUsageCsvSaver`).
///
/// Как использовать: привязан в `app_scope.dart`; [pickPath] — шов диалога
/// для тестов. Любой сбой, включая исключение диалога, — [ProtocolExportFailed]
/// с классом исключения.
final class FileSelectorProtocolExportSaver implements ProtocolExportSaver {
  const FileSelectorProtocolExportSaver({
    SaveLocationPicker pickPath = _pickWithFileSelector,
  }) : _pickPath = pickPath;

  final SaveLocationPicker _pickPath;

  @override
  Future<ProtocolExportSaveResult> save({
    required String suggestedName,
    required String text,
  }) async {
    try {
      final path = await _pickPath(suggestedName);
      if (path == null) {
        return const ProtocolExportCancelled();
      }
      await writeFileAtomically(path, utf8.encode(text));
      return const ProtocolExportSaved();
    } on Object catch (error) {
      return ProtocolExportFailed(error.runtimeType.toString());
    }
  }
}
