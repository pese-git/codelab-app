import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Предконфигурация провайдера, заданная флагами `serve` (`--provider-type`,
/// `--provider-config`).
///
/// Почему отдельный тип: загрузчик не читает argv и файлы `@путь` — это дело
/// хоста; он получает готовый текст JSON. Значение флага может содержать
/// заголовки с токеном, поэтому [toString] его не печатает (CFG-12).
///
/// Для чего: переносит флаги от разбора аргументов (`apps/codelab_agent`) к
/// `ConfigLoader`, где они образуют слой флагов и затеняют переменные
/// `CODELAB_PROVIDER_*` (design.md change `add-config-writer-and-reload`, D3;
/// `agent-core-architecture` §17.5.3).
///
/// Как использовать: хост проверяет пару и сочетания флагов (код `64`), читает
/// `@путь` и передаёт `ProviderPreconfigFlags(providerType: …, providerConfig:
/// <текст JSON>)` в `ConfigLoader.load(preconfigFlags: …)`. У встроенного агента
/// флагов нет, только переменные.
final class ProviderPreconfigFlags {
  const ProviderPreconfigFlags({this.providerType, this.providerConfig});

  /// Значение `--provider-type`.
  final String? providerType;

  /// Текст JSON из `--provider-config` (для `@путь` — содержимое файла).
  final String? providerConfig;

  /// Задан ли хотя бы один из двух флагов: тогда переменные не читаются.
  bool get isSet => providerType != null || providerConfig != null;

  @override
  String toString() =>
      'ProviderPreconfigFlags(type: ${providerType != null}, '
      'config: ${providerConfig != null})';
}

/// Результат [preconfigLayer].
///
/// [layer] равен `null`, если предконфигурации нет или в ней проблемы
/// ([issues]); [notices] — информационные записи лога (`config.preconfig.
/// shadowed`), не мешающие запуску.
typedef PreconfigResult = ({
  ConfigTree? layer,
  List<ConfigIssue> issues,
  List<ConfigIssue> notices,
});

const _typeVar = 'CODELAB_PROVIDER_TYPE';
const _configVar = 'CODELAB_PROVIDER_CONFIG';
const _base64Var = 'CODELAB_PROVIDER_CONFIG_BASE64';

const _kinds = ['openai-compatible', 'anthropic'];

/// Поля JSON предконфигурации (`agent-core-architecture` §17.5.3).
const _fields = [
  'id',
  'base_url',
  'model',
  'context_window',
  'max_output_tokens',
  'name',
  'image',
  'reasoning',
  'api_key_env',
  'api_key_secret',
  'auth_header',
  'headers',
  'connect_timeout',
  'idle_timeout',
];

/// Поля, в которых секрет записан значением (CFG-9): JSON-ключи, не
/// входящие в таблицу полей.
const _secretFields = {
  'api_key',
  'apiKey',
  'key',
  'token',
  'secret',
  'password',
};

final _idFormat = RegExp(r'^[a-z0-9_-]+$');

/// Слой предконфигурации провайдера: переменные `CODELAB_PROVIDER_*` или
/// флаги (`agent-core-architecture` §17.5.3; design.md change
/// `add-config-writer-and-reload`, D3, D5; L-25).
///
/// Почему в `codelab_agent_io`: окружение и argv читает хост, ядро получает
/// готовое дерево (CFG-5). Слой общий для `serve`, встроенного агента и
/// `config check` — второго пути загрузки провайдеров нет (§17.5.12).
///
/// Для чего: превращает `TYPE` и JSON-описание одного провайдера в таблицу
/// `providers.<id>` и `agent.default_model`. Слой стоит перед
/// `buildEnvironmentLayer` (`CODELAB_MODEL` — более частное значение) или, для
/// флагов, перед слоем `--model`; доверие §15.3 к нему не применяется.
///
/// Как использовать: загрузчик зовёт функцию один раз за загрузку. Если
/// [flags] заданы ([ProviderPreconfigFlags.isSet]), переменные не читаются, а в
/// [PreconfigResult.notices] попадает `config.preconfig.shadowed {by: flags}`;
/// источник слоя — `flags`. Иначе слой читает переменные, источник —
/// `env:CODELAB_PROVIDER_CONFIG` (или `…_BASE64`), а ни одной переменной нет —
/// пустой результат. Пустое значение переменной равно её отсутствию.
///
/// Ошибки — [ConfigIssue] без позиции: текст называет переменную (флаг) и
/// поле, но не цитирует значение, фрагмент JSON и текст исключения парсера
/// (CFG-12). Секрет значением — `inlineSecret` с подсказкой `codelab/<id>`.
PreconfigResult preconfigLayer(
  Map<String, String> environment, {
  ProviderPreconfigFlags? flags,
}) {
  final fromFlags = flags != null && flags.isSet;
  final String? type;
  final String? config;
  final String? configBase64;
  final String typeName, configName, base64Name, source;
  final notices = <ConfigIssue>[];
  if (fromFlags) {
    type = _nonEmpty(flags.providerType);
    config = _nonEmpty(flags.providerConfig);
    configBase64 = null;
    typeName = '--provider-type';
    configName = '--provider-config';
    base64Name = configName;
    source = 'flags';
    notices.add(
      const ConfigIssue(
        kind: ConfigIssueKind.semantic,
        key: '',
        source: 'flags',
        message:
            'CODELAB_PROVIDER_* variables are ignored: preconfiguration '
            'flags are set',
        event: 'config.preconfig.shadowed',
        fields: {'by': 'flags'},
        level: LogLevel.info,
      ),
    );
  } else {
    type = _nonEmpty(environment[_typeVar]);
    config = _nonEmpty(environment[_configVar]);
    configBase64 = _nonEmpty(environment[_base64Var]);
    typeName = _typeVar;
    configName = _configVar;
    base64Name = _base64Var;
    source =
        'env:${configBase64 != null && config == null ? _base64Var : _configVar}';
    if (type == null && config == null && configBase64 == null) {
      return (layer: null, issues: const [], notices: const []);
    }
  }

  final issues = <ConfigIssue>[];
  ConfigIssue issue(
    String message, {
    String? from,
    ConfigIssueKind kind = ConfigIssueKind.value,
    String key = '',
  }) => ConfigIssue(
    kind: kind,
    key: key,
    source: from ?? source,
    message: message,
  );

  if (config != null && configBase64 != null) {
    issues.add(
      issue(
        '$_configVar and $_base64Var are both set; set only one of them',
        from: 'env:$_configVar',
      ),
    );
    return (layer: null, issues: issues, notices: notices);
  }
  final text = config ?? configBase64;
  if (type == null || text == null) {
    issues.add(
      issue(
        fromFlags
            ? '$typeName and $configName must be set together'
            : '$typeName and $configName (or $base64Name) must be set '
                  'together',
        from: fromFlags
            ? source
            : 'env:${type == null ? configName : typeName}',
      ),
    );
    return (layer: null, issues: issues, notices: notices);
  }
  final name = configBase64 != null && config == null ? base64Name : configName;
  if (!_kinds.contains(type)) {
    issues.add(
      issue(
        '$typeName: expected one of: ${_kinds.join(', ')}',
        from: fromFlags ? source : 'env:$_typeVar',
      ),
    );
  }

  var json = text;
  if (configBase64 != null) {
    final decoded = _decodeBase64(configBase64);
    if (decoded == null) {
      issues.add(issue('$name: not base64'));
      return (layer: null, issues: issues, notices: notices);
    }
    json = decoded;
  }
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException catch (error) {
    // Текст исключения парсера цитирует фрагмент значения, поэтому берётся
    // только смещение (§17.5.3, шаг 4).
    final offset = error.offset;
    issues.add(
      issue(
        offset == null
            ? '$name: invalid JSON'
            : '$name: invalid JSON at offset $offset',
      ),
    );
    return (layer: null, issues: issues, notices: notices);
  }
  if (root is! Map<String, Object?>) {
    issues.add(issue('$name: expected a JSON object'));
    return (layer: null, issues: issues, notices: notices);
  }

  final built = _build(root, name: name, kind: type, issue: issue);
  issues.addAll(built.issues);
  if (issues.isNotEmpty) {
    return (layer: null, issues: issues, notices: notices);
  }
  return (
    layer: ConfigTree(
      kind: fromFlags ? ConfigLayerKind.flags : ConfigLayerKind.environment,
      source: source,
      values: built.values,
    ),
    issues: const [],
    notices: notices,
  );
}

typedef _IssueFactory =
    ConfigIssue Function(
      String message, {
      String? from,
      ConfigIssueKind kind,
      String key,
    });

/// Проверяет поля JSON и строит значения слоя (шаги 5–6 §17.5.3).
///
/// Все проблемы собираются сразу, чтобы `config check` напечатал их вместе.
({Map<String, Object?> values, List<ConfigIssue> issues}) _build(
  Map<String, Object?> root, {
  required String name,
  required String kind,
  required _IssueFactory issue,
}) {
  final issues = <ConfigIssue>[];
  void bad(String field, String problem) =>
      issues.add(issue('$name.$field: $problem'));

  final rawId = root['id'];
  var id = 'env';
  if (root.containsKey('id')) {
    if (rawId is! String) {
      bad('id', 'expected string');
    } else if (!_idFormat.hasMatch(rawId)) {
      bad('id', 'expected a provider id: a-z, 0-9, _ and -');
    } else {
      id = rawId;
    }
  }

  String? string(String field) {
    final value = root[field];
    if (!root.containsKey(field)) {
      return null;
    }
    if (value is! String) {
      bad(field, 'expected string');
      return null;
    }
    return value;
  }

  int? integer(String field) {
    final value = root[field];
    if (!root.containsKey(field)) {
      return null;
    }
    if (value is! int) {
      bad(field, 'expected integer');
      return null;
    }
    return value;
  }

  bool? boolean(String field) {
    final value = root[field];
    if (!root.containsKey(field)) {
      return null;
    }
    if (value is! bool) {
      bad(field, 'expected boolean');
      return null;
    }
    return value;
  }

  for (final field in root.keys) {
    if (_fields.contains(field)) {
      continue;
    }
    if (_secretFields.contains(field) || isSecretLikeName(field)) {
      // Имя подсказки — то же `SecretNames.suggestFor`, что у
      // `ConfigInlineSecretException.suggestedSecretName`: в stderr и в поле
      // одно имя.
      final key = 'providers.$id.$field';
      final secret = SecretNames.suggestFor(key);
      issues.add(
        issue(
          '$name.$field: secrets are not stored in the config; run: codelab '
          'secret set $secret, then use api_key_secret: $secret '
          '(or api_key_env with an environment variable)',
          kind: ConfigIssueKind.inlineSecret,
          key: key,
        ),
      );
      continue;
    }
    final hint = nearestKey(field, _fields);
    bad(
      field,
      hint == null ? 'unknown key' : 'unknown key (did you mean $hint?)',
    );
  }

  final baseUrl = string('base_url');
  if (baseUrl == null && kind == 'openai-compatible') {
    bad('base_url', 'required for openai-compatible providers');
  }
  final model = string('model');
  if (!root.containsKey('model')) {
    bad('model', 'required');
  }
  final contextWindow = integer('context_window');
  if (!root.containsKey('context_window')) {
    bad('context_window', 'required');
  }
  final modelValues = <String, Object?>{
    'context_window': ?contextWindow,
    'max_output_tokens': ?integer('max_output_tokens'),
    'name': ?string('name'),
    'image': ?boolean('image'),
    'reasoning': ?boolean('reasoning'),
  };

  final apiKeyEnv = string('api_key_env');
  final apiKeySecret = string('api_key_secret');
  if (root.containsKey('api_key_env') && root.containsKey('api_key_secret')) {
    issues.add(issue('$name: set only one of api_key_env and api_key_secret'));
  }

  Map<String, Object?>? headers;
  if (root.containsKey('headers')) {
    final raw = root['headers'];
    if (raw is! Map<String, Object?>) {
      bad('headers', 'expected an object of strings');
    } else {
      headers = {};
      for (final MapEntry(key: header, value: value) in raw.entries) {
        if (value is! String) {
          bad('headers.$header', 'expected string');
          continue;
        }
        // Правило D5: литерал в секретном заголовке — проблема, значение не
        // цитируется (CFG-9, CFG-12).
        if (value.isNotEmpty &&
            isSecretLikeName(header) &&
            !hasSecretReference(value)) {
          final key = 'providers.$id.headers.$header';
          final secret = SecretNames.suggestFor(key);
          issues.add(
            issue(
              '$name.headers.$header: a literal value in a secret header; '
              'run: codelab secret set $secret, then use \${secret:$secret} '
              '(or reference an environment variable with \${NAME})',
              kind: ConfigIssueKind.inlineSecret,
              key: key,
            ),
          );
          continue;
        }
        headers[header] = value;
      }
    }
  }

  final provider = <String, Object?>{
    'kind': kind,
    'base_url': ?baseUrl,
    'api_key_env': ?apiKeyEnv,
    'api_key_secret': ?apiKeySecret,
    'auth_header': ?string('auth_header'),
    if (headers != null && headers.isNotEmpty) 'headers': headers,
    'connect_timeout': ?string('connect_timeout'),
    'idle_timeout': ?string('idle_timeout'),
    if (model != null) 'models': {model: modelValues},
  };
  return (
    values: {
      'providers': {id: provider},
      if (model != null) 'agent': {'default_model': '$id/$model'},
    },
    issues: issues,
  );
}

/// Декодирует base64 стандартного или URL-safe алфавита, `=` необязательны.
///
/// `null` — не base64 или не UTF-8. Причина сбоя не возвращается: исключение
/// кодека цитирует символ входа (§17.5.3, шаг 3).
String? _decodeBase64(String raw) {
  try {
    final normalized = raw
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .replaceAll('=', '');
    return utf8.decode(base64.decode(base64.normalize(normalized)));
  } on FormatException {
    return null;
  }
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
