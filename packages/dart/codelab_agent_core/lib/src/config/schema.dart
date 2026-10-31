/// Декларативная схема конфигурации (`agent-core-architecture` §15.4;
/// design.md change `add-agent-configuration`, D6).
///
/// Почему таблицей: строгая проверка (CFG-1) и список «ключей без
/// потребителя» должны выводиться из одного места, а не из россыпи
/// `switch`. Новая функция добавляет ключ строкой этой таблицы и признаком
/// `applied: true` вместе со своим потребителем (критерий (г) итерации).
///
/// Для чего: валидатор обходит дерево слоя по этой схеме, находит неизвестные
/// ключи, неверные типы и ключи, которые ещё никто не читает.
library;

/// Бюджет инструкций проекта по умолчанию, байты (`tools.project_context.
/// max_bytes`, §15.4; design.md change `add-agent-project-files`, D5).
const defaultProjectContextMaxBytes = 32768;

/// Верхняя граница `tools.project_context.max_bytes`, байты (§15.4).
const maxProjectContextMaxBytes = 262144;

/// Скалярные типы §15.4.
enum ScalarType { string, integer, float, boolean, duration, path }

/// Узел схемы.
sealed class SchemaNode {
  const SchemaNode({this.applied = true});

  /// `false` — у ключа ещё нет потребителя в коде: явно заданный ключ даёт
  /// предупреждение `config.key.not_applied` (D6, OQ4 (а)).
  final bool applied;
}

/// Скаляр; [allowed] ограничивает строку перечислением.
final class ScalarNode extends SchemaNode {
  const ScalarNode(
    this.type, {
    this.allowed,
    this.allowedLabel = 'value',
    super.applied,
  });

  final ScalarType type;
  final List<String>? allowed;

  /// Как называется перечисление в сообщении: `provider kind`.
  final String allowedLabel;
}

/// Список скаляров.
final class ListNode extends SchemaNode {
  const ListNode(this.item, {super.applied});

  final ScalarType item;
}

/// Отображение строка → строка (`headers`, `env`).
final class StringMapNode extends SchemaNode {
  const StringMapNode({super.applied});
}

/// Отображение с фиксированными ключами и/или именованными записями.
///
/// [named] — схема значений по произвольному имени (`providers.<id>`);
/// [nameFormat] проверяет имя; [nameLabel] называет его в сообщении.
/// [rejectsInlineSecrets] — секция, в которой ключи `api_key`, `token` и т. п.
/// дают `inlineSecret` (CFG-2).
final class SectionNode extends SchemaNode {
  const SectionNode(
    this.fields, {
    this.named,
    this.nameFormat,
    this.nameLabel = 'name',
    this.rejectsInlineSecrets = false,
    super.applied,
  });

  final Map<String, SchemaNode> fields;
  final SchemaNode? named;
  final RegExp? nameFormat;
  final String nameLabel;
  final bool rejectsInlineSecrets;
}

/// Список отображений (`mcp.servers`, `exec.secrets`); [keyField] — поле
/// имени записи, по которому слои сливаются и которое стоит в пути:
/// `mcp.servers[github].url`.
final class ObjectListNode extends SchemaNode {
  const ObjectListNode(this.item, {this.keyField, super.applied});

  final SectionNode item;
  final String? keyField;
}

/// Раздел без проверки типов: ключи «после MVP» (D6). Явно заданный лист
/// даёт `config.key.not_applied`, схему введёт change с потребителем.
final class OpaqueNode extends SchemaNode {
  const OpaqueNode() : super(applied: false);
}

/// Значение `profile.<name>.<capability>`: `"off"` или список транспортов.
final class ProfileValueNode extends SchemaNode {
  const ProfileValueNode();
}

/// `permissions.mode`: перечисление с синонимами и особым правилом
/// `autopilot` (CFG-4).
final class ModeNode extends SchemaNode {
  const ModeNode();
}

/// `agents.*`: определения агентов не живут в YAML (DF-12).
final class AgentsNode extends SchemaNode {
  const AgentsNode();
}

/// Виды провайдеров §15.4 (DF-15: без подмены mock-провайдером).
const providerKinds = ['openai-compatible', 'anthropic', 'gemini'];

/// Секреты значением (CFG-2, §17.5.4, пункт 1).
const inlineSecretKeys = {'api_key', 'apiKey', 'token', 'secret', 'password'};

const _opaque = OpaqueNode();
const _str = ScalarNode(ScalarType.string);
const _int = ScalarNode(ScalarType.integer);
const _bool = ScalarNode(ScalarType.boolean);
const _dur = ScalarNode(ScalarType.duration);

