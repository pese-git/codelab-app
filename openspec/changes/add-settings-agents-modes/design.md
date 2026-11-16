## Context

Экран 21 холста «CodeLab Desktop — Feature UI/UX» («Settings — Agents & modes») показывает семь блоков: режим разрешений по умолчанию, effort по умолчанию, «Remember model per project folder», таблицу определений агентов, роли моделей, переопределение лимитов модели и удалённые A2A-агенты. Разбор разрыва (2026-11-16):

| Блок | Цель | Ядро и конфиг | Мост, kit, app | Этот change |
|---|---|---|---|---|
| Default permission mode | P-05, P-06 | `permissions.mode` (`settings_registry.dart`, `restartRequired: true`); `autopilot` из файла — ошибка (`validate.dart`, CFG-4); проект только ужесточает (`trust.dart`, §15.3) | ничего | да |
| Default reasoning effort | L-16 | `agent.effort` (`low`/`medium`/`high`, умолчание `medium`, живое применение); опция `effort` сессии (`codelab_agent_acp/lib/src/config_options.dart`) | общий select композера | да |
| Remember model per folder | U-27 | — | — (§12.6.9, `add-folder-model-memory`) | нет |
| Agent definitions | R-15, U-31 | `ProjectFilesLoader`, `parseAgentDefinitions`, `builtinSubagentTypes`; `config check` (`config_commands.dart`) печатает диагностику | ничего; `/agents` app — панель субагентов, другая сущность | да, только чтение |
| Model roles | L-10 | `llm` непрозрачен, `agent.summary_model` не применяется | — | нет |
| Model limits override | U-30, L-34 | `providers.*.models.*.context_window`, `max_output_tokens`; источник значения `ModelInfoSource`; умолчание 4096 | мастер пишет только `context_window` (F.6) | нет, `add-model-limits` |
| Remote A2A agents | E-22 | `a2a` непрозрачен, клиента нет | — | нет |

Существующие образцы: страницы «Providers» и «MCP servers» (change `add-provider-setup-ui`, D5, D6, D10, D11, D18, D21): Cubit на каждое открытие страницы, закрытая иерархия `Loading | ReadOnly | Unreadable | Ready`, запись только через `AgentConfigStore.apply` моста, номер загрузки против поздних снимков, конфликт без автоповтора (SETUP-6), события `codelab_desktop.settings` без значений и путей. Этот change повторяет их и не вводит конкурирующего механизма (`AGENTS.md` §14).

## Goals / Non-Goals

**Goals:**
- показать страницу «Agents & modes» с блоками режима, effort и определений агентов;
- писать `permissions.mode` и `agent.effort` только через мост, с честной подсказкой о перезапуске и о сужении режима проектом;
- показать определения агентов и их ошибки тем же разбором, что у агента и `config check`.

**Non-Goals:**
- изменения ACP, ядра агента (кроме экспорта), kit клиента и CLI;
- правка определений агентов из app;
- блоки U-27, L-10, U-30/L-34, E-22 (см. proposal, «Не входит»).

## Decisions

### D1. Охват и итерации

Первый change — блоки 1, 2 и 4 (решение пользователя 2026-11-16, Q1 (а)). Итерации — отдельными PR в `develop`:
- 0 — документы;
- 1 — оболочка страницы, режим и effort;
- 2 — таблица определений, «Open file», «Open folder», «Reload»;
- 3 — ручная проверка, документы, Definition of Done.

*Альтернативы:* (б) плюс блок 6 — пересекается с F.6 change `add-subagents-and-tasks` (те же ключи, другой автор записи); (в) всё, что не заблокировано ядром, включая U-27 — новая клиентская функция трёх пакетов и CLI. Обе отклонены пользователем.

### D2. Источник правды — конфиг агента через мост

Режим и effort по умолчанию — ключи конфига агента, а не клиентские настройки app: тот же агент читает их и из CLI, и из `codelab-agent serve` (§12.4.9, колонка «Куда пишет» — `ConfigWriter`). Доступ — `resolveSettingsAccess` (spec client-agent-setup «Доступ к настройкам агента»), папка — как у «Providers»: папка сессии в фокусе, иначе выбранный проект, иначе без папки.

