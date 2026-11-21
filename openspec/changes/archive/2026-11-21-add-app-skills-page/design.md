## Context

Источники:
- дорожная карта [`delivery-roadmap.md`](../../../../docs/architecture/proposals/delivery-roadmap.md) §10.1, экран 24 (`E-01, E-17 (только чтение)` в M4; E-06, E-09, E-10, E-18, E-19 в M5), §6.1, строка 11 (E-06 сделано, страница app вынесена решением Q8);
- матрица целей [`agent-parity-goals.md`](../../../../docs/architecture/proposals/agent-parity-goals.md): E-01, E-06, E-07, E-08, E-17;
- [`12-4-first-run-and-settings.md`](../../../../docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md): §12.4.2 (контракт моста), §12.4.5–§12.4.6 (страницы Providers и MCP servers как образец), §12.4.8 (удалённый агент — только чтение), §12.4.9 (строка экрана 24), §12.4.11 (SETUP-1…SETUP-24; SETUP-25 и §12.4.6а — устройство этой страницы, внесены задачей 0.2);
- change [`add-agent-skills`](../2026-11-18-add-agent-skills/design.md), заархивирован 2026-11-18; действующий контракт — основные спецификации `openspec/specs/agent-skills`, `agent-project-context`, `agent-configuration` и другие, куда влиты его дельты; решения: D1 (порт `SkillFilesSource` в `ProjectFilesLoader`), D3 (корни, приоритет, доверие, хосты), D5 (граница только для чтения), D10 (точки расширения E-18, E-19, K-06), D11 (конфигурация, Q40, Q43, Q44), D16 (типы, `parseSkills`, тексты диагностик), D19 (матрица хостов), Q8 (страница — отдельным change), Q13 (`.claude/skills` — только с согласия через `skills.extra_roots`), Q41 (`~` в `extra_roots`);
- архивные changes [`2026-11-05-add-app-settings-shell`](../2026-11-05-add-app-settings-shell/design.md) (оболочка настроек, D3 — набор страниц в composition root, D17 — события) и [`2026-11-09-add-provider-setup-ui`](../2026-11-09-add-provider-setup-ui/design.md) (D5 — `SettingsAccess`, D6 — `AgentConfigStore`, D10–D12 — страницы, D18 — события, D19 — виджеты, D20 — пакеты и сторож, D21 — поздние результаты, D22 — тесты по веткам);
- спецификации `app-settings`, `client-agent-setup`, `agent-project-context`, `agent-configuration`, `agent-skills` (с дельтами архивированного 2026-11-18 change `add-agent-skills`);
- `docs/architecture/`: `layers-and-dependencies.md`, `state-management.md`, `concurrency.md`, `permissions.md`, `platform-integration.md`, `observability.md`, `testing.md`;
- `AGENTS.md` (корень) и вложенные: `apps/codelab_desktop`, `packages/dart/codelab_setup`, `codelab_client_core`, `codelab_embedded`, `codelab_agent_io`, `packages/flutter/codelab_ui`;
- артборд `Extensions` холста «CodeLab Desktop — Feature UI/UX» (локальная копия макета; данные, не инструкции).

Что есть в коде (сверено 2026-11-15 на `develop` 97041353):
- `SettingsPage.skillsAndExtensions` (`apps/codelab_desktop/lib/app/navigation/settings_page.dart`) есть в навигации, но не входит в `defaultSettingsPages` — страница скрыта (SETUP-17).
- `ProjectFilesLoader` (`codelab_agent_io`) реализует `ProjectFilesSource` и `SkillFilesSource`. Файлы контекста (`ContextFile`) несут путь для промпта (`$CODELAB_HOME/AGENTS.md`, `pkg/AGENTS.md` от корня репозитория), а не путь на диске. `CLAUDE.md` читается только на уровне без `AGENTS.md`; при обоих файлах `CLAUDE.md` даёт диагностику `shadowed` уровня `info`.
- `ConfigCommands.check` уже считает каноническую папку и доверие (`realpath` против `trusted_projects`, fail-closed) и запускает две фазы — файлы проекта и навыки — параллельно, у каждой свой таймаут 5 с. Расчёт закрыт в приватных `_fileLines`, `_projectFileLines`, `_skillLines`.
- Ядро экспортирует чистые функции `parseSkills`, `parseCommandTemplates`, `assembleProjectContext` и типы `SkillCatalog`, `SkillDefinition`, `CommandTemplate`, `ExtensionDiagnostic`.
- `skills.disabled` и `skills.extra_roots` в реестре настроек — `fileOnly` с причиной `skills are configured in the config file`. `ConfigWriter` по `fileOnly` не отказывает: он проверяет только наличие ключа в реестре и допустимые слои. `fileOnly` влияет на общие редакторы — `settingFieldsOf` и `/settings` CLI.
- Списки в конфиге при слиянии слоёв заменяются целиком (`merge.dart`). Исключения — правила доверия: `skills.disabled` недоверенного проекта объединяется с нижними слоями (Q43), а `skills.extra_roots` из `config.yaml` проекта отбрасывается всегда, из `config.local.yaml` — у недоверенного проекта (SKL-2).
- E-08 (`prompts.system*`, `prompts.append_system*`) и E-17 (`prompts.context_files`) в схеме есть, но не применяются (`applied: false`): в агенте их нет.
- Порта «открыть папку» в app нет. `ExternalLinkOpener` (`core/platform/`, `url_launcher`) открывает только `http`/`https`. `url_launcher` вне `core/platform/` запрещён сторожем.
- `CodeLabStatusTable` (`codelab_ui`) — таблица с колонками одинаковой ширины, текстовыми ячейками и кнопкой строки.

## Goals / Non-Goals

**Goals:**
- Показать на экране 24 то, что агент действительно загрузит для папки: цепочку `AGENTS.md`, навыки и шаблоны. Расчёт — по тем же правилам и тем же кодом, что у агента и `codelab config check`, без второй реализации правил.
- Дать выключить навык (`skills.disabled`) и дать согласие на каталог навыков другого агента (`skills.extra_roots`) записью через мост — с теми же гарантиями записи, что у страниц Providers и MCP servers.
- Честно показать ограничения: недоверенный проект, удалённый или сторонний агент, «действует в новых сессиях».

**Non-Goals:**
- Hooks (E-09), Plugins (E-10), System prompt override (E-08), context-файлы других агентов (E-17), обновление списка навыков в идущих сессиях (E-19), встроенные навыки (E-18).
- Изменения ACP и поведения агента. В агентской стороне — только вынесение уже существующего расчёта `config check` в публичную функцию и аддитивные типы данных ядра для её результата (D3).
- Правка файлов навыков и шаблонов, создание навыков, правка `trusted_projects` из app.
- CLI-экран навыков.

## Decisions

### D1. Источник данных: файлы через мост `codelab_setup`, а не агент по ACP

Страница читает файлы на машине клиента функцией `io.dart` моста. Это та же модель, что у Providers и MCP servers (D5, D6 change `add-provider-setup-ui`) и у `codelab config check`. Чтение и разбор делают `ProjectFilesLoader` и чистые функции ядра. Вторых правил корней, доверия, перекрытия и мягкой проверки в app и мосте нет.

Почему не агент:
- в ACP нет метода «перечислить навыки». `available_commands_update` несёт только имя, описание и подсказку ввода. Источник команды ACP не передаёт (D8 change `add-agent-skills`), а угадывать навык по префиксу `skill:` запрещено (`AGENTS.md` §3.4). Новый метод, `_meta` или `_codelab/*` — изменение ACP-контракта. Оно потребовало бы отдельного change и всё равно не покрыло бы сторонних агентов;
- навыки нужны и без запущенного агента: страница открывается до подключения, после сбоя старта и для профиля по умолчанию;
- выключенный навык агент не загружает и не объявляет. Показать его с выключателем «Off» агент не может, а мост может (D4).

Альтернативы:
- (а) ACP-расширение `_codelab/skills/list` — изменение протокола, отклонено (§3.4, приоритет 2);
- (б) встроенная команда `/skills` и её текст через `SessionHandle.send`, как `/mcp list` (D12 change `add-provider-setup-ui`) — такой команды в агенте нет, нужна живая сессия, а текст пришлось бы разбирать. Отклонено;
- (в) только встроенный агент через `EmbeddedAgent` (как живой статус MCP) — не покрывает stdio-`codelab-agent` и состояние «агент не запущен». Отклонено.

