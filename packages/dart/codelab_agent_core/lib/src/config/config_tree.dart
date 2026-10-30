/// Разобранный слой конфигурации (`agent-core-architecture` §15.1).
///
/// Почему в ядре: проверка и слияние конфига — чистая функция над уже
/// разобранным деревом (CFG-5). Разборщики YAML живут в `codelab_agent_io`,
/// а мобильный и web-хосты передают дерево из хранилища приложения без
/// позиций и получают ту же проверку.
///
/// Для чего: [ConfigTree] несёт значения слоя и позиции узлов, чтобы ошибка
/// называла файл, строку и столбец; [ConfigLayerKind] задаёт порядок и
/// правила доверия слоя (§15.2, §15.3).
///
/// Как использовать: хост строит по дереву на слой и передаёт список от
/// низшего приоритета к высшему в `CoreConfig.fromLayers`.
library;

/// Вид слоя: порядок и правила доверия (§15.2, §15.3).
enum ConfigLayerKind {
  /// Встроенные значения по умолчанию: предупреждений `not_applied` не дают.
  defaults,

  /// Глобальный `$CODELAB_HOME/config.yaml` (слой 2).
  user,

  /// Проектный `<cwd>/.codelab/config.yaml` (слой 3): правила доверия.
  project,

  /// Локальный проектный `config.local.yaml` (слой 4).
  projectLocal,

  /// `--config <path>` / `CODELAB_CONFIG` (слой 4а): файл назвал тот, кто
  /// запускает агента, доверие не применяется.
  extra,

  /// Переменные `CODELAB_*` (слой 5).
  environment,

  /// Флаги командной строки (слой 6): единственный источник `autopilot`
  /// (CFG-4).
  flags,

  /// Настройки из хранилища приложения (мобильный и web-хосты): без
  /// позиций.
  appStorage,
}

/// Позиция узла в файле; нумерация с 1, как у `package:yaml` + 1.
final class ConfigPosition {
  const ConfigPosition(this.line, this.column);

  final int line, column;

  @override
  bool operator ==(Object other) =>
      other is ConfigPosition && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => '$line:$column';
}

/// Разобранный слой: значения и позиции их ключей.
///
/// [values] — только `String`, `int`, `double`, `bool`, `List` и
/// `Map<String, Object?>`. [positions] связывает путь ключа
/// (`mcp.servers[github].url`, `providers.ollama.models."llama3.1:70b".x`;
/// формат — `KeyPath` ядра) с позицией; пусто — слой без строк (окружение,
/// флаги, хранилище приложения).
final class ConfigTree {
  const ConfigTree({
    required this.kind,
    required this.source,
    required this.values,
    this.positions = const {},
  });

  /// Слой встроенных умолчаний без значений: ядро держит умолчания в
  /// конструкторах `CoreConfig`, а загрузчик добавляет этот слой, чтобы
  /// `sources` начинался с `defaults`.
  const ConfigTree.defaults()
    : kind = ConfigLayerKind.defaults,
      source = 'defaults',
      values = const {},
      positions = const {};

  final ConfigLayerKind kind;

  /// Путь файла, `defaults`, `env`, `flags` или `app-storage`.
  final String source;
  final Map<String, Object?> values;
  final Map<String, ConfigPosition> positions;
}