Смена на одну сессию — не дело страницы: композер уже шлёт стандартные опции сессии (`mode`, `effort`, `agent`; spec agent-workbench-ui «Композер показывает объявленные агентом config options»). Страница их не читает и не меняет.

*Альтернатива:* хранить умолчания в `shared_preferences` app и отправлять их опциями после `session/new` — работало бы и с чужим агентом, но расходилось бы с CLI и с агентом вне app и дублировало бы U-27. Отклонено.

### D3. Режим вступает в силу после «Restart agent»

`permissions.mode` — `restartRequired` (spec agent-configuration «Реестр настроек»: `restartRequired` истинен для `permissions.*`; правило отложенного применения — защита от смены режима посреди работы агента). Ядро не меняется (решение пользователя 2026-11-16, Q2 (а)).

После `ConfigSaved`, в `restartRequiredKeys` которого есть `permissions.mode`, страница перечитывает снимок и, если действующее значение совпадает с записанным, показывает баннер `agents-modes-banner`: `Saved. New sessions use <mode> after Restart agent.`, если агент профиля сейчас подключён (`Connected`/`Reconnecting`), иначе `Saved. New sessions use <mode> when the agent starts.` Кнопки перезапуска на странице нет: «Restart agent» живёт на странице «Connection» (одно место, D9 change `add-app-settings-shell`). Подпись блока: `New sessions start in it after Restart agent; change it for one session from the composer.` — отступление от подписи холста «New sessions start in it», которая обещала бы живое применение (D10).

`agent.effort` применяется живой перезагрузкой конфига (`config.watch`, по умолчанию включён): баннер `Saved. New sessions use <effort>.` Если запись вернула `agent.effort` в `restartRequiredKeys` (наблюдение выключено), текст — как у режима. Если после перечитывания действующее значение отличается от записанного, баннер строится по D16.

*Альтернатива:* (б) применять режим к следующей сессии живого агента — изменение ядра с отдельным ревью безопасности; отклонено пользователем.

### D4. Цель записи

Как у «Default model» (решение пользователя 2026-11-16, Q3 (б); D10 change `add-provider-setup-ui`): по умолчанию — слой, где ключ определён сейчас, если он редактируемый, иначе `user`. Над блоками режима и effort — переключатель цели `agents-modes-target`: «All projects» (`user`) и «This project only» (`projectLocal(<папка>)`). «This project only» предлагается, только если `EditableSettings` даёт цель `projectLocal` (известна папка) и `SettingDescriptor.layers` ключа содержит `projectLocal`. Переключатель один на оба блока — режим и effort (решение пользователя 2026-11-16, Q10 (а)): одна модель записи на странице. Начальное положение переключателя — слой источника `permissions.mode`, если он редактируемый, иначе `user`. Слой `project` (`.codelab/config.yaml`) и `--config` не пишутся (SETUP-3).

Правило «проект только ужесточает режим» (§15.3, spec agent-configuration «Доверие к проектному конфигу») страница не повторяет и не предсказывает (SETUP-8): показывает итоговый режим из снимка и, если загрузчик дал предупреждение `config.project.untrusted_key` для `permissions.mode`, InfoBar `agents-modes-mode-narrowed` уровня `warning`: `This project is not trusted, so its config can only make the mode stricter. New sessions here use <effective>.` Итог `ask` с запретом `write` и `exec` (сочетание `ask` и `plan`) показывается как `ask (edits and commands blocked by plan)`.

*Альтернатива:* (а) всегда `user` — проще, но расходится с «Default model» и не даёт режима «только для этого проекта». Отклонено.

### D5. Подтверждение `bypass` и строка `autopilot`

Выбор `bypass` (радиокнопка) не пишет сразу: открывается `ContentDialog` `agents-modes-bypass-confirm` (заголовок — `CodeLabDialogTitle` `Use bypass for new sessions?`, текст — дословно по D15: `Only critical commands, changes to the agent's configuration and network tools still ask. Commands run without asking and can reach the network too. Use bypass only in a disposable checkout.`, кнопки «Use bypass» и «Cancel») (решение пользователя 2026-11-16, Q4 (б); текст — Q13 (а), D15). Подтверждение привязано к состоянию страницы на момент открытия диалога (D17). «Cancel» и Esc возвращают радиогруппу к итоговому значению снимка, записи нет. Причина: запись постоянна и действует на все новые сессии во всех проектах цели — безопасность выше UX (`AGENTS.md` §2). Подтверждения других режимов нет: только `bypass` исполняет команды без вопроса; `accept-edits` разрешает без вопроса лишь правки, команды и сеть по-прежнему спрашиваются (P-06, spec agent-permissions «Режимы и уровни»).

