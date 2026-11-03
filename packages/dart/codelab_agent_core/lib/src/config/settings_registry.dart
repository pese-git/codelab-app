/// Реестр настроек: что можно показать и записать в конфиг
/// (`agent-core-architecture` §17.5.2, §17.5.8; design.md change
/// `add-config-writer-and-reload`, D4; E-15, CFG-19).
///
/// Почему отдельная таблица, а не метаданные узлов `schema.dart`: схема —
/// дерево узлов валидатора и описывает проверку (тип, перечисление, «есть ли
/// потребитель»), а реестр — плоский список в порядке показа и описывает
/// запись (раздел UI, подпись, `shared`/`fileOnly`, `restartRequired`,
/// слои). Слить их — значит тащить UI-поля в проверенный валидатор (§19).
/// Согласованность двух описаний держит тест полноты
/// `settings_registry_complete_test.dart`: новый ключ схемы без дескриптора
/// роняет сборку.
///
/// Для чего: клиенты (`/settings`, страница настроек) рисуют редакторы по
/// [SettingType], `ConfigWriter` отклоняет ключи вне реестра и слои, которые
/// ключ не допускает, а перезагрузка берёт [SettingDescriptor.restartRequired]
/// как единственный источник ключей «только после перезапуска» (D4, D8).
///
/// Как использовать: [SettingsRegistry.lookup] по пути ключа
/// (`providers.openai.api_key_secret`), [SettingsRegistry.parseCliValue] —
/// разбор строки `config set`. Чистый Dart (PKG-1): реестром пользуются
/// мобильный и web-хосты и клиенты через реэкспорт `codelab_setup`.
library;

import 'dart:convert';

import '../secrets/secret_names.dart';
import 'config_edit.dart' show ConfigLayer;
import 'key_path.dart';

/// Где ключ редактируют: в UI клиента или только в файле.
enum SettingScope {
  /// Клиент показывает редактор по [SettingType].
  shared,

  /// Клиент не показывает редактор, а даёт ссылку «открыть файл» с
  /// [SettingDescriptor.fileOnlyReason].
  fileOnly,
}

/// Тип значения для редактора и разбора `config set` (§17.5.2).
enum SettingType {
  string,
  int,
  float,
  bool,
  duration,
  path,
  enumeration,
  stringList,
  pathList,

  /// `provider/model` — клиент даёт выбор из каталога моделей.
  modelRef,
  modelRefList,

  /// Имя секрета (`SecretNames`); редактор — «задать ключ» через
  /// `SecretStore`, в конфиг пишется только имя.
  secretName,

  /// Имя переменной окружения.
  envVarName,

  /// Отображение; ключ такого типа покрывает всё своё поддерево.
  map,

  /// Список отображений (`mcp.servers`); покрывает всё своё поддерево.
  mapList,
}

/// Описание одного ключа конфигурации (§17.5.2).
///
/// Как создавать: только в таблице [SettingsRegistry]; новый ключ схемы
/// получает дескриптор в том же изменении (критерий (г) итерации,
/// CFG-19).
final class SettingDescriptor {
  const SettingDescriptor({
    required this.key,
    required this.type,
    required this.scope,
    required this.section,
    required this.label,
    required this.description,
    required this.layers,
    this.defaultValue,
    this.fileOnlyReason,
    this.secret = false,
    this.restartRequired = false,
    this.enumValues,
    this.min,
    this.max,
  });

  /// Путь с `*` вместо имён записей: `providers.*.base_url`, `mcp.servers`.
  final String key;
  final SettingType type;

  /// Умолчание как в §15.4; `null` — «нет». Для ключей, чьё умолчание
  /// применяет ядро, тест полноты сверяет его с настоящим разрешением
  /// конфигурации.
  final Object? defaultValue;
  final SettingScope scope;

  /// Причина `fileOnly`; задана тогда и только тогда, когда
  /// `scope == fileOnly`.
  final String? fileOnlyReason;

  /// Группа UI: Models, Providers, Permissions, Budget, MCP, Tools, Agent,
  /// Logging, Advanced.
  final String section;

  /// Подпись и описание на английском; клиент МОЖЕТ локализовать по [key].
  final String label, description;

  /// Значение — имя секрета; в конфиге хранится только имя.
  final bool secret;

