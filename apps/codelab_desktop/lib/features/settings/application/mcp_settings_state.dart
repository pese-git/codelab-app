import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:codelab_setup/codelab_setup.dart';

/// Состояние страницы «MCP servers» (design.md change
/// `add-provider-setup-ui`, D11, D12, D21; spec app-settings «Страница «MCP
/// servers»», «Панель «Agent status» страницы MCP servers»).
///
/// Почему закрытая иерархия, а не флаги: страница либо загружается, либо
/// только читает (WebSocket и сторонний агент, SETUP-2), либо не может
/// прочитать `config.yaml`, либо готова к правкам; невозможные сочетания
/// («только чтение» со строками серверов) не представимы (AGENTS.md §8).
///
/// Для чего: чистые значения для отображения. Значений секретов, `env`,
/// `headers` и текстов исключений здесь нет — только то, что видит
/// пользователь (SETUP-1).
sealed class McpSettingsState {
  const McpSettingsState();
}

/// Доступ к настройкам ещё определяется или конфиг читается.
final class McpSettingsLoading extends McpSettingsState {
  const McpSettingsLoading();
}

/// Любое состояние после первой загрузки. Панель «Agent status» есть у всех:
/// в `ReadOnly` она единственное содержимое, в `Unreadable` от локального
/// конфига не зависит (D12).
sealed class McpSettingsLoaded extends McpSettingsState {
  const McpSettingsLoaded({required this.agentStatus});

  final McpAgentStatus agentStatus;

  /// Копия с новым состоянием панели.
  McpSettingsLoaded withAgentStatus(McpAgentStatus status);
}

/// Агент не наш или удалённый: настройки не читаются и не пишутся (SETUP-2).
final class McpSettingsReadOnly extends McpSettingsLoaded {
  const McpSettingsReadOnly({
    required this.notice,
    this.hint,
    required super.agentStatus,
  });

  /// Заголовок InfoBar `mcp-read-only`.
  final String notice;

  /// Команды для хоста агента; у стороннего агента `null`.
  final String? hint;

  @override
  McpSettingsReadOnly withAgentStatus(McpAgentStatus status) =>
      McpSettingsReadOnly(notice: notice, hint: hint, agentStatus: status);

  @override
  String toString() => 'McpSettingsReadOnly($notice)';
}

/// Файл не разбирается или нарушает схему: запись недоступна, файл не
/// перезаписывается (целостность данных, AGENTS.md §2; решение Q26).
final class McpSettingsUnreadable extends McpSettingsLoaded {
  const McpSettingsUnreadable({
    required this.problems,
    required super.agentStatus,
  });

  /// Проблемы загрузчика с путём ключа, по строке на проблему.
  final List<String> problems;

  @override
  McpSettingsUnreadable withAgentStatus(McpAgentStatus status) =>
      McpSettingsUnreadable(problems: problems, agentStatus: status);

  @override
  String toString() => 'McpSettingsUnreadable(${problems.length})';
}

/// Вид баннера итога записи и удаления (`mcp-banner`).
enum McpBannerKind { saved, conflict, error }

/// Баннер итога: первая строка — итог, остальные — подробности (оставшиеся
/// секреты, предупреждения записи).
final class McpBanner {
  const McpBanner(this.kind, this.lines);

  final McpBannerKind kind;
  final List<String> lines;

  @override
  String toString() => 'McpBanner(${kind.name}, ${lines.length} lines)';
}

/// Содержимое InfoBar `mcp-rejected`: агент отклоняет конфиг (решение Q26).
final class McpRejectedConfig {
  const McpRejectedConfig({
    required this.title,
    required this.problems,
    this.editServer,
  });

  /// `Saved, but the agent rejected the new config` после своей записи,
  /// `The agent rejects the current config` при открытии страницы.
  final String title;

  /// Строки `<путь ключа>: <проблема>`; значений в них нет.
  final List<String> problems;

  /// Сервер, на которого указывает путь проблемы (`Edit <server>`).
  final String? editServer;

  @override
  String toString() => 'McpRejectedConfig(${problems.length} problems)';
}

/// Вопрос «Replace it»: секреты с этими именами уже есть (SETUP-5).
final class McpReplaceQuestion {
  const McpReplaceQuestion({required this.server, required this.names});

  /// Правимый сервер; `null` — карточка `New server`.
  final String? server;
  final List<String> names;

  @override
  String toString() => 'McpReplaceQuestion(${names.length})';
}

/// Проблемы черновика до записи (имя, адрес, пустые значения).
final class McpDraftIssues {
  const McpDraftIssues({required this.server, required this.problems});

  /// Правимый сервер; `null` — карточка `New server`.
  final String? server;
  final List<McpDraftProblem> problems;

  @override
  String toString() => 'McpDraftIssues(${problems.length})';
}

/// Хранилище секретов для флажка «Secret» (D3).
final class McpSecretStorage {
  const McpSecretStorage({
    required this.backendId,
    required this.writable,
    this.unavailableReason,
  });

  final String backendId;
  final bool writable;
  final String? unavailableReason;
}