Строка `autopilot` — неактивная радиокнопка с текстом `Only as a launch flag of the agent (codelab-agent serve --permission-mode autopilot); never saved in config.` Холст пишет «Headless only (codelab -p)», но у `codelab -p` флага `--permission-mode` нет (D10). Значение `autopilot` из файла конфига — ошибка схемы: страница в состоянии `Unreadable` (как «Providers»).

### D6. Мост: `SessionDefaultsView`

Основной барель `codelab_setup` (чистый Dart) получает:

```dart
final class SessionDefaultsView {
  final ModeChoiceView mode;      // итог, источник, сужен ли проектом
  final EffortChoiceView effort;  // итог, источник
  final ConfigLayer suggestedTarget; // слой источника режима, если редактируем, иначе user
}
SessionDefaultsView sessionDefaultsOf(AgentConfigSnapshot snapshot, EditableSettings access);
```

- итоговые значения берутся из разобранного итога `snapshot.loaded.config` (`CoreConfig`: режим и дополнительно запрещённые уровни `PermissionsConfig`, effort), а не из сырых листьев: псевдонимы (`acceptEdits`, `alwaysAsk`) и сочетание `ask`+`plan` уже разобраны ядром;
- источник — `snapshot.originOf(key)` (`ConfigSourceView`); без листа — `default` (умолчание профиля хоста: режим `standard`, effort `medium`);
- признак сужения — предупреждение `config.project.untrusted_key` с путём `permissions.mode` в `loaded.warnings`;
- сочетание `ask`+`plan` (итог `ask` с запретом `write` и `exec`) не совпадает ни с одним слоем, и снимок приписывает ему внешний источник. Источником отдаётся слой `user`, только если в листьях слоя `user` `permissions.mode` даёт `ask` (основной id или псевдоним, `ModeId.tryParse`); иначе — источник снимка как есть (`ask` из окружения или `--config` не выдаётся за `user`). Ветки по `modeOverride` (`autopilot` флагом запуска) в мосте нет: спецификация её не требует, а для клиента она недостижима — снимок строит мост в процессе клиента без флагов запуска агента, флаг `--permission-mode autopilot` есть только у процесса `codelab-agent serve` (ревью итерации 1).

Отдельного автомата или коммиттера нет: запись — одна `SetValue` в `AgentConfigStore.apply`, как «Default model» (§13 пропорциональность). Представление нужно, чтобы правила чтения итога и источника не повторялись в app и, позже, в TUI.

### D7. Мост и `codelab_agent_io`: строки определений агентов

Сейчас сборка «файлы проекта → каталог моделей → `parseAgentDefinitions` → диагностика» живёт закрытой в `ConfigCommands` (`config_commands.dart`). Чтобы app и `config check` видели одно и то же (SETUP-8), `[agent]` выносит её в публичную функцию `codelab_agent_io` без изменения вывода `config check`:

```dart
Future<AgentDefinitionsReport> loadAgentDefinitions({
  required CoreConfig config, required String? cwd, required bool projectTrusted,
  required ProjectFilesSource source, Duration timeout = const Duration(seconds: 5),
});
// AgentDefinitionsReport: definitions, diagnostics, timedOut
```

Без папки (`cwd == null`) читается только `$CODELAB_HOME/agents`; если `ProjectFilesLoader` требует `cwd`, функция добавляет узкий путь для пользовательского каталога, не меняя `ProjectFilesLoader.load` для агента. Ядро экспортирует `builtinSubagentTypes()` из основного бареля (поведение не меняется).

Мост:
- основной барель — `AgentDefinitionRowView` и чистая `agentDefinitionRowsOf(report-данные, builtins, subagentsEnabled)`: строки, колонки и статус;
- `io.dart` — `agentDefinitionRowsAt({snapshot, access, env})`: строит `ProjectFilesLoader` для дома и окружения агента, вызывает `loadAgentDefinitions` и `agentDefinitionRowsOf`.

