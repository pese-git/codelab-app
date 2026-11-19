import 'package:codelab_setup/codelab_setup.dart' show ConfigSourceKind;

import 'agent_defaults_rows.dart';

export 'agent_defaults_rows.dart' show AgentDefaultsGroup, AgentDefaultsRow;

/// Состояние блока «Agent defaults» страницы «General» (design.md change
/// `add-app-general-page`, D7; spec app-settings «Умолчания агента на
/// странице «General»: доступ и строки»).
///
/// Для чего: чистые значения для отображения; строит их `AgentDefaultsCubit`.
/// Текст в состоянии не хранится: баннер и ошибки — типизированные данные, а
/// текст строит страница из ARB на языке интерфейса (D7, D15).
///
/// Почему закрытая иерархия, а не набор флагов: блок либо загружается, либо
/// только читает (WebSocket и сторонний агент, SETUP-2), либо не может
/// прочитать `config.yaml`, либо готов к правкам; «только чтение» с
/// редактором не представимо (AGENTS.md §8).
sealed class AgentDefaultsState {
  const AgentDefaultsState();
}

/// Доступ ещё определяется или конфиг читается.
final class AgentDefaultsLoading extends AgentDefaultsState {
  const AgentDefaultsLoading();
}

/// Почему блок только читает (SETUP-2).
enum AgentDefaultsReadOnlyKind {
  /// Агент удалённый: [AgentDefaultsReadOnly.subject] — `scheme://host:port`.
  remote,

  /// Агент не наш: [AgentDefaultsReadOnly.subject] — имя агента.
  notManaged,
}

/// Агент не наш или удалённый: локальный конфиг не читается, строк нет.
final class AgentDefaultsReadOnly extends AgentDefaultsState {
  const AgentDefaultsReadOnly({required this.kind, required this.subject});

  final AgentDefaultsReadOnlyKind kind;

  /// Адрес без пути или имя агента (подставляется в текст страницей).
  final String subject;
}

/// Хвост баннера о перезапуске агента (`ConfigSaved.restartRequiredKeys`).
enum AgentDefaultsRestart {
  /// Ключ вступает в силу сразу.
  none,

  /// Агент подключён: `Applies after Restart agent.`
  afterRestart,

  /// Агент не подключён: `Applies when the agent starts.`
  whenStarts,
}

/// Вид баннера записи `settings-general-agent-banner`.
enum AgentDefaultsBannerKind {
  /// `Saved.` (с хвостом [AgentDefaultsRestart]).
  saved,

  /// Значение перекрыто другим слоем: уровень `warning`.
  overridden,

  /// Записано, но перечитать не удалось: `Saved to <home>/config.yaml.`
  savedUnverified,

  /// Файл изменился на диске: `The config file changed on disk…`
  conflict,

  /// Писатель отклонил правку: уровень `error`, проблемы — [problems].
  rejected,

  /// Значение выглядит как секрет: `Change it with codelab secret set.`
  inlineSecret,
}

/// Баннер результата записи: данные, текст строит страница.
final class AgentDefaultsBanner {
  const AgentDefaultsBanner(
    this.kind, {
    this.key,
    this.restart = AgentDefaultsRestart.none,
    this.overriddenByKind,
    this.effective,
    this.problems = const [],
  });

  final AgentDefaultsBannerKind kind;

  /// Ключ реестра, к которому относится баннер.
  final String? key;

  final AgentDefaultsRestart restart;

  /// Вид слоя, перекрывшего запись: подпись строит страница по
  /// `ConfigSourceKind` (D7, В1).
  final ConfigSourceKind? overriddenByKind;

  /// Действующее значение нового снимка (`SettingFieldView.displayValue`).
  final String? effective;

  /// Проблемы писателя с путём ключа, как они есть.
  final List<String> problems;
}

/// Почему блок не может показать настройки (D7: текст в состоянии не хранится,
/// сообщение строит страница из ARB).
enum AgentDefaultsUnreadableReason {
  /// Загрузчик ядра назвал проблемы: [AgentDefaultsUnreadable.problems]
  /// показываются как есть (`ConfigIssue`, английский текст ядра).
  loader,

  /// Папка `$CODELAB_HOME` неизвестна.
  homeUnavailable,

  /// Сессия настроек или снимок не открылись (исключение; текст не хранится).
  cannotRead,

  /// Пользовательский `config.yaml` не читается, а проблем загрузчик не назвал.
  userLayerUnreadable,
}

/// `config.yaml` не разбирается или нарушает схему: записи нет
/// (`settings-general-agent-unreadable`).
final class AgentDefaultsUnreadable extends AgentDefaultsState {
  const AgentDefaultsUnreadable({
    required this.reason,
    this.problems = const [],
    this.banner,
    this.configHome = _defaultConfigHome,
  });

  /// Причина; для не-[AgentDefaultsUnreadableReason.loader] сообщение строит
  /// страница из ARB.
  final AgentDefaultsUnreadableReason reason;

  /// Проблемы загрузчика с путём ключа, по строке на проблему (только для
  /// [AgentDefaultsUnreadableReason.loader]).
  final List<String> problems;

  /// Баннер записи, после которой перечитать не удалось; `null` — записи не
  /// было.
  final AgentDefaultsBanner? banner;

  /// Метка `$CODELAB_HOME` для текста `Saved to <home>/config.yaml.`
  final String configHome;
}

/// Блок готов к правкам; запись — флаг [saving] (D7: одна запись за раз).
final class AgentDefaultsReady extends AgentDefaultsState {
  const AgentDefaultsReady({
    required this.groups,
    this.banner,
    this.saving = false,
    this.fieldErrors = const {},
    this.configHome = _defaultConfigHome,
  });

  /// Строки по разделам реестра: Budget, Agent, Subagents, Logging.
  final List<AgentDefaultsGroup> groups;

  /// Баннер последней записи; `null` — записи не было или новая её сбросила.
  final AgentDefaultsBanner? banner;

  /// Запись идёт: повторные правки игнорируются.
  final bool saving;

  /// Ключи, чей введённый текст не разобран; подсказку формата страница
  /// строит по типу и границам дескриптора. Значение не хранится (CFG-10).
  final Set<String> fieldErrors;

  /// Метка `$CODELAB_HOME` для текста InfoBar `settings-general-shared-info`
  /// (`<home>/config.yaml`): путь с `~` вместо домашнего каталога, как его
  /// строит `homePathLabel`. Заполняет Cubit, страница путей не вычисляет
  /// (AGENTS.md §11).
  final String configHome;
}

/// Метка по умолчанию: `$CODELAB_HOME` без переопределения.
const _defaultConfigHome = '~/.codelab';
