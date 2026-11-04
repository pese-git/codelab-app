/// Правило литеральных секретов в заголовках, переменных окружения и элементах
/// `args` MCP-серверов конфига (design.md change `add-config-writer-and-reload`,
/// D5; CFG-9, CFG-12; change `add-config-literal-secrets-and-migrate`, D5, OQ3,
/// R8-5: шаблоны `literalSecretTag` и подсказка `--env` для `args`).
///
/// Почему отдельный файл: одно и то же правило имён нужно предконфигурации
/// провайдера (D3, итерация 1), записи конфига `ConfigWriter` (D5, итерация 3)
/// и маскированию вывода `config get` / `provider list` (D6, R0-2). Если оно
/// разойдётся, CLI запишет токен, который загрузчик отклонил бы, или наоборот.
///
/// Для чего: отличить заголовок или переменную, значение которых — секрет, от
/// обычных (`X-Team`). Имя нормализуется (нижний регистр, без `-` и `_`), чтобы
/// `X-API-KEY`, `x_api_key` и `ApiKey` не обходили правило.
///
/// Как использовать: `isSecretLikeName(name) && !hasSecretReference(value)` —
/// значение литеральный секрет, его нельзя записывать в конфиг (нужна ссылка
/// `${secret:…}` или `${VAR}`). Ложное срабатывание (`X-Keyboard-Layout`)
/// обходится ссылкой `${VAR}`: отказ дешевле, чем записанный токен.
///
/// Сами функции имён (`isSecretLikeName`, `hasSecretReference`) перенесены в
/// ядро (`secret_name_rule.dart`, публичный барель): тем же правилом
/// пользуется перезагрузка для определения «провайдер с ключом» (D8, R0-4).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Литеральные секреты в итоговом поддереве документа, изменённые записью
/// (design.md change `add-config-writer-and-reload`, D5, «Секреты»; CFG-9).
///
/// Почему по дереву, а не по типу правки: `config set mcp.servers '[…]'`,
/// `config set providers.x.headers '{…}'`, `config set exec '{…}'` и
/// `UpsertMcpServer` пишут один и тот же итоговый документ; проверка типа
/// правки пропустила бы вложенное значение (ревью безопасности итерации 2).
///
/// Для чего: `ConfigWriter.apply` вызывает функцию над деревом слоя до и
/// после правок и отклоняет запись, если в изменённых листьях есть литерал.
/// Правила (все на любой глубине итогового дерева):
/// - литеральная часть значения `headers`/`env` по шаблону §12.4
///   (`literalSecretTag`, R1-1) — при любом имени ключа; значение режется по
///   `${…}`, поэтому ссылка рядом с литералом его не прикрывает;
/// - элемент `mcp.servers[*].args` по шаблону §12.4 (R4-6, OQ3) — с подсказкой
///   `--env <NAME>='${secret:<имя>}'` (R8-5); загрузка `args` не проверяет;
/// - значение в `providers.*.headers`, `mcp.servers[*].headers`,
///   `mcp.servers[*].env`, `exec.env`, чьё имя секретное
///   ([isSecretLikeName]) и в нём нет ссылки ([hasSecretReference]);
/// - `exec.secrets[*].secret` хранит имя секрета: значение, не
///   проходящее `SecretNames.problem`, — литерал (правило `inlineSecretKeys`
///   к этому полю не применяется, иначе любой правильный элемент был бы
///   отклонён);
/// - прочий лист с именем из `inlineSecretKeys` (`api_key`, `token`, …;
///   имя нормализуется, `Token` и `API_KEY` — те же) — по правилу CFG-9,
///   п. 1, независимо от значения;
/// - строка в секретном листе непрозрачного поддерева реестра
///   (`providers.*.auth`, `tools.web`, …) без ссылки.
///
/// «Изменённый» лист — тот, чьё значение по тому же пути (элемент списка
/// с `name` — по имени, иначе по номеру) в [before] другое или отсутствует:
/// ручная правка с литералом до 8.11 загружается и не должна блокировать
/// несвязанные записи (граница D5, R1-1).
///
/// Элементы `args` сравниваются по номеру (у строк нет `name`): вставка перед
/// прежним литералом сдвигает его и даёт отказ — допустимо по D5.
///
/// Как использовать: пустой результат — запись допустима. Проблема
/// называет путь ключа и подсказку `codelab secret set <name>`; значения в
/// тексте нет (CFG-2). [source] — путь файла для текста проблемы.
List<ConfigIssue> literalSecretIssues({
  required Map<String, Object?> before,
  required Map<String, Object?> after,
  required String source,
}) {
  final known = <String, Object?>{};
  _walkLeaves(before, KeyPath.root, const [], (leaf) {
    known[leaf.path] = leaf.value;
  });
  final issues = <ConfigIssue>[];
  _walkLeaves(after, KeyPath.root, const [], (leaf) {
    if (known.containsKey(leaf.path) && known[leaf.path] == leaf.value) {
      return;
    }
    final message = _literalMessage(leaf);
    if (message != null) {
      issues.add(
        ConfigIssue(
          kind: ConfigIssueKind.inlineSecret,
          key: leaf.path,
          source: source,
          message: message,
        ),
      );
    }
  });
  return issues;
}