Строки (решение пользователя 2026-11-16, Q6 (б)):

| Строка | Source | Available in | Tools | Model | Status |
|---|---|---|---|---|---|
| `default` | `built-in` | `session` | `all` | `session model` | `Available` |
| `general`, `explore`, `review`, `plan` | `built-in` | `subagent` | из определения (`all`, если `tools == null`) | `session model` | `Available`; `Overridden by <путь>` при определении с тем же именем и `scope` `subagent`/`both`; `Subagents off` при `subagents.enabled: false` (решение пользователя 2026-11-16, Q12 (а)) |
| файл, прошедший проверку | путь с `~` вместо дома (`homePathLabel`) | `session`, `subagent` или `both` (`scope`) | список или `all` | `<provider>/<model>` или `session model` | `Available` |
| файл с диагностикой `error` кода `model` | путь | — | — | — | `Model not configured` (решение пользователя 2026-11-16, Q7 (а)) |
| файл с другой диагностикой `error` | путь | — | — | — | `Error · line N` (без строки — `Error`) |
| файл с `duplicate` | путь | — | — | — | `Not loaded: duplicate name` |
| пользовательский файл с `shadowed` | путь | — | — | — | `Shadowed by project` |

Имя строки файла, не прошедшего проверку, — имя файла без `.md`: разбор ядра не отдаёт имя отклонённого определения, спецификация `agent-definitions` не меняется (Q7 (а)). Описание и тело файла в строку не попадают, кроме `description` прошедшего проверку определения (как в опции `agent`). Сообщения ошибок — фиксированные тексты кодов (D14 change `add-agent-project-files`): ни ключа, ни фрагмента файла.

Недоверенный проект: диагностика `untrusted_project` даёт InfoBar `agents-definitions-untrusted` уровня `info`: `Definitions in <project>/.codelab/agents are not read: the project is not trusted.` Тайм-аут загрузки — InfoBar `agents-definitions-timeout`: `Agent definitions were not read within 5 s.`; непредвиденное исключение — `Agent definitions could not be read.` (имя типа — только в журнал).

*Альтернатива:* строить строки в app из событий `agents.loaded` живой сессии — только у встроенного агента, без ошибок разбора и только при открытой сессии. Отклонено.

### D8. Порт открытия пути `PathOpener`

`apps/codelab_desktop/lib/core/platform/path_opener.dart` (решение пользователя 2026-11-16, Q8 (б)):

```dart
enum PathOpenOutcome { opened, created, failed, notAllowed }
abstract interface class PathOpener {
  Future<PathOpenOutcome> open(String path);
  Future<PathOpenOutcome> openDirectory(String path, {bool create = false});
}
final class UrlLauncherPathOpener implements PathOpener { … } // launchUrl(Uri.file(path)); create — Directory.create(recursive: true)
```

`ExternalLinkOpener` не расширяется схемой `file:`: его политика — ссылки из ответа агента (DSK-7), а путь из настроек — другой источник; общая политика ослабила бы первую. Cubit страницы передаёт в порт только пути из своего текущего состояния: файл строки определения и каталоги `$CODELAB_HOME/agents` и `<project>/.codelab/agents` (последний — только для доверенного проекта); иначе — `notAllowed` без вызова платформы. `url_launcher` по-прежнему импортируется только в `core/platform/` (правило сторожа есть, меняется его комментарий). Исход `failed` — InfoBar `agents-definitions-open-failed`: `Could not open <label>.`

«Open folder» — `DropDownButton` с пунктами `User definitions (~/.codelab/agents)` и `This project (.codelab/agents)`; второй — только при доверенной папке проекта. Отсутствующий каталог (решение пользователя 2026-11-16, Q11 (а) + (б)):
- `$CODELAB_HOME/agents` — Cubit вызывает `openDirectory(path, create: true)`: порт создаёт каталог (`recursive`) и открывает его, исход `created`; сбой создания — `failed` и тот же InfoBar. Создание каталога в доме безвредно и нужно, чтобы положить туда первое определение;
- `<project>/.codelab/agents` — пункт неактивен с подсказкой `Create .codelab/agents in the project to add definitions.`; app без явной просьбы ничего не создаёт в рабочем дереве проекта. `create: true` для проектного каталога Cubit не передаёт никогда.

