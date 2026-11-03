import 'key_path.dart';

/// Плоская карта листьев итогового дерева конфигурации (`ConfigLoadResult.
/// values`; design.md change `add-config-writer-and-reload`, D8).
///
/// Почему отдельная функция: перезагрузка сравнивает снимки по ключам, а
/// `CoreConfig` и `HostSettings` общего вида листьев не имеют. Карта строится
/// один раз при сборке снимка и совпадает по путям с `SettingsRegistry`,
/// `ConfigSnapshot` и `ConfigEdit`.
///
/// Правила: отображение раскрывается до листьев, ключ собирается [KeyPath]
/// (сегмент с символами вне `A-Za-z0-9_./-` — в кавычках); список — один лист
/// (`permissions.deny`), чтобы изменение элемента давало один ключ, а не
/// индекс; исключение — `mcp.servers`: каждый элемент лежит целиком под
/// `mcp.servers[<имя>]`, и только у серверов из [servers] — тех, что попали в
/// `CoreConfig.mcpServers`. Выключенный сервер (`enabled: false`) теперь тоже
/// там (D10 change `add-config-writer-and-reload`), а элемент, который нечем
/// запустить (`{name, enabled: false}` без `type`), — нет.
/// Пустое отображение — один лист-маркер `{}` (появление и исчезновение пустого
/// узла, например модели без параметров, — изменение). Значения копируются: карта не должна
/// меняться вместе со слоями хоста.
///
/// Как использовать: `_Builder` вызывает один раз после слияния слоёв.
Map<String, Object?> flattenConfigValues(
  Map<String, Object?> tree,
  Set<String> servers,
) {
  final out = <String, Object?>{};

  void visit(KeyPath path, Object? node) {
    switch (node) {
      case final Map<String, Object?> map when map.isEmpty:
        // Пустой узел (`providers.a.models.m3: {}` — модель без параметров) —
        // лист-маркер `{}`: без него появление и исчезновение узла diff не
        // видел бы, хотя каталог моделей меняется.
        if (!path.isRoot) {
          out[path.value] = <String, Object?>{};
        }
      case final Map<String, Object?> map:
        for (final MapEntry(:key, :value) in map.entries) {
          visit(path.child(key), value);
        }
      case final List<Object?> list when path.value == 'mcp.servers':
        for (final item in list) {
          if (item is Map<String, Object?> &&
              item['name'] is String &&
              servers.contains(item['name'])) {
            out[path.at(item['name']! as String).value] = _copy(item);
          }
        }
      default:
        out[path.value] = _copy(node);
    }
  }

  for (final MapEntry(:key, :value) in tree.entries) {
    visit(KeyPath.root.child(key), value);
  }
  return out;
}

Object? _copy(Object? node) => switch (node) {
  final Map<String, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) key: _copy(value),
  },
  final List<Object?> list => [for (final item in list) _copy(item)],
  _ => node,
};
