/// Файл `usage.json` в каталоге сессии (design.md change `add-usage-ledger`,
/// D3, D13; `agent-core-architecture` §8.9, §12.6.1).
///
/// ЗАГЛУШКА красной итерации (задача 1.5): сигнатуры из design.md, тела —
/// `UnimplementedError`. Реализация — задача 1.10.
///
/// Почему отдельный класс над `JsonlSessionStore`: путь файла строит
/// хранилище по `SessionId` своего индекса, а не по строке извне (D13), но
/// порт ядра `UsageLedgerStore` не входит в контракт `SessionStore`.
///
/// Как использовать: хост создаёт `JsonlUsageLedgerStore(sessions)` над тем
/// же `JsonlSessionStore`, что передаёт в `AgentCoreServices.sessions`, и
/// кладёт в `AgentCoreServices.usageLedger`.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'jsonl_session_store.dart';

/// Порт `UsageLedgerStore` на файлах: `<журнал без .jsonl>/usage.json`,
/// запись через `usage.json.tmp` и `rename` без `fsync`.
final class JsonlUsageLedgerStore implements UsageLedgerStore {
  JsonlUsageLedgerStore(this.sessions);

  /// Хранилище журналов: источник пути каталога сессии.
  final JsonlSessionStore sessions;

  @override
  Future<String?> read(SessionId id) =>
      throw UnimplementedError('usage ledger store: task 1.10');

  @override
  Future<void> write(SessionId id, String content) =>
      throw UnimplementedError('usage ledger store: task 1.10');
}
