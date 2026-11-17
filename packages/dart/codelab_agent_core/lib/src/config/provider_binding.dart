/// Привязка ключа проектного провайдера и ссылок HTTP-сервера MCP к адресу
/// (приоритет 1; design.md change `require-project-folder`, D23, Q14, Q16, Q17;
/// change `bind-mcp-secrets-to-origin`, D3; spec agent-secrets «Ключ проектного
/// провайдера привязан к адресу», «Ссылки MCP-сервера проектного слоя
/// привязаны к адресу»).
///
/// Угроза: `config.yaml` проекта лежит в репозитории, и его пишет не
/// пользователь. Провайдер из него мог бы сослаться на секрет процесса
/// (`api_key_secret`, `${secret:…}`), на переменную с ключом
/// (`api_key_env`, `${ENV}`) или на литеральный `api_key` глобального слоя и
/// указать свой `base_url`: ключ пользователя ушёл бы на чужой адрес. Доверие
/// к проекту (`trusted_projects`) разрешает его правила и серверы, но не
/// «отдаёт ему ключи».
///
/// Два шага, оба чистые и без чтения секретов:
/// 1. [applyProviderGroupRule] — «группа адреса и аутентификации» провайдера
///    берётся целиком из одного слоя (правило 2);
/// 2. [ProviderKeyBinding] — ссылка на ключ из проектного слоя разрешается
///    только в `config.local.yaml` или при привязке к тому же origin глобальными
///    слоями (правило 3).
library;

import 'config_tree.dart';
import 'interpolate.dart';
import 'merge.dart';

/// Поля группы «адрес и аутентификация» провайдера, кроме `kind` (D23,
/// правило 2). `headers` берётся целиком: заголовки нижнего слоя к адресу
/// проекта не наследуются.
const providerGroupKeys = [
  'base_url',
  'headers',
  'api_key',
  'api_key_env',
  'api_key_secret',
  'auth_header',
];

bool _isProjectLayer(ConfigTree layer) =>
    layer.kind == ConfigLayerKind.project ||
    layer.kind == ConfigLayerKind.projectLocal;

/// Запись `providers.<id>` слоя или `null`.
Map<String, Object?>? providerEntry(ConfigTree layer, String id) {
  final providers = layer.values['providers'];
  if (providers is! Map<String, Object?>) {
    return null;
  }
  final provider = providers[id];
  return provider is Map<String, Object?> ? provider : null;
}

bool _setsGroup(Map<String, Object?>? provider) =>
    provider != null &&
    (provider.containsKey('kind') ||
        providerGroupKeys.any(provider.containsKey));

/// Правило 2 D23 с уточнением Q21 (a): если поля группы провайдера задают
/// несколько слоёв и среди них есть проектный, верхний из них `T` задаёт
/// аутентификацию (`headers`, `api_key`, `api_key_env`, `api_key_secret`,
/// `auth_header`) один: чего `T` не задал, того нет. Поля адреса (`kind`,
/// `base_url`), которых `T` не задал, берутся из слияния НЕпроектных слоёв
/// ниже `T`; адрес проектного слоя ниже `T` не наследуется.
///
/// Почему отдельный шаг до слияния: слияние по ключам смешало бы `base_url`
/// проекта с `api_key_secret` пользователя — ровно ту пару, которой нельзя
/// встречаться. Обобщает правило `providers.cli` слоя флагов (`mergeLayers`).
/// Почему адрес всё же наследуется от пользователя: проект, переопределивший
/// только ключ или только `base_url` провайдера пользователя, иначе не
/// загружался бы (`kind`/`base_url` required). Ссылка на ключ при этом судится
/// правилом 3 по origin итогового адреса ([ProviderKeyBinding]).
///
/// Возвращает слои в том же порядке; изменённые слои — копии без вытесненных
/// полей, позиции сохранены.
List<ConfigTree> applyProviderGroupRule(List<ConfigTree> layers) {
  final ids = <String>{
    for (final layer in layers)
      if (layer.values['providers'] case final Map<String, Object?> map)
        ...map.keys,
  };
  // Слой (индекс) -> id -> поля, которые нужно убрать.
  final cuts = <int, Map<String, Set<String>>>{};
  for (final id in ids) {
    final setters = [
      for (var i = 0; i < layers.length; i++)
        if (_setsGroup(providerEntry(layers[i], id))) i,
    ];
    if (setters.length < 2 || !setters.any((i) => _isProjectLayer(layers[i]))) {
      continue;
    }
    final winner = setters.last;
    for (final i in setters) {
      if (i == winner) {
        continue;
      }
      final lower = providerEntry(layers[i], id)!;
      // Q21 (a): поля аутентификации нижних слоёв не наследуются никогда;
      // поля адреса (`kind`, `base_url`) — только из непроектных слоёв ниже
      // верхнего (иначе ключ из `config.local.yaml` ушёл бы на `base_url`
      // закоммиченного `config.yaml`, Q17 (a)).
      final fromProject = _isProjectLayer(layers[i]);
      cuts.putIfAbsent(i, () => {})[id] = {
        for (final key in providerGroupKeys)
          if (lower.containsKey(key) && (fromProject || key != 'base_url')) key,
        if (fromProject && lower.containsKey('kind')) 'kind',
      };
    }
  }
  if (cuts.isEmpty) {
    return layers;
  }
  return [
    for (var i = 0; i < layers.length; i++)
      if (cuts[i] case final cut?) _without(layers[i], cut) else layers[i],
  ];
}

