/// Вид страницы «Skills & extensions»: цепочка `AGENTS.md`, навыки и шаблоны
/// команд папки (design.md change `add-app-skills-page`, D4; `dart-agent-and-
/// clients` §12.4.6а).
///
/// Почему модели в мосте: знание формата навыков, корней и правил ядра — это
/// агентская сторона; клиенты получают его только через `codelab_setup`
/// (`AGENTS.md` §5, SETUP-8), и CLI сможет взять те же виды без второй
/// реализации.
///
/// Для чего: данные для показа без текстов файлов. Тексты `AGENTS.md`, тела
/// навыков и шаблонов в виды НЕ попадают ни в поля, ни в `toString()`
/// (SETUP-25); `toString()` печатает только имена и числа.
///
/// Как использовать: виды строит `agentExtensionsOf` (чистая функция) или
/// `readAgentExtensions` (`io.dart`, читает файлы); поля только для чтения.
/// Имена, описания и подсказки — недоверенный текст из файлов: показывать
/// простым текстом, без markdown и ссылок.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ExtensionDiagnostic, ExtensionScope;

import 'skills_list_edit.dart' show SkillToggle;

/// Исход чтения раздела (D4 «Фазы»).
///
/// Почему sealed: страница обязана показать причину пустого раздела, а не
/// молча пустой список.
sealed class SectionOutcome {
  const SectionOutcome();
}

/// Раздел прочитан.
final class SectionRead extends SectionOutcome {
  const SectionRead();

  @override
  String toString() => 'SectionRead';
}

/// Фаза не уложилась в предел (`Skills were not read within 5 s.`).
final class SectionTimedOut extends SectionOutcome {
  const SectionTimedOut();

  @override
  String toString() => 'SectionTimedOut';
}

/// Исключение порта; [errorType] — только имя типа (`... (<тип>).`).
final class SectionFailed extends SectionOutcome {
  const SectionFailed(this.errorType);

  final String errorType;

  @override
  String toString() => 'SectionFailed($errorType)';
}

/// Навыки выключены `skills.enabled: false`; [source] — файл, откуда ключ.
final class SectionOff extends SectionOutcome {
  const SectionOff(this.source);

  final String source;

  @override
  String toString() => 'SectionOff($source)';
}

/// Доступность навыка в каталоге сессии.
enum SkillAvailability {
  /// Навык в каталоге сессии.
  enabled,

  /// Выключен `skills.disabled`: сессия его не загрузит.
  disabled,
}

/// Корень навыков: откуда взята строка.
final class SkillRootView {
  const SkillRootView({
    required this.scope,
    required this.label,
    required this.path,
  });

  final ExtensionScope scope;

  /// Подпись источника: проект — путь от папки проекта (`.codelab/skills`,
  /// `../.agents/skills`), пользователь — путь с `~` вместо домашнего
  /// каталога, extra — элемент `extra_roots` как записан с пометкой
  /// `(extra root)`.
  final String label;

  /// Абсолютный путь корня на диске (для «Open»).
  final String path;

  @override
  String toString() => 'SkillRootView($label)';
}

/// Каталог другого агента, на чтение которого пользователь может согласиться
/// записью в `skills.extra_roots` (решение Q3).
final class SkillConsentView {
  const SkillConsentView({
    required this.entry,
    required this.path,
    required this.skillDirs,
    required this.granted,
    required this.toggle,
  });

  /// Элемент, как он запишется в `extra_roots`: `.claude/skills` или
  /// `~/.claude/skills`.
  final String entry;

  /// Каталог на диске.
  final String path;

  /// Число подкаталогов с `SKILL.md`; `null` — каталог не ответил за предел
  /// времени сбора (скорее всего завис том), число неизвестно, а согласие на
  /// каталог по-прежнему можно дать.
  final int? skillDirs;

  /// Согласие действует: элемент есть в действующем `skills.extra_roots`.
  ///
  /// Почему не просто «есть в списке»: относительный элемент
  /// (`.claude/skills`) у недоверенного проекта загрузчик не читает
  /// (`untrusted_project`), поэтому для него признак `false`, даже если
  /// элемент записан (например, в слое `user`): согласие записано, но не
  /// действует. Для `~/…` доверие не нужно.
  final bool granted;