  /// Изменение не применяется живой перезагрузкой, нужен перезапуск
  /// (§17.5.6; D8, R0-1). Единственный источник для
  /// `ConfigWriteResult.restartRequiredKeys` и перезагрузки.
  final bool restartRequired;

  /// Допустимые значения для [SettingType.enumeration].
  final List<String>? enumValues;

  /// Границы числа (включительно).
  final num? min, max;

  /// Слои, в которые писатель может писать ключ. Это грубая граница по
  /// правилам доверия §15.3; условные ограничения («проект в
  /// `trusted_projects`») проверяет сам писатель (D5).
  final Set<ConfigLayer> layers;
}

/// Ошибка разбора значения `config set` (D4).
///
/// Почему исключение ядра, а не `ConfigUsageException`: та живёт в
/// `codelab_agent_io` (`config_loader.dart`) и означает ошибку использования
/// загрузчика; ядро её не видит (PKG-1). Подкоманда переводит это
/// исключение в код `64`.
///
/// Текст называет ключ и ожидаемый формат и НИКОГДА не цитирует значение:
/// оно может оказаться секретом (CFG-2).
///
/// [key] — ключ дескриптора (с `*`: `providers.*.api_key_env`): разбор
/// получает дескриптор, а не путь, по которому его нашли. Путь для человека
/// печатает подкоманда (итерация 4).
final class ConfigValueException implements Exception {
  const ConfigValueException(this.key, this.expected);

  /// Путь ключа, значение которого не разобрано.
  final String key;

  /// Ожидаемый формат: `true or false`, `an integer from 1`, ...
  final String expected;

  @override
  String toString() => 'ConfigValueException: $key: expected $expected';
}

const _allLayers = {
  ConfigLayer.user,
  ConfigLayer.project,
  ConfigLayer.projectLocal,
};

/// Слои 2 и 4: проектный слой 3 такие ключи не читает (`trust.dart`, §15.3).
const _userAndLocal = {ConfigLayer.user, ConfigLayer.projectLocal};
const _userOnly = {ConfigLayer.user};

const _notSupported = 'not supported in this version; edit the file manually';

SettingDescriptor _shared(
  String key,
  SettingType type,
  String section,
  String label,
  String description, {
  Object? defaultValue,
  bool secret = false,
  bool restartRequired = false,
  List<String>? enumValues,
  num? min,
  num? max,
  Set<ConfigLayer> layers = _allLayers,
}) => SettingDescriptor(
  key: key,
  type: type,
  scope: SettingScope.shared,
  section: section,
  label: label,
  description: description,
  defaultValue: defaultValue,
  secret: secret,
  restartRequired: restartRequired,
  enumValues: enumValues,
  min: min,
  max: max,
  layers: layers,
);

SettingDescriptor _fileOnly(
  String key,
  SettingType type,
  String section,
  String label,
  String description,
  String reason, {
  Object? defaultValue,
  bool secret = false,
  bool restartRequired = false,
  List<String>? enumValues,
  num? min,
  num? max,
  Set<ConfigLayer> layers = _allLayers,
}) => SettingDescriptor(
  key: key,
  type: type,
  scope: SettingScope.fileOnly,
  fileOnlyReason: reason,
  section: section,
  label: label,
  description: description,
  defaultValue: defaultValue,
  secret: secret,
  restartRequired: restartRequired,
  enumValues: enumValues,
  min: min,
  max: max,
  layers: layers,
);

/// Непрозрачный узел схемы (раздел «после MVP»): один дескриптор
/// `map`/`fileOnly` на узел (D4). Его подробные строки введёт change раздела
/// вместе со схемой.
SettingDescriptor _opaque(
  String key, {
  bool restartRequired = false,
  Set<ConfigLayer> layers = _allLayers,
}) => _fileOnly(
  key,
  SettingType.map,
  'Advanced',
  key,
  'Reserved for a later release; this build does not apply it.',
  _notSupported,
  restartRequired: restartRequired,
  layers: layers,
);

