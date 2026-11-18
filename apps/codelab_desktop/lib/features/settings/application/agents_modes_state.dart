import 'package:codelab_setup/codelab_setup.dart' show ConfigLayer;

/// Состояние страницы «Agents & modes» (design.md change
/// `add-settings-agents-modes`, D3, D4, D11; spec app-settings «Страница
/// «Agents & modes» только для чтения»).
///
/// Для чего: чистые значения для отображения; строит их `AgentsModesCubit`.
///
/// Почему закрытая иерархия, а не набор флагов: страница либо загружается,
/// либо только читает (WebSocket и сторонний агент, SETUP-2), либо не может
/// прочитать `config.yaml`, либо готова к правкам; невозможные сочетания
/// («только чтение» с радиогруппой режима) не представимы (AGENTS.md §8).
sealed class AgentsModesState {
  const AgentsModesState();
}

/// Доступ ещё определяется или конфиг читается.
final class AgentsModesLoading extends AgentsModesState {
  const AgentsModesLoading();
}

/// Агент не наш или удалённый: конфиг и определения не читаются (SETUP-2).
final class AgentsModesReadOnly extends AgentsModesState {
  const AgentsModesReadOnly({required this.notice});

  /// Текст InfoBar `agents-modes-read-only`: `Read-only: this agent runs on
  /// ORIGIN. Change its modes and agents on that host: codelab config set,
  /// .codelab/agents.` или `Agent settings are managed by AGENT.`
  final String notice;
}

/// `config.yaml` не разбирается или нарушает схему (в том числе
/// `permissions.mode: autopilot`): записи нет (`agents-modes-unreadable`).
final class AgentsModesUnreadable extends AgentsModesState {
  const AgentsModesUnreadable({required this.problems, this.banner});

  /// Проблемы загрузчика с путём ключа, по строке на проблему.
  final List<String> problems;

  /// Баннер записи, после которой перечитывание не удалось: `Saved to
  /// <цель>.` без утверждений о новых сессиях (design.md D16); `null` — записи
  /// не было.
  final AgentsModesBanner? banner;
}

/// Вид баннера результата записи (`agents-modes-banner`).
enum AgentsModesBannerKind { saved, warning, conflict, error }

/// Баннер результата записи.
final class AgentsModesBanner {
  const AgentsModesBanner(this.kind, this.text);

  final AgentsModesBannerKind kind;
  final String text;
}

/// Тон тега статуса строки определения.
enum AgentsStatusTone { success, warning, danger }

/// Строка таблицы `agents-definitions-table` в виде готовых ячеек.
final class AgentsDefinitionRow {
  const AgentsDefinitionRow({
    required this.name,
    required this.description,
    required this.source,
    required this.availableIn,
    required this.tools,
    required this.model,
    required this.status,
    required this.tone,
  });

  final String name;
  final String description;

  /// `built-in` или путь файла с `~` вместо домашнего каталога.
  final String source;

  /// `session`, `subagent`, `both`; прочерк у файла с ошибкой.
  final String availableIn;
  final String tools;
  final String model;

  /// Текст тега: `Available`, `Error · line 4`, `Overridden by <путь>` и т. д.
  final String status;
  final AgentsStatusTone tone;
}

/// Файл определения с ошибкой: InfoBar `agents-definitions-error-<index>`.
final class AgentsDefinitionError {
  const AgentsDefinitionError({
    required this.index,
    required this.path,
    required this.pathLabel,
    required this.message,
    this.line,
  });

  final int index;

  /// Полный путь: только для `openDefinitionFolder`, в журнал и текст не идёт.
  final String path;

  /// Путь с `~` вместо домашнего каталога: показывается пользователю.
  final String pathLabel;

  /// Номер строки, если известен.
  final int? line;

  /// Фиксированное сообщение кода диагностики, без значений и фрагментов файла.
  final String message;
}

/// Блок «Agent definitions» страницы (design.md change
/// `add-settings-agents-modes`, D7, D8, D11); `null` у `AgentsModesReady`,
/// пока загрузчика нет.
final class AgentsDefinitionsView {
  const AgentsDefinitionsView({
    required this.rows,
    this.errors = const [],
    this.untrustedProject = false,
    this.projectLabel,
    this.timedOut = false,
    this.failed = false,
    this.projectFolderAvailable = false,
    this.projectFolderExists = false,
    this.openFailure,
    this.userFolderLabel = '~/.codelab/agents',
  });

  final List<AgentsDefinitionRow> rows;
  final List<AgentsDefinitionError> errors;

  /// InfoBar `agents-definitions-untrusted`.
  final bool untrustedProject;

  /// Папка проекта с `~` для текста InfoBar `untrusted`.
  final String? projectLabel;

  /// InfoBar `agents-definitions-timeout`.
  final bool timedOut;

  /// Непредвиденное исключение: `Agent definitions could not be read.`
  final bool failed;

  /// Пункт «This project (.codelab/agents)» меню есть (доверенный проект).
  final bool projectFolderAvailable;

  /// Проектный каталог существует; иначе пункт неактивен с подсказкой.
  final bool projectFolderExists;

  /// Подпись того, что не открылось: InfoBar `agents-definitions-open-failed`
  /// (`Could not open <label>.`); `null` — сбоя нет.
  final String? openFailure;

  /// Подпись пользовательского каталога определений для меню «Open folder».
  final String userFolderLabel;
}

/// Страница готова к правкам; запись — флаг [saving] (D11).
final class AgentsModesReady extends AgentsModesState {
  const AgentsModesReady({
    required this.mode,
    required this.modeLabel,
    required this.modeSource,
    this.narrowedNotice,
    required this.effort,
    required this.effortSource,
    required this.target,
    required this.canTargetProject,
    this.saving = false,
    this.banner,
    this.definitions,
  });

  /// Итоговый основной id режима: `plan`, `ask`, `standard`, `accept-edits`,
  /// `bypass`.
  final String mode;

  /// Подпись итога: `<mode>` или `ask (edits and commands blocked by plan)`.
  final String modeLabel;

  /// Источник режима для `agents-modes-mode-source`: `default`, `user`,
  /// `project`, `local` и т. п.
  final String modeSource;

  /// Текст InfoBar `agents-modes-mode-narrowed`; `null` — сужения нет.
  final String? narrowedNotice;

  /// Итоговый effort: `low`, `medium`, `high`.
  final String effort;

  /// Источник effort: `default`, `user`, `project`, `local`.
  final String effortSource;

  /// Выбранная цель записи: `ConfigLayer.user` или `ConfigLayer.projectLocal`;
  /// одна на режим и effort (Q10 (а)).
  final ConfigLayer target;

  /// Есть ли цель «This project only» (известна папка проекта, D4).
  final bool canTargetProject;

  /// Запись идёт: повторные выборы игнорируются (D11).
  final bool saving;

  /// Баннер результата последней записи (`agents-modes-banner`); `null` — записи
  /// не было или баннер сброшен началом новой записи.
  final AgentsModesBanner? banner;

  /// Блок «Agent definitions»; `null` — определения не загружаются.
  final AgentsDefinitionsView? definitions;
}