Существует ли каталог, сообщает строка состояния моста (`agentDefinitionRowsAt` возвращает признаки наличия обоих каталогов), а не проверка в виджете.

### D9. Разметка, ключи и виджеты

Порядок блоков: шапка (`Agents & modes`, «Open folder», «Reload»), «Default permission mode», «Default reasoning effort», «Agent definitions». Блоков «Remember model per project folder», «Model roles», «Model limits override», «Remote A2A agents» нет (SETUP-17; Q9 (а)).

Ключи тестов: тело `settings-agents-modes`; `agents-modes-target`, `agents-modes-mode-<id>` (`plan`, `ask`, `standard`, `accept-edits`, `bypass`, `autopilot`), `agents-modes-mode-source`, `agents-modes-mode-narrowed`, `agents-modes-bypass-confirm`, `agents-modes-effort`, `agents-modes-banner`, `agents-modes-read-only`, `agents-modes-unreadable`; `agents-definitions-table`, `agents-definitions-row-<name>`, `agents-definitions-error-<n>`, `agents-definitions-open-file-<n>`, `agents-definitions-open-folder`, `agents-definitions-reload`, `agents-definitions-untrusted`, `agents-definitions-timeout`, `agents-definitions-open-failed`.

Виджеты `codelab_ui` переиспользуются: `CodeLabSettingsSection`, `CodeLabSettingsRow`, `CodeLabForm*` (радио), `CodeLabStatusTable` (таблица определений: колонки и ячейки — готовые строки, виджет не знает `AgentDefinitionRowView`), `CodeLabBadge` (статус с текстом рядом со значком, `CodeLabTone`), `CodeLabDialogTitle`. Новый виджет — только если радио с подписью под вариантом не собирается из `CodeLabForm*` и встречается второй раз (правило атома, `codelab_ui/AGENTS.md` §3). Тон статуса решает app: `Available` — `success`, `Model not configured`, `Shadowed by project`, `Overridden by …`, `Subagents off` — `warning`, `Error`, `Not loaded` — `danger`.

### D10. Отступления от холста

| Холст | Решение | Причина |
|---|---|---|
| «New sessions start in it» | `New sessions start in it after Restart agent; …` | D3, Q2 (а) |
| `autopilot`: «Headless only (codelab -p)» | `Only as a launch flag of the agent (codelab-agent serve --permission-mode autopilot); never saved in config.` | у `codelab -p` флага нет |
| строки `architect`, `review` как профили сессии | `general`, `explore`, `review`, `plan` с колонкой «Available in: subagent» | C-04 не реализован; Q6 (б) |
| «Open folder» одной кнопкой | меню из двух каталогов | у определений два каталога (D8) |
| «Remember model per project folder», «Model roles», «Model limits override», «Remote A2A agents» | не показываются | SETUP-17; U-27, L-10, U-30, E-22 вне change |
| «same list as /agents in the CLI» | подпись без ссылки на `/agents` | команды CLI ещё нет (U-31 вне change) |

HTML и CSS холста в репозиторий не копируются; разметка собирается из виджетов кита.

### D11. Конкурентность и поздние результаты

| Операция | Владелец | Защита |
|---|---|---|
| снимок конфига и строки определений | `AgentsModesCubit` | один номер загрузки на пару «снимок + определения»: поздний результат после «Reload», смены подключения или папки, `close()` отбрасывается (`agents_modes.load_discarded`) |
| загрузка определений | функция моста | тайм-аут 5 с и отмена `CancelTokenSource` при новой загрузке и `close()` (как `config check`) |
| запись режима или effort | `AgentsModesCubit` | флаг `Ready.saving`: повторные выборы и «Reload» игнорируются до итога; конфликт — баннер и перечитывание без автоповтора (SETUP-6); после `close()` итог только в журнал |
| диалог `bypass` | страница и `AgentsModesCubit` | запись начинается после «Use bypass» и только если токен подтверждения (номер загрузки + цель) ещё действителен (D17); закрытие страницы закрывает диалог без записи |
| «Open file» / «Open folder» | порт | путь сверяется с текущим состоянием Cubit-а в момент клика; исход — только InfoBar, без повторов |

