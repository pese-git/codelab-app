/// Порт файла журнала usage сессии (design.md change `add-usage-ledger`, D3).
///
/// Почему отдельный порт, а не методы `SessionStore`: от `SessionStore`
/// зависят `MemorySessionStore`, тестовые хранилища и контракт хранилища, а
/// вспомогательный файл нужен не каждому хосту. Ядро не видит файлов (PKG-1),
/// поэтому читает и пишет `usage.json` только через этот порт.
///
/// Для чего: хранить производную свёртку (OBS-10) рядом с журналом сессии.
/// Файл — кэш: его можно удалить, ядро пересчитает его из записей журнала.
///
/// Как использовать: хост на `dart:io` (`codelab_agent_io`) реализует порт по
/// каталогу сессии и передаёт в `AgentCoreServices.usageLedger`; хост без
/// файлов (web, тесты на памяти, сессия только для чтения) оставляет `null`,
/// и отчёт строится в памяти.
library;

import '../loop/agent_events.dart' show SessionId;

/// Файл `usage.json` сессии (design.md, D3).
abstract interface class UsageLedgerStore {
  /// Содержимое файла сессии [id] или `null`, если файла нет.
  Future<String?> read(SessionId id);

  /// Записывает содержимое; сбой — [UsageLedgerStoreException], не падение
  /// процесса.
  Future<void> write(SessionId id, String content);
}

/// Сбой записи или чтения файла журнала usage (design.md, D3).
///
/// Почему типизированная ошибка: ядро превращает её в статус `notSaved` и
/// warning `usage.ledger.write_failed`, а [message] показывает `/usage`
/// («причина ОС на английском»).
final class UsageLedgerStoreException implements Exception {
  const UsageLedgerStoreException(this.message);

  final String message;

  @override
  String toString() => 'UsageLedgerStoreException: $message';
}