ConfigTree _without(ConfigTree layer, Map<String, Set<String>> cut) {
  final values = {...layer.values};
  final providers = {...(values['providers']! as Map<String, Object?>)};
  for (final MapEntry(key: id, value: keys) in cut.entries) {
    final provider = {...(providers[id]! as Map<String, Object?>)};
    keys.forEach(provider.remove);
    providers[id] = provider;
  }
  values['providers'] = providers;
  return ConfigTree(
    kind: layer.kind,
    source: layer.source,
    values: values,
    positions: layer.positions,
  );
}

/// Вид ссылки на ключ в конфиге: секрет хранилища (`api_key_secret`,
/// `${secret:…}`) или переменная окружения (`api_key_env`, `${ENV}`).
///
/// Почему отдельный тип: привязка к адресу (D23) сравнивает «ту же ссылку» —
/// вид и имя, — а секрет `X` и переменная `X` разные ссылки.
///
/// Для чего: часть [ProviderReference]; мигратор `codelab_agent_io` по виду
/// строит текст отказа (`secret …` / `variable …`, D26, C5.6).
///
/// Как использовать: значения получают из [providerReferences] и
/// [referencesIn], сами не создают.
enum ProviderReferenceKind { secret, env }

/// Ссылка на ключ или переменную в поле провайдера.
///
/// Почему: правило 3 D23 решает судьбу не поля, а каждой ссылки внутри него
/// (`headers` и `api_key` могут нести несколько), поэтому ссылка — значение со
/// своим видом, именем и местом.
///
/// Для чего: единица, которую проверяет [ProviderKeyBinding.isBound]; её
/// читают загрузка конфига (`resolve.dart`) и мигратор секретов (D26, C5.6).
/// Название историческое: ссылки HTTP-сервера MCP ([mcpServerReferences])
/// того же типа (`bind-mcp-secrets-to-origin`, D3 — тип не переименован ради
/// публичного API).
///
/// Как использовать: список даёт [providerReferences] по записи
/// `providers.<id>` слоя или [mcpServerReferences] по элементу
/// `mcp.servers`. Имя ссылки может быть значением секрета, вписанным
/// вместо имени, — в логи и тексты его выводят только после проверки
/// `literalSecretTag`.
final class ProviderReference {
  const ProviderReference(this.kind, this.name, this.field);

  final ProviderReferenceKind kind;
  final String name;

  /// Путь поля внутри провайдера: `api_key_secret`, `headers.X-Key`.
  final String field;

  /// Идентификатор для сравнения «та же ссылка»: вид и имя.
  String get identity => '${kind.name}:$name';
}

