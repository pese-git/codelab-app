import 'config_tree.dart';

/// Слияние слоёв по правилам §15.2 (design.md change
/// `add-agent-configuration`, D4).
///
/// Почему отдельная функция: слияние чистое и тестируется без проверки
/// схемы; тот же результат нужен правилам доверия (сравнение «только
/// ужесточение» идёт с итогом нижних слоёв) и сборке `CoreConfig`.
///
/// Правила:
/// * отображения сливаются рекурсивно;
/// * скаляры и списки заменяются целиком;
/// * слой `flags` заменяет `providers.cli` целиком: хост не может удалить
///   значения нижних слоёв, а `--provider` описывает провайдера полностью —
///   `headers` из файла не должны уходить на адрес из `--base-url`
///   (приоритет 1, D4);
/// * `mcp.servers` сливается по `name`: тот же `name` заменяет сервер, новый
///   добавляется в конец;
/// * `tools.disabled` слоёв 2–4 объединяется (ключ ещё не применяется, но
///   правило слияния — часть схемы).
Map<String, Object?> mergeLayers(Iterable<ConfigTree> layers) {
  var result = <String, Object?>{};
  for (final layer in layers) {
    result = _mergeMaps(result, layer.values, layer.kind, const []);
  }
  return result;
}

const _fileLayers = {
  ConfigLayerKind.user,
  ConfigLayerKind.project,
  ConfigLayerKind.projectLocal,
};

Map<String, Object?> _mergeMaps(
  Map<String, Object?> base,
  Map<String, Object?> over,
  ConfigLayerKind kind,
  List<String> path,
) {
  final out = {...base};
  for (final MapEntry(key: key, value: value) in over.entries) {
    if (value == null) {
      // Контейнер без листьев (`exec:`) ничего не меняет.
      continue;
    }
    final here = [...path, key];
    final old = out[key];
    if (kind == ConfigLayerKind.flags && here.join('.') == 'providers.cli') {
      out[key] = _clone(value);
    } else if (old is Map<String, Object?> && value is Map<String, Object?>) {
      out[key] = _mergeMaps(old, value, kind, here);
    } else if (here.join('.') == 'mcp.servers' && value is List) {
      out[key] = _mergeServers(old is List ? old : const [], value);
    } else if (here.join('.') == 'tools.disabled' &&
        old is List &&
        value is List &&
        _fileLayers.contains(kind)) {
      out[key] = [
        ...old,
        for (final item in value)
          if (!old.contains(item)) item,
      ];
    } else {
      out[key] = _clone(value);
    }
  }
  return out;
}

List<Object?> _mergeServers(List<Object?> base, List<Object?> over) {
  final out = [...base];
  for (final server in over) {
    final name = server is Map<String, Object?> ? server['name'] : null;
    final index = out.indexWhere(
      (s) => s is Map<String, Object?> && s['name'] == name,
    );
    if (index >= 0) {
      out[index] = _clone(server);
    } else {
      out.add(_clone(server));
    }
  }
  return out;
}

Object? _clone(Object? value) => switch (value) {
  final Map<String, Object?> map => {
    for (final MapEntry(:key, value: item) in map.entries) key: _clone(item),
  },
  final List<Object?> list => [for (final item in list) _clone(item)],
  _ => value,
};