/// Таблица дескрипторов в порядке показа (§17.5.8, объём сборки 1.0, D4).
///
/// Отличия от целевой таблицы §17.5.8 (D4: дескрипторы — на ключи схемы
/// этой сборки):
/// - `tools.project_context.max_bytes` — лист с умолчанием и границами, а не
///   карта: тест полноты сверяет их с валидатором;
/// - `loop.empty_response_retries` — лист, потому что в схеме это
///   `ScalarNode`; умолчание `2` взято из §15.4 и тестом не сверяется
///   (ключ `_intU`, потребителя нет);
/// - `agents` добавлен: это ключ верхнего уровня схемы;
/// - `shared` — только ключ с потребителем (`applied`); ключ без потребителя —
///   `fileOnly` с причиной `not applied in this version`;
/// - числа проверяются на границах: у `budget.max_cost` и
///   `budget.max_duration` валидатор требует значение строго больше нуля, а
///   `min` дескриптора включительно и для `float` не задаётся.
final List<SettingDescriptor> _descriptors = List.unmodifiable([
  // ---- Models / Agent -----------------------------------------------------
  _shared(
    'agent.default_model',
    SettingType.modelRef,
    'Models',
    'Default model',
    'Model for new sessions, as provider/model; it must be in the catalog.',
  ),
  _fileOnly(
    'agent.fallback',
    SettingType.modelRefList,
    'Models',
    'Fallback models',
    'Models tried after the default model fails.',
    'not applied in this version',
    defaultValue: const <String>[],
  ),
  _fileOnly(
    'agent.summary_model',
    SettingType.modelRef,
    'Models',
    'Summary model',
    'Model that writes compaction summaries; empty uses the session model.',
    'not applied in this version',
  ),
  _shared(
    'agent.effort',
    SettingType.enumeration,
    'Agent',
    'Reasoning effort',
    'Initial reasoning level of a new session.',
    defaultValue: 'medium',
    enumValues: const ['low', 'medium', 'high'],
  ),
  _opaque('llm'),
  _opaque('images'),

  // ---- Providers ----------------------------------------------------------
  _shared(
    'providers.*.kind',
    SettingType.enumeration,
    'Providers',
    'Provider kind',
    'Adapter that talks to the provider.',
    enumValues: const ['openai-compatible', 'anthropic', 'gemini'],
  ),
  _shared(
    'providers.*.base_url',
    SettingType.string,
    'Providers',
    'Base URL',
    'Endpoint of the provider API.',
  ),
  // Литеральный ключ из файла (design.md change
  // `add-config-literal-secrets-and-migrate`, D4, R8-4): читается и работает,
  // но клиенты его не пишут — запись секрета значением запрещена (CFG-2), а
  // перенос в хранилище делает `secret migrate`.
  _fileOnly(
    'providers.*.api_key',
    SettingType.string,
    'Providers',
    'API key (literal)',
    'API key stored in the config file as is; move it to the secret store.',
    'a secret is never written by clients; run: codelab secret migrate',
    secret: true,
  ),
  _shared(
    'providers.*.api_key_env',
    SettingType.envVarName,
    'Providers',
    'API key variable',
    'Name of the environment variable that holds the API key.',
  ),
  _shared(
    'providers.*.api_key_secret',
    SettingType.secretName,
    'Providers',
    'API key secret',
    'Name of the stored secret that holds the API key.',
    secret: true,
  ),
  _fileOnly(
    'providers.*.auth_header',
    SettingType.string,
    'Providers',
    'Key header',
    'Name of the header that carries the API key.',
    'non-standard gateways; edit the file manually',
  ),
  _fileOnly(
    'providers.*.headers',
    SettingType.map,
    'Providers',
    'Extra headers',
    'Additional request headers; values may use \${VAR} or \${secret:name}.',
    'headers hold \${...} references and are edited as text',
  ),
  _fileOnly(
    'providers.*.connect_timeout',
    SettingType.duration,
    'Providers',
    'Connect timeout',
    'Time to wait for response headers.',
    'fine-tuning of the network; the default suits most setups',
    defaultValue: '30s',
  ),
  _fileOnly(
    'providers.*.idle_timeout',
    SettingType.duration,
    'Providers',
    'Idle timeout',
    'Pause between stream events before the request is abandoned.',
    'fine-tuning of the network; the default suits most setups',
    defaultValue: '120s',
  ),
  _fileOnly(
    'providers.*.idle_timeout_reasoning',
    SettingType.duration,
    'Providers',
    'Reasoning idle timeout',
    'Idle timeout before the first content of a hidden-reasoning model.',
    'fine-tuning of the network; the default suits most setups',
    defaultValue: '600s',
  ),
  _fileOnly(
    'providers.*.rate_limit_retries',
    SettingType.int,
    'Providers',
    'Rate limit retries',
    'Retries after HTTP 429, not counting the first attempt.',
    'fine-tuning of the network; the default suits most setups',
    defaultValue: 3,
    min: 0,
  ),
  _fileOnly(
    'providers.*.transient_retries',
    SettingType.int,
    'Providers',
    'Transient retries',
    'Retries of network failures and 5xx before any output is visible.',
    'fine-tuning of the network; the default suits most setups',
    defaultValue: 3,
    min: 0,
  ),
  _fileOnly(
    'providers.*.prompt_cache_key',
    SettingType.bool,
    'Providers',
    'Prompt cache key',
    'Send the session id as prompt_cache_key (openai-compatible only).',
    'compatibility of a specific server; the default suits most setups',
  ),
  _fileOnly(
    'providers.*.reasoning_format',
    SettingType.enumeration,
    'Providers',
    'Reasoning format',
    'Shape of the reasoning level field in requests.',
    'compatibility of a specific server; the default suits most setups',
    enumValues: const ['openai', 'openrouter', 'none'],
  ),
  _fileOnly(
    'providers.*.list_models',
    SettingType.bool,
    'Providers',
    'List models',
    'Ask the endpoint for its model list.',
    'not applied in this version',
    defaultValue: true,
  ),
  _fileOnly(
    'providers.*.list_models_include',
    SettingType.stringList,
    'Providers',
    'Listed models filter',
    'Glob patterns that narrow the endpoint model list.',
    'not applied in this version',
    defaultValue: const <String>[],
  ),
  _opaque('providers.*.preset'),
  _opaque('providers.*.auth'),
  _opaque('providers.*.key_rotation'),
  _opaque('providers.*.key_cooldown'),
  _opaque('providers.*.think_tags'),
  _opaque('providers.*.usage_in_choice'),
  _opaque('providers.*.image_reject_retry'),
  _opaque('providers.*.schema_simplify_retry'),
  _opaque('providers.*.overflow_phrases'),
  _opaque('providers.*.retry_base_delay'),
  _opaque('providers.*.retry_max_delay'),
  _opaque('providers.*.max_retry_after'),
  _opaque('providers.*.stall_retries'),
  _opaque('providers.*.stall_key_rotations'),
  _opaque('providers.*.stall_base_delay'),
  _opaque('providers.*.stall_max_delay'),

  // ---- Provider models ----------------------------------------------------
  _shared(
    'providers.*.models.*.context_window',
    SettingType.int,
    'Models',
    'Context window',
    'Model context window in tokens.',
    min: 1,
  ),
  _shared(
    'providers.*.models.*.max_output_tokens',
    SettingType.int,
    'Models',
    'Max output tokens',
    'Limit of one model answer in tokens.',
    min: 1,
  ),
  _shared(
    'providers.*.models.*.name',
    SettingType.string,
    'Models',
    'Display name',
    'Name shown in the model selector; the model id by default.',
  ),
  _shared(
    'providers.*.models.*.image',
    SettingType.bool,
    'Models',
    'Accepts images',
    'The model accepts image input.',
    defaultValue: false,
  ),
  _shared(
    'providers.*.models.*.reasoning',
    SettingType.bool,
    'Models',
    'Supports reasoning',
    'The model supports a reasoning level.',
    defaultValue: false,
  ),
  _shared(
    'providers.*.models.*.cost_input',
    SettingType.float,
    'Models',
    'Input price',
    'USD per million input tokens.',
  ),
  _shared(
    'providers.*.models.*.cost_output',
    SettingType.float,
    'Models',
    'Output price',
    'USD per million output tokens.',
  ),
  _shared(
    'providers.*.models.*.cost_cache_read',
    SettingType.float,
    'Models',
    'Cache read price',
    'USD per million cached input tokens.',
  ),
  _shared(
    'providers.*.models.*.cost_cache_write',
    SettingType.float,
    'Models',
    'Cache write price',
    'USD per million tokens written to the cache.',
  ),
  _shared(
    'providers.*.models.*.hidden_reasoning',
    SettingType.bool,
    'Models',
    'Hidden reasoning',
    'The model reasons without streaming it; use the long idle timeout.',
  ),
  _shared(
    'providers.*.models.*.thinking_mode',
    SettingType.enumeration,
    'Models',
    'Thinking mode',
    'Anthropic reasoning form: budget is for Claude 4.5 and older.',
    enumValues: const ['adaptive', 'budget'],
  ),
  _opaque('providers.*.models.*.tools'),
  _fileOnly(
    'model_catalog',
    SettingType.map,
    'Advanced',
    'Model catalog',
    'External model metadata source and its network parameters.',
    'external metadata source and network parameters of the catalog',
  ),

  // ---- Permissions --------------------------------------------------------
  _shared(
    'trusted_projects',
    SettingType.pathList,
    'Permissions',
    'Trusted projects',
    'Project roots whose own config may widen permissions.',
    defaultValue: const <String>[],
    restartRequired: true,
    layers: _userOnly,
  ),
  _shared(
    'permissions.mode',
    SettingType.enumeration,
    'Permissions',
    'Permission mode',
    'Mode of a new session.',
    restartRequired: true,
    enumValues: const ['plan', 'ask', 'standard', 'accept-edits', 'bypass'],
  ),
  _fileOnly(
    'permissions.timeout',
    SettingType.duration,
    'Permissions',
    'Approval timeout',
    'How long to wait for an answer before the request is denied.',
    'not applied in this version',
    restartRequired: true,
  ),
  _shared(
    'permissions.deny',
    SettingType.stringList,
    'Permissions',
    'Denied actions',
    'Explicit denials in the form tool:pattern; they win over everything.',
    defaultValue: const <String>[],
    restartRequired: true,
  ),
  _shared(
    'permissions.tools',
    SettingType.map,
    'Permissions',
    'Tool policies',
    'Per-tool override: allow, ask or deny.',
    restartRequired: true,
  ),

  // ---- Budget -------------------------------------------------------------
  _shared(
    'budget.max_steps',
    SettingType.int,
    'Budget',
    'Max steps',
    'Model requests per turn.',
    defaultValue: 50,
    min: 1,
  ),
  _shared(
    'budget.max_tokens',
    SettingType.int,
    'Budget',
    'Max tokens',
    'Sum of input and output tokens per turn.',
    min: 1,
  ),
  _shared(
    'budget.max_cost',
    SettingType.float,
    'Budget',
    'Max cost',
    'USD per turn; works only with known prices.',
  ),
  _shared(
    'budget.max_duration',
    SettingType.duration,
    'Budget',
    'Max duration',
    'Turn time without waiting for approvals.',
  ),

  // ---- Compaction ---------------------------------------------------------
  _shared(
    'compaction.enabled',
    SettingType.bool,
    'Agent',
    'Automatic compaction',
    'Compact the context automatically when it grows.',
    defaultValue: true,
  ),
  _opaque('compaction.engine'),
  _opaque('compaction.structured'),
  _fileOnly(
    'compaction.context_window_cap',
    SettingType.int,
    'Advanced',
    'Context window cap',
    'Upper bound of the context window used for thresholds.',
    'token arithmetic; a wrong value breaks compaction',
    min: 1,
  ),
  _fileOnly(
    'compaction.reserve_tokens',
    SettingType.int,
    'Advanced',
    'Reserved tokens',
    'Tokens kept free for the answer.',
    'token arithmetic; a wrong value breaks compaction',
    min: 1,
  ),
  _fileOnly(
    'compaction.keep_recent_tokens',
    SettingType.int,
    'Advanced',
    'Kept recent tokens',
    'Recent tokens that compaction never summarises.',
    'token arithmetic; a wrong value breaks compaction',
    min: 1,
  ),
  _fileOnly(
    'compaction.keep_recent_user_turns',
    SettingType.int,
    'Advanced',
    'Kept user turns',
    'Recent user turns that compaction never summarises.',
    'token arithmetic; a wrong value breaks compaction',
  ),

  // ---- Tools --------------------------------------------------------------
  _fileOnly(
    'tools.disabled',
    SettingType.stringList,
    'Tools',
    'Disabled tools',
    'Tools to switch off: names, mcp__server__tool or patterns.',
    'not applied in this version',
    defaultValue: const <String>[],
  ),
  _fileOnly(
    'tools.output',
    SettingType.map,
    'Tools',
    'Output limits',
    'Truncation limits of tool output.',
    'limits change deliberately',
  ),
  _fileOnly(
    'tools.untrusted_paths',
    SettingType.stringList,
    'Tools',
    'Untrusted paths',
    'Directories whose read and search output is treated as untrusted.',
    'trust boundary; changes deliberately',
    defaultValue: const ['node_modules', '.dart_tool', 'vendor'],
  ),
  _fileOnly(
    'tools.project_context.max_bytes',
    SettingType.int,
    'Tools',
    'Project instructions budget',
    'Bytes of project instruction files put into the system prompt; 0 '
        'reads none.',
    'trust boundary and truncation limit; changes deliberately',
    defaultValue: 32768,
    min: 0,
    max: 262144,
  ),
  _opaque('tools.load'),
  _opaque('tools.mounted'),
  _opaque('tools.heartbeat'),
  _opaque('tools.web'),
  _opaque('tools.read'),
  _opaque('tools.edit'),
  _opaque('tools.inspect_image'),
  _opaque('tools.checkpoint'),
  _opaque('tools.ask'),
  _opaque('tools.history'),
  _opaque('tools.spill'),

  // ---- Loop ---------------------------------------------------------------
  _fileOnly(
    'loop.empty_response_retries',
    SettingType.int,
    'Advanced',
    'Empty response retries',
    'Retries of consecutive empty model answers.',
    'loop behaviour on model failures; the default suits most setups',
    defaultValue: 2,
  ),
  _fileOnly(
    'loop.misuse',
    SettingType.map,
    'Advanced',
    'Misuse guard',
    'Guard against repeated invalid tool calls.',
    'loop behaviour on model failures; the default suits most setups',
  ),
  _opaque('loop.final_response'),

  // ---- Command execution and prompts --------------------------------------
  _fileOnly(
    'exec',
    SettingType.map,
    'Advanced',
    'Command execution',
    'Shell, timeouts, environment and secrets of commands.',
    'environment and secrets of commands are a security boundary',
    layers: _userAndLocal,
  ),
  _fileOnly(
    'prompts',
    SettingType.map,
    'Advanced',
    'Prompts',
    'Paths and texts of system prompt parts.',
    'long texts and paths of prompts',
  ),

  // ---- MCP ----------------------------------------------------------------
  _shared(
    'mcp.servers',
    SettingType.mapList,
    'MCP',
    'MCP servers',
    'Servers whose tools the agent can use; secrets go through '
        '\${secret:name}.',
  ),

  // ---- Host: sessions, logging, profile, secrets ---------------------------
  _fileOnly(
    'sessions',
    SettingType.map,
    'Advanced',
    'Sessions',
    'Layout of session logs on disk.',
    'layout of logs on disk',
    restartRequired: true,
    layers: _userAndLocal,
  ),
  _shared(
    'logging.level',
    SettingType.enumeration,
    'Logging',
    'Log level',
    'Verbosity of the agent log.',
    defaultValue: 'info',
    restartRequired: true,
    enumValues: const ['trace', 'debug', 'info', 'warning', 'error'],
    layers: _userAndLocal,
  ),
  _fileOnly(
    'logging.file',
    SettingType.path,
    'Logging',
    'Log file',
    'File that receives the log; none by default.',
    'the sink is opened once at start',
    restartRequired: true,
    layers: _userAndLocal,
  ),
  _fileOnly(
    'logging.trace',
    SettingType.bool,
    'Logging',
    'Trace',
    'Write the diagnostic trace.',
    'diagnostics',
    restartRequired: true,
    layers: _userAndLocal,
  ),
  _fileOnly(
    'logging.trace_payload',
    SettingType.bool,
    'Logging',
    'Trace payloads',
    'Include payloads in the diagnostic trace.',
    'diagnostics',
    restartRequired: true,
    layers: _userAndLocal,
  ),
  _opaque('logging.llm_snapshot', restartRequired: true, layers: _userAndLocal),
  _fileOnly(
    'redact',
    SettingType.map,
    'Advanced',
    'Secret redaction',
    'Layers and allowlist of secret redaction.',
    'security boundary: weakening redaction is a deliberate file edit',
  ),
  _fileOnly(
    'profile',
    SettingType.map,
    'Advanced',
    'Host profile',
    'Narrowing of host capabilities per profile.',
    'narrowing depends on the host',
    restartRequired: true,
  ),
  _fileOnly(
    'secrets.backend',
    SettingType.enumeration,
    'Advanced',
    'Secret store backend',
    'Where secrets are stored.',
    'an open secrets file is chosen only by a deliberate edit',
    defaultValue: 'auto',
    restartRequired: true,
    enumValues: const ['auto', 'keychain', 'env', 'file'],
    layers: _userOnly,
  ),
  _fileOnly(
    'agents',
    SettingType.map,
    'Advanced',
    'Agent definitions',
    'Definitions of agents live in markdown files, not in YAML.',
    'agent definitions are markdown files',
  ),

  // ---- Sections after the MVP (opaque in this build) -----------------------
  _opaque('skills'),
  _opaque('subagents'),
  _opaque('jobs'),
  _opaque('hooks'),
  _opaque('plugins'),
  _opaque('a2a'),
  _opaque('memory'),
  _opaque('steering'),
  _opaque('lsp'),
  // Наблюдение за файлами конфига (D7): листья вместо прежнего непрозрачного
  // узла; наблюдатель создаётся один раз, поэтому `restartRequired`. Менять
  // их из UI бессмысленно — `fileOnly`.
  _fileOnly(
    'config.watch',
    SettingType.bool,
    'Advanced',
    'Watch config files',
    'Reload the config when its files change.',
    'the watcher is created once at start',
    defaultValue: true,
    restartRequired: true,
    layers: _userAndLocal,
  ),
  _fileOnly(
    'config.poll_interval',
    SettingType.duration,
    'Advanced',
    'Config poll interval',
    'How often files are polled where file events are unavailable; '
        '1s..60s.',
    'the watcher is created once at start',
    defaultValue: '2s',
    restartRequired: true,
    layers: _userAndLocal,
  ),
]);