Для внешнего агента: `resolveSettingsAccess` даёт `RemoteReadOnly` (WebSocket) или `NotManaged` (сторонний stdio). Тогда локальные файлы НЕ читаются (SETUP-2): агент может работать на другой машине или читать файлы по своим правилам. Страница показывает только InfoBar `skills-read-only` (решение Q1). stdio-`codelab-agent` считается агентом на этой машине — то же допущение, что у Providers (D5 change `add-provider-setup-ui`) и у известного предела «клиент stdio на той же машине» (Risks change `add-agent-skills`).

### D2. Чьи настройки, какая папка, доверие

- **Профиль и доступ** — ровно как у Providers и MCP servers (app-settings «Доступ к настройкам агента на страницах Providers и MCP servers»): профиль текущего подключения (`Connected`/`Reconnecting`), без подключения — профиль по умолчанию; доступ — `resolveSettingsAccess`. Смена подключения перечитывает страницу.
- **Папка** — папка сессии в фокусе, без неё — выбранный проект: то же правило, что у Providers. Это `cwd`, от которого агент откроет сессию и будет искать файлы проекта и навыки. Без папки страница показывает состояние `noFolder`: `Open a project folder to see the context files, skills and prompt templates the agent uses there.` Кнопка «Open .codelab folder» в этом состоянии открывает `$CODELAB_HOME` (Q4). Загрузчик всегда обходит уровни проекта от `cwd`, поэтому «только пользовательский уровень» без папки показать нельзя без второго правила. В app папка проекта обязательна для старта агента (change `require-project-folder`), так что это редкое состояние.
- **Окружение** — окружение агента, как в `openProviderSettingsSession`: переменные app, дополненные `env` stdio-профиля. `CODELAB_HOME` — из `EditableSettings.paths`. Домашний каталог для `~/.agents/skills` и `~` в `extra_roots` — `userHomeOf(environment)`, та же функция, что у хостов (D19 change `add-agent-skills`).
- **Конфигурация** — снимок `AgentConfigStore.snapshot(cwd)` страницы. Это та же загрузка слоёв, что у агента для сессии этой папки (Q44: `skills.*` — ключи сессии). Нечитаемый или нарушающий схему конфиг — состояние `unreadable`, файлы не читаются и не пишутся. Так же поступает `config check`: у невалидного конфига файлы проекта не проверяются.
- **Доверие** считает функция D3: канонический `cwd` (`realpath`) сравнивается с `trusted_projects` загруженного конфига, без `realpath` проект недоверенный (fail-closed). Это тот же расчёт, что у `config check` и рантайма. Для недоверенного проекта загрузчик сам не читает корни навыков и шаблоны проекта и отдаёт диагностику `untrusted_project`. Страница показывает InfoBar `skills-untrusted`: `This project is not in trusted_projects, so the agent does not read its skills and prompt templates. Your own skills and AGENTS.md files are shown.` Подсказка о доверии называет файл: `Trust is set in trusted_projects of <$CODELAB_HOME>/config.yaml.` Кнопки «доверять» нет (Non-Goals). Цепочка `AGENTS.md` читается и для недоверенного проекта (E-01, OQ2 change `add-agent-project-files`), и страница её показывает.

### D3. Один расчёт для `config check` и моста (`codelab_agent_io`; типы — в ядре)

Тело `ConfigCommands._fileLines` (канонический `cwd`, доверие, один `ProjectFilesLoader` на обе фазы, параллельные фазы со своими таймаутами и отменой) выносится в публичную функцию `codelab_agent_io`:

```dart
// codelab_agent_io: функция
/// Файлы проекта и навыки папки так, как их прочитает сессия агента.
Future<ProjectExtensions> loadProjectExtensions({
  required String cwd,                       // как задал пользователь; канонизирует функция
  required CoreConfig config,                // конфигурация сессии этой папки
  required Map<String, String> environment,  // окружение агента
  ProjectFilesSource? projectFiles,         // null — ProjectFilesLoader по умолчанию
  SkillFilesSource? skillFiles,             // null — тот же загрузчик
  Duration timeout = const Duration(seconds: 5),   // предел фазы файлов проекта
  Duration? skillsTimeout,                  // предел фазы навыков; null — = timeout
});
typedef ProjectExtensionsLoader = Future<ProjectExtensions> Function({ /* те же параметры */ });
// ConfigCommands(extensionsLoader: …) — шов тестов; check передаёт свои источники и раздельные пределы фаз

// codelab_agent_io, lib/src/project/skill_roots.dart — единый план корней (чистая функция)
SkillRootPlan skillRootPlan({required List<String> levels, required String cwd, required bool trusted,
    String? home, String? userHome, List<String> extraRoots = const []});
final class SkillRootPlan { List<PlannedSkillRoot> roots; List<SkippedSkillRoot> skipped; }
final class PlannedSkillRoot { String path; ExtensionScope scope; String area; String? extraRoot; }
final class SkippedSkillRoot { String path; SkippedRootReason reason; }
enum SkippedRootReason { untrustedProject, untrustedRelativeExtra, unresolvedHome }

// codelab_agent_core (lib/src/project/, рядом с портами ProjectFiles/SkillFiles); codelab_agent_io реэкспортирует
final class ProjectExtensions {
  final String cwd;                 // канонический корень (или исходный при Err realpath)
  final bool trusted;               // fail-closed
  final String contextRoot;         // уровень, от которого считаются пути ContextFile проекта
  final String? codelabHome;        // для пути $CODELAB_HOME/AGENTS.md на диске
  final PhaseOutcome<ProjectFiles> projectFiles;
  final PhaseOutcome<SkillFiles>? skills;      // null — skills.enabled: false, фаза не запускалась
  final List<SkillRootInfo> skillRoots;        // корни по rootIndex
  final String? preparationError;              // имя типа исключения подготовки; null — подготовка прошла
}
sealed class PhaseOutcome<T> {}   // PhaseLoaded(T value) | PhaseTimedOut() | PhaseFailed(String errorType)
final class SkillRootInfo {        // const-конструктор, именованные параметры
  const SkillRootInfo({required this.scope, required this.path, this.extraRoot});
  final ExtensionScope scope;      // project | user | extra
  final String path;               // корень на диске (форма ядра)
  final String? extraRoot;         // элемент skills.extra_roots как записан; null — не extra
}
```

- **План корней — одна чистая функция `skillRootPlan`** (`skill_roots.dart`; там же `projectSkillSubdirs`). Загрузчик обходит `SkillRootPlan.roots` и превращает `skipped` в свои диагностики (`untrusted_project`, `unresolved_root`), а `loadProjectExtensions` отображает те же `roots` в `SkillRootInfo`. Это и есть «тот же список корней, что у загрузчика» требования client-agent-setup «Обзор расширений агента». `contextRoot` — из `projectLevels`, как у загрузчика. Поэтому путь на диске для «Open» и подпись источника навыка не расходятся с тем, что прочитано (D10 change `add-agent-skills`: номер корня — порядок, значение не уходит в журнал).
- **Типы — в ядре, функция — в `codelab_agent_io`** (решение координатора по красным тестам итерации 1). Построитель вида `agentExtensionsOf` живёт в web-безопасном основном бареле `codelab_setup` (D4), а основной барель НЕ ДОЛЖЕН импортировать `codelab_agent_io` (`codelab_setup/AGENTS.md` §2). Поэтому `ProjectExtensions`, `PhaseOutcome` и `SkillRootInfo` — чистые данные рядом с портами `ProjectFiles` и `SkillFiles` в `codelab_agent_core` (PKG-1 соблюдён, `dart:io` не нужен), барель ядра их экспортирует, `codelab_agent_io` реэкспортирует для своих потребителей. Ядро меняется аддитивно: новых зависимостей и поведения нет. Отклонено: зеркальный тип в мосте с переводом из типа `codelab_agent_io` — дублирование модели и перевод в `io.dart` без пользы.
- **Параметры без `@visibleForTesting`.** `projectFiles`, `skillFiles` и `skillsTimeout` передаёт `ConfigCommands` из `lib/` (у него раздельные пределы фаз и свои источники), поэтому это рабочий API, а не шов тестов. Шов тестов `check` — `ConfigCommands(extensionsLoader:)` с типом `ProjectExtensionsLoader`.
- `ConfigCommands.check` переходит на функцию без изменения вывода. Существующие тесты `config check` (`config_check_skills_test.dart` и тесты файлов проекта) — страж этой правки, новые строки вывода не появляются.
- Функция не пишет журнал и не бросает исключений файлов: исход фазы — значение. Непредвиденное исключение подготовки (канонизация, загрузчик) — `ProjectExtensions.preparationError` с именем типа и `PhaseFailed` с тем же типом у обеих фаз; `config check` печатает по нему ОДНУ строку `warning: <cwd>: project files could not be read: <тип>`, как до выделения. Исключения чистых функций разбора в `check` (`StaticModelCatalog`, `parseCommandTemplates`, `parseAgentDefinitions`, `parseSkills`) дают строку `warning:` с `runtimeType`; `check` не падает.