/// Строка списка серверов.
final class McpServerRow {
  const McpServerRow({
    required this.name,
    required this.entry,
    required this.sourceLabel,
    required this.layer,
    required this.enabled,
    required this.canToggle,
    required this.canEdit,
    required this.canRemove,
    required this.canDisableHere,
    required this.canEnableHere,
    this.note,
    this.draft,
  });

  final String name;

  /// Вид из моста: тип, цель, значения `args`/`env`/`headers` уже очищены.
  final McpServerEntryView entry;

  /// `user`, `this project` или `defined in <file>`.
  final String sourceLabel;

  /// Слой сервера: показывает неизменяемая цель «Save to» (Q27).
  final ConfigLayer layer;
  final bool enabled;

  /// Слои `user` и `projectLocal`; у слоя 3 и «disabled here» нет.
  final bool canToggle;
  final bool canEdit;
  final bool canRemove;

  /// «Disable here» сервера слоя 3 (при известной папке проекта).
  final bool canDisableHere;
  final bool canEnableHere;

  /// Готовый черновик правки из СЫРОГО элемента слоя; `null` — править
  /// нельзя (слой 3, «disabled here»). Строится при загрузке, а не в
  /// `build()` (AGENTS.md §15).
  final McpServerDraft? draft;

  /// Пояснение строки слоя 3 и `disabled here` вместо редактора (Q25 (5)).
  final String? note;

  @override
  String toString() => 'McpServerRow($name)';
}

/// Страница готова: серверы, баннеры, карточка нового сервера.
final class McpSettingsReady extends McpSettingsLoaded {
  const McpSettingsReady({
    required this.rows,
    required this.secretStorage,
    required this.canSaveToProject,
    this.banner,
    this.rejected,
    this.newServerOpen = false,
    this.replaceQuestion,
    this.draftIssues,
    this.saving = false,
    required super.agentStatus,
  });

  final List<McpServerRow> rows;
  final McpSecretStorage secretStorage;

  /// Цель «This project only» доступна: известна папка проекта (D5).
  final bool canSaveToProject;
  final McpBanner? banner;
  final McpRejectedConfig? rejected;
  final bool newServerOpen;
  final McpReplaceQuestion? replaceQuestion;
  final McpDraftIssues? draftIssues;

  /// Идёт запись: повторные действия блокируются (D21).
  final bool saving;

  @override
  McpSettingsReady withAgentStatus(McpAgentStatus status) => McpSettingsReady(
    rows: rows,
    secretStorage: secretStorage,
    canSaveToProject: canSaveToProject,
    banner: banner,
    rejected: rejected,
    newServerOpen: newServerOpen,
    replaceQuestion: replaceQuestion,
    draftIssues: draftIssues,
    saving: saving,
    agentStatus: status,
  );

  @override
  String toString() => 'McpSettingsReady(${rows.length} rows, saving: $saving)';
}

/// План удаления для диалога `Remove <server>?` (Q25 (3)).
final class McpRemovalPlan {
  const McpRemovalPlan({required this.server, required this.secrets});

  final String server;

  /// Секреты страницы, которые будут удалены, если ими никто не пользуется.
  final List<String> secrets;
}

/// Панель «Agent status» (D12).
sealed class McpAgentStatus {
  const McpAgentStatus();
}

/// Нет открытой сессии, соединения, порта или команды `/mcp`.
final class McpAgentStatusUnavailable extends McpAgentStatus {
  const McpAgentStatusUnavailable();

  @override
  String toString() => 'McpAgentStatusUnavailable';
}

/// Строка таблицы встроенного агента.
final class McpStatusRow {
  const McpStatusRow({
    required this.name,
    required this.state,
    required this.stateLabel,
    required this.tools,
    required this.lastError,
    required this.canReconnect,
  });

  final String name;
  final McpServerState state;

  /// `connected`, `failed · retry in 24 s`, `disabled`…
  final String stateLabel;

  /// Число инструментов; у `disabled` — `—`.
  final String tools;

  /// Причина последней ошибки или `—`.
  final String lastError;

  /// У выключенного сервера «Reconnect» нет.
  final bool canReconnect;
}

/// Живая таблица встроенного агента.
final class McpAgentStatusLive extends McpAgentStatus {
  const McpAgentStatusLive({required this.rows, required this.updatedAt});

  final List<McpStatusRow> rows;

  /// Время последнего события (`Live from the embedded agent · hh:mm`).
  final DateTime updatedAt;

  @override
  String toString() => 'McpAgentStatusLive(${rows.length} rows)';
}

/// Ответ `/mcp …` агента вне процесса как есть, без разбора (SETUP-11).
final class McpAgentStatusText extends McpAgentStatus {
  const McpAgentStatusText({
    this.text,
    this.sending = false,
    required this.canSend,
    this.notice,
  });

  /// Текст последнего ответа; `null` — ещё не запрашивали.
  final String? text;

  /// Команда отправлена, ответ не пришёл.
  final bool sending;

  /// Кнопки активны: `Connected`, свободная сессия, пустая очередь.
  final bool canSend;

  /// `/mcp list did not complete. Try Refresh again.` над прежним текстом.
  final String? notice;

  // Текст ответа может быть любым: в строку состояния он не попадает.
  @override
  String toString() =>
      'McpAgentStatusText(sending: $sending, canSend: $canSend)';
}