/// Реестр настроек: таблица, поиск и разбор значения CLI (D4).
abstract final class SettingsRegistry {
  /// Все дескрипторы в порядке показа.
  static List<SettingDescriptor> get all => _descriptors;

  /// Дескриптор ключа [key] с учётом `*` и покрытия поддерева ключами типа
  /// `map`/`mapList`; более конкретный дескриптор побеждает `*` и «прочие».
  /// `null` — ключа нет в реестре. [key] пишется как в [KeyPath]: сегмент в
  /// кавычках — одно имя, `[имя]` — элемент списка.
  static SettingDescriptor? lookup(String key) {
    final found = coveringDescriptors(_descriptors, key);
    return found.isEmpty ? null : found.first;
  }

  /// Разбирает строку значения `config set` по типу [d] (D4).
  ///
  /// Возвращает значение для `SetValue`: `bool`, `int`, `double`, строку
  /// (длительность остаётся в форме конфига: `30s`), список строк или
  /// JSON-структуру. Ошибка — [ConfigValueException] с ожидаемым форматом;
  /// значение в текст не попадает.
  static Object parseCliValue(SettingDescriptor d, String raw) {
    Never fail(String expected) => throw ConfigValueException(d.key, expected);

    switch (d.type) {
      case SettingType.bool:
        return switch (raw) {
          'true' => true,
          'false' => false,
          _ => fail('true or false'),
        };
      case SettingType.int:
        final value = _strictInt.hasMatch(raw) ? int.tryParse(raw) : null;
        if (value == null || !_inRange(value, d)) {
          fail(_numberExpected('an integer', d));
        }
        return value;
      case SettingType.float:
        final value = double.tryParse(raw);
        if (value == null ||
            !value.isFinite ||
            raw.trim() != raw ||
            !_inRange(value, d)) {
          fail(_numberExpected('a number', d));
        }
        return value;
      case SettingType.duration:
        if (parseConfigDuration(raw) == null) {
          fail('a duration like 500ms, 30s, 2m or 1h');
        }
        return raw;
      case SettingType.enumeration:
        final values = d.enumValues ?? const [];
        if (!values.contains(raw)) {
          fail('one of: ${values.join(', ')}');
        }
        return raw;
      case SettingType.modelRef:
        if (!_modelRef.hasMatch(raw)) {
          fail('a model reference like provider/model');
        }
        return raw;
      case SettingType.secretName:
        if (SecretNames.problem(raw) case final problem?) {
          // Текст `problem` не содержит имя (контракт `SecretNames`).
          fail(problem.replaceFirst('expected ', ''));
        }
        return raw;
      case SettingType.envVarName:
        if (!_envVar.hasMatch(raw)) {
          fail('an environment variable name like OPENAI_API_KEY');
        }
        return raw;
      case SettingType.string:
      case SettingType.path:
        if (raw.isEmpty) {
          fail(d.type == SettingType.path ? 'a path' : 'a non-empty string');
        }
        return raw;
      case SettingType.stringList:
      case SettingType.pathList:
        return _jsonStrings(d, raw, 'a JSON array of strings');
      case SettingType.modelRefList:
        final list = _jsonStrings(d, raw, 'a JSON array of provider/model');
        if (!list.every(_modelRef.hasMatch)) {
          fail('a JSON array of provider/model');
        }
        return list;
      case SettingType.map:
        final value = _json(raw);
        if (value is! Map<String, Object?>) {
          fail('a JSON object');
        }
        return value;
      case SettingType.mapList:
        final value = _json(raw);
        if (value is! List<Object?> ||
            !value.every((e) => e is Map<String, Object?>)) {
          fail('a JSON array of objects');
        }
        return value;
    }
  }