Альтернатива — скопировать расчёт в мост — отклонена: правило доверия и канонизации живёт в двух местах (`AGENTS.md` §14; так уже случился SETUP-8 для мастера).

### D4. Мост: вид страницы и построитель (основной барель, чистый Dart)

`codelab_setup/lib/src/extensions/` (web-безопасно, без `dart:io`):

```dart
final class AgentExtensionsView {
  final String folder;                        // канонический cwd
  final bool trusted;
  final ContextChainView context;             // файлы, итог, усечение
  final SkillsSectionView skills;             // строки, диагностики, кандидаты согласия, состояние фазы
  final TemplatesSectionView templates;
}
sealed class SectionOutcome {}    // SectionRead() | SectionTimedOut() | SectionFailed(String errorType)
                                  // | SectionOff(String source) — skills.enabled: false, source — файл из snapshot.origins
final class ContextChainView { SectionOutcome outcome; List<ContextFileView> files;
  int shownBytes; int omittedCount; int truncatedCount;
  List<ExtensionDiagnostic> warnings; }   // диагностики файлов контекста (раскладка — ниже)
final class ContextFileView { String path; String? openDir; int bytes; int shownBytes;
  ExtensionScope scope; bool isClaudeAlias; bool omitted; bool truncated; }
  // truncated — признак ядра (assembleProjectContext), а не shownBytes < bytes:
  // ядро срезает завершающие пробелы и перевод строки, и файл в пределах бюджета
  // показывается на несколько байтов короче (найдено ручным прогоном итерации 5)
final class SkillsSectionView { SectionOutcome outcome; List<SkillEntryView> entries;
  List<ExtensionDiagnostic> warnings; List<SkillConsentView> consents; }
final class TemplatesSectionView { SectionOutcome outcome; List<TemplateEntryView> entries;
  List<ExtensionDiagnostic> warnings; }
enum SkillAvailability { enabled, disabled }
final class SkillRootView { ExtensionScope scope; String label; String path; }
final class SkillConsentView { String entry;   // элемент extra_roots как запишется: `.claude/skills`, `~/.claude/skills`
  String path; int? skillDirs;   // null — подсчёт не уложился в предел времени
  bool granted; }
final class SkillEntryView { String name; String description; String? argumentHint;
  String? invokeAs;            // `/skill:<name>[ <hint>]`; null — userInvocable == false
  SkillAvailability availability;   // «Command only» = enabled && userInvocable && !modelVisible
  bool modelVisible; bool userInvocable; SkillRootView root;
  List<SkillRootView> overrides;    // корни навыков, перекрытых этим (shadowed)
  String? overridesLabel;           // `Overrides <user|project|extra> skill` | `Overrides another skill`
  List<ExtensionDiagnostic> warnings;   // error/warning с путём этого SKILL.md
  SkillToggle toggle; }              // доступен ли выключатель и почему нет (D5; поле — с итерации 2, задача 2.2)
final class TemplateEntryView { String command;   // со слэшем: `/review-pr`
  String? argumentHint; String description; String sourcePath; ExtensionScope scope; }

// основной барель — чистая функция
AgentExtensionsView agentExtensionsOf(AgentConfigSnapshot snapshot, ProjectExtensions extensions,
    {required String? userHome, List<SkillConsentView> consents = const []});
// io.dart
Future<AgentExtensionsView> readAgentExtensions(AgentConfigSnapshot snapshot,
    {required String? codelabHome, required Map<String, String> environment,
    Duration consentTimeout = const Duration(seconds: 5),   // общий предел сбора кандидатов
    int consentEntryLimit = 1000,                            // записей на каталог-кандидат
    @visibleForTesting ConsentDirScanner? scanConsentDir});
// исключение построителя уходит вызывающему; вызывающий (Cubit, итерация 4) пишет только runtimeType
```

`ProjectExtensions` и `ProjectFiles` содержат тела файлов, поэтому `agentExtensionsOf` вызывается внутри функции `io.dart` (D7), а наружу уходит только вид. Тексты `AGENTS.md`, тела навыков и шаблонов в вид не попадают: ни в поля, ни в `toString()` (SETUP-25). Исключение — описание шаблона: без `description` во frontmatter им служит первая строка тела, как в `available_commands_update` агента (новой утечки нет); на странице оно показывается как недоверенный текст (D12).

Правила построения:
- **Цепочка** — `ProjectFiles.context` в порядке ядра (пользовательский, затем от корня к `cwd`). `shownBytes` и `omitted` берутся из `assembleProjectContext(files, config.projectContextMaxBytes)` — бюджет считает ядро, а не мост. `isClaudeAlias` — у файла с именем `CLAUDE.md`. Путь на диске: `$CODELAB_HOME/AGENTS.md` → `<codelabHome>/AGENTS.md`, иначе `<contextRoot>/<path>`.
- **Навыки** — каталог `parseSkills(files, config.skills, rules: config.permissions.rules)` — то же, что получит сессия. Для строк выключенных навыков — второй вызов `parseSkills` с `disabled: []`. Выключение действует по имени на все файлы с этим именем (шаг 3 `parseSkills`), поэтому победитель по имени во втором вызове — та строка, которую включит выключатель. Строки: `catalog.skills` (включённые) плюс победители второго вызова, чьё имя в `skills.disabled` (`availability: disabled`). Порядок — по имени, как в каталоге.
- **«Command only»** — навык с `userInvocable` вне `modelVisible` (`disable-model-invocation: true` или запрет `skill:<name>` правилами разрешений). Навык без `userInvocable` — `invokeAs: null`, ячейка `Model only`.
- **Перекрытие** — по диагностикам `shadowed` ядра: путь диагностики — `SKILL.md` проигравшего. Его `SkillFile` разбирается одиночным `parseSkills`, чтобы получить имя по тому же правилу ядра. Победитель — `catalog.skill(name)`. Текст сообщения не разбирается. Подпись: `Overrides <user|project|extra> skill`; если уровень тот же — `Overrides another skill`.
- **Источник** — `SkillRootView` по `SkillFile.rootIndex` → `skillRoots[rootIndex]`. Подпись `label` строит мост: проект — путь от папки проекта (`.codelab/skills`, `../.agents/skills`); пользователь — путь корня с `~` вместо `userHome` (`~/.codelab/skills` при `CODELAB_HOME` по умолчанию, `~/.agents/skills`; вне домашнего каталога — абсолютный путь); extra — `SkillRootInfo.extraRoot` как записан, с пометкой `(extra root)`. Подпись строит мост, а не presentation app: это чистая функция над данными загрузчика, и CLI возьмёт её без второй реализации (SETUP-8); `path` остаётся абсолютным для «Open».
- **Предупреждения** — `[...SkillFiles.diagnostics, ...catalog.diagnostics]`. Уровни `error`/`warning` с путём показанного навыка идут в его строку (`1 warning`). Остальные `error`/`warning` (пропущенные навыки, корни) — в `SkillsSectionView.warnings` (InfoBar `skills-warnings`). `shadowed` проигравшего — тоже в предупреждения раздела (путь проигравшего — не строка таблицы), а у победителя — `overrides` и `overridesLabel`; `info` не показываются: `info` не показываются: то же правило, что у `config check`. Дополнительно `untrusted_project` превращается в признак D2. Текст — фиксированное сообщение ядра (D16 change `add-agent-skills`) и путь.
- **Шаблоны** — `parseCommandTemplates(files.templates).templates`: команда `/<name>`, подсказка, описание (`CommandTemplate.description`: поле frontmatter или первая строка тела, как у агента), путь файла.
- **Раскладка диагностик `ProjectFiles`** по пути: имя файла `AGENTS.md` или `CLAUDE.md` — `ContextChainView.warnings`; путь с сегментом `prompts` — `TemplatesSectionView.warnings`; с сегментом `agents` — не показывается (определений агентов на странице нет, это страница «Agents & modes»); прочее — цепочка. `TemplatesSectionView.warnings` — только диагностики шаблонов загрузчика и `parseCommandTemplates`, без `info`.
- **Фазы** — `PhaseOutcome` переводится в `SectionOutcome` раздела: `PhaseLoaded` → `SectionRead`, `PhaseTimedOut` → `SectionTimedOut` (`Skills were not read within 5 s.`), `PhaseFailed` → `SectionFailed(errorType)` (`Skills could not be read (<тип>).`). Фаза файлов проекта даёт исход и цепочке, и шаблонам. Раздел без данных пуст, остальные разделы не затронуты. `skills: null` (`skills.enabled: false`) — `SectionOff(source)` с файлом источника ключа из `snapshot.origins`: `Skills are switched off: skills.enabled is false in <файл>.`
- **Кандидаты согласия** (D5) — каталоги из фиксированного списка моста (решение Q3: `.claude/skills` проекта и `~/.claude/skills`), существующие на диске, с числом подкаталогов с `SKILL.md` (`skillDirs`). Их нужен диск, поэтому собирает `readAgentExtensions` (`lib/src/io/`) и передаёт построителю параметром `consents:`; `agentExtensionsOf` остаётся чистой функцией и кладёт список в `SkillsSectionView.consents` как есть, без `copyWith` готового вида. `granted` — элемент как записан (`entry`) уже есть в действующем `skills.extra_roots`; его считает `readAgentExtensions` по снимку. Без параметра (тесты построителя, хост без диска) список пуст.
  Пределы сбора (технические решения итерации 1): общий предел времени `consentTimeout` 5 с и не больше `consentEntryLimit` (1000) записей на каталог; не уложился во время — кандидат с `skillDirs == null` (страница пишет число неизвестным); исключение сканера — кандидат выпадает; симлинки не раскрываются (считаются только каталоги, видимые как каталоги); пути — через `toHostPath`. `granted` относительного элемента (`.claude/skills` проекта) требует доверенного проекта — иначе загрузчик его не читает (SKL-1); для `~/.claude/skills` доверие не нужно. Швы: `consentTimeout`, `consentEntryLimit`, `@visibleForTesting scanConsentDir` (тип `ConsentDirScanner` из `io.dart`).

