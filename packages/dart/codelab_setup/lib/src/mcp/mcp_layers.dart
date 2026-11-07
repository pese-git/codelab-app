/// Серверы `mcp.servers` по слоям снимка (design.md change
/// `add-provider-setup-ui`, D11 «Сверка с кодом»). Внутренний файл моста: из
/// основного бареля не экспортируется.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigLayer, SecretNames;

import '../config/agent_config_store.dart';
import '../config/config_source_view.dart';
import '../config/config_values.dart';

/// Сервер эффективного конфига: элемент слоя-источника как в файле.
///
/// [projectElement] задан у «disabled here» (Q21): [element] — переопределение
/// `{name, enabled: false}` слоя `projectLocal`, а [projectElement] — проектное
/// определение под ним.
final class EffectiveMcpServer {
  const EffectiveMcpServer({
    required this.name,
    required this.layer,
    required this.element,
    this.projectElement,
  });

  final String name;
  final ConfigLayer layer;
  final Map<String, Object?> element;
  final Map<String, Object?>? projectElement;

  /// Строка отключена переопределением «Disable here».
  bool get disabledHere => projectElement != null;
}

/// Элементы `mcp.servers` читаемого слоя [layer], если загрузчик их применил:
/// слой 3 или 4 недоверенного проекта отбрасывается целиком (CFG-3).
List<Map<String, Object?>> layerMcpServers(
  AgentConfigSnapshot snapshot,
  ConfigLayer layer,
) {
  final values = snapshot.layers[layer]?.values;
  if (values == null ||
      isIgnoredByTrust(snapshot.loaded, layer, 'mcp.servers')) {
    return const [];
  }
  final servers = (values['mcp'] is Map<Object?, Object?>)
      ? (values['mcp'] as Map<Object?, Object?>)['servers']
      : null;
  if (servers is! List<Object?>) {
    return const [];
  }
  return [
    for (final item in servers)
      if (item is Map<Object?, Object?> && item['name'] is String)
        {for (final e in item.entries) '${e.key}': e.value},
  ];
}

/// Переопределение «Disable here»: ровно `name` и `enabled: false`.
bool isDisableHereOverride(Map<String, Object?> element) =>
    element['enabled'] == false &&
    element.keys.every((k) => k == 'name' || k == 'enabled');

/// Серверы эффективного конфига в порядке слияния слоёв (`merge.dart` ядра,
/// `_mergeServers`): порядок первого появления, сервер с тем же `name` в слое
/// выше заменяется на месте целиком.
///
/// Почему повторяет слияние ядра, а не берёт `loaded.values['mcp.servers']`:
/// строке нужен слой-источник каждого элемента (редактируемость, запись в
/// нужный файл), а итоговый список его не хранит. Расхождения порядка ловит
/// тест на снимке настоящего `FileAgentConfigStore` (`mcp_server_entry_view_test`,
/// «порядок слияния»): он сверяет порядок с итогом загрузчика.
List<EffectiveMcpServer> effectiveMcpServers(AgentConfigSnapshot snapshot) {
  final out = <EffectiveMcpServer>[];
  for (final layer in configLayersByPriority) {
    for (final element in layerMcpServers(snapshot, layer)) {
      final name = element['name']! as String;
      final index = out.indexWhere((s) => s.name == name);
      EffectiveMcpServer next;
      if (index >= 0 &&
          layer == ConfigLayer.projectLocal &&
          out[index].layer == ConfigLayer.project &&
          isDisableHereOverride(element)) {
        next = EffectiveMcpServer(
          name: name,
          layer: layer,
          element: element,
          projectElement: out[index].element,
        );
      } else {
        next = EffectiveMcpServer(name: name, layer: layer, element: element);
      }
      if (index >= 0) {
        out[index] = next;
      } else {
        out.add(next);
      }
    }
  }
  return out;
}

/// Эффективный сервер [name] или `null`.
EffectiveMcpServer? effectiveMcpServer(
  AgentConfigSnapshot snapshot,
  String name,
) {
  for (final server in effectiveMcpServers(snapshot)) {
    if (server.name == name) {
      return server;
    }
  }
  return null;
}

/// Источник строки: файл слоя.
ConfigSourceView sourceOfLayer(
  AgentConfigSnapshot snapshot,
  ConfigLayer layer,
) => ConfigSourceView(
  kind: switch (layer) {
    ConfigLayer.user => ConfigSourceKind.user,
    ConfigLayer.project => ConfigSourceKind.project,
    ConfigLayer.projectLocal => ConfigSourceKind.projectLocal,
  },
  label: snapshot.layers[layer]?.path ?? '',
);

/// Пространство секретов, которое создаёт страница для сервера [name]:
/// `codelab/mcp/<имя в нижнем регистре>/` (`SecretNames.forMcp`).
///
/// Почему из `forMcp`, а не свой префикс: нормализация имени (регистр,
/// недопустимые символы) одна на запись и удаление; у `GitHub` и `github`
/// пространство общее.
String mcpSecretNamespace(String name) {
  final sample = SecretNames.forMcp(name, 'x');
  return sample.substring(0, sample.length - 1);
}