Папка страницы — папка сессии в фокусе, иначе выбранный проект (D2). Фокус может перейти на сессию другой папки при открытых настройках без смены профиля и подключения; страница ДОЛЖНА следить и за папкой фокуса, а не только за подключением: смена папки — новый номер загрузки, перечитывание доступа и снимка (`agents_modes.load_discarded` с `reason: access_changed` для прежней загрузки) и недействительный токен открытого диалога `bypass` (D17). Иначе цель «This project only» и подтверждение могли бы относиться к папке, которой уже нет в фокусе (ревью итерации 1).

Ошибки fire-and-forget (загрузка, открытие пути) переводятся в состояние и событие журнала (`AGENTS.md` §12).

### D12. Наблюдаемость

Логгер `codelab_desktop.settings`, компонент `settings`:

| Событие | Уровень | Поля |
|---|---|---|
| `agents_modes.loaded` | debug | `access: editable \| remote \| not_managed`, `definitions` (число строк файлов), `errors` (число) |
| `agents_modes.unreadable` | warning | `error_type` |
| `agents_modes.load_discarded` | debug | `reason: reload \| access_changed \| closed` |
| `agents_modes.definitions_failed` | warning | `reason: timeout \| error`, `error_type?` |
| `agents_modes.mode_changed` | info | `mode`, `target: user \| local` |
| `agents_modes.bypass_cancelled` | info | — |
| `agents_modes.effort_changed` | info | `effort`, `target` |
| `agents_modes.save_failed` | warning | `key: mode \| effort`, `outcome: conflict \| rejected \| stale \| error`, `error_type?` (`stale` — D17) |
| `agents_modes.open_path` | info | `kind: file \| user_dir \| project_dir`, `outcome: opened \| created \| failed \| not_allowed` |

Пути, имена файлов определений, описания, тела и тексты исключений в события не попадают (§16; D14 change `add-agent-project-files`).

### D13. Пакеты, зависимости, сторож и граф

| Пакет | Что меняется | Слой |
|---|---|---|
| `codelab_agent_core` | экспорт `builtinSubagentTypes` | core |
| `codelab_agent_io` | `loadAgentDefinitions`, `AgentDefinitionsReport`; `ConfigCommands.check` на ней | io |
| `codelab_setup` | `SessionDefaultsView`, `sessionDefaultsOf`, `AgentDefinitionRowView`, `agentDefinitionRowsOf` (основной барель); `agentDefinitionRowsAt` (`io.dart`); show-списки реэкспорта | мост |
| `apps/codelab_desktop` | `features/settings/`: `AgentsModesCubit`, `AgentsModesState`, `AgentsModesPage`; `core/platform/path_opener.dart`; `lib/app/`: сборка сессии страницы, `defaultSettingsPages`, `settingsPageBuilders`, поиск | app |

Новых рёбер зависимостей нет (`codelab_desktop → codelab_setup → codelab_agent_core`, `codelab_setup/io.dart → codelab_agent_io` уже есть); граф в `README.md` не меняется. Новых правил сторожа нет: `codelab_setup/io.dart` только в `lib/app/`, `dart:io` запрещён в `features/settings/presentation`, `url_launcher` — только в `core/platform/` (правила уже есть). Allowlist ядра (PKG-2) не меняется. Основной барель `codelab_setup` остаётся web-безопасным (`web-compile`). Исполнитель задач моста — `[agent]`, как в change `add-provider-setup-ui` (D2).

### D14. Тесты по веткам

В `feature/*`: `fvm dart test` — `codelab_agent_core`, `codelab_agent_io`, `codelab_setup`; `fvm flutter test` — `codelab_desktop`, при новом виджете — `codelab_ui`; `melos run guard`, `melos run web-compile`. Интеграционный тест app `integration_test/agents_modes_settings_flow_test.dart` во временном `CODELAB_HOME` в `feature/*` только компилируется (`fvm flutter analyze`); на устройстве — в `release/<version>` (`AGENTS.md` §21).