/// Лист дерева: путь ключа ([KeyPath]), «форма» пути (имена ключей, элемент
/// списка — `[]`) и значение.
typedef _Leaf = ({String path, List<String> shape, Object? value});

void _walkLeaves(
  Object? node,
  KeyPath path,
  List<String> shape,
  void Function(_Leaf leaf) visit,
) {
  switch (node) {
    case final Map<String, Object?> map:
      for (final MapEntry(:key, :value) in map.entries) {
        _walkLeaves(value, path.child(key), [...shape, key], visit);
      }
    case final List<Object?> list:
      // Имя элемента — путь, пока оно уникально; у одноимённых элементов
      // путь по номеру, иначе дубль повторял бы путь прежнего сервера и
      // прятал литерал за «неизменённым» значением.
      final names = <Object?>[
        for (final item in list)
          item is Map<String, Object?> ? item['name'] : null,
      ];
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        final name = names[i];
        final unique =
            name is String &&
            name.isNotEmpty &&
            names.where((other) => other == name).length == 1;
        _walkLeaves(item, path.at(unique ? name : i), [...shape, '[]'], visit);
      }
    default:
      visit((path: path.value, shape: shape, value: node));
  }
}

bool _isEmptyValue(Object? value) =>
    value == null || (value is String && value.isEmpty);

/// Текст проблемы листа либо `null`, если лист допустим.
String? _literalMessage(_Leaf leaf) {
  final value = leaf.value;
  if (_isEmptyValue(value)) {
    return null;
  }
  final shape = leaf.shape;
  // Имя листа — ближайший именованный сегмент: у строки списка
  // (`keys: [...]`) последний сегмент `[]`.
  final name = shape.lastWhere((s) => s != '[]', orElse: () => '');
  final suggested = SecretNames.suggestFor(leaf.path);
  const reference =
      'then use \${secret:NAME} (or reference an environment variable with '
      '\${VAR})';

  // exec.secrets[*].secret: имя секрета, а не значение.
  if (shape.length == 4 &&
      shape[0] == 'exec' &&
      shape[1] == 'secrets' &&
      shape[2] == '[]' &&
      name == 'secret') {
    if (value is String && SecretNames.problem(value) == null) {
      return null;
    }
    return 'not a valid secret name; store the secret with `codelab secret '
        'set <name>` and write its name here';
  }

  final inHeaders =
      (shape.length == 4 && shape[0] == 'providers' && shape[2] == 'headers') ||
      (shape.length == 5 &&
          shape[0] == 'mcp' &&
          shape[1] == 'servers' &&
          shape[2] == '[]' &&
          shape[3] == 'headers');
  final inEnv =
      (shape.length == 5 &&
          shape[0] == 'mcp' &&
          shape[1] == 'servers' &&
          shape[2] == '[]' &&
          shape[3] == 'env') ||
      (shape.length == 3 && shape[0] == 'exec' && shape[1] == 'env');
  // Элемент `mcp.servers[*].args` (R4-6, OQ3): токен, поданный аргументом
  // командной строки. Имя флага не смотрим (`--token <значение>` — два
  // элемента), только значение по шаблону §12.4; значение с `${…}` режется
  // по ссылкам в `literalSecretTag`. Подсказка ведёт в `--env`: сервер
  // получит переменную окружения со ссылкой на хранилище (R8-5). Загрузка
  // `args` не проверяет: некоторые серверы принимают токен только так.
  final inArgs =
      shape.length == 5 &&
      shape[0] == 'mcp' &&
      shape[1] == 'servers' &&
      shape[2] == '[]' &&
      shape[3] == 'args' &&
      shape[4] == '[]';
  if (inArgs) {
    if (value is String && literalSecretTag(value) != null) {
      return 'a literal secret in an argument; store it with `codelab secret '
          'set $suggested` and pass it with '
          "--env <NAME>='\${secret:$suggested}'";
    }
    return null;
  }

  if (inHeaders || inEnv) {
    // R1-1: литеральная часть значения по шаблону — отказ независимо от
    // имени (`X-Team: Bearer ghp_…`, `GREETING=ghp_…`). Значение режется по
    // `${…}`, поэтому ссылка не маскирует литерал рядом с ней.
    if (value is String && literalSecretTag(value) != null) {
      return 'a literal secret in a ${inHeaders ? 'header' : 'variable'}; '
          'run: codelab secret set $suggested, '
          '${reference.replaceAll('NAME', suggested)}';
    }
    // Нестроковое значение (число, булево) под секретным именем — тоже
    // литерал: ссылку `${…}` оно содержать не может.
    // Строка — по подстроке имени; число и булево — только если имя в
    // самом деле секретное (`X-Api-Key`), а не счётчик (`X-Max-Tokens`).
    final secretName = value is String
        ? isSecretLikeName(name)
        : _isSecretScalarName(name);
    if (secretName && (value is! String || !hasSecretReference(value))) {
      return 'a literal value in a secret ${inHeaders ? 'header' : 'variable'}; '
          'run: codelab secret set $suggested, ${reference.replaceAll('NAME', suggested)}';
    }
    return null;
  }

  final normalized = _normalize(name);
  if (_inlineSecretNames.contains(normalized)) {
    return 'secrets are not stored in the config; run: codelab secret set '
        '$suggested, ${reference.replaceAll('NAME', suggested)}';
  }
  // Непрозрачное поддерево (`providers.*.auth`, `tools.web`, разделы после
  // MVP): схемы листьев нет, поэтому секретное имя листа с литералом
  // отклоняется целиком. Поля, хранящие ссылку (`api_key_env`,
  // `api_key_secret`), допустимы, только если значение — имя переменной или
  // секрета, а не сам ключ.
  // Число и булево под секретным именем — тоже литерал (как в `headers`).
  if (value is! String &&
      value is! Map &&
      value is! List &&
      _isOpaque(leaf.path) &&
      _isSecretScalarName(name)) {
    return 'a literal value in a secret field; run: codelab secret set '
        '$suggested, ${reference.replaceAll('NAME', suggested)}';
  }
  if (value is String && _isOpaque(leaf.path)) {
    if (_referenceFields.contains(normalized)) {
      final valid = normalized == 'apikeyenv'
          ? _envName.hasMatch(value)
          : SecretNames.problem(value) == null;
      return valid
          ? null
          : 'a literal value in a secret field; use the name of a variable '
                'or of a secret stored with `codelab secret set`';
    }
    if (isSecretLikeName(name) && !hasSecretReference(value)) {
      return 'a literal value in a secret field; run: codelab secret set '
          '$suggested, ${reference.replaceAll('NAME', suggested)}';
    }
  }
  return null;
}