  /// Переключатель согласия: правило `skillsListEdit` с `present: !granted`
  /// (одна реализация для вида и записи, D5); неактивен с причиной, если
  /// запись не подействует.
  final SkillToggle toggle;

  @override
  String toString() => 'SkillConsentView($entry, $skillDirs, $granted)';
}

/// Файл цепочки инструкций проекта.
final class ContextFileView {
  const ContextFileView({
    required this.path,
    required this.openDir,
    required this.bytes,
    required this.shownBytes,
    required this.scope,
    required this.isClaudeAlias,
    required this.omitted,
  });

  /// Путь для промпта: `$CODELAB_HOME/AGENTS.md` или от корня репозитория.
  final String path;

  /// Каталог файла на диске для «Open»; `null` — `$CODELAB_HOME` неизвестен.
  final String? openDir;

  /// Полный размер файла, байты.
  final int bytes;

  /// Сколько попало в промпт по бюджету (`shownBytes < bytes` — усечён).
  final int shownBytes;

  final ExtensionScope scope;

  /// `CLAUDE.md`, прочитанный вместо `AGENTS.md` (решение Q6).
  final bool isClaudeAlias;

  /// Файл не вошёл в промпт: бюджет исчерпан.
  final bool omitted;

  @override
  String toString() => 'ContextFileView($path, $shownBytes/$bytes)';
}

/// Цепочка инструкций папки.
final class ContextChainView {
  const ContextChainView({
    required this.outcome,
    required this.files,
    required this.shownBytes,
    required this.omittedCount,
    required this.truncatedCount,
    this.warnings = const [],
  });

  final SectionOutcome outcome;

  /// `error`/`warning` файлов цепочки (`AGENTS.md`, `CLAUDE.md`: слишком
  /// большой, не UTF-8, нечитаемый, вне корня), в InfoBar предупреждений.
  final List<ExtensionDiagnostic> warnings;

  /// В порядке агента: пользовательский, затем от корня репозитория к папке.
  final List<ContextFileView> files;

  /// Итог попавшего в промпт, байты.
  final int shownBytes;
  final int omittedCount;
  final int truncatedCount;

  @override
  String toString() => 'ContextChainView(${files.length} files, $outcome)';
}

/// Строка навыка.
final class SkillEntryView {
  const SkillEntryView({
    required this.name,
    required this.description,
    required this.argumentHint,
    required this.invokeAs,
    required this.availability,
    required this.modelVisible,
    required this.userInvocable,
    required this.root,
    required this.directory,
    required this.overrides,
    required this.overridesLabel,
    required this.warnings,
    required this.toggle,
  });

  final String name;
  final String description;
  final String? argumentHint;

  /// `/skill:<name>[ <hint>]`; `null` — у навыка нет команды (`Model only`).
  final String? invokeAs;

  final SkillAvailability availability;

  /// Навык виден модели; «Command only» — включён, с командой и `false` здесь.
  final bool modelVisible;
  final bool userInvocable;
  final SkillRootView root;

  /// Каталог, где лежит `SKILL.md` навыка (для «Open»).
  ///
  /// Почему поле, а не `<root.path>/<name>`: имя во frontmatter может не
  /// совпадать с именем каталога (предупреждение `name_mismatch`, навык
  /// загружается под именем из frontmatter) (D8 «API итерации 4»).
  ///
  /// Как использовать: `agentExtensionsOf` отдаёт путь в форме ядра (как
  /// `root.path`), `readAgentExtensions` — в форме хоста; выключенный
  /// `skills.disabled` навык тоже знает свой каталог.
  final String directory;

  /// Корни навыков, перекрытых этим (по диагностикам `shadowed` ядра).
  final List<SkillRootView> overrides;

  /// `Overrides <user|project|extra> skill` или `Overrides another skill`.
  final String? overridesLabel;

  /// `error`/`warning` с путём `SKILL.md` этого навыка.
  final List<ExtensionDiagnostic> warnings;

