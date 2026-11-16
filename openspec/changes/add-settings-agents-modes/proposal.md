## Why

Страница настроек «Agents & modes» (экран 21; `dart-agent-and-clients` §12.4.9, строка «Agent | Agents & modes (21)») есть в навигации app только как значение `SettingsPage.agentsAndModes`: composition root её не показывает (SETUP-17), потому что содержимого нет. Между тем ядро уже умеет всё, что нужно первой версии страницы:

- режим новой сессии — ключ `permissions.mode` (`plan`, `ask`, `standard`, `accept-edits`, `bypass`; `autopilot` — только флаг запуска, CFG-4), с правилами доверия проекта (только ужесточение, §15.3);
- уровень рассуждения новой сессии — ключ `agent.effort` (`low`, `medium`, `high`);
- определения агентов в Markdown (R-15) — `ProjectFilesLoader` и `parseAgentDefinitions` с диагностикой; `config check` уже показывает их ошибки в терминале, а в app ошибку битого определения не видно нигде;
- встроенные типы субагентов `general`, `explore`, `review`, `plan` (change `add-subagents-and-tasks`).

Сейчас пользователь app меняет режим и effort по умолчанию только правкой `config.yaml` руками или `codelab config set`, а о битом определении агента узнаёт по его отсутствию в меню композера. Цели: P-05, P-06 (режим по умолчанию), L-16 (effort по умолчанию), R-15 (определения с ошибками загрузки), частично U-31 (список определений и встроенных; дорожная карта, экран 21: M3 — P-05, R-15; M4 — P-06).

## What Changes

- **Страница «Agents & modes»** в группе «Agent» (`settings-agents-modes`), видимая между «MCP servers» и «Skills & extensions» (change `add-app-skills-page`; design.md, D20.1); поиск по ключевым словам `mode`, `permission`, `bypass`, `plan`, `effort`, `reasoning`, `agent`, `definition`, `subagent`.
- **Default permission mode** — радиогруппа `plan` / `ask` / `standard` / `accept-edits` / `bypass` и неактивная строка `autopilot` с объяснением, что он включается только флагом запуска. Выбор `bypass` требует подтверждения в `ContentDialog` (решение пользователя 2026-11-16, Q4 (б)). Запись — `SetValue('permissions.mode')` через мост; режим вступает в силу после «Restart agent» (ключ `restartRequired`, ядро не меняется — Q2 (а)), страница это говорит.
- **Default reasoning effort** — ComboBox `low` / `medium` / `high`; запись `SetValue('agent.effort')`; применяется к новым сессиям без перезапуска (живая перезагрузка конфига).
- **Цель записи** обоих ключей — как у «Default model»: слой, где ключ определён сейчас, если он редактируемый, иначе `user`; плюс явная цель «This project only» (`projectLocal`), если известна папка проекта (Q3 (б)). Если проект не может смягчить режим (недоверенный проект), страница показывает итоговый режим и предупреждение загрузчика.
- **Agent definitions** — таблица только для чтения: строка `default` (профиль сессии без определения), встроенные типы субагентов `general` / `explore` / `review` / `plan` и определения из `$CODELAB_HOME/agents/` и `<project>/.codelab/agents/` (только доверенный проект) с колонками Name, Description, Source, Available in, Tools, Model, Status (Q6 (б)). Статусы — из диагностики загрузчика: `Available`, `Model not configured` (диагностика «модель вне каталога» — код `invalid_value` с константой текста ядра, Q7 (а), D18), `Error · line N`, `Not loaded` (повтор имени), `Shadowed by project`. Ошибка разбора — InfoBar с фиксированным текстом кода и «Open folder» (каталог, где лежит файл; файлы app не открывает, Q14 (б)). «Open folder» в шапке и «Reload». Текст из файлов выводится экранированным (D20.4).
- **Мост `codelab_setup`** — представление умолчаний сессии (`SessionDefaultsView`) в основном бареле и загрузка определений (`agentDefinitionRowsAt`) в `io.dart` поверх загрузчика файлов проекта, функции доверия `projectTrustAt` и разбора определений, общих с `config check` (D20.2); клиенты не повторяют правил ядра (SETUP-8).
- **Порт открытия каталогов** — `LocalFolderOpener` в `apps/codelab_desktop/lib/core/platform/` (из change `add-app-skills-page`), отдельно от `ExternalLinkOpener`; одна политика со страницей навыков: ссылка раскрывается, каталоги-пакеты отклоняются, файлы не открываются; порт получает создание отсутствующего `$CODELAB_HOME/agents` (Q8 (б), Q11, Q14 (б), Q15 (а); design.md, D8, D21).
- **Только чтение** для удалённого (`RemoteReadOnly`) и чужого (`NotManaged`) агента: InfoBar `agents-modes-read-only`, без таблицы и без кнопок записи (Q5 (а)).

