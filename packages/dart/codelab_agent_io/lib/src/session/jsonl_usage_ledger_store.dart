/// Файл `usage.json` в каталоге сессии (design.md change `add-usage-ledger`,
/// D3, D13; `agent-core-architecture` §8.9, §12.6.1).
///
/// Почему отдельный класс над `JsonlSessionStore`: путь файла строит
/// хранилище по `SessionId` своего индекса, а не по строке извне (D13), но
/// порт ядра `UsageLedgerStore` не входит в контракт `SessionStore`.
///
/// Как использовать: хост создаёт `JsonlUsageLedgerStore(sessions)` над тем
/// же `JsonlSessionStore`, что передаёт в `AgentCoreServices.sessions`, и
/// кладёт в `AgentCoreServices.usageLedger`. Файл производный (OBS-10): его
/// можно удалить, ядро пересчитает; запись идёт без `fsync`.
///
/// Containment (D13): каталог данных, `usage.json` и `usage.json.tmp` лежат
/// рядом с журналом и могут оказаться ссылками наружу (файлы подложил кто
/// угодно с доступом к `$CODELAB_HOME`). Поэтому каталог данных проверяется
/// через `resolveSymbolicLinks` относительно корня хранилища, ссылка
/// `usage.json` не читается, а ссылка `usage.json.tmp` перед записью
/// удаляется (удаляется сама ссылка, не цель).
library;

import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'jsonl_session_store.dart';
import 'write_queue.dart';

/// Предел размера читаемого `usage.json`: 32 МиБ.
///
/// Почему: замер R4 даёт для журнала 1 000 ходов × 40 шагов порядка 5–8 МБ
/// JSON, а файл читается целиком в память. Предел в четыре раза выше этого
/// замера отсекает подложенный огромный файл, но не обычную длинную сессию.
/// Больший файл — ошибка чтения: ядро считает его битым и пересчитывает.
const _maxLedgerBytes = 32 * 1024 * 1024;

/// Порт `UsageLedgerStore` на файлах: `<журнал без .jsonl>/usage.json`,
/// запись через `usage.json.tmp` и `rename` без `fsync`.
final class JsonlUsageLedgerStore implements UsageLedgerStore {
  JsonlUsageLedgerStore(this.sessions);

  /// Хранилище журналов: источник пути каталога сессии.
  final JsonlSessionStore sessions;

  static const _name = 'usage.json';

  @override
  Future<String?> read(SessionId id) async {
    final dir = await _contained(id);
    if (dir == null) {
      return null;
    }
    final path = '$dir/$_name';
    // Ссылка вместо файла не читается: цель могла бы быть любым файлом
    // процесса (D13).
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    try {
      final file = File(path);
      if ((await file.stat()).size > _maxLedgerBytes) {
        throw const UsageLedgerStoreException('the ledger file is too large');
      }
      return await file.readAsString();
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (error) {
      throw UsageLedgerStoreException(_reason(error));
    }
  }

  @override
  Future<void> write(SessionId id, String content) async {
    final dir = await _dataDirectory(id);
    if (dir == null) {
      throw const UsageLedgerStoreException('the session has no journal');
    }
    if (await _contained(id) == null) {
      throw const UsageLedgerStoreException(
        'the data directory is outside the sessions root',
      );
    }
    final target = '$dir/$_name';
    // Запись одного файла идёт по очереди хранилища: два вызова не мешают
    // друг другу `.tmp` (D3).
    await writeQueue.run(target, () async {
      final tmp = File('$target.tmp');
      try {
        await Directory(dir).create(recursive: true);
        // Остаток прошлой записи или подложенная ссылка: запись через ссылку
        // ушла бы по её цели (D13), поэтому перед записью `.tmp` удаляется.
        switch (FileSystemEntity.typeSync(tmp.path, followLinks: false)) {
          case FileSystemEntityType.link:
            Link(tmp.path).deleteSync();
          case FileSystemEntityType.notFound:
            break;
          default:
            tmp.deleteSync(recursive: true);
        }
        await tmp.writeAsString(content, flush: false);
        await tmp.rename(target);
      } on FileSystemException catch (error) {
        // Остаток `.tmp` не должен лежать рядом с журналом.
        try {
          if (FileSystemEntity.typeSync(tmp.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            tmp.deleteSync();
          }
        } on FileSystemException {
          // Не удалось убрать — причина записи важнее.
        }
        throw UsageLedgerStoreException(_reason(error));
      }
    });
  }

  /// Каталог данных сессии или `null`, если журнала нет; сбой ОС при поиске —
  /// типизированная ошибка, чтобы `/usage` показал `notSaved`, а не упал.
  Future<String?> _dataDirectory(SessionId id) async {
    try {
      return await sessions.dataDirectoryOf(id);
    } on FileSystemException catch (error) {
      throw UsageLedgerStoreException(_reason(error));
    }
  }

  /// Каталог данных, если он под корнем хранилища (после разрешения ссылок);
  /// несуществующий каталог ещё не может быть ссылкой.
  Future<String?> _contained(SessionId id) async {
    final dir = await _dataDirectory(id);
    if (dir == null) {
      return null;
    }
    if (FileSystemEntity.typeSync(dir, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return dir;
    }
    return await sessions.isInsideRoot(dir) ? dir : null;
  }

  /// Причина ОС на английском без пути: путь может нести имя пользователя
  /// (§16).
  static String _reason(FileSystemException error) {
    final text = error.osError?.message.trim() ?? '';
    return text.isEmpty ? error.message : text;
  }
}