Почему построитель в мосте, а не в app: знание формата навыков, корней и правил ядра — агентская сторона. Клиенты получают его только через `codelab_setup` (`AGENTS.md` §5; SETUP-8), и CLI сможет взять те же виды без второй реализации.

### D5. Запись `skills.disabled` и `skills.extra_roots`

Оба ключа — списки, а списки при слиянии заменяются целиком. Поэтому запись меняет список **того слоя, который сейчас действует**, а не дописывает слой ниже, — иначе правка молча не подействует. Правило одно для двух ключей (`skillsListEdit` моста), по образцу «Default model» страницы Providers:

1. Цель — самый верхний слой, чьё значение ключа действует (`snapshot.origins` итога загрузки), если он редактируемый (`user` или `projectLocal`, SETUP-3). Значение, отброшенное правилами доверия (`extra_roots` из `config.yaml` проекта), источником не считается. Для ключей, которые недоверенный проект объединяет с нижними слоями (сейчас только `skills.disabled`; набор `mergedByUntrustedProject` во внутреннем `codelab_setup/lib/src/config/project_trust.dart`), источник в `origins` определяется по `CoreConfig.withoutProjectValues`: слои `project` и `projectLocal` недоверенного проекта при выборе источника пропускаются, а `--config` — источник, только если сам задаёт ключ. Если ключ не задан нигде — `user` (решение Q2).
2. Верхний слой не редактируемый (`project` — только для `disabled` доверенного проекта; `--config`) — выключатель неактивен с подсказкой `Set in <файл>; edit that file.`. Запись в нижний слой не подействовала бы.
3. Новое значение — сырой список целевого слоя (`ConfigWriter.read`), плюс или минус элемент, с сохранением порядка и без дублей. Это одна правка `SetValue('skills.<key>', list)`. Пустой список пишется `UnsetValue` в этом слое: файл не копит пустых ключей.
4. **`skills.disabled` недоверенного проекта** — и `config.yaml`, и `config.local.yaml` — объединяется с нижними слоями (Q43). Имя, выключенное любым из этих слоёв (безопасная сторона), страница включить не может: выключатель неактивен с подсказкой `Disabled by the project config (<файл>).`. Выключить навык можно всегда — по правилу 1.
5. **`skills.extra_roots`** НИКОГДА не пишется в `project` (SKL-2), а в `projectLocal` — только для доверенного проекта. Иначе загрузчик его отбросит, и правило 2 даёт неактивный переключатель. Относительный элемент (`.claude/skills`) у недоверенного проекта не читается (`untrusted_project`), переключатель неактивен с подсказкой `Trust this project to read .claude/skills.`.
6. Запись — `AgentConfigStore.apply(base, edits)` с базой снимка страницы. `ConfigConflict` — баннер `skills-banner` и перечитывание без автоповтора (SETUP-6). `ConfigRejected` — баннер с проблемами загрузчика, файл не изменён. Пока идёт запись, повторные действия игнорируются (`saving`).

**API (контракт итерации 2, по красным тестам 2.1):**

```dart
SkillsListEditResult skillsListEdit(AgentConfigSnapshot snapshot, String key, String element,
    {required bool present});   // present: true — элемент должен оказаться в списке
                                //   (выключить навык, дать согласие); false — выйти из него
sealed class SkillsListEditResult {}
final class SkillsListPlan extends SkillsListEditResult {
  final ConfigLayer layer;          // user | projectLocal
  final ConfigSnapshot base;        // снимок целевого слоя из snapshot.layers
  final List<ConfigEdit> edits;     // пусто — уже так (идемпотентно)
}
final class SkillsListRefused extends SkillsListEditResult { final SkillsListRefusal refusal; }
sealed class SkillsListRefusal {}
final class SkillsListNotEditable extends SkillsListRefusal { final String source; }        // ConfigSourceView.label
final class SkillsListDisabledByProject extends SkillsListRefusal { final String source; }  // ConfigSourceView.label
final class SkillsListUntrustedProject extends SkillsListRefusal {}
final class SkillsListLayerUnreadable extends SkillsListRefusal { final ConfigLayer layer; }  // файл слоя вне снимка (AgentConfigSnapshot.issues)
final class SkillToggle { final bool isAvailable; final SkillsListRefusal? refusal; }
// SkillEntryView.toggle, SkillConsentView.toggle (обязательное)
```

