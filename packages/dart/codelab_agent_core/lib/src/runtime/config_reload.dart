import '../config/config_issue.dart';

/// Итог перезагрузки конфигурации (design.md change
/// `add-config-writer-and-reload`, D8, шаг «Итог»).
enum ConfigReloadOutcome {
  /// Снимок заменён (или отложенные ключи ждут перезапуска).
  applied,

  /// Файлы не дали ни одного изменённого ключа; снимок обновлён теми же
  /// значениями, кэш секретов сброшен, функция модели пересобрана.
  unchanged,

  /// Загрузка или повторная проверка не прошла; прежний снимок цел (CFG-15).
  failed,
}

/// Отчёт `AgentRuntime.reloadConfig()`.
///
/// Почему отчёт, а не булево: `/config reload` и `codelab config check`
/// показывают человеку и применённое, и отложенное, и причину отказа.
///
/// Как использовать: [changedKeys] — листовые пути, применённые сейчас
/// (серверы MCP — `mcp.servers[<имя>]`); [restartRequiredKeys] — отложенные до
/// перезапуска (ключи с `restartRequired`, ключи вне реестра, правки R0-1 и
/// R0-4; провайдер — `providers.<id>`). Оба списка отсортированы. [issues]
/// непусто только при [ConfigReloadOutcome.failed]; значений ключей в отчёте
/// нет (CFG-2).
final class ConfigApplyReport {
  ConfigApplyReport({
    required this.outcome,
    List<ConfigIssue> issues = const [],
    List<String> changedKeys = const [],
    List<String> restartRequiredKeys = const [],
  }) : issues = List.unmodifiable(issues),
       changedKeys = List.unmodifiable(changedKeys),
       restartRequiredKeys = List.unmodifiable(restartRequiredKeys);

  final ConfigReloadOutcome outcome;
  final List<ConfigIssue> issues;
  final List<String> changedKeys;
  final List<String> restartRequiredKeys;
}

/// Состояние конфигурации рантайма (`AgentRuntime.configStatus()`).
///
/// Для чего: `/config` и `codelab config` отвечают, когда конфиг загружен,
/// из каких источников, чем кончилась последняя неудачная перезагрузка и что
/// ждёт перезапуска. Объект неизменяемый и описывает момент вызова.
///
/// [loadedAt] — время применённого снимка (по часам хоста); [sources] —
/// источники его слоёв; [lastFailureAt] и [lastIssues] — последняя неудача
/// (`lastIssues` очищается успешной перезагрузкой, `lastFailureAt` остаётся
/// историей); [pendingRestartKeys] — ключи, которые по последней успешной
/// перезагрузке ещё отличаются от применённого снимка (отсортированы, без
/// повторов); ключ, возвращённый в файле к прежнему значению, из них уходит.
final class ConfigStatus {
  ConfigStatus({
    required this.loadedAt,
    required List<String> sources,
    required this.lastFailureAt,
    required List<ConfigIssue> lastIssues,
    required List<String> pendingRestartKeys,
  }) : sources = List.unmodifiable(sources),
       lastIssues = List.unmodifiable(lastIssues),
       pendingRestartKeys = List.unmodifiable(pendingRestartKeys);

  final DateTime loadedAt;
  final List<String> sources;
  final DateTime? lastFailureAt;
  final List<ConfigIssue> lastIssues;
  final List<String> pendingRestartKeys;
}
