import 'package:codelab_setup/codelab_setup.dart' show ConfigLayer;

/// Состояние страницы «Agents & modes» (design.md change
/// `add-settings-agents-modes`, D3, D4, D11; spec app-settings «Страница
/// «Agents & modes» только для чтения»).
///
/// ЗАГЛУШКА итерации 1, задача 1.1: форма состояния нужна, чтобы компилировались
/// красные тесты; логику и документацию полей допишет задача 1.3.
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
  const AgentsModesUnreadable({required this.problems});

  /// Проблемы загрузчика с путём ключа, по строке на проблему.
  final List<String> problems;
}

/// Вид баннера результата записи (`agents-modes-banner`).
enum AgentsModesBannerKind { saved, conflict, error }

/// Баннер результата записи.
final class AgentsModesBanner {
  const AgentsModesBanner(this.kind, this.text);

  final AgentsModesBannerKind kind;
  final String text;
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

  final AgentsModesBanner? banner;
}
