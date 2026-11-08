/// Общее правило очистки секретов MCP-сервера (design.md change
/// `add-provider-setup-ui`, D11, Q22; SETUP-24). Внутренний файл моста: из
/// основного бареля не экспортируется.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigIssueKind, ConfigLayer, secretReferencesIn;

import '../config/agent_config_store.dart';
import '../config/secret_references.dart';
import '../provider/provider_keys.dart';
import '../provider/provider_remover.dart' show SecretCleanup, SecretDeletion;
import 'mcp_layers.dart';

/// Секреты, на которые элемент ссылается в `env` и `headers`, по порядку, без
/// повторов.
///
/// Почему одна функция: кандидатов ищут и удаление сервера, и правка
/// (`McpServerCommitter`); две копии правила разошлись бы (Q22).
List<String> referencedSecrets(Map<String, Object?> element) {
  final names = <String>[];
  for (final field in ['env', 'headers']) {
    final table = element[field];
    if (table is! Map<Object?, Object?>) {
      continue;
    }
    for (final value in table.values) {
      if (value is! String) {
        continue;
      }
      for (final name in secretReferencesIn(value)) {
        if (!names.contains(name)) {
          names.add(name);
        }
      }
    }
  }
  return names;
}

/// Секреты пространства страницы сервера [name] из [secrets].
List<String> inPageNamespace(String name, Iterable<String> secrets) {
  final namespace = mcpSecretNamespace(name);
  return [
    for (final secret in secrets)
      if (secret.startsWith(namespace)) secret,
  ];
}

/// Удаляет [candidates] после успешной записи конфига (SETUP-24): секрет
/// остаётся (`stillReferenced`), если по СВЕЖЕМУ снимку на него есть ссылки.
///
/// Без свежего снимка безопасность удаления не доказана — все `failed`, ключи
/// не трогаются. Исключения хранилища превращаются в `failed`.
Future<Map<String, SecretCleanup>> cleanUpSecrets({
  required AgentConfigStore config,
  required ProviderKeys keys,
  required String cwd,
  required List<String> candidates,
}) async {
  if (candidates.isEmpty) {
    return const {};
  }
  final AgentConfigSnapshot fresh;
  try {
    fresh = await config.snapshot(cwd: cwd);
  } on Object {
    return {for (final c in candidates) c: SecretCleanup.failed};
  }
  // Fail-safe (SETUP-24): ссылки нечитаемого слоя не видны, поэтому секрет
  // мог остаться нужным. Любой нечитаемый слой (user, project, projectLocal) или проблемы
  // синтаксиса/профиля YAML — ничего не удаляем.
  // `FileAgentConfigStore.snapshot` читает все три слоя (отсутствующий файл —
  // пустой слой), поэтому нехватка любого слоя означает «не прочитан».
  if (ConfigLayer.values.any((layer) => !fresh.isReadable(layer)) ||
      fresh.loaded.issues.any(
        (i) =>
            i.kind == ConfigIssueKind.syntax ||
            i.kind == ConfigIssueKind.profile,
      )) {
    return {for (final c in candidates) c: SecretCleanup.failed};
  }
  final result = <String, SecretCleanup>{};
  for (final candidate in candidates) {
    result[candidate] = snapshotReferencesSecret(fresh, candidate)
        ? SecretCleanup.stillReferenced
        : await _delete(keys, candidate);
  }
  return result;
}

Future<SecretCleanup> _delete(ProviderKeys keys, String name) async {
  try {
    return switch (await keys.delete(name)) {
      SecretDeletion.deleted => SecretCleanup.deleted,
      SecretDeletion.notSet => SecretCleanup.alreadyAbsent,
      SecretDeletion.failed => SecretCleanup.failed,
    };
  } on Object {
    return SecretCleanup.failed;
  }
}