const _strU = ScalarNode(ScalarType.string, applied: false);
const _intU = ScalarNode(ScalarType.integer, applied: false);
const _boolU = ScalarNode(ScalarType.boolean, applied: false);
const _durU = ScalarNode(ScalarType.duration, applied: false);
const _pathU = ScalarNode(ScalarType.path, applied: false);
const _strListU = ListNode(ScalarType.string, applied: false);

/// Разделы верхнего уровня «после MVP» (§15.4): распознаются по имени и дают
/// `config.key.not_applied` без проверки типов (D6).
const afterMvpSections = [
  'llm',
  'images',
  'skills',
  'subagents',
  'jobs',
  'hooks',
  'plugins',
  'a2a',
  'memory',
  'steering',
  'lsp',
  'config',
];

/// Слои редакции секретов §12.4.3.
const redactLayerNames = [
  'exact',
  'credential_files',
  'formats',
  'pem',
  'connection_strings',
  'key_values',
  'entropy',
];

/// Слои редакции по умолчанию: шесть без `entropy` (§15.4).
const redactDefaultLayers = [
  'exact',
  'credential_files',
  'formats',
  'pem',
  'connection_strings',
  'key_values',
];

const redactBuiltinAllowlist = ['git_sha', 'uuid'];

const logLevelNames = ['trace', 'debug', 'info', 'warning', 'error'];

/// Корень схемы MVP (§15.4).
final SectionNode rootSchema = SectionNode({
  'trusted_projects': ListNode(ScalarType.path),
  'providers': SectionNode(
    {},
    named: _providerSchema,
    nameFormat: _idFormat,
    nameLabel: 'provider id',
  ),
  'agent': SectionNode({
    'default_model': _str,
    'fallback': _strListU,
    'summary_model': _strU,
    'effort': ScalarNode(
      ScalarType.string,
      allowed: ['low', 'medium', 'high'],
      allowedLabel: 'effort',
    ),
  }),
  'agents': AgentsNode(),
  'model_catalog': SectionNode({
    'ttl': _durU,
    'fetch_timeout': _durU,
    'metadata_url': _strU,
  }),
  'permissions': SectionNode({
    'mode': ModeNode(),
    'timeout': _durU,
    'deny': ListNode(ScalarType.string),
    'tools': SectionNode(
      {},
      named: ScalarNode(
        ScalarType.string,
        allowed: ['allow', 'ask', 'deny'],
        allowedLabel: 'tool policy',
      ),
      nameLabel: 'tool name',
    ),
  }),
  'budget': SectionNode({
    'max_steps': _int,
    'max_tokens': _int,
    'max_cost': ScalarNode(ScalarType.float),
    'max_duration': _dur,
  }),
  'compaction': SectionNode({
    'enabled': _bool,
    'context_window_cap': _int,
    'reserve_tokens': _int,
    'keep_recent_tokens': _int,
    'keep_recent_user_turns': _int,
    'engine': _opaque,
    'structured': _opaque,
  }),
  'tools': SectionNode({
    'output': SectionNode({'max_lines': _intU, 'max_bytes': _intU}),
    'untrusted_paths': _strListU,
    'project_context': SectionNode({'max_bytes': _int}),
    'disabled': _strListU,
    'load': _opaque,
    'mounted': _opaque,
    'heartbeat': _opaque,
    'web': _opaque,
    'read': _opaque,
    'edit': _opaque,
    'inspect_image': _opaque,
    'checkpoint': _opaque,
    'ask': _opaque,
    'history': _opaque,
    'spill': _opaque,
  }),
  'loop': SectionNode({
    'empty_response_retries': _intU,
    'misuse': SectionNode({
      'enabled': _boolU,
      'warn_after': _intU,
      'block_after': _intU,
    }),
    'final_response': _opaque,
  }),
  'exec': SectionNode({
    'shell': _strU,
    'default_timeout': _durU,
    'max_timeout': _durU,
    'secrets': ObjectListNode(
      SectionNode({'env': _str, 'secret': _str}),
      applied: false,
    ),
    'local_fallback': _boolU,
    'env': StringMapNode(applied: false),
  }),
  'prompts': SectionNode({
    'system': _pathU,
    'system_text': _strU,
    'append_system': _pathU,
    'append_system_text': _strU,
    'context_files': _strListU,
    'modes': SectionNode({'plan': _pathU}),
    'compaction': SectionNode({'summary': _pathU, 'summary_update': _pathU}),
    'templates': _opaque,
    'templates_dirs': _opaque,
  }),
  'mcp': SectionNode({
    'servers': ObjectListNode(_mcpServerSchema, keyField: 'name'),
  }),
  'sessions': SectionNode({
    'dir': ScalarNode(ScalarType.path),
    'fsync': ScalarNode(
      ScalarType.string,
      allowed: ['checkpoints', 'always', 'never'],
      allowedLabel: 'fsync mode',
    ),
    'lease': _opaque,
    'branch_summary': _opaque,
    'read_only': _opaque,
    'window': _opaque,
    'segments': _opaque,
    'search': _opaque,
  }),
  'logging': SectionNode({
    'level': ScalarNode(
      ScalarType.string,
      allowed: logLevelNames,
      allowedLabel: 'log level',
    ),
    'file': ScalarNode(ScalarType.path),
    'trace': _boolU,
    'trace_payload': _boolU,
    'llm_snapshot': _opaque,
  }),
  'redact': SectionNode({
    'enabled': _boolU,
    'layers': _strListU,
    'allowlist': SectionNode({'builtin': _strListU, 'patterns': _strListU}),
    'exempt_tools': _strListU,
    'block': _opaque,
    'command_rewrite': _opaque,
  }),
  // Хранилище секретов (этап 8.9, design.md change `add-agent-secret-store`,
  // D7). Допустимость значения проверяет `resolve.dart`: текст проблемы
  // `expected one of: auto, keychain, env, file` задан спецификацией и
  // отличается от общего текста `allowed`.
  'secrets': SectionNode({'backend': _str}),
  'profile': SectionNode(
    {},
    named: SectionNode({}, named: ProfileValueNode(), nameLabel: 'capability'),
    nameLabel: 'profile name',
  ),
  for (final name in afterMvpSections) name: _opaque,
});

