import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:codelab_setup/codelab_setup.dart'
    show McpDraftProblem, McpDraftProblemCode, McpServerRefusal, SecretCleanup;

import '../../../l10n/app_localizations.dart';
import '../application/mcp_messages.dart';

/// Подпись состояния MCP-сервера в таблице «Agent status»: `connected`,
/// `failed · retry in 24 s` (с [retryIn] в секундах), `disabled` (D5, D8).
///
/// Почему не в состоянии: подпись зависит от языка, а Cubit хранит
/// `McpServerState` и `retryIn` (D5, «Уточнение итерации 5»). «с» у секунд —
/// сокращение единицы без `plural` (D8).
String mcpServerStateText(
  AppLocalizations l10n,
  McpServerState state, {
  Duration? retryIn,
}) => switch (state) {
  McpServerState.connecting => l10n.mcpStateConnecting,
  McpServerState.connected => l10n.mcpStateConnected,
  McpServerState.disabled => l10n.mcpStateDisabled,
  McpServerState.failed =>
    retryIn == null
        ? l10n.mcpStateFailed
        : l10n.mcpStateFailedRetry('${retryIn.inSeconds}'),
};

/// Текст проблемы черновика MCP-сервера по её коду и аргументу (имя ключа);
/// при `code == null` — `message` как есть (проблема чужого источника).
///
/// Почему по коду: `message` моста остаётся английским для CLI, а app строит
/// текст на своём языке (spec client-agent-setup «Типизированные проблемы
/// черновика MCP-сервера», D6).
String mcpDraftProblemText(AppLocalizations l10n, McpDraftProblem problem) {
  final key = problem.argument ?? '';
  return switch (problem.code) {
    null => problem.message,
    McpDraftProblemCode.nameInvalid => l10n.mcpProblemNameInvalid,
    McpDraftProblemCode.renameNotAllowed => l10n.mcpProblemRenameNotAllowed,
    McpDraftProblemCode.nameTaken => l10n.mcpProblemNameTaken,
    McpDraftProblemCode.commandEmpty => l10n.mcpProblemCommandEmpty,
    McpDraftProblemCode.urlInvalid => l10n.mcpProblemUrlInvalid,
    McpDraftProblemCode.urlHasUserinfo => l10n.mcpProblemUrlHasUserinfo,
    McpDraftProblemCode.keyHasSpaces => l10n.mcpProblemKeyHasSpaces(key),
    McpDraftProblemCode.keyDuplicate => l10n.mcpProblemKeyDuplicate(key),
    McpDraftProblemCode.keyEmpty => l10n.mcpProblemKeyEmpty,
    McpDraftProblemCode.secretValueEmpty => l10n.mcpProblemSecretValueEmpty(
      key,
    ),
    McpDraftProblemCode.secretNameCollision =>
      l10n.mcpProblemSecretNameCollision(key),
  };
}

/// Секрет попадает в баннер, только если он оставлен или не удалён: удалённый
/// и отсутствующий секреты баннер не называет (Q25 (4)).
bool _hasNote(McpSecretNote note) =>
    note.cleanup == SecretCleanup.kept ||
    note.cleanup == SecretCleanup.stillReferenced ||
    note.cleanup == SecretCleanup.failed;

/// Строки баннера страницы «MCP servers» по сообщению: первая — итог, остальные
/// — подробности (секреты, предупреждения). Команда `codelab secret delete
/// <имя>` и тексты ядра агента и хранилища — без изменений (D6, D7).
List<String> mcpMessageLines(AppLocalizations l10n, McpMessage message) {
  String note(McpSecretNote n) => switch (n.cleanup) {
    SecretCleanup.kept => l10n.mcpSecretKept(n.name),
    SecretCleanup.stillReferenced => l10n.mcpSecretStillUsed(n.name),
    _ => l10n.mcpSecretDeleteFailed(n.name),
  };
  List<String> leftovers(
    List<String> notRolledBack, [
    List<String>? replaced,
  ]) => [
    for (final name in notRolledBack) l10n.mcpSecretDeleteFailed(name),
    for (final name in replaced ?? const <String>[])
      l10n.mcpSecretNotRestored(name),
  ];
  return switch (message) {
    McpServerSavedMessage(
      :final server,
      :final restartHint,
      :final warnings,
      :final secrets,
    ) =>
      [
        restartHint
            ? l10n.mcpBannerSavedRestart(server)
            : l10n.mcpBannerSaved(server),
        ...warnings,
        for (final n in secrets.where(_hasNote)) note(n),
      ],
    McpServerEnabledMessage(:final server) => [
      l10n.mcpBannerEnabledRestart(server),
    ],
    McpServerRemovedMessage(:final server, :final secrets) => [
      l10n.mcpBannerRemoved(server),
      for (final n in secrets.where(_hasNote)) note(n),
    ],
    McpSecretNotStoredMessage(:final reason, :final notRolledBack) => [
      l10n.mcpSecretNotStored(reason),
      ...leftovers(notRolledBack),
    ],
    McpRefusedMessage(:final reason) => [
      switch (reason) {
        McpServerRefusal.unknownServer ||
        McpServerRefusal.layerUnreadable ||
        McpServerRefusal.notDisabledHere => l10n.mcpRefusalChanged,
        McpServerRefusal.notEditable => l10n.mcpRefusalNotEditable,
        McpServerRefusal.notProject => l10n.mcpRefusalNotProject,
        McpServerRefusal.noProjectTarget => l10n.mcpRefusalNoProjectTarget,
      },
    ],
    McpWriteFailedMessage(
      :final failure,
      :final issues,
      :final key,
      :final notRolledBack,
      :final replacedSecrets,
    ) =>
      [
        switch (failure) {
          McpWriteFailure.settingsChanged => l10n.mcpFailSettingsChanged,
          McpWriteFailure.secretStoreUnreadable => l10n.mcpFailSecretStore,
          McpWriteFailure.changeNotSaved => l10n.mcpFailChange,
          McpWriteFailure.conflict => l10n.mcpFailConflict,
          McpWriteFailure.rejected => l10n.mcpFailRejected(issues ?? ''),
          McpWriteFailure.inlineSecret => l10n.configNotSavedInlineSecret(
            key ?? '',
          ),
          McpWriteFailure.configNotSaved => l10n.mcpFailConfig,
        },
        ...leftovers(notRolledBack, replacedSecrets),
      ],
  };
}