- Вызывающий записывает план сам: `store.apply(plan.base, plan.edits)`. `base` — снимок **целевого** слоя, поэтому отпечаток и конфликт (SETUP-6) проверяются по файлу, который меняется. Пустой `edits` — запись не нужна.
- Ключ, кроме `skills.disabled` и `skills.extra_roots`, — `ArgumentError`: это ошибка программиста, а не отказ для пользователя.
- **Идемпотентность.** Добавить имеющийся элемент или убрать отсутствующий — `SkillsListPlan` с пустым `edits`; повторное нажатие и гонка двух вкладок не пишут файл.
- **Правило 4 опирается на Q43.** Список `skills.disabled` недоверенного проекта (`project` и `projectLocal`) объединяется с нижними слоями. Источник такого ключа в `origins` считается по `CoreConfig.withoutProjectValues` (правило 1), поэтому цель выбирается без проектных слоёв. `SkillsListDisabledByProject` определяется по сырому значению этих слоёв из `snapshot.layers` (только при `present: false`). *Исправлено ревью итерации 2:* прежнее допущение «`origins` его источником не называет» и эвристика «источник — окружение» были ошибкой: при совпадении объединения со списком проекта источником назывался `project`, и любое выключение отказывалось.
- **`SkillsListLayerUnreadable(layer)`** — файл целевого или действующего слоя не прочитан в снимке (есть проблема в `AgentConfigSnapshot.issues`): писать поверх нечитаемого файла нельзя (SETUP-6, целостность данных).
- **Порядок причин отказа** (закреплён тестом `skills_list_edit_guards_test.dart`): `SkillsListNotEditable` → `SkillsListDisabledByProject` → `SkillsListUntrustedProject` → `SkillsListLayerUnreadable`. Отказ по политике (источник, Q43, SKL-2) сообщается раньше технической причины, чтобы подсказка на странице называла то, что пользователь может изменить.
- **Доверие без IO.** Мост решает доверие сам, без файловой системы: `projectTrustedIn` сравнивает `projectRoot` снимка с `trustedProjects` итога загрузки; без итога загрузки проект недоверенный (fail-closed).
- **Предикаты элементов `extra_roots`** (`isAbsoluteSkillRoot`, `isHomeSkillRoot`, `isRelativeSkillRoot`) — в `codelab_agent_core/lib/src/skills/skill_root_entry.dart`, общие для загрузчика `codelab_agent_io` и моста: одно правило «относительный ли элемент» для чтения и для отказа `SkillsListUntrustedProject`.
- **Правило 5 только для выдачи:** `SkillsListUntrustedProject` — отказ только при `present: true` для относительного элемента недоверенного проекта. Отзыв согласия (`present: false`) разрешён: он только сужает доступ (приоритет 1).
- **Одна реализация для вида и записи.** `SkillToggle` вычисляется той же `skillsListEdit`: для навыка — `present: availability == enabled` (переключение выключит его), для согласия — `present: !granted`. `isAvailable` — результат `SkillsListPlan`, иначе `refusal` даёт подсказку D5. `toggle` навыков строит `agentExtensionsOf`, `toggle` согласия — `readAgentExtensions` по снимку вместе с кандидатом.

`fileOnly` в реестре остаётся. Страница — не общий редактор ключа, а действие предметной области: выключить навык по имени или дать согласие на каталог. Так же MCP servers пишет элементы `mcp.servers` своими правками. `/settings` CLI эти ключи по-прежнему не показывает, причина реестра остаётся верной для общих редакторов. Отклонено: сделать ключи `shared` — это добавило бы строки в `/settings` CLI без редактора списков (`SettingType.stringList` клиенты не поддерживают), вне объёма (§19).

PERM-11 (запись конфигурации агента критична для инструментов агента) к app не относится: пишет пользователь своей кнопкой, а не модель. Правило не ослабляется: страница не даёт агенту нового пути записи, а app не принимает решений от имени агента.

### D6. Состояние: `SkillsSettingsCubit`

`features/settings/application/skills_settings_cubit.dart`, по образцу `McpSettingsCubit` и `ProviderSettingsCubit` (`state-management.md`). Закрытая иерархия `SkillsSettingsState`:
- `SkillsSettingsLoading`;
- `SkillsSettingsReadOnly(RemoteReadOnly | NotManaged)` — InfoBar `skills-read-only`, файлы не читались;
- `SkillsSettingsNoFolder` — без папки (D2);
- `SkillsSettingsUnreadable(issues, configPath)` — битый конфиг, `skills-unreadable`;
- `SkillsSettingsReady(view, {saving, banner})`.

Cubit создаётся на каждое открытие страницы (`CodeLabDependencies.createSkillsSettingsCubit`, `app_scope.dart`). Страница вызывает `reload()` и закрывает Cubit. Cubit подписан на `ClientWorkspace.state`: смена профиля подключения или папки сессии в фокусе перечитывает страницу. Подписка одна, её владелец — Cubit, `close()` её отменяет (`AGENTS.md` §9).

Порт — метод существующей сессии настроек `ProviderSettingsSession` (`features/settings/application/provider_settings_session.dart`): `Future<AgentExtensionsView> extensions(AgentConfigSnapshot snapshot)`. Сессия уже открывается по доступу на каждую загрузку, держит `AgentConfigStore`, окружение агента и `CODELAB_HOME`. Второй порт и второй открыватель не нужны (`AGENTS.md` §13). Реализация — `lib/app/provider_settings_session.dart` вызовом `readAgentExtensions` моста. Имя порта не меняется (§19).

### D7. Чтение — в изоляте UI, асинхронно, с таймаутами

`readAgentExtensions` (мост, `lib/src/io/`) вызывает `loadProjectExtensions` (D3), затем `agentExtensionsOf` и возвращает вид. Работа — асинхронный ввод-вывод с пределами загрузчика: 128 КиБ на `SKILL.md`, 1000 записей на корень, 5000 записей обхода на каталог навыка, 200 навыков и таймаут фазы 5 с. Тот же объём встроенный агент уже выполняет в процессе app при каждом открытии сессии (D19 change `add-agent-skills`). Отдельный изолят (`Isolate.run`) отклонён: прироста нет, а закрыть страницу во время чтения было бы нельзя без потерянной работы изолята. Пересмотреть, если профилирование покажет рывки (`AGENTS.md` §12).

### D8. «Reload», «Open .codelab folder», «Open»

- **Reload** — `SkillsSettingsCubit.reload()`: новый снимок конфига и новое чтение файлов. На идущие сессии не влияет. Команд агенту не отправляет: перечитывания каталога без перезапуска в агенте нет (E-19).
- **Открытие** — новый порт `LocalFolderOpener` (`lib/core/platform/local_folder_opener.dart`, по образцу `ExternalLinkOpener`): `Future<FolderOpenOutcome> open(String directory)`. Реализация `UrlLauncherLocalFolderOpener` вызывает `launchUrl(Uri.directory(path))`. Порт принимает только абсолютный путь существующего **каталога**. Файлы не открываются и не запускаются: у `.md` обработчиком ОС может оказаться что угодно, а у исполняемых файлов — запуск (приоритет 1). Исключение платформы — исход `failed` без текста. Тесты подставляют `FakeLocalFolderOpener` швом `createCodeLabRootScope(localFolderOpener:)`.
- **«Open» строки** цепочки, навыка и шаблона открывает каталог, где лежит файл (решение Q5). Путь берётся только из текущего вида (`openDir`), а не из ввода.
- **«Open .codelab folder»** — `<папка проекта>/.codelab`, если каталог есть, иначе `$CODELAB_HOME` профиля (решение Q4). Подсказка кнопки называет путь.
- Отказ (`failed`, `missing`) — баннер `skills-banner` `Could not open <путь>.` и событие `skills_settings.open_failed` без пути.

API итерации 4 (по красным тестам 4.1, 4.3, 4.5):

