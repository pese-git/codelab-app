import 'package:collection/collection.dart';

import '../mcp/mcp_server_config.dart';
import 'core_config.dart';
import 'key_path.dart';
import 'secret_name_rule.dart';
import 'settings_registry.dart';

/// План применения перезагрузки: что применить сейчас, что отложить до
/// перезапуска, и значения применённого снимка (design.md change
/// `add-config-writer-and-reload`, D8, шаги 4–5).
///
/// Почему отдельная чистая функция: решение «применить или отложить» — это
/// граница безопасности (R0-1, R0-4: ослабление прав и отправка секрета на
/// другой адрес не действуют на лету), и его нужно проверять без рантайма,
/// сессий и часов. Рантайм только вызывает [planConfigReload] и применяет
/// результат одной атомарной заменой.
///
/// Для чего: ключи diff (листья `ConfigLoadResult.values`) делятся на
/// применяемые ([changedKeys]) и отложенные ([restartRequiredKeys]);
/// [appliedValues] — карта нового снимка, где отложенные листья возвращены к
/// прежним значениям (или удалены, если их не было). План покрывает оба
/// снимка `CoreConfig` — полный и [CoreConfig.withoutProject] (R0-1): сессия
/// вне корня проекта читает второй, и правка слоя, скрытая в полном снимке
/// проектным слоем, видна только в нём.
final class ConfigReloadPlan {
  ConfigReloadPlan({
    required List<String> changedKeys,
    required List<String> restartRequiredKeys,
    required Map<String, Object?> appliedValues,
    Map<String, Object?>? appliedWithoutProjectValues,
    this.deferred = const DeferredConfigParts(),
  }) : changedKeys = List.unmodifiable(changedKeys),
       restartRequiredKeys = List.unmodifiable(restartRequiredKeys),
       appliedValues = Map.unmodifiable(appliedValues),
       appliedWithoutProjectValues = appliedWithoutProjectValues == null
           ? null
           : Map.unmodifiable(appliedWithoutProjectValues);

  /// Применяемые листья, отсортированные.
  final List<String> changedKeys;

  /// Отложенные ключи показа (лист; `mcp.servers[<имя>]`; `providers.<id>`),
  /// отсортированные.
  final List<String> restartRequiredKeys;

  /// `values` нового снимка с прежними значениями отложенных листьев.
  final Map<String, Object?> appliedValues;

  /// То же для снимка без проектных слоёв; `null` — у снимков его нет.
  final Map<String, Object?>? appliedWithoutProjectValues;

  /// Отложенные части `CoreConfig` в структурированном виде: имена серверов
  /// и идентификаторы провайдеров берутся из самих снимков, а не из разбора
  /// ключей показа (имя с `[`, `]`, `"` не разбирается обратно, R0-1).
  /// Объединение по обоим снимкам: подстановка одним набором в оба.
  final DeferredConfigParts deferred;

  /// Ничего не изменилось: ни применяемых, ни отложенных ключей.
  bool get isEmpty => changedKeys.isEmpty && restartRequiredKeys.isEmpty;
}

/// Поля провайдера, по которым секрет может уйти на другой адрес (R0-4):
/// группа адреса и аутентификации, атомарная при отложенной правке. Поля
/// `preset`, `auth`, `key_rotation` войдут сюда с потребителем (D8,
/// «Обязанность будущих change»).
const _providerGroup = {
  'kind',
  'base_url',
  'headers',
  'auth_header',
  'api_key_secret',
  'api_key_env',
};

/// Ключи-ссылки на модели: откладываются вместе с отложенным новым
/// провайдером (D8, R0-4). Без потребителя пока: `agent.fallback`,
/// `agent.summary_model`, `llm.roles.*`.
bool _isModelRefKey(String key) =>
    key == 'agent.default_model' ||
    key == 'agent.fallback' ||
    key == 'agent.summary_model' ||
    key.startsWith('llm.roles.');