/// `inlineSecretKeys` после нормализации имени: `api_key`, `apiKey` и
/// `API-KEY` дают `apikey`.
final _inlineSecretNames = {for (final k in inlineSecretKeys) _normalize(k)};

/// Ключи схемы, значением которых служит имя переменной или секрета.
const _referenceFields = {'apikeyenv', 'apikeysecret'};

final _envName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

String _normalize(String name) =>
    name.toLowerCase().replaceAll(RegExp('[-_]'), '');

/// Лист лежит в поддереве, которое реестр описывает целиком отображением
/// (`map`/`mapList`), а не листьями.
bool _isOpaque(String path) {
  final type = SettingsRegistry.lookup(path)?.type;
  return type == SettingType.map || type == SettingType.mapList;
}

/// Секретное ли имя для нестрокового значения (число, булево) — то же
/// правило, что у писателя, для маскирования вывода (`cli/config_output.dart`,
/// design.md change `add-config-writer-and-reload`, D6, R0-2): запись и
/// вывод не расходятся в том, что считать секретным числом.
bool isSecretScalarName(String name) => _isSecretScalarName(name);

/// Секретное ли имя для нестрокового значения (число, булево).
///
/// Подстрока `token`/`key` дала бы ложные срабатывания на счётчиках
/// (`max_tokens`, `X-Max-Tokens`), поэтому смотрится последнее слово имени
/// (по `-`, `_`, пробелу и границе camelCase) и имя целиком для
/// множественного числа (`keys`, `tokens`).
bool _isSecretScalarName(String name) {
  final words = name
      .split(RegExp(r'[-_\s]+|(?<=[a-z0-9])(?=[A-Z])'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.toLowerCase())
      .toList();
  if (words.isEmpty) {
    return false;
  }
  final normalized = _normalize(name);
  return _scalarSecretWords.contains(words.last) ||
      _scalarSecretWords.contains(normalized) ||
      _pluralSecretNames.contains(normalized);
}

const _scalarSecretWords = {
  'token',
  'key',
  'apikey',
  'auth',
  'cookie',
  'secret',
  'password',
  'privatetoken',
  'accesstoken',
};

const _pluralSecretNames = {'keys', 'tokens', 'secrets', 'passwords'};