- `FolderOpenOutcome { opened, failed, missing }`: относительный или пустой путь, `~` — `failed` без вызова платформы; нет каталога или это файл — `missing`; шов `UrlLauncherLocalFolderOpener(launch:)`.
- `SkillsSettingsCubit` — конструктор по образцу `McpSettingsCubit` (без `statusSource`, с `folderOpener`); методы `reload()`, `openCodelabFolder()`, `openFolder(String directory)`. `openCodelabFolder` диск не проверяет: просит порт открыть `<папка>/.codelab`, при `missing` — `$CODELAB_HOME`; без папки — сразу `$CODELAB_HOME`. `openFolder` принимает только каталог из текущего вида (`openDir` контекста, каталог навыка, каталог файла шаблона), остальное отвергается без вызова порта и без события.
- Состояния: `SkillsSettingsLoading`, `SkillsSettingsReadOnly(notice, hint?)`, `SkillsSettingsNoFolder`, `SkillsSettingsUnreadable(problems)`, `SkillsSettingsReady(view, userConfigPath, {banner, saving})`, `SkillsBanner(kind, text)` с `SkillsBannerKind.openFailed`. `userConfigPath` — файл слоя `user` снимка (подсказка InfoBar `skills-untrusted`).
- Перечитывание по событию рабочего пространства — только при смене профиля или папки сессии в фокусе.
- Каталог навыка — поле моста `SkillEntryView.directory` (каталог, где лежит `SKILL.md`), а не `<корень>/<имя>`: имя во frontmatter может не совпадать с каталогом. Аддитивная правка `codelab_setup` в итерации 4; построитель берёт его из `SkillFile.dir`.
- Форма путей вида. Построитель `agentExtensionsOf` (основной барель, web-безопасный) отдаёт пути в форме ядра (`/c/p` на Windows). `readAgentExtensions` (`io.dart`) переводит **все** пути диска в виде в форму хоста одним проходом через `toHostPath` (`extensionsInHostForm`, внутренний файл моста): папка, корни навыков и `overrides`, `openDir` цепочки, `directory` навыка, файл шаблона, пути кандидатов согласия, `path` диагностик (текст `message` не трогается). Переводятся только абсолютные пути. `ContextFileView.path` не переводится: это путь для промпта (`AGENTS.md`, `sub/AGENTS.md`, `$CODELAB_HOME/…`), а не путь диска. На POSIX перевод тождественен. Без него «Open» на Windows получал бы путь, которого нет (`AGENTS.md` §11).
- Порт не открывает каталоги-пакеты (ревью безопасности итерации 4). На macOS `.app`, `.workflow`, `.pkg`, `.prefPane` — каталоги, и `launchUrl` их **запускает**; на Windows каталог `name.{GUID}` открывается как объект оболочки. Порт раскрывает симлинки (`resolveSymbolicLinks`), отказывает `failed`, если у имени раскрытого каталога есть расширение или суффикс `{…}` (`.codelab` и `.agents` проходят: расширение пустое), и передаёт платформе раскрытый путь. Симлинк на файл и битый симлинк — `missing`. Каталог с точкой в имени (`pdf.tools`) тоже не откроется: плата за то, что недоверенный репозиторий не может запустить код через «Open». Подмена самого реального каталога между проверкой и вызовом платформы остаётся (TOCTOU), для неё нужен локальный процесс с правом записи.
- Состояние несёт папку и дом показанного вида: `SkillsSettingsReady(view, folder, codelabHome, userConfigPath, …)`, `SkillsSettingsNoFolder(codelabHome)`. «Open .codelab folder» берёт их из текущего состояния, а не из идущей загрузки; подсказка кнопки называет `<папка>/.codelab` и запасной `$CODELAB_HOME`, в `NoFolder` — `$CODELAB_HOME`. Каталог шаблона вычисляет Cubit: `openTemplateFolder(TemplateEntryView)`.
- Баннер `skills-banner` (заголовок `Cannot open the folder`) показывает путь экранированным (ячейка таблицы с `untrusted`). Сбой чтения профиля по умолчанию — `Unreadable` («Cannot read the agent settings.») и событие `skills_settings.unreadable {error_type}`, как в `McpSettingsCubit`.
- В итерации 4 в состоянии «только для чтения» нет Reload и «Open .codelab folder»; переключатели навыков показывают состояние, записи нет (итерация 5).
- Ключи: `skills-open-context-<n>`, `skills-open-skill-<name>`, `skills-open-template-<name>`, `skills-search-order`, `skills-template-<команда без />`. Размер файла — 1024-ичный, одна цифра после точки (`4.8 KB`).

### D9. Когда изменения действуют

Список навыков сессии — неизменный снимок открытия (SKL-4). Перечитывания без перезапуска нет (E-19). Агент перечитывает конфиг сам при изменении файла (§17.5.6), а ключи `skills.*` — ключи сессии (Q44). Поэтому запись действует **на сессии, открытые после неё**, без «Restart agent». Баннер после `ConfigSaved`: `Saved. New sessions use it; open sessions keep their skills.` Подпись раздела под таблицей — по артборду, с этой же оговоркой (D13). Подсказки «Restart agent» нет. Это не тот класс, что `restartRequiredServers`: `planConfigReload` не откладывает `skills.*`. Если реестр однажды пометит ключ `restartRequired`, баннер возьмёт признак из `ConfigSaved.restartRequiredKeys`. Правило одно — в ядре.

API итерации 5 (по красным тестам 5.1):

- `SkillsSettingsCubit.setSkillEnabled(String name, {required bool enabled})` и `setRootConsent(String entry, {required bool granted})`. Каждое действие берёт **свежий** снимок конфига в момент нажатия и само вызывает `skillsListEdit` (а не берёт `toggle` из показанного вида): между показом и нажатием файл мог измениться, а `base` плана должен быть снимком того файла, который меняется (SETUP-6).
- Пустые `edits` — без записи, баннера и события. План — `store.apply(plan.base, plan.edits)`; после `ConfigSaved` — баннер `saved` (`Saved. New sessions use it; open sessions keep their skills.`) и перечитывание; события `skill_toggled` и `root_consent` пишутся только после `ConfigSaved`.
- `SkillsBannerKind`: `openFailed`, `saved`, `conflict`, `error`. Заголовки InfoBar: `saved` — success `Saved`; `conflict` и `error` — warning `Not saved`; `openFailed` — warning `Cannot open the folder`. Текст баннера выводится экранированным (ячейка с `untrusted`): тексты отказов и сообщения загрузчика содержат пути. Конфликт и отклонение — тексты страницы Providers: `The config changed on disk, so nothing was saved. The page was reloaded; review it and try again.` (одно перечитывание, без автоповтора) и `The config was not saved: <key: message; …>`. Исключение `apply` — баннер `error` без его текста, событие `save_failed {outcome: <имя типа>}`.
- Подсказки отказов: `SkillsListNotEditable` — `Set in <файл>; edit that file.`; `SkillsListDisabledByProject` — `Disabled by the project config (<файл>).`; `SkillsListUntrustedProject` — `Trust this project to read <элемент>.`; `SkillsListLayerUnreadable` — `The config file of this layer cannot be read. Fix it first.`
- Пока идёт запись (`saving`), переключатели неактивны, остальные действия игнорируются: одна запись на нажатие; флаг снимается после перечитывания, которое следует за записью. Закрытие страницы между взятием снимка и `apply` отменяет неначатую запись. Результат записи после `close()` не применяется; перечитывание на новую папку во время записи несёт баннер записи в свежее состояние.
- Строки согласия — только для кандидатов вида: ключи `skills-consent-project` и `skills-consent-home` (вид по `~` в начале элемента), подпись `skills-consent-note-<kind>` с числом каталогов навыков (если число не посчитано — `The number of skill folders is not counted.`); вид согласия по `~` вычисляет одна функция, её используют и событие `root_consent`, и страница; подсказка отказа экранируется; `in every trusted project` — только у относительного элемента.

### D10. Наблюдаемость

Логгер `codelab_desktop.settings`, компонент `settings` (D17 change `add-app-settings-shell`). События:
- `skills_settings.loaded {access, trusted, context_files, skills, disabled, templates, warnings}` — виды и числа;
- `skills_settings.unreadable {issues}` (при исключении порта или хранилища — ещё `error_type`, имя типа) и `skills_settings.read_only {access: remote|not_managed}`;
- `skills_settings.phase_failed {phase: project_files|skills, reason: timeout|<имя типа>}`;
- `skills_settings.skill_toggled {name, enabled, layer}`, `skills_settings.root_consent {root_kind: project_relative|home, enabled, layer}`;
- `skills_settings.save_failed {outcome: conflict|rejected|inline_secret|<имя типа>}`, `skills_settings.load_discarded` (поздний результат);
- `skills_settings.open_failed {target: codelab_folder|file_dir}`.

Имя навыка допустимо: это идентификатор, ядро пишет его в `skills.loaded`. Пути, описания, тела, тексты диагностик и `toString()` исключений в журнал НЕ попадают (`observability.md`; app-settings «События журнала настроек без секретов»).

### D11. Пакеты, зависимости, сторож, граф