/// Строит [ConfigReloadPlan] для перехода от применённого снимка к новому.
///
/// Параметры: [previousValues] и [previous] — применённые `values` и
/// `CoreConfig`; [nextValues] и [next] — результат новой загрузки. Значения
/// снимка без проекта берутся из `CoreConfig.withoutProjectValues` (R0-1);
/// если снимок без проекта есть только у одной стороны, другая сторона
/// сравнивается своим полным снимком.
///
/// Правила (D8, шаг 4–5) применяются к каждому снимку отдельно, а результат —
/// объединение (отложено в любом снимке — отложено в обоих), от частного к
/// общему:
/// 1. Провайдер «с ключом» (в прежних или новых `values` есть `api_key_*`,
///    подстановка `${…}` в `base_url`, `headers`, `auth_header` или
///    литеральный секретный заголовок по правилу имён) откладывается целиком
///    по группе полей, если он новый или поле группы изменилось; ключ показа
///    — `providers.<id>`. Модели существующего провайдера применяются.
/// 2. Ссылка на модели нового отложенного провайдера откладывается с ним.
/// 3. Сервер `mcp.servers[<имя>]` откладывается, если нет прежнего с
///    `sameConnection` (включение `false → true` при тех же параметрах тоже
///    откладывается) и он `stdio` (R0-1) либо `http` с подстановкой `${…}` в
///    `url`, `headers`, `env` (R0-4) — независимо от `enabled` (R6-1: у
///    выключенного сервера правка команды тоже ждёт перезапуска, иначе
///    `/mcp enable` запустил бы непроверенную команду). Удаление, выключение
///    `true → false` и правка без смены соединения при том же `enabled`
///    применяются. Выключение вместе с правкой соединения: выключение
///    применяется, правка ждёт — в снимке и в `values` прежний элемент с
///    `enabled: false`, ключ в `restartRequiredKeys` (R6-1).
/// 4. Остальное: дескриптор реестра с `restartRequired` — отложен; ключ без
///    дескриптора — отложен (fail closed: расхождение схемы и реестра не
///    должно превращаться в живое применение).
ConfigReloadPlan planConfigReload({
  required Map<String, Object?> previousValues,
  required CoreConfig previous,
  required Map<String, Object?> nextValues,
  required CoreConfig next,
}) {
  final snapshots = [_planSnapshot(previousValues, previous, nextValues, next)];
  final hasBare =
      previous.withoutProject != null || next.withoutProject != null;
  if (hasBare) {
    // R0-1: слои ниже проектных могут быть скрыты в полном снимке проектным
    // слоем, а сессия вне корня читает снимок без проекта.
    snapshots.add(
      _planSnapshot(
        previous.withoutProject == null
            ? previousValues
            : previous.withoutProjectValues ?? const {},
        previous.withoutProject ?? previous,
        next.withoutProject == null
            ? nextValues
            : next.withoutProjectValues ?? const {},
        next.withoutProject ?? next,
      ),
    );
  }

  // Выключение вместе с правкой соединения (R6-1) действует в том снимке,
  // чей план его дал: объединять по снимкам его нельзя.
  final unionDeferred = snapshots
      .map((plan) => plan.deferred)
      .reduce((a, b) => a.union(b));
  final deferred = DeferredConfigParts(
    providers: unionDeferred.providers,
    servers: unionDeferred.servers,
    disabledServers: snapshots.first.deferred.disabledServers,
    disabledServersWithoutProject: snapshots.last.deferred.disabledServers,
    permissions: unionDeferred.permissions,
    defaultModel: unionDeferred.defaultModel,
  );
  final restart = <String>{for (final plan in snapshots) ...plan.restart};
  final reverted = <String>{};
  final changed = <String>{};
  final applied = <Map<String, Object?>>[];
  for (final plan in snapshots) {
    changed.addAll(plan.diff);
    reverted.addAll(plan.reverted);
    // Отложенная часть из другого снимка действует и здесь: подстановка в
    // `CoreConfig` идёт одним набором, значения должны ей соответствовать.
    for (final key in plan.diff) {
      if (plan.reverted.contains(key)) {
        continue;
      }
      if (_coveredDisplay(deferred, key, plan.previousProviders)
          case final display?) {
        reverted.add(key);
        restart.add(display);
      }
    }
  }
  for (final plan in snapshots) {
    final values = {...plan.nextValues};
    for (final key in reverted) {
      if (plan.previousValues.containsKey(key)) {
        final before = plan.previousValues[key];
        values[key] = plan.disabledKeys.contains(key) && before is Map
            ? {...before, 'enabled': false}
            : before;
      } else {
        values.remove(key);
      }
    }
    applied.add(values);
  }
  return ConfigReloadPlan(
    changedKeys: [
      for (final key in changed)
        if (!reverted.contains(key)) key,
    ]..sort(),
    restartRequiredKeys: restart.toList()..sort(),
    appliedValues: applied.first,
    appliedWithoutProjectValues: hasBare ? applied.last : null,
    deferred: deferred,
  );
}

/// Результат правил D8 для одного снимка.
final class _SnapshotPlan {
  _SnapshotPlan({
    required this.previousValues,
    required this.nextValues,
    required this.previousProviders,
    required this.diff,
    required this.restart,
    required this.reverted,
    required this.disabledKeys,
    required this.deferred,
  });

  final Map<String, Object?> previousValues;
  final Map<String, Object?> nextValues;
  final Set<String> previousProviders;
  final List<String> diff;
  final Set<String> restart;
  final Set<String> reverted;

  /// Подмножество [reverted]: элемент остаётся прежним, но с `enabled: false`.
  final Set<String> disabledKeys;
  final DeferredConfigParts deferred;
}

