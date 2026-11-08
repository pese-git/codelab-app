/// Удаление MCP-сервера и «Enable here» (`dart-agent-and-clients` §12.4.6;
/// design.md change `add-provider-setup-ui`, D11, решения Q21, Q22; SETUP-24).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigLayer, RemoveMcpServer;

import '../config/agent_config_store.dart';
import '../provider/provider_keys.dart';
import '../provider/provider_remover.dart' show SecretCleanup;
import 'mcp_layers.dart';
import 'mcp_secret_cleanup.dart';
import 'mcp_server_committer.dart';

/// Итог [McpServerRemover.remove].
sealed class McpServerRemovalOutcome {
  const McpServerRemovalOutcome();
}

/// Сервер удалён; [secrets] — судьба секретов, на которые он ссылался
/// (имя → итог), пусто, если ссылок не было.
final class McpServerRemoved extends McpServerRemovalOutcome {
  const McpServerRemoved({required this.saved, required this.secrets});

  final ConfigSaved saved;
  final Map<String, SecretCleanup> secrets;

  @override
  String toString() => 'McpServerRemoved(${secrets.length} secrets)';
}

/// Запись не состоялась: [outcome] — конфликт или отказ валидатора; `null` —
/// исключение `apply`, [errorType] — имя его типа. Секреты не тронуты
/// (SETUP-24), автоповтора нет (SETUP-6).
final class McpServerRemovalNotSaved extends McpServerRemovalOutcome {
  const McpServerRemovalNotSaved({
    required this.outcome,
    required this.errorType,
  });

  final ConfigSaveOutcome? outcome;
  final String? errorType;

  @override
  String toString() => 'McpServerRemovalNotSaved(${outcome ?? errorType})';
}

/// Удаление отклонено до записи: файл и хранилище не тронуты.
final class McpServerRemovalRefused extends McpServerRemovalOutcome {
  const McpServerRemovalRefused(this.reason);

  final McpServerRefusal reason;

  @override
  String toString() => 'McpServerRemovalRefused(${reason.name})';
}

/// Порядок удаления сервера: одна запись `RemoveMcpServer`, затем секреты.
///
/// Почему отдельный класс: порядок общий для app и CLI и важен для
/// целостности данных. Секрет удаляется только после `ConfigSaved` и только
/// если по СВЕЖЕМУ снимку на него не осталось ссылок (SETUP-24, правило
/// `ProviderRemover`): отказ записи не должен оставить сервер без секрета.
///
/// Для чего: кандидаты на удаление — секреты, на которые ссылался удалённый
/// элемент через `${secret:…}` в `env` и `headers` (Q22), и удаляются из них
/// только секреты пространства `codelab/mcp/<name>/` (их создала страница) и
/// только без оставшихся ссылок. Любое другое имя (`${secret:shared}`)
/// остаётся — исход `SecretCleanup.kept`. Пространство общее у `GitHub` и
/// `github` (`SecretNames.forMcp` приводит имя к нижнему регистру), поэтому
/// удаление по префиксу без проверки ссылок небезопасно. Порт секретов —
/// `ProviderKeys`, второго нет.
///
/// Как использовать: `remove(snapshot, name:)`; «Enable here» — `enableHere`.
final class McpServerRemover {
  McpServerRemover({
    required AgentConfigStore config,
    required ProviderKeys keys,
  }) : _config = config,
       _keys = keys;

  final AgentConfigStore _config;
  final ProviderKeys _keys;