| Пакет | Что меняется | Слой | Метка |
|---|---|---|---|
| `codelab_agent_core` | аддитивно: типы данных `ProjectExtensions`, `PhaseOutcome` (`PhaseLoaded`, `PhaseTimedOut`, `PhaseFailed`), `SkillRootInfo` в `lib/src/project/` (D3); предикаты элементов `extra_roots` `isAbsoluteSkillRoot`, `isHomeSkillRoot`, `isRelativeSkillRoot` в `lib/src/skills/skill_root_entry.dart` (D5); экспорт бареля | core | `[agent]` |
| `codelab_agent_io` | `loadProjectExtensions` (экспорт бареля), реэкспорт типов D3 ядра; `ConfigCommands.check` — на функции | io | `[agent]` |
| `codelab_setup` | основной барель: виды D4, `agentExtensionsOf`, `skillsListEdit` (D5); `io.dart`: `readAgentExtensions` | мост | `[agent]` |
| `codelab_ui` | аддитивно: `CodeLabStatusTable` — вторая строка и теги ячейки, переключатель строки, доли колонок (D12) | ui | `[desktop]` |
| `apps/codelab_desktop` | Cubit, состояние, страница, метод сессии, `LocalFolderOpener`, сборка, `defaultSettingsPages`, ключевые слова поиска | app | `[desktop]` |

- Направление зависимостей не меняется: `codelab_desktop → codelab_setup → codelab_agent_core`, `codelab_setup (io.dart) → codelab_agent_io`. Новых рёбер нет, граф `README.md` не меняется.
- Новых зависимостей нет: `setupAllowlist`, `desktopAllowlist`, allowlist ядра (PKG-2) не меняются. Ядро меняется только аддитивно — типы данных D3 и предикаты элементов `extra_roots` D5, без новых импортов (PKG-1), правило сторожа ядра не нужно; проверка — `web-compile` ядра.
- **Новое правило сторожа не нужно.** `codelab_setup/io.dart` вне `lib/app/` и `dart:io` в `features/settings/presentation` уже запрещены (D20 change `add-provider-setup-ui`), `url_launcher` вне `core/platform/` — тоже. Основной барель моста остаётся web-безопасным, проверка — `web-compile`.
- `codelab_client_core` и `codelab_client_io` не меняются: данные агентской стороны приходят мостом, клиентского состояния ACP страница не добавляет.
- `[protocol]` и `[client]` задач нет.

### D12. Виджеты `codelab_ui`

Таблиц в пакете одна — `CodeLabStatusTable`. Новой таблицы не заводится, существующая расширяется аддитивно, без изменения поведения по умолчанию (страница MCP servers и её тесты не меняются):
- `CodeLabStatusTableCell.secondary` — вторая строка приглушённым текстом (описание навыка под именем), с ограничением двумя строками и полным текстом в подсказке;
- `CodeLabStatusTableCell.tags` — теги `CodeLabBadge` после текста («Overrides user skill», «Command only», «1 warning»);
- `CodeLabStatusTableRow.toggle` — переключатель вместо кнопки действия (`value`, `onChanged`, `null` — неактивен, подсказка причины);
- `CodeLabStatusTable.columnFlex` — веса ширины колонок (по умолчанию — равные); параметр с тем же именем и типом `List<int>?` пришёл в develop раньше (вёрстка страницы MCP servers на окне 800 pt), страница навыков переиспользует его;
- `CodeLabStatusTableCell.untrusted` — экранирование недоверенного текста (ниже).

Цепочка `AGENTS.md` и шаблоны — та же таблица с текстовыми ячейками и кнопкой «Open». Выключатели согласия и пустые состояния — существующие `CodeLabSettingsRow` и `CodeLabSettingsSection`. Превью и тесты — в `codelab_organism_previews.dart`, `codelab_previews_test.dart`, `codelab_status_table_test.dart`. Знания о навыках у виджетов нет.

Текст из файлов (имена, описания, подсказки аргументов, пути) — недоверенный. Ячейка получает признак `CodeLabStatusTableCell.untrusted`: таблица рисует такой текст через внутреннюю `escapeForDisplay` пакета (управляющие, невидимые и bidi-символы становятся видимыми; функция не экспортируется, поэтому экранирует сам виджет), только как простой текст, без markdown и ссылок. По умолчанию признак выключен — ячейки MCP servers не меняются.

API (итерация 3, по красным тестам и двойному ревью):

```dart
CodeLabStatusTableCell(text, {tone, secondary, tags = const [], untrusted = false});
CodeLabStatusTableTag(label, {tone = CodeLabTone.neutral, tooltip});
CodeLabStatusTableToggle({required value, required onChanged, required label, tooltip, key});
CodeLabStatusTableRow(cells, {action, toggle});           // строка навыка: переключатель и «Open» вместе
CodeLabStatusTable(columns, rows, {columnFlex});          // List<int>?, null — колонки равны
```

- `secondary` — не больше двух строк с многоточием, полный текст в `Tooltip`; `tags` — бейджи в `Wrap` после основного текста, у тега необязательная подсказка (тег «`<n>` warning(s)» несёт тексты предупреждений с путём `SKILL.md`).
- `untrusted` экранирует все пути вывода ячейки: `text`, `secondary` и его подсказку, подпись индикатора при `tone`, подпись и подсказку тега. Подпись и подсказка переключателя экранируются всегда (на доверенном тексте без изменений): подпись содержит имя навыка.
- `onChanged: null` — переключатель неактивен, `tooltip` объясняет причину; `label` уходит в `semanticLabel`; `key` вешается на `ToggleSwitch` (`skills-toggle-<name>`).
- `columnFlex` — положительные целые веса, как `Expanded.flex`; длину проверяет `assert` конструктора, положительность — `assert` в `build` (`every` не вычисляется в `assert` константного конструктора). Сначала тип был `List<double>`; при перебазировании на develop, где тот же параметр уже был `List<int>?`, оставлен тип develop: все вызовы передают целые веса; колонка действий остаётся фиксированной: 120 px, а если в таблице есть строка с переключателем и кнопкой одновременно — 190 px.
- `escapeForDisplay` дополнительно делает видимыми теги Unicode U+E0000–E007F (по символам, не по code unit), U+2060–U+2064, U+00AD, U+180E, U+034F и заполнители Hangul U+115F, U+1160, U+3164: через теги Unicode в описание навыка можно спрятать текст для модели.

### D13. Отступления от артборда `Extensions`

- Разделы **Hooks** и **Plugins (Dart)**, строка **System prompt override** и переключатель **Read context files of other agents** не показываются (Non-Goals, решение пользователя по объёму; Q6).
- Подпись под навыками: вместо «running sessions get an updated command list (available_commands_update)» — `The list is fixed when a session opens: new and changed skills apply to new sessions.` (D9; E-19 не реализован).
- Подпись порядка поиска строится по фактическим корням: `.codelab/skills`, затем `.agents/skills` от этой папки до корня репозитория; затем `$CODELAB_HOME/skills`, `~/.agents/skills`; extra roots — последними. Ближний перекрывает дальний (D3 change `add-agent-skills`). В артборде `~/.codelab/skills` — так подпись выглядит только при `CODELAB_HOME` по умолчанию.
- «Open» строк открывает каталог, а не файл (D8, Q5).
- Дополнительные состояния, которых нет в артборде: `skills-read-only`, `skills-untrusted`, `skills-unreadable`, «Skills are switched off», нет папки, сбой фазы.
- Цепочка `AGENTS.md` показывает `CLAUDE.md` с пометкой `used because this folder has no AGENTS.md` (E-01; Q6).

Ключи тестов: тело `settings-skills`; `skills-reload`, `skills-open-codelab`, `skills-read-only`, `skills-untrusted`, `skills-unreadable`, `skills-no-folder`, `skills-banner`, `skills-warnings`, `skills-context-<n>`, `skills-row-<name>`, `skills-toggle-<name>`, `skills-consent-<kind>`, `skills-template-<name>`. Ключевые слова поиска: `skill`, `agents.md`, `context`, `template`, `prompt`, `extension`.

### D14. Конкурентность и поздние результаты

| Операция | Владелец | Защита |
|---|---|---|
| загрузка страницы (снимок + файлы) | `SkillsSettingsCubit` | номер загрузки: результат после новой загрузки, смены доступа или папки и `close()` отбрасывается (`load_discarded`); таймауты фаз внутри D3; фаза отменяется своим `CancelToken` по таймауту |
| запись `skills.*` | `SkillsSettingsCubit` | `saving` до итога, повторные действия игнорируются; конфликт — `ConfigConflict` без автоповтора; после `ConfigSaved` — новая загрузка |
| подписка на `ClientWorkspace.state` | `SkillsSettingsCubit` | одна подписка, отмена в `close()` |
| одновременная запись app и CLI | `ConfigWriter` | блокировка и отпечаток базы (§17.5.2), проигравший — `ConfigConflict` |
| открытие каталога | `LocalFolderOpener` | без состояния; исход — баннер; повторное нажатие безопасно |