final _idFormat = RegExp(r'^[a-z0-9_-]+$');

const SectionNode _mcpServerSchema = SectionNode({
  'name': _str,
  'type': _str,
  'command': _str,
  'args': ListNode(ScalarType.string),
  'env': StringMapNode(),
  'url': _str,
  'headers': StringMapNode(),
  'enabled': _bool,
  'connect_timeout': _dur,
  'call_timeout': _dur,
}, rejectsInlineSecrets: true);

const SectionNode _providerSchema = SectionNode({
  'kind': ScalarNode(
    ScalarType.string,
    allowed: providerKinds,
    allowedLabel: 'provider kind',
  ),
  'base_url': _str,
  'api_key_env': _str,
  'api_key_secret': _str,
  'auth_header': _str,
  'headers': StringMapNode(),
  'connect_timeout': _dur,
  'idle_timeout': _dur,
  'idle_timeout_reasoning': _dur,
  'rate_limit_retries': _int,
  'transient_retries': _int,
  'prompt_cache_key': _bool,
  'reasoning_format': ScalarNode(
    ScalarType.string,
    allowed: ['openai', 'openrouter', 'none'],
    allowedLabel: 'reasoning format',
  ),
  'list_models': _boolU,
  'list_models_include': _strListU,
  'models': SectionNode({}, named: _modelSchema, nameLabel: 'model id'),
  'preset': _opaque,
  'auth': _opaque,
  'key_rotation': _opaque,
  'key_cooldown': _opaque,
  'think_tags': _opaque,
  'usage_in_choice': _opaque,
  'image_reject_retry': _opaque,
  'schema_simplify_retry': _opaque,
  'overflow_phrases': _opaque,
  'retry_base_delay': _opaque,
  'retry_max_delay': _opaque,
  'max_retry_after': _opaque,
  'stall_retries': _opaque,
  'stall_key_rotations': _opaque,
  'stall_base_delay': _opaque,
  'stall_max_delay': _opaque,
}, rejectsInlineSecrets: true);

const SectionNode _modelSchema = SectionNode({
  'context_window': _int,
  'max_output_tokens': _int,
  'name': _str,
  'image': _bool,
  'reasoning': _bool,
  'cost_input': ScalarNode(ScalarType.float),
  'cost_output': ScalarNode(ScalarType.float),
  'cost_cache_read': ScalarNode(ScalarType.float),
  'cost_cache_write': ScalarNode(ScalarType.float),
  'hidden_reasoning': _bool,
  'thinking_mode': ScalarNode(
    ScalarType.string,
    allowed: ['adaptive', 'budget'],
    allowedLabel: 'thinking mode',
  ),
  'tools': _opaque,
});