### D15. Текст подтверждения `bypass` и руководства — точно и с предупреждением

Решение пользователя 2026-11-16, Q13 (а), по итогам ревью безопасности итерации 1. Прежний текст D5 («Tools run without asking, except critical command patterns, edits of the agent config in the project and network access») был неточен в двух местах:
- по spec agent-permissions «Режимы и уровни» в `bypass` спрашивается только уровень `network` (`codelab_agent_core/lib/src/permissions/modes.dart`, `bypass` → `PermissionMode.yolo`); это уровень сетевых *инструментов*, а `exec curl …` — уровень `exec` и идёт без вопроса. Фраза «network access» обещала защиту, которой нет;
- защита правок конфигурации агента (PERM-11, spec agent-permissions: вопрос «в любом режиме, включая `bypass`») покрывает и проект, и `$CODELAB_HOME` (`agentConfigPathsFor`), а не только «config in the project».

Текст диалога `agents-modes-bypass-confirm` (англ., дословно):

> Only critical commands, changes to the agent's configuration and network tools still ask. Commands run without asking and can reach the network too. Use bypass only in a disposable checkout.

Раздел «Agents & modes» руководства пользователя (`apps/codelab_desktop/doc/user-guide.md`, задача 3.2) описывает `bypass` той же семантикой: спрашиваются только критические команды, правки конфигурации агента (проект и `$CODELAB_HOME`) и сетевые инструменты; команды, в том числе сетевые, идут без вопроса; только в одноразовой копии. Страница семантику режима не вычисляет — текст фиксированный и меняется вместе со spec agent-permissions.

*Альтернатива:* (б) короткий текст без перечисления («Most tools run without asking») — не врёт, но не предупреждает о сети через команды. Отклонено пользователем.

### D16. Баннер «Saved» — по действующему значению после перечитывания

Ревью архитектуры итерации 1 (MEDIUM): запись в слой `user` не гарантирует, что новые сессии получат записанное значение — его может перекрыть слой выше (`projectLocal`, `project` доверенного проекта, окружение, `--config`) или сузить недоверенный проект (D4). Баннер «Saved. New sessions use <value>…» в таком случае обманывал бы.

Правило: после `ConfigSaved` страница перечитывает снимок (как при конфликте) и строит баннер по `sessionDefaultsOf` нового снимка:
- действующее значение равно записанному — тексты D3 (`Saved. New sessions use <value> after Restart agent.` / `… when the agent starts.` / `Saved. New sessions use <effort>.`);
- значение перекрыто другим слоем (источник действующего значения ≠ цель записи) — уровень `warning`: `Saved to <target>; <source> overrides it: new sessions use <effective>` и хвост по D3 (` after Restart agent.` / ` when the agent starts.` / `.`). `<target>` — `All projects` или `This project only`; `<source>` — подпись источника, как у `agents-modes-mode-source`;
- значение сужено недоверенным проектом (признак `narrowedByProject`) — тот же `warning` с `<source>` = `the untrusted project` и `<effective>` в виде D4 (`ask (edits and commands blocked by plan)` для сочетания); InfoBar `agents-modes-mode-narrowed` остаётся.

Сравнение — по основным id из моста (`ModeChoiceView.id`, `EffortChoiceView.id`), без своего разбора слоёв (SETUP-8). Если перечитывание не удалось, баннер — `Saved to <target>.` без утверждения о новых сессиях, а состояние — по общим правилам (`Unreadable`). Событие `agents_modes.mode_changed`/`effort_changed` пишется по факту записи, как раньше; новых полей журнала нет.

*Альтернатива:* предупреждать до записи, предсказывая перекрытие, — повтор правил слоёв в app (SETUP-8). Отклонено.

### D17. Подтверждение `bypass` привязано к состоянию на момент открытия

Ревью безопасности итерации 1 (MEDIUM): между открытием `agents-modes-bypass-confirm` и «Use bypass» могут смениться подключение, папка (D11), доступ (`RemoteReadOnly`, `NotManaged`) или цель переключателя; запись `bypass` по новому состоянию была бы согласием, которого пользователь не давал.