ACP не меняется: смена режима, модели, effort и агента на одну сессию остаётся стандартными опциями сессии в композере (`session/set_config_option`, `session/set_mode`).

## Не входит

- **U-27** «Remember model per project folder» — отдельный change `add-folder-model-memory` (`dart-agent-and-clients` §12.6.9: логика в `codelab_client_core`, состояние CLI в `cli_state.json`, app — `shared_preferences`). До него переключатель на странице не показывается (Q9 (а), SETUP-17).
- **L-10** «Model roles» — в ядре `llm.roles` непрозрачен (раздел после MVP), ролей `smol`/`vision` нет; нужен change ядра.
- **E-22** «Remote A2A agents» — в ядре нет A2A-клиента, раздел `a2a` непрозрачен; после C-06 и C-17.
- **C-04** встроенные профили `architect` и `review` в опции `agent` — change ядра; сейчас только устаревший алиас `architect → plan`.
- **U-31** полностью: команда `/agents` CLI — отдельный change, может переиспользовать представление моста этого change.
- **U-30, L-34 и F.6** change `add-subagents-and-tasks` — один change `add-model-limits`: блок «Model limits override», запись `max_output_tokens` мастером и пересмотр умолчания 4096.
- Создание, правка и удаление определений агентов из app; применение «Reload» к живым сессиям (определения читаются при создании сессии).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `app-settings`: страница «Agents & modes» в навигации (изменено требование «Страницы Providers и MCP servers в навигации»), новые требования страницы, блоков режима и effort, подтверждения `bypass`, таблицы определений, открытия каталогов определений, событий журнала.
- `client-agent-setup`: умолчания новой сессии и строки определений агентов в мосте.

## Impact

- `packages/dart/codelab_agent_core` — экспорт `builtinSubagentTypes` из основного бареля; поведение не меняется.
- `packages/dart/codelab_agent_io` — `loadAgentDefinitions` для моста, общая функция доверия `projectTrustAt` (её вызывает и `loadProjectExtensions` `config check`) и общий разбор определений; вывод `config check` не меняется (D20.2).
- `packages/dart/codelab_setup` — `SessionDefaultsView`, `sessionDefaultsOf`, `AgentDefinitionRowView` (основной барель), `agentDefinitionRowsAt` (`io.dart`).
- `apps/codelab_desktop` — `features/settings/`: `AgentsModesCubit`, состояние, `AgentsModesPage`; `core/platform/local_folder_opener.dart` (параметр `create`); сборка в `lib/app/`, пять видимых страниц группы «Agent».
- `packages/flutter/codelab_ui` — переиспользование `CodeLabSettingsRow`, `CodeLabSettingsSection`, `CodeLabStatusTable`, `CodeLabForm*`, `CodeLabDialogTitle`; аддитивно `maxLines` у `CodeLabStatusIndicator` и `CodeLabStatusTableCell` (D20.4); новые виджеты — только по D9.
- Сторож: новых правил нет; правило `url_launcher` только в `core/platform/` покрывает порт `LocalFolderOpener`, его комментарий называет двух потребителей.
- ACP, фикстуры, `codelab_client_*`, CLI — без изменений.