final _envRef = RegExp(r'^\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
final _secretRef = RegExp(r'^\$\{secret:([^}]+)\}');

/// Ссылки `${NAME}` и `${secret:name}` в [raw]; `$${` — литерал.
///
/// Почему: правило привязки (D23) должно решить, раскрывать ли ссылку, до того
/// как значение переменной окажется в памяти. Разбор повторяет
/// `expandEnvironment` (`interpolate.dart`), но ничего не читает из окружения.
///
/// Для чего: основа [providerReferences]; мигратор секретов (D26, C5.6) зовёт
/// её для остатка строки заголовка без участков литералов, которые заменяет
/// сам.
///
/// Как использовать: передайте строку значения из слоя; результат — пары
/// «вид, имя» в порядке появления.
List<(ProviderReferenceKind, String)> referencesIn(String raw) {
  final out = <(ProviderReferenceKind, String)>[];
  var i = 0;
  while (i < raw.length) {
    if (raw.codeUnitAt(i) != 0x24) {
      i++;
      continue;
    }
    final rest = raw.substring(i);
    if (rest.startsWith(r'$${')) {
      i += 3;
    } else if (_secretRef.firstMatch(rest) case final match?) {
      out.add((ProviderReferenceKind.secret, match.group(1)!));
      i += match.group(0)!.length;
    } else if (_envRef.firstMatch(rest) case final match?) {
      out.add((ProviderReferenceKind.env, match.group(1)!));
      i += match.group(0)!.length;
    } else {
      i++;
    }
  }
  return out;
}

/// Все ссылки группы провайдера [provider] слоя (карта `providers.<id>`).
///
/// Почему: ссылки группы лежат в разных полях (`api_key_secret`,
/// `api_key_env`, `api_key`, `base_url`, значения `headers`), а правило D23
/// судит их одинаково.
///
/// Для чего: вход [ProviderKeyBinding] (условие (b), привязка глобальными
/// слоями) и проверки ссылок проекта в загрузке и в мигранторе (D26, C5.6).
///
/// Как использовать: [provider] — запись `providers.<id>` одного слоя.
/// `field` у `headers` — `headers.<имя>`. Значения не читаются, окружение не
/// раскрывается.
List<ProviderReference> providerReferences(Map<String, Object?> provider) {
  final out = <ProviderReference>[];
  void scan(String field, Object? value) {
    if (value is! String) {
      return;
    }
    for (final (kind, name) in referencesIn(value)) {
      out.add(ProviderReference(kind, name, field));
    }
  }

  if (provider['api_key_secret'] case final String name) {
    out.add(
      ProviderReference(ProviderReferenceKind.secret, name, 'api_key_secret'),
    );
  }
  if (provider['api_key_env'] case final String name) {
    out.add(ProviderReference(ProviderReferenceKind.env, name, 'api_key_env'));
  }
  scan('api_key', provider['api_key']);
  scan('base_url', provider['base_url']);
  if (provider['headers'] case final Map<String, Object?> headers) {
    for (final MapEntry(:key, :value) in headers.entries) {
      scan('headers.$key', value);
    }
  }
  return out;
}

/// Ссылки HTTP-сервера MCP [server] (элемент `mcp.servers`): `${secret:…}` и
/// `${ENV}` в значениях `headers.*` (`field` — `headers.<Name>`), `${ENV}` в
/// `url` (`field` — `url`). У stdio-сервера и элемента без `type: http`
/// список пуст.
///
/// Почему: правило привязки к адресу (D23) распространено на `mcp.servers`
/// проектных слоёв (change `bind-mcp-secrets-to-origin`, D1, D3; agent-secrets
/// «Ссылки MCP-сервера проектного слоя привязаны к адресу»). Stdio-серверы
/// не судятся: у них нет адреса, граница — доверие к проекту (D1, Q1 (a)).
/// `${secret:…}` в `url` здесь тоже возвращается (мигратор не должен
/// пропустить её молча), но загрузка её не судит: `_interpolate` отвергает
/// такую ссылку проблемой загрузки (секрет допустим только в `env` и
/// `headers`).
///
/// Для чего: единая реализация для загрузки (`_Builder._buildMcpServer`),
/// привязок глобальных серверов ([ProviderKeyBinding.fromLayers]) и мигратора
/// секретов `codelab_agent_io` (D7).
///
/// Как использовать: [server] — карта элемента одного слоя. Значения не
/// читаются, окружение не раскрывается.
List<ProviderReference> mcpServerReferences(Map<String, Object?> server) {
  if (server['type'] != 'http') {
    return const [];
  }
  final out = <ProviderReference>[];
  void scan(String field, Object? value) {
    if (value is! String) {
      return;
    }
    for (final (kind, name) in referencesIn(value)) {
      out.add(ProviderReference(kind, name, field));
    }
  }

  scan('url', server['url']);
  if (server['headers'] case final Map<String, Object?> headers) {
    for (final MapEntry(:key, :value) in headers.entries) {
      scan('headers.$key', value);
    }
  }
  return out;
}

/// Origin HTTP-сервера MCP [server] по его `url` (`${ENV}` раскрыт только для
/// сравнения); `null` — адрес не разобрался, не http(s) или переменная не
/// задана (D3: тогда ни одна ссылка не привязана по условию (b)).
///
/// Почему отдельно от [providerOrigin]: у сервера нет `base_url` по умолчанию
/// для вида, а `url` обязателен. Сравнение origin — то же ([originOf]).
///
/// Как использовать: [environment] — окружение процесса; значение переменной
/// наружу не уходит.
String? mcpServerOrigin(
  Map<String, Object?> server,
  Map<String, String> environment,
) {
  final raw = server['url'];
  if (raw is! String) {
    return null;
  }
  final expansion = expandEnvironment(raw, environment);
  return expansion.missing.isEmpty ? originOf(expansion.text) : null;
}

/// `base_url` по умолчанию для вида провайдера (как в `_Builder._provider`).
String? _defaultBase(String? kind) => switch (kind) {
  'anthropic' => 'https://api.anthropic.com',
  'gemini' => 'https://generativelanguage.googleapis.com',
  _ => null,
};

/// `scheme://host:port` адреса [url]; порт по умолчанию схемы подставляется,
/// хост без учёта регистра. `null` — адрес не разобрался или не http(s).
String? originOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    return null;
  }
  return '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';
}

