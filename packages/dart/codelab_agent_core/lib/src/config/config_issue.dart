import '../secrets/secret_names.dart';
import '../util/logger.dart';
import 'core_config.dart';
import 'host_settings.dart';

/// Имена ключей, значение которых — секрет, записанный в конфиг (CFG-2,
/// `agent-core-architecture` §17.5.4, пункт 1).
///
/// Почему здесь, а не в `schema.dart`: схема — внутренность проверки и не
/// экспортируется (CFG-5), а список нужен и за её пределами — писателю
/// `ConfigWriter` и маскированию вывода `config get` в `codelab_agent_io`
/// (design.md change `add-config-writer-and-reload`, D5, D6). Один список на
/// валидатор, писатель и вывод: иначе запись и загрузка расходились бы.
///
/// Как использовать: `inlineSecretKeys.contains(name)` для имени листа
/// (регистр важен: `apiKey` и `api_key` — разные имена).
const inlineSecretKeys = {'api_key', 'apiKey', 'token', 'secret', 'password'};

/// Событие проблемы «переменная `${NAME}` не задана» (`ConfigIssue.event`,
/// поле `variable`): структурный признак для писателя конфига, чтобы он не
/// разбирал текст сообщения (design.md change `add-config-writer-and-reload`,
/// D5, шаг 6).
const unsetVariableEvent = 'config.variable.unset';

/// Событие служебной проблемы «проверка неполна» (`ConfigIssue.event`):
/// режим `collectAll` не смог вырезать ошибочный ключ или исчерпал число
/// кругов, поэтому поздние ступени (в том числе правила доверия) не
/// выполнены (R3-3, решение 2026-11-03). Писатель всегда считает её новой
/// проблемой кандидата (fail-closed); значений ключей в ней нет.
const validationIncompleteEvent = 'config.validation.incomplete';

/// Класс проблемы конфигурации (`agent-core-architecture` §15.1, §17.5.2).
///
/// Почему отдельный enum: тестам и `ConfigInlineSecretException` нужен класс
/// проблемы без разбора текста сообщения.
enum ConfigIssueKind {
  /// Синтаксис файла (разборщик хоста).
  syntax,

  /// Нарушение строгого профиля YAML (разборщик хоста).
  profile,

  /// Ключа нет в схеме (CFG-1).
  unknownKey,

  /// Неверный тип значения.
  type,

  /// Значение вне допустимого: перечисление, формат, подстановка.
  value,

  /// Секрет, записанный значением (CFG-2).
  inlineSecret,

  /// Межключевая проверка §15.5, шаг 8.
  semantic,
}

/// Одна проблема или предупреждение загрузки конфигурации.
///
/// Почему такая форма: сообщение должно назвать файл, строку, столбец и
/// путь ключа (CFG-1), но НИКОГДА не содержать значение — оно может быть
/// секретом (CFG-2, D3 change `add-agent-configuration`). Поэтому
/// [message] строится из пути, типа и допустимых значений.
///
/// Как использовать: хост печатает [toString] (`<источник>:<строка>:
/// <столбец>: <ключ>: <сообщение>`) или пишет предупреждение в лог событием
/// [event] с полями [fields]. У слоя без позиций строки и столбца нет.
final class ConfigIssue {
  const ConfigIssue({
    required this.kind,
    required this.key,
    required this.source,
    required this.message,
    this.line,
    this.column,
    this.event,
    this.fields = const {},
    this.level = LogLevel.warning,
  });

  final ConfigIssueKind kind;

  /// Путь ключа; пустой — файл целиком (синтаксис).
  final String key;
  final String source;
  final int? line, column;
  final String message;

  /// Имя события лога (`config.key.not_applied`, ...) у предупреждения;
  /// у проблемы — `null`. Журнал событий — §12.2.
  final String? event;

  /// Поля записи лога у предупреждения; значений ключей в них нет.
  final Map<String, Object?> fields;

  /// Уровень записи лога у предупреждения (§12.2): `mcp.server.skipped` —
  /// `info`, остальные — `warning`.
  final LogLevel level;

  /// `источник` или `источник:строка:столбец`.
  String get location => line == null ? source : '$source:$line:$column';

  @override
  String toString() =>
      key.isEmpty ? '$location: $message' : '$location: $key: $message';
}

/// Результат `CoreConfig.fromLayers` (§17.5.2).
///
/// Инвариант: [config] и [host] равны `null` тогда и только тогда, когда
/// [issues] не пусто. [warnings] не мешают запуску.
final class ConfigLoadResult {
  const ConfigLoadResult({
    this.config,
    this.host,
    this.issues = const [],
    this.warnings = const [],
    this.sources = const [],
  });

  final CoreConfig? config;

  /// Ключи, которые читает хост, а не ядро.
  final HostSettings? host;
  final List<ConfigIssue> issues;
  final List<ConfigIssue> warnings;

  /// Источники слоёв по порядку.
  final List<String> sources;

  /// Конфиг или исключение: так делает хост, которому ошибка конфигурации —
  /// отказ при старте (`serve`, код `64`). При секрете значением бросается
  /// [ConfigInlineSecretException] (§17.5.2).
  CoreConfig orThrow() {
    final config = this.config;
    if (config != null && issues.isEmpty) {
      return config;
    }
    for (final issue in issues) {
      if (issue.kind == ConfigIssueKind.inlineSecret) {
        throw ConfigInlineSecretException(issues, issue.key);
      }
    }
    throw ConfigException(issues);
  }
}

/// Ошибка конфигурации, найденная при старте (§15.5).
class ConfigException implements Exception {
  const ConfigException(this.issues);

  final List<ConfigIssue> issues;

  @override
  String toString() =>
      'ConfigException:\n${issues.map((i) => '  $i').join('\n')}';
}

/// Секрет записан значением (CFG-2): ключ API нельзя хранить в конфиге.
final class ConfigInlineSecretException extends ConfigException {
  const ConfigInlineSecretException(super.issues, this.key);

  /// Путь первого ключа с секретом.
  final String key;

  /// Имя для подсказки `codelab secret set <name>`: `SecretNames.suggestFor`
  /// от [key] (design.md change `add-agent-secret-store`, D2). Допустимое имя
  /// по правилу `SecretNames`; значения секрета в нём нет.
  String get suggestedSecretName => SecretNames.suggestFor(key);
}