_SnapshotPlan _planSnapshot(
  Map<String, Object?> previousValues,
  CoreConfig previous,
  Map<String, Object?> nextValues,
  CoreConfig next,
) {
  const equality = DeepCollectionEquality();
  final diff =
      <String>{...previousValues.keys, ...nextValues.keys}
          .where(
            (key) =>
                previousValues.containsKey(key) !=
                    nextValues.containsKey(key) ||
                !equality.equals(previousValues[key], nextValues[key]),
          )
          .toList()
        ..sort();
  final diffSet = diff.toSet();

  final restart = <String>{};
  // Листья, значения которых возвращаются к прежним.
  final reverted = <String>{};
  // Структурированные отложенные части: имена берутся из снимков, а не из
  // разбора ключей (имя с `[`, `]`, `"` не разбирается, R0-1).
  final deferredProviders = <String>{};
  final deferredServers = <String>{};
  final disabledServers = <String>{};
  final disabledKeys = <String>{};
  var deferredPermissions = false;
  var deferredModel = false;

  final previousProviders = {for (final p in previous.providers) p.config.name};
  final nextProviders = {for (final p in next.providers) p.config.name};
  final previousServers = {for (final s in previous.mcpServers) s.name: s};
  final nextServers = {for (final s in next.mcpServers) s.name: s};

  // 1. Провайдеры.
  final newDeferredProviders = <String>{};
  for (final id in {...previousProviders, ...nextProviders}) {
    if (!nextProviders.contains(id)) {
      continue; // удаление применяется
    }
    if (!diff.any((key) => _isUnderProvider(key, id))) {
      continue;
    }
    final isNew = !previousProviders.contains(id);
    final groupChanged =
        isNew || diff.any((key) => _providerGroupKey(key, id) != null);
    if (!groupChanged) {
      continue;
    }
    final withKey =
        (!isNew && _providerWithKey(previousValues, id)) ||
        _providerWithKey(nextValues, id);
    if (!withKey) {
      continue;
    }
    restart.add(KeyPath('providers').child(id).value);
    deferredProviders.add(id);
    if (isNew) {
      newDeferredProviders.add(id);
    }
    for (final key in diff) {
      final inGroup = _providerGroupKey(key, id) != null;
      if (inGroup || (isNew && _isUnderProvider(key, id))) {
        reverted.add(key);
      }
    }
  }

  // 2. Ссылки на модели нового отложенного провайдера.
  if (newDeferredProviders.isNotEmpty) {
    for (final key in diff) {
      if (!_isModelRefKey(key)) {
        continue;
      }
      final value = nextValues[key];
      final refs = switch (value) {
        final String text => [text],
        final List<Object?> list => list.whereType<String>().toList(),
        _ => const <String>[],
      };
      if (refs.any(
        (ref) => newDeferredProviders.any((id) => ref.startsWith('$id/')),
      )) {
        restart.add(key);
        reverted.add(key);
        deferredModel = deferredModel || key == 'agent.default_model';
      }
    }
  }

  // 3. Серверы MCP. Ключ строится из имени сервера снимка, а не наоборот:
  // `x]y`, `a[b]` обратно в имя не разбираются, и сервер остался бы в
  // снимке (fail-open, R0-1).
  for (final MapEntry(key: name, value: fresh) in nextServers.entries) {
    final key = KeyPath('mcp.servers').at(name).value;
    if (!diffSet.contains(key)) {
      continue;
    }
    // R6-1: правка параметров соединения откладывается и у выключенного
    // сервера — `/mcp enable` подключит сервер с параметрами применённого
    // снимка, и непроверенная команда не должна попасть в него живой
    // перезагрузкой. Применяются: правка без смены соединения при том же
    // `enabled` (например, `call_timeout`) и выключение `true → false`.
    final old = previousServers[name];
    if (old != null && old.sameConnection(fresh)) {
      if (old.enabled == fresh.enabled || !fresh.enabled) {
        continue;
      }
    }
    final defer = switch (fresh) {
      McpStdioServerConfig() => true,
      McpHttpServerConfig() => _serverHasSubstitution(nextValues[key]),
    };
    if (defer) {
      restart.add(key);
      reverted.add(key);
      deferredServers.add(name);
      // Выключение вместе с правкой соединения: выключение применяется, а
      // правка ждёт перезапуска — остаётся прежний элемент с `enabled: false`.
      if (old != null && old.enabled && !fresh.enabled) {
        disabledServers.add(name);
        disabledKeys.add(key);
      }
    }
  }

  // 4. Реестр настроек. Ключи `mcp.servers[…]` целиком решены правилом 3.
  for (final key in diff) {
    if (reverted.contains(key) || key.startsWith('mcp.servers[')) {
      continue;
    }
    final descriptor = SettingsRegistry.lookup(key);
    // Пустой узел раздела (`permissions: {}`) значения не несёт: без
    // дескриптора он не повод для перезапуска (fail closed — для значений).
    final carriesValue =
        _isValue(previousValues[key]) || _isValue(nextValues[key]);
    if (descriptor == null ? carriesValue : descriptor.restartRequired) {
      restart.add(key);
      reverted.add(key);
      if (key == 'permissions' || key.startsWith('permissions.')) {
        deferredPermissions = true;
      }
      if (key == 'agent.default_model') {
        deferredModel = true;
      }
    }
  }

  return _SnapshotPlan(
    previousValues: previousValues,
    nextValues: nextValues,
    previousProviders: previousProviders,
    diff: diff,
    restart: restart,
    reverted: reverted,
    disabledKeys: disabledKeys,
    deferred: DeferredConfigParts(
      providers: deferredProviders,
      servers: deferredServers,
      disabledServers: disabledServers,
      permissions: deferredPermissions,
      defaultModel: deferredModel,
    ),
  );
}

