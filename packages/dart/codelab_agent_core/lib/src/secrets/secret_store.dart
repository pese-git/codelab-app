/// Порт хранилища секретов и описание бэкенда (`agent-core-architecture`
/// §10.3, §17.5.2; design.md change `add-agent-secret-store`, D3).
library;

/// Порт хранилища секретов (§10.3), без изменений.
///
/// Почему порт в ядре: ядро не знает, где лежат секреты (переменные
/// окружения, файл, позже — хранилище ОС, связка ключей мобильного
/// приложения); реализацию приносит хост.
///
/// Как использовать: прямой вызов [read] из ядра и хостов ЗАПРЕЩЁН —
/// единственная дорога к значению это `SecretResolver` (кэш, порядок
/// источников, диагностика без значения; D3, D10). Исключение — подкоманды
/// `secret` и `config check` в `codelab_agent_io` (D8, D9), которые значения
/// не показывают.
abstract interface class SecretStore {
  /// `null` — секрета нет. Недоступность хранилища — [SecretStoreUnavailableException].
  Future<String?> read(String name);

  Future<void> write(String name, String value);

  Future<void> delete(String name);

  /// Имена сохранённых секретов; у `env` их нет (D6).
  Future<List<String>> names();
}

/// Расширение §10.3: хранилище сообщает, куда оно пишет и читает.
///
/// Почему отдельный интерфейс: порт `SecretStore` остаётся прежним, а
/// резолверу и подсказкам нужны id бэкенда, признак записи и причина, по
/// которой `auto` выбрал не то хранилище (D3).
abstract interface class DescribedSecretStore implements SecretStore {
  SecretBackendInfo get backend;
}

/// Описание бэкенда хранилища.
///
/// Почему отдельный тип: резолверу, `config check` и подсказкам нужны id
/// бэкенда, признак записи и причина выбора, и менять ради них порт
/// [SecretStore] нельзя (D3). Для чего: поле `source` результата поиска и
/// диагностика называют бэкенд по [id]. Как использовать: реализация
/// [DescribedSecretStore] отдаёт одно значение на жизнь хранилища.
final class SecretBackendInfo {
  const SecretBackendInfo({
    required this.id,
    required this.writable,
    this.unavailableReason,
  });

  /// `env` | `file` | `memory`; после 1.0 — идентификаторы хранилищ ОС.
  final String id;

  /// `false` у `env`: запись и удаление невозможны.
  final bool writable;

  /// Почему `auto` не выбрал хранилище ОС; иначе `null`.
  final String? unavailableReason;
}

/// Хранилище недоступно (права `secrets.yaml`, после 1.0 — утилита ОС не
/// ответила).
///
/// Для чего: «недоступно» и «не задан» требуют от человека разных действий,
/// поэтому резолвер превращает исключение в `SecretUnavailable`, а не в
/// отсутствие значения (D3).
///
/// Как использовать: бэкенд бросает его из `read`/`write`/`delete`/`names`.
/// [reason] — наш текст на английском, БЕЗ значения секрета и без stderr
/// внешних утилит: он попадает в лог и в ошибку хода.
final class SecretStoreUnavailableException implements Exception {
  const SecretStoreUnavailableException({
    required this.backend,
    required this.reason,
  });

  final String backend;
  final String reason;

  @override
  String toString() => 'SecretStoreUnavailableException($backend): $reason';
}