  /// Удаляет сервер [name] из слоя, где он определён. Сервер слоя 3 и
  /// «disabled here» удалить нельзя (`notEditable`).
  Future<McpServerRemovalOutcome> remove(
    AgentConfigSnapshot snapshot, {
    required String name,
  }) async {
    final server = effectiveMcpServer(snapshot, name);
    if (server == null) {
      return const McpServerRemovalRefused(McpServerRefusal.unknownServer);
    }
    if (server.layer == ConfigLayer.project || server.disabledHere) {
      return const McpServerRemovalRefused(McpServerRefusal.notEditable);
    }
    final base = snapshot.layers[server.layer];
    if (base == null) {
      return const McpServerRemovalRefused(McpServerRefusal.layerUnreadable);
    }
    // Все ссылки элемента: чужие попадают в итог как `kept`, поэтому список
    // шире публичных кандидатов, но фильтр общий (`secretCandidatesOf`).
    final candidates = referencedSecrets(server.element);

    final ConfigSaveOutcome outcome;
    try {
      outcome = await _config.apply(base, [RemoveMcpServer(name)]);
    } on Object catch (error) {
      return McpServerRemovalNotSaved(
        outcome: null,
        errorType: error.runtimeType.toString(),
      );
    }
    if (outcome is! ConfigSaved) {
      return McpServerRemovalNotSaved(outcome: outcome, errorType: null);
    }
    if (candidates.isEmpty) {
      return McpServerRemoved(saved: outcome, secrets: const {});
    }
    // Между снимком и записью другой процесс мог добавить ссылку: конфиг
    // читается заново (SETUP-24). Чужое имя (`${secret:shared}`) создал не
    // мастер страницы: оно принадлежит пользователю и не удаляется (решение
    // пользователя, ревью 5a; Q22) — итог `kept`.
    final owned = inPageNamespace(name, candidates);
    final cleaned = await cleanUpSecrets(
      config: _config,
      keys: _keys,
      cwd: snapshot.cwd,
      candidates: owned,
    );
    final secrets = {
      for (final candidate in candidates)
        candidate: cleaned[candidate] ?? SecretCleanup.kept,
    };
    return McpServerRemoved(saved: outcome, secrets: secrets);
  }

  /// Секреты, которые удаление [name] попытается удалить: подтверждение в app
  /// показывает именно их (Q30, design.md D11).
  ///
  /// Почему здесь: правило одно на подтверждение и на [remove] — иначе список
  /// на экране разойдётся с тем, что будет удалено. Кандидат — секрет
  /// пространства `codelab/mcp/<name>/` из `${secret:…}` в `env` и `headers`
  /// элемента; ручные и чужие секреты не кандидаты (в [remove] это `kept`).
  /// Секрет, на который ссылается другой элемент, остаётся кандидатом: итог
  /// `stillReferenced` [remove] определяет по свежему снимку после записи.
  ///
  /// Как использовать: чистая функция по снимку, хранилища не трогает.
  /// Неизвестный сервер, сервер слоя 3 и «disabled here» дают пустой список
  /// (как отказы [remove]: `unknownServer`, `notEditable`).
  static List<String> secretCandidatesOf(
    AgentConfigSnapshot snapshot,
    String name,
  ) {
    final server = effectiveMcpServer(snapshot, name);
    if (server == null ||
        server.layer == ConfigLayer.project ||
        server.disabledHere) {
      return const [];
    }
    return inPageNamespace(name, referencedSecrets(server.element));
  }

  /// «Enable here» (Q21): убирает переопределение `{name, enabled: false}`
  /// из `projectLocal`; проектное определение снова действует.
  Future<McpServerWriteOutcome> enableHere(
    AgentConfigSnapshot snapshot, {
    required String name,
  }) async {
    final server = effectiveMcpServer(snapshot, name);
    if (server == null) {
      return const McpServerRefused(McpServerRefusal.unknownServer);
    }
    final base = snapshot.layers[ConfigLayer.projectLocal];
    if (!server.disabledHere || base == null) {
      return const McpServerRefused(McpServerRefusal.notDisabledHere);
    }
    try {
      final outcome = await _config.apply(base, [RemoveMcpServer(name)]);
      return outcome is ConfigSaved
          ? McpServerWritten(outcome)
          : McpServerNotWritten(outcome: outcome, errorType: null);
    } on Object catch (error) {
      return McpServerNotWritten(
        outcome: null,
        errorType: error.runtimeType.toString(),
      );
    }
  }
}