/// Ключ показа, если [key] закрыт отложенной частью [deferred] другого
/// снимка (его значение должно остаться прежним); иначе `null`.
String? _coveredDisplay(
  DeferredConfigParts deferred,
  String key,
  Set<String> previousProviders,
) {
  if (deferred.permissions &&
      (key == 'permissions' || key.startsWith('permissions.'))) {
    return key;
  }
  if (deferred.defaultModel && key == 'agent.default_model') {
    return key;
  }
  for (final id in deferred.providers) {
    if (_providerGroupKey(key, id) != null ||
        (!previousProviders.contains(id) && _isUnderProvider(key, id))) {
      return KeyPath('providers').child(id).value;
    }
  }
  if (key.startsWith('mcp.servers[')) {
    for (final name in deferred.servers) {
      if (key == KeyPath('mcp.servers').at(name).value) {
        return key;
      }
    }
  }
  return null;
}

bool _isValue(Object? node) =>
    node != null && !(node is Map<String, Object?> && node.isEmpty);

/// Лежит ли [key] в поддереве провайдера [id]. Префикс строится [KeyPath], а
/// не разбором ключа: идентификатор со скобками или кавычками обратно не
/// разбирается (R0-1).
bool _isUnderProvider(String key, String id) {
  final prefix = KeyPath('providers').child(id).value;
  return key == prefix || key.startsWith('$prefix.');
}

/// Поле группы адреса и аутентификации провайдера [id], если [key] лежит
/// в ней; иначе `null`.
String? _providerGroupKey(String key, String id) {
  final prefix = '${KeyPath('providers').child(id).value}.';
  if (!key.startsWith(prefix)) {
    return null;
  }
  final rest = key.substring(prefix.length);
  for (final field in _providerGroup) {
    if (rest == field || rest.startsWith('$field.')) {
      return field;
    }
  }
  return null;
}

/// Провайдер «с ключом» по значениям файла (D8, R0-4): ссылка определяется
/// по значению, а не по имени. `${VAR}` в `base_url` тоже делает провайдера
/// «с ключом»: значение переменной может нести токен в query или userinfo.
bool _providerWithKey(Map<String, Object?> values, String id) {
  final prefix = KeyPath('providers').child(id).value;
  if (values['$prefix.api_key_secret'] != null ||
      values['$prefix.api_key_env'] != null) {
    return true;
  }
  for (final field in const ['base_url', 'auth_header']) {
    if (_hasSubstitution(values['$prefix.$field'])) {
      return true;
    }
  }
  // Имя заголовка берётся из ключа по префиксу, а не через `splitKeyPath`:
  // точка в имени (`X.Api.Key`) не квотируется и делила бы его на сегменты.
  final headers = '$prefix.headers.';
  for (final MapEntry(:key, :value) in values.entries) {
    if (!key.startsWith(headers) || value is! String) {
      continue;
    }
    var name = key.substring(headers.length);
    if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
      name = name.substring(1, name.length - 1);
    }
    // Подстановка в значении или литерал в секретно названном заголовке
    // (правило имён D5, после ручной правки).
    if (hasSecretReference(value) || isSecretLikeName(name)) {
      return true;
    }
  }
  return false;
}

/// Есть ли подстановка `${…}` (`${secret:…}` или `${VAR}`) в скаляре или в
/// любом значении вложенного отображения и списка.
bool _hasSubstitution(Object? node) => switch (node) {
  final String text => hasSecretReference(text),
  final Map<String, Object?> map => map.values.any(_hasSubstitution),
  final List<Object?> list => list.any(_hasSubstitution),
  _ => false,
};

/// Подстановка в полях подключения сервера: `url`, `headers`, `env` (R0-4).
bool _serverHasSubstitution(Object? element) =>
    element is Map<String, Object?> &&
    [element['url'], element['headers'], element['env']].any(_hasSubstitution);
