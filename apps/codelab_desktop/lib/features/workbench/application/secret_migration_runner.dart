/// Типизированный итог плана или переноса секретов встроенного агента.
///
/// Почему: app не видит типов `codelab_agent_*` (PKG-4), а Cubit не должен
/// разбирать текст CLI. Отчёт `SecretMigrator` переводится в эти поля на
/// стороне порта (design.md change `add-config-literal-secrets-and-migrate`,
/// D8).
///
/// Для чего: переносит в `SecretMigrationCubit` только строки пунктов без
/// значений секретов и признаки, по которым диалог выбирает кнопки.
///
/// Как использовать: порт создаёт отчёт на каждый вызов. [problem] — готовый
/// безопасный текст проблемы (из типизированного отчёта, не из
/// `error.toString()`); при `problem != null` Cubit показывает
/// `planFailed`/`applyFailed`.
final class SecretMigrationOutcome {
  const SecretMigrationOutcome({
    required this.items,
    required this.canApply,
    this.readOnlyBackend = false,
    this.nameConflict = false,
    this.onlyExtraLayerFindings = false,
    this.problem,
    this.detail,
    this.movedAny = false,
    this.exitCode = 0,
    this.backendId,
  });

  /// Строки `describe()` пунктов плана или переноса, без значений секретов.
  final List<String> items;

  /// Есть что и куда переносить: пункты есть, конфликтов нет.
  final bool canApply;

  /// Бэкенд хранилища `env` только для чтения: сохранить секрет некуда.
  final bool readOnlyBackend;

  /// Имя секрета уже занято в хранилище; замена в app не предлагается (L7).
  final bool nameConflict;

  /// Все находки лежат только в файле `CODELAB_CONFIG` (`not migrated`).
  final bool onlyExtraLayerFindings;

  /// Безопасный текст проблемы загрузки или записи; `null` — успех.
  final String? problem;

  /// Готовый английский текст для блокирующего признака: подсказка бэкенда
  /// `env` (с веткой Windows, как у `secret set`) или текст конфликта имени.
  /// Строит порт: платформу и `<home>` знает он, а не виджет.
  final String? detail;

  /// Хотя бы один файл переписан (при `problem` — частичный сбой).
  final bool movedAny;

  /// Код выхода движка; пишется в журнал, чисел-секретов в нём нет.
  final int exitCode;

  /// Id открытого хранилища (`file`, `env`) для журнала; `null` — не
  /// открывалось.
  final String? backendId;
}

/// Порт переноса секретов из файла конфига встроенного агента в хранилище.
///
/// Почему: перенос — файловый IO и работа с хранилищем секретов; виджеты и
/// Cubit их не делают (`AGENTS.md` §6, §13). Порт изолирует их и позволяет
/// тестировать автомат на фейке (design.md D8).
///
/// Для чего: единственная точка входа Cubit в движок `SecretMigrator`.
///
/// Как использовать: реализация живёт в `lib/app/` (composition root) и
/// строится через `package:codelab_embedded/io.dart` с теми же `CODELAB_HOME`,
/// `CODELAB_CONFIG` и окружением, что у открывателя встроенного агента.
/// Реализация вправе бросать исключения; Cubit покажет только имя типа.
abstract interface class SecretMigrationRunner {
  /// План (`--all --dry-run`) для папки проекта [cwd]; файлы не меняются.
  Future<SecretMigrationOutcome> plan(String cwd);

  /// Перенос (`--all`, без `--force`) для папки проекта [cwd].
  Future<SecretMigrationOutcome> apply(String cwd);
}