Правило: при открытии диалога Cubit выдаёт токен подтверждения — номер загрузки и цель записи (`ConfigLayer` и папка `projectLocal`). «Use bypass» передаёт токен обратно; запись выполняется, только если состояние — `Ready` с тем же номером загрузки и той же целью и не идёт другая запись. Иначе записи нет, диалог закрывается, баннер `agents-modes-banner` уровня `warning`: `Settings changed while the dialog was open; bypass was not saved.`, событие `agents_modes.save_failed` с `key: mode`, `outcome: stale` (дополнение D12). Смена доступа на `ReadOnly`/`Unreadable` при открытом диалоге закрывает его без записи.

Нет целевого слоя (LOW): если цель записи (`user` или `projectLocal(<папка>)`) отсутствует в снимке (`EditableSettings` её не даёт, путь не разрешён), запись не выполняется для любого режима и для effort — баннер уровня `error` `Cannot save: the target config file is not available.`, событие `agents_modes.save_failed` с `outcome: rejected`. Молчаливой подмены цели на `user` нет: пользователь выбрал «This project only», и запись во все проекты расширила бы действие (особенно для `bypass`).

*Альтернатива:* перечитывать снимок при «Use bypass» и писать по свежему состоянию — тот же разрыв согласия. Отклонено.

## Risks / Trade-offs

- [Пользователь ждёт, что новый режим действует сразу] → подпись блока и баннер называют «Restart agent» (D3).
- [`bypass` по ошибке] → подтверждение (D5) с точным текстом (D15), привязанное к состоянию открытия (D17); подтверждение не защищает от правки файла руками, это вне страницы.
- [Записанное значение перекрыто или сужено] → баннер по действующему значению после перечитывания (D16).
- [Недоверенный проект не может смягчить режим] → итоговый режим и InfoBar по предупреждению загрузчика (D4), без своей копии правила.
- [Строка отклонённого файла без имени определения] → имя файла (D7, Q7 (а)); при необходимости — отдельный change `agent-definitions`.
- [Расхождение с агентом из-за другого каталога моделей] → тот же `StaticModelCatalog` конфига, что у `config check`; каталог `/models` провайдера (`list_models`) агент тоже не использует для проверки определения.
- [Открытие пути] → только пути из состояния (D8); symlink файла определения открывается как есть — содержимое не читается app.

## Migration Plan

Миграции данных нет: ключи конфига уже существуют. Откат — скрыть страницу из `defaultSettingsPages`.

## Решения пользователя 2026-11-16

- Q1 (а) — первый change: блоки 1, 2, 4 (D1).
- Q2 (а) — режим вступает в силу после «Restart agent», ядро не меняется (D3).
- Q3 (б) — цель записи как у «Default model» плюс «This project only» (D4).
- Q4 (б) — `ContentDialog` подтверждения перед записью `bypass` (D5).
- Q5 (а) — для удалённого и чужого агента InfoBar только для чтения, без таблицы (spec app-settings «Страница «Agents & modes» только для чтения»).
- Q6 (б) — таблица: `default`, встроенные типы субагентов с колонкой «Available in», файлы (D7).
- Q7 (а) — строка файла по диагностике `model`, без изменения `agent-definitions` (D7).
- Q8 (б) — новый узкий порт открытия пути в `core/platform` (D8).
- Q9 (а) — U-27 на странице не показывается (D9).
- Q10 (а) — один переключатель «This project only» на режим и effort (D4).
- Q11 (а) + (б) — отсутствующий `$CODELAB_HOME/agents` создаётся и открывается; отсутствующий проектный `.codelab/agents` — пункт неактивен с подсказкой (D8).
- Q12 (а) — встроенные типы субагентов при `subagents.enabled: false` показываются со статусом `Subagents off` (D7).
- Q13 (а) — текст подтверждения `bypass` и руководства — точно и с предупреждением о командах и сети (D15; ревью итерации 1).

Ревью итерации 1 (безопасность и архитектура) без вопросов пользователю: баннер по действующему значению (D16), токен подтверждения `bypass` и запрет подмены цели (D17), перечитывание при смене папки фокуса (D11), источник `ask`+`plan` и отказ от ветки `modeOverride` в мосте (D6).

## Open Questions

Нет: Q1–Q13 решены пользователем 2026-11-16 (раздел выше).