  /// Выключатель «Enabled»: правило `skillsListEdit` с `present:
  /// availability == enabled` (одна реализация для вида и записи, D5);
  /// неактивен с причиной, если запись не подействует.
  final SkillToggle toggle;

  @override
  String toString() => 'SkillEntryView($name, ${availability.name})';
}

/// Раздел навыков.
final class SkillsSectionView {
  const SkillsSectionView({
    required this.outcome,
    required this.entries,
    required this.warnings,
    this.consents = const [],
  });

  final SectionOutcome outcome;
  final List<SkillEntryView> entries;

  /// Остальные `error`/`warning`: пропущенные навыки, корни, перекрытые.
  final List<ExtensionDiagnostic> warnings;

  /// Кандидаты согласия на каталоги других агентов.
  final List<SkillConsentView> consents;

  @override
  String toString() => 'SkillsSectionView(${entries.length} skills, $outcome)';
}

/// Строка шаблона команды (`/<имя файла>`).
///
/// Почему: шаблоны — часть того, что агент объявляет клиенту командами
/// (E-07); страница показывает их только для чтения.
///
/// Как использовать: поля — недоверенный текст из файла, показывать простым
/// текстом. Тело шаблона в строку не входит (SETUP-25).
final class TemplateEntryView {
  const TemplateEntryView({
    required this.command,
    required this.argumentHint,
    required this.description,
    required this.sourcePath,
    required this.scope,
  });

  /// Со слэшем: `/review-pr`.
  final String command;

  /// Подсказка ввода из `argument-hint`; `null` — не задана.
  final String? argumentHint;

  /// Описание из `description` frontmatter; если его нет, ядро берёт первую
  /// строку шаблона — это допустимо: ту же строку агент и так отдаёт клиенту
  /// в `available_commands_update`, новой утечки тела нет.
  final String description;

  /// Путь файла шаблона на диске (для подписи и каталога «Open»).
  final String sourcePath;

  /// Проект или пользователь; при совпадении имён проект заменяет
  /// пользователя.
  final ExtensionScope scope;

  @override
  String toString() => 'TemplateEntryView($command)';
}

/// Раздел шаблонов команд.
///
/// Почему отдельный раздел: шаблоны читает та же фаза, что и цепочку, поэтому
/// [outcome] общий, а предупреждения свои — только про шаблоны.
///
/// Как использовать: [warnings] — диагностики каталога `prompts` и самих
/// шаблонов (`parseCommandTemplates`), без `info`. Определения агентов
/// (`.codelab/agents`) на странице не показываются, их диагностики сюда не
/// попадают.
final class TemplatesSectionView {
  const TemplatesSectionView({
    required this.outcome,
    required this.entries,
    required this.warnings,
  });

  /// Исход фазы файлов проекта.
  final SectionOutcome outcome;

  /// По имени команды; пустой при сбое фазы.
  final List<TemplateEntryView> entries;
  final List<ExtensionDiagnostic> warnings;

  @override
  String toString() =>
      'TemplatesSectionView(${entries.length} templates, $outcome)';
}

/// Вид расширений агента для папки.
///
/// Почему: страница «Skills & extensions» показывает то, что агент загрузит
/// для папки; вид собирает один раз мост, а не app.
///
/// Как использовать: получить из `agentExtensionsOf` или
/// `readAgentExtensions`; поля только для чтения, тексты файлов в них нет
/// (SETUP-25).
final class AgentExtensionsView {
  const AgentExtensionsView({
    required this.folder,
    required this.trusted,
    required this.context,
    required this.skills,
    required this.templates,
  });

  /// Канонический `cwd`.
  final String folder;

  /// Проект в `trusted_projects` (fail-closed).
  final bool trusted;

  /// Цепочка инструкций `AGENTS.md`/`CLAUDE.md` в порядке агента.
  final ContextChainView context;

  /// Навыки: строки таблицы, предупреждения, кандидаты согласия.
  final SkillsSectionView skills;

  /// Шаблоны команд `prompts/*.md`.
  final TemplatesSectionView templates;

  @override
  String toString() => 'AgentExtensionsView($folder, trusted: $trusted)';
}