/// Origin провайдера [provider] с учётом `${ENV}` в `base_url` и `base_url` по
/// умолчанию для вида [kind]; `null` — адрес неизвестен (переменная не задана).
///
/// Почему: ссылка привязана к origin (`scheme://host:port`), а не к тексту
/// URL (D23): порт по умолчанию и регистр хоста не должны менять вердикт.
///
/// Для чего: адрес для [ProviderKeyBinding.isBound] в загрузке и в
/// мигранторе (D26, C5.6).
///
/// Как использовать: [provider] — карта с `base_url` (итоговый адрес, если он
/// унаследован от другого слоя, подставляет вызывающий), [kind] — итоговый вид,
/// [environment] — окружение процесса. Значение переменной здесь только
/// сравнивается и наружу не уходит.
String? providerOrigin(
  Map<String, Object?> provider,
  String? kind,
  Map<String, String> environment,
) {
  final raw = switch (provider['base_url']) {
    final String text => text,
    _ => _defaultBase(kind),
  };
  if (raw == null) {
    return null;
  }
  final expansion = expandEnvironment(raw, environment);
  return expansion.missing.isEmpty ? originOf(expansion.text) : null;
}

/// Привязки ссылок глобальных слоёв к origin (D23, правило 3, условие (b)).
/// Тип обслуживает и провайдеров, и HTTP-серверы MCP; название историческое
/// и оставлено ради публичного API (`bind-mcp-secrets-to-origin`, D3).
///
/// Источники привязок: провайдеры (origin `base_url`) и HTTP-серверы MCP (origin `url`,
/// `bind-mcp-secrets-to-origin`, D3). Множество одно: ссылка — пара «вид,
/// имя», а утечка определяется адресом назначения.
///
/// Почему из деревьев слоёв, а не из собранного снимка: в снимке `${ENV}`
/// заголовков уже раскрыт, а привязка сравнивает ссылки «как написано».
///
/// Как использовать: два потребителя. `_Builder` (`resolve.dart`) создаёт
/// привязки один раз на загрузку по слоям до правила группы; мигратор
/// секретов `codelab_agent_io` (`secret_migrator.dart`, D26, C5.6) создаёт их
/// по слоям загрузки и не переносит в `config.local.yaml` ссылку, которую
/// [isBound] не подтверждает. Проектные слои фабрика сама отбрасывает;
/// [isBound] отвечает, связывают ли глобальные слои ссылку с адресом.
final class ProviderKeyBinding {
  ProviderKeyBinding._(this._bound);

  /// Строит привязки из слоёв, которые пишет не репозиторий: `user`,
  /// `appStorage`, `--config`, окружение, флаги.
  factory ProviderKeyBinding.fromLayers(
    List<ConfigTree> layers,
    Map<String, String> environment,
  ) {
    final global = mergeLayers([
      for (final layer in layers)
        if (!_isProjectLayer(layer)) layer,
    ]);
    final bound = <String>{};
    if (global['providers'] case final Map<String, Object?> providers) {
      for (final provider in providers.values) {
        if (provider is! Map<String, Object?>) {
          continue;
        }
        final kind = provider['kind'];
        final origin = providerOrigin(
          provider,
          kind is String ? kind : null,
          environment,
        );
        if (origin == null) {
          continue;
        }
        for (final ref in providerReferences(provider)) {
          bound.add('${ref.identity}@$origin');
        }
      }
    }
    // Глобальные HTTP-серверы MCP привязывают свои ссылки к origin `url`
    // (D3): ссылка — пара «вид, имя», а утечка определяется адресом
    // назначения, поэтому множество привязок общее с провайдерами. Stdio-
    // серверы адреса не имеют и привязок не дают ([mcpServerReferences]).
    if (global['mcp'] case {'servers': final List<Object?> servers}) {
      for (final server in servers) {
        if (server is! Map<String, Object?>) {
          continue;
        }
        final origin = mcpServerOrigin(server, environment);
        if (origin == null) {
          continue;
        }
        for (final ref in mcpServerReferences(server)) {
          bound.add('${ref.identity}@$origin');
        }
      }
    }
    return ProviderKeyBinding._(bound);
  }

  final Set<String> _bound;

  /// Связана ли [reference] с [origin] глобальными слоями.
  bool isBound(ProviderReference reference, String? origin) =>
      origin != null && _bound.contains('${reference.identity}@$origin');
}
