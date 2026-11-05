/// Плоские значения конфига и их сравнение (design.md change
/// `add-provider-setup-ui`, D6).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigLayer, ConfigSnapshot, KeyPath;

/// Раскладывает дерево слоя в карту «путь ключа → лист».
///
/// Почему: итог загрузки (`ConfigLoadResult.values`) хранит листья по путям
/// `KeyPath`, а снимок слоя — вложенное дерево; чтобы сравнить их и найти
/// источник ключа, дерево приводится к тому же виду. Отображения раскрываются
/// до листьев, список — один лист (как у ядра).
///
/// Как использовать: вызывают [AgentConfigSnapshot] и тесты; значения в
/// журнал и тексты не попадают.
Map<String, Object?> flattenConfigValues(Map<String, Object?> tree) {
  final out = <String, Object?>{};
  void walk(KeyPath path, Object? node) {
    if (node is Map<String, Object?> && node.isNotEmpty) {
      node.forEach((name, child) => walk(path.child(name), child));
    } else if (!path.isRoot) {
      out[path.value] = node;
    }
  }

  walk(KeyPath.root, tree);
  return out;
}

/// Слои в порядке возрастания приоритета (§15.2: 2, 3, 4).
const configLayersByPriority = [
  ConfigLayer.user,
  ConfigLayer.project,
  ConfigLayer.projectLocal,
];

/// Эффективные листья по файловым слоям: слияние снизу вверх.
///
/// Почему: при проблеме загрузки `ConfigLoadResult.values` пуст, а странице
/// настроек всё равно нужен список провайдеров, чтобы показать, что
/// исправлять. Берутся только читаемые слои из [layers].
///
/// [ignored] отбрасывает листья, которые загрузчик не применил: недоверенный
/// проект (CFG-3) не должен добавлять провайдеров в список.
Map<String, Object?> mergeLayerLeaves(
  Map<ConfigLayer, ConfigSnapshot> layers, {
  bool Function(ConfigLayer layer, String key)? ignored,
}) {
  final merged = <String, Object?>{};
  for (final layer in configLayersByPriority) {
    final snapshot = layers[layer];
    if (snapshot != null) {
      flattenConfigValues(snapshot.values).forEach((key, value) {
        if (ignored == null || !ignored(layer, key)) {
          merged[key] = value;
        }
      });
    }
  }
  return merged;
}

/// Равенство значений листьев: числа, строки, списки и отображения по
/// содержимому.
///
/// Почему своя функция: `collection` не входит в allowlist моста
/// (`setupAllowlist`), а листья конфига — только JSON-подобные значения.
bool sameConfigValue(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!sameConfigValue(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || !sameConfigValue(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
