/// Поиск ссылок на секрет в снимке конфига (design.md change
/// `add-provider-setup-ui`, D9, D10, D11; SETUP-24).
library;

import 'agent_config_store.dart';
import 'config_values.dart';

/// Есть ли в снимке ссылка на секрет [name]: значение, равное имени
/// (`api_key_secret`), или подстановка `${secret:<name>}` в любой строке.
///
/// Почему по всем строкам и слоям, включая недоверенный проект: пропустить
/// ссылку значит удалить секрет, который кто-то использует; лишняя ссылка
/// стоит только неудалённого секрета (SETUP-24, fail-safe). Экранированный
/// литерал тоже считается ссылкой по той же причине.
///
/// Для чего: единое правило «секрет удаляется только если на него не осталось
/// ссылок» для `ProviderRemover` и `McpServerRemover`; две копии разошлись бы.
///
/// Как использовать: [exceptPrefix] — префикс плоского ключа, который не
/// считается (ключи удаляемого провайдера, `providers.<id>.`).
bool snapshotReferencesSecret(
  AgentConfigSnapshot snapshot,
  String name, {
  String? exceptPrefix,
}) {
  final marker = '\${secret:$name}';
  bool inValue(Object? value) => switch (value) {
    String() => value == name || value.contains(marker),
    List<Object?>() => value.any(inValue),
    Map<Object?, Object?>() => value.values.any(inValue),
    _ => false,
  };
  bool inLeaves(Map<String, Object?> leaves) => leaves.entries.any(
    (e) =>
        (exceptPrefix == null || !e.key.startsWith(exceptPrefix)) &&
        inValue(e.value),
  );
  return inLeaves(snapshot.leaves) ||
      snapshot.layers.values.any(
        (layer) => inLeaves(flattenConfigValues(layer.values)),
      );
}