Закрытие страницы во время чтения не прерывает ввод-вывод загрузчика: поздний результат отбрасывается по номеру. Загрузчик ограничен таймаутами фаз, поэтому работа не висит дольше 5 с. Ошибки fire-and-forget не теряются: исход загрузки и записи переводится в состояние и событие (`AGENTS.md` §12).

### D15. Тесты по веткам

В `feature/*` (`AGENTS.md` §21; D22 change `add-provider-setup-ui`):
- `fvm dart test` — `codelab_agent_io` (функция D3 на временных каталогах; `config check` без изменения вывода), `codelab_setup` (построитель D4 на фейковых `SkillFiles`/`ProjectFiles`, правила D5 на снимках настоящего `FileAgentConfigStore` во временном `CODELAB_HOME`, `readAgentExtensions` на настоящих файлах, маркер `sk-test-leak-…` в теле `SKILL.md` и `AGENTS.md` не попадает в вид и `toString()`);
- `fvm flutter test` — `codelab_ui` (таблица), `codelab_desktop` (Cubit на двойнике сессии, виджет страницы на `FakeLocalFolderOpener`, без настоящей файловой системы в `testWidgets`);
- `melos run guard`, `melos run web-compile` (основной барель `codelab_setup`).

Интеграционный тест app (`integration_test/skills_settings_flow_test.dart`) в `feature/*` только компилируется (`fvm flutter analyze`), на устройстве — в `release/<version>`.

### D16. Итерации

Итерации — отдельными pull request, когда сливать — решает пользователь:
0. документы;
1. `codelab_agent_io` и мост — данные (D3, D4);
2. мост — правила записи (D5);
3. `codelab_ui` — таблица (D12);
4. app — страница только для чтения: доступ, папка, доверие, разделы, Reload, открытие папок (D2, D6–D8, D10, D13);
5. app — выключатели и согласие (D5, D9);
6. закрытие: документы, матрица и дорожная карта.

После итерации 4 страница уже целостна (только чтение), и её можно включить в `defaultSettingsPages`. Итерация 5 добавляет запись.

## Risks / Trade-offs

- **Страница и агент видят разные файлы** (известный предел): stdio-агент на другой машине через ssh-туннель, агент запущен с другим `HOME` вне `env` профиля, `--llm-script`. Страница считает, что stdio-`codelab-agent` работает на этой машине с окружением app плюс `env` профиля (D1, D2) — то же допущение, что у Providers и известного предела `add-agent-skills`. *Смягчение:* WebSocket и сторонние агенты — только для чтения; подпись источника показывает пути, по которым читала страница.
- **`profile.<name>.skills: off`** (известный предел): capability хоста страница не знает (профиль stdio-агента клиенту неизвестен). Если профиль хоста выключил навыки, страница покажет навыки, которых агент не загрузит. Встроенный профиль `embedded-app-desktop` навыки включает (D16 change `add-agent-skills`).
- **Сессии уже открыты** — выключенный навык остаётся в идущей сессии до её закрытия (SKL-4). *Смягчение:* баннер и подпись D9.
- **Согласие на относительный корень действует шире одной папки** (решение Q3): `.claude/skills` в слое `user` читается во всех доверенных проектах, где такой каталог есть. *Смягчение:* подпись переключателя говорит `in every trusted project`; недоверенные проекты его не читают (SKL-1).
- **Недоверенный текст на экране:** описания и имена навыков из `~/.agents/skills` пишут и другие агенты пользователя. *Смягчение:* ячейки `untrusted` с `escapeForDisplay` (D12), без markdown и ссылок; тела не показываются.
- **Чтение файлов в процессе app** — та же нагрузка, что открытие сессии встроенного агента (D7). *Смягчение:* пределы и таймауты загрузчика, поздний результат отбрасывается.
- **Открытие каталога** через `url_launcher` зависит от файлового менеджера ОС (Linux — `xdg-open`). *Смягчение:* исход `failed` даёт баннер, путь остаётся в подсказке.
- **Источник ключа зависит от `CoreConfig.withoutProjectValues`** (D5): `fromLayers` и внешние источники снимка (`_ExternalOrigins`) берут источник объединяемого ключа из этого поля ядра. Если ядро перестанет его заполнять, источник не определится, и цель — `user` по умолчанию: безопасно, `user` всегда редактируем, а объединение недоверенного проекта и отказ правила 4 от этого не зависят. Страж — тесты `skills_list_edit_test.dart`.
- **Гонки** (§9, §12): номер загрузки, одна подписка, `saving`, конфликт без автоповтора (D14).

## Migration Plan

1. Страница появляется в навигации после итерации 4 (`defaultSettingsPages` += `skillsAndExtensions`); до этого она скрыта, как сейчас.
2. Конфиг: новые ключи не появляются; страница пишет `skills.disabled` и `skills.extra_roots` в существующие файлы слоёв `user`/`projectLocal`.
3. `config check` выводит то же, что раньше (D3).
4. Откат — revert pull request; записанные страницей ключи остаются валидным конфигом.

## Решения пользователя 2026-11-15

Вопросы Q1–Q6 решены пользователем 2026-11-15; во всех случаях выбран вариант (а). D-решения, сценарии `specs/` и задачи приведены к ним.

- **Q1. Что показывать для внешнего агента** (WebSocket, сторонний stdio). **Решено: (а) только InfoBar `skills-read-only`, ответ пользователя.** Текст: `Read-only: this agent runs on <scheme://host:port>. Its skills, context files and prompt templates are read on that host: codelab-agent config check.`, для стороннего агента — `Skills are managed by <agentName>.`. Локальные файлы не читаются (SETUP-2), как у Providers и MCP servers (D1). Отклонены: (б) список команд сессии из `available_commands_update` без разметки «навык/шаблон» — ACP не передаёт источник команды; (в) чтение локальных файлов с пометкой «may differ» — нарушает SETUP-2.
- **Q2. Куда пишет выключатель «Enabled»** (`skills.disabled`). **Решено: (а) в `user` (`$CODELAB_HOME/config.yaml`); если список уже действует из `projectLocal` — туда (правило D5), ответ пользователя.** Навык выключается по имени во всех папках — так работает сам ключ. Отклонены: (б) по умолчанию `projectLocal` — локальный список заменил бы пользовательский; (в) вопрос «Everywhere / This project only» при каждом выключении.
- **Q3. Согласие на каталоги других агентов.** **Решено: (а) каталоги `.claude/skills` в папке проекта и `~/.claude/skills` — каждый отдельной строкой, только если каталог есть; слой — по правилу D5 (обычно `user`); подпись говорит, что согласие на относительный каталог действует во всех доверенных проектах; ответ пользователя.** Отклонены: только `.claude/skills` проекта; расширяемый список каталогов; запись в `projectLocal` с копией действующего списка.
- **Q4. «Open .codelab folder».** **Решено: (а) `<проект>/.codelab`, если каталог есть, иначе `$CODELAB_HOME` профиля; путь — в подсказке кнопки; ответ пользователя.** Отклонены: всегда `$CODELAB_HOME`; меню из двух пунктов.
- **Q5. «Open» у строки файла.** **Решено: (а) открывает каталог, где лежит файл; файл не открывается и не запускается (D8); ответ пользователя.** Отклонены: открыть файл приложением ОС (непредсказуемый обработчик, нужен белый список расширений); показать в панели Files (она ограничена папкой проекта).
- **Q6. `CLAUDE.md` и E-17.** **Решено: (а) переключателя «Read context files of other agents» нет; `CLAUDE.md` показывается в цепочке с пометкой `used because this folder has no AGENTS.md`; ответ пользователя.** Отклонено: (б) неактивная строка артборда с подписью `Not available in this version` — показывает функцию, которой нет (принцип SETUP-17).

## Open Questions

Открытых вопросов нет: Q1–Q6 решены пользователем 2026-11-15 (раздел выше).