  static final _strictInt = RegExp(r'^-?\d{1,18}$');
  static final _modelRef = RegExp(r'^[^/\s]+/\S+$');
  static final _envVar = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static bool _inRange(num value, SettingDescriptor d) =>
      (d.min == null || value >= d.min!) && (d.max == null || value <= d.max!);

  static String _numberExpected(String noun, SettingDescriptor d) {
    final (min, max) = (d.min, d.max);
    if (min != null && max != null) {
      return '$noun from $min to $max';
    }
    if (min != null) {
      return '$noun of $min or greater';
    }
    if (max != null) {
      return '$noun of $max or less';
    }
    return noun;
  }

  /// JSON без исключения наружу: `FormatException` цитирует кусок входа, а
  /// значение не должно попасть в текст ошибки.
  static Object? _json(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return const _NotJson();
    }
  }

  static List<String> _jsonStrings(
    SettingDescriptor d,
    String raw,
    String expected,
  ) {
    final value = _json(raw);
    if (value is! List<Object?> || !value.every((e) => e is String)) {
      throw ConfigValueException(d.key, expected);
    }
    return [for (final item in value) item! as String];
  }
}

/// Все дескрипторы из [descriptors], покрывающие [key], от самого конкретного
/// к самому общему. Внутренняя функция: барель экспортирует файл с `hide`
/// (PKG-5-подобная граница: публичный контракт — `SettingsRegistry.lookup`),
/// её вызывают `lookup` и тест полноты на испорченных копиях таблицы.
///
/// Порядок: точное совпадение раньше покрытия предком; среди совпадений —
/// больше сегментов без `*`; среди предков — глубже; при равном счёте — по
/// ключу дескриптора, чтобы порядок не зависел от порядка таблицы. Так
/// `plugins.enabled` побеждает `plugins.*`, а оно — `plugins`.
///
/// [key] — путь пользователя: неразбираемый путь (`a..b`, незакрытая кавычка)
/// и любой сегмент `*`, в том числе в кавычках, ничего не находят: `*` —
/// метасимвол таблицы, а не имя записи. Путь схемы с `*` вместо имён
/// ([schemaPath]) разрешает только тест полноты.
List<SettingDescriptor> coveringDescriptors(
  Iterable<SettingDescriptor> descriptors,
  String key, {
  bool schemaPath = false,
}) {
  final segments = splitKeyPath(key);
  if (segments == null) {
    return const [];
  }
  final target = [
    for (final segment in segments)
      segment.isElement ? '[${segment.value}]' : segment.value,
  ];
  if (!schemaPath && target.contains('*')) {
    return const [];
  }
  final scored = <(int, SettingDescriptor)>[];
  for (final d in descriptors) {
    final pattern = d.key.split('.');
    if (pattern.length > target.length) {
      continue;
    }
    var literals = 0;
    var matches = true;
    for (var i = 0; i < pattern.length && matches; i++) {
      if (pattern[i] == '*') {
        // Звёздочка — любое имя записи, но не элемент списка.
        matches = !target[i].startsWith('[') || target[i] == '*';
      } else {
        matches = pattern[i] == target[i];
        literals++;
      }
    }
    if (!matches) {
      continue;
    }
    final exact = pattern.length == target.length;
    if (!exact && d.type != SettingType.map && d.type != SettingType.mapList) {
      continue;
    }
    scored.add(((exact ? 10000 : 0) + pattern.length * 100 + literals, d));
  }
  scored.sort((a, b) {
    final byScore = b.$1.compareTo(a.$1);
    return byScore != 0 ? byScore : a.$2.key.compareTo(b.$2.key);
  });
  return [for (final (_, d) in scored) d];
}

/// Метка «разбор JSON не удался»: отличается от любого значения JSON.
final class _NotJson {
  const _NotJson();
}
