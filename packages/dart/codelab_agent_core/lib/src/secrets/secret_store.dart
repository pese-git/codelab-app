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

  /// Сохраняет или заменяет значение секрета [name].
  ///
  /// Почему исключения: хранилище только для чтения (`env`) и отказ
  /// файлового бэкенда (права, ссылка) не одно и то же, но для вызывающего
  /// это «записать нельзя» — не молчаливый успех.
  ///
  /// Как использовать: вызывает только администрирование (`SecretAdmin` в
  /// `codelab_agent_io`) после проверки имени и значения. Бросает
  /// [SecretStoreUnavailableException] с причиной без значения: если запись
  /// невозможна (бэкенд только для чтения) или хранилище отказало.
  Future<void> write(String name, String value);

  /// Удаляет секрет [name]; отсутствующее имя — не ошибка (идемпотентно).
  ///
  /// Почему идемпотентно: `secret delete` повторяют после сбоев, и повтор не
  /// должен падать (D8).
  ///
  /// Как использовать: как [write] — через `SecretAdmin`. Бросает
  /// [SecretStoreUnavailableException], если бэкенд только для чтения или
  /// недоступен.
  Future<void> delete(String name);

  /// Имена сохранённых секретов; у `env` их нет (D6).
  Future<List<String>> names();
}

/// Расширение §10.3: хранилище сообщает, куда оно пишет и читает.
///
/// Почему отдельный интерфейс: порт `SecretStore` остаётся прежним, а
/// резолверу и подсказкам нужны id бэкенда, признак записи и причина, по
/// которой `auto` выбрал не то хранилище (D3).
///
/// Для чего: `SecretResolver` берёт из [backend] идентификатор для поля
/// `source` результата и для диагностики; `config check` и подкоманды
/// `secret` — признак записи и причину выбора.
///
/// Как использовать: каждая реализация хранилища (`env`, `file`, `memory`)
/// реализует этот интерфейс, а не голый [SecretStore]; хост передаёт его в
/// `SecretResolver(store: …)`.
abstract interface class DescribedSecretStore implements SecretStore {
  /// Описание бэкенда; одно и то же значение на всю жизнь хранилища.
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

  /// Идентификатор бэкенда (`SecretBackendInfo.id`): по нему человек понимает,
  /// какое хранилище чинить; попадает в лог и текст ошибки хода.
  final String backend;

  /// Причина на английском без значения секрета, содержимого файла и stderr
  /// внешних утилит: текст идёт в лог и сообщение об ошибке как есть (CFG-10).
  final String reason;

  @override
  String toString() => 'SecretStoreUnavailableException($backend): $reason';
}
