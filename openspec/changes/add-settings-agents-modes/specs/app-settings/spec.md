## MODIFIED Requirements

### Requirement: Страницы Providers и MCP servers в навигации
Composition root SHALL делать видимыми страницы «Connection», «Providers», «MCP servers» и «Agents & modes» группы «Agent» в порядке требования «Навигация настроек»; остальные страницы остаются скрытыми (SETUP-17). Тела страниц SHALL иметь ключи `settings-providers`, `settings-mcp` и `settings-agents-modes`. Поиск «Find a setting» SHALL находить «Providers» по ключевым словам `provider`, `model`, `api key`, `key storage`, `base url`, «MCP servers» — по `mcp`, `server`, `tools`, `headers`, а «Agents & modes» — по `mode`, `permission`, `bypass`, `plan`, `effort`, `reasoning`, `agent`, `definition`, `subagent` (design.md change `add-settings-agents-modes`, D9).

#### Scenario: Четыре страницы группы Agent
- **WHEN** пользователь открывает настройки
- **THEN** навигация показывает в группе «Agent» пункты `settings-nav-connection`, `settings-nav-providers`, `settings-nav-mcp-servers`, `settings-nav-agents-and-modes` в этом порядке, заголовка «App» нет

#### Scenario: Поиск ключа API
- **WHEN** пользователь вводит `api key` в «Find a setting»
- **THEN** в навигации остаётся «Providers»

#### Scenario: Поиск режима bypass
- **WHEN** пользователь вводит `bypass` в «Find a setting»
- **THEN** в навигации остаётся «Agents & modes», а выбор результата открывает тело `settings-agents-modes`

## ADDED Requirements

### Requirement: Страница «Agents & modes» только для чтения
Страница «Agents & modes» SHALL вычислять доступ так же, как «Providers» и «MCP servers»: `resolveSettingsAccess` для профиля текущего подключения, без подключения — для профиля по умолчанию; папка — папка сессии в фокусе, иначе выбранный проект, иначе без папки (требование «Доступ к настройкам агента на страницах Providers и MCP servers»). Смена подключения или папки SHALL перечитывать доступ и снимок, в том числе смена папки сессии в фокусе при открытых настройках без смены профиля (design.md, D11).

Для `RemoteReadOnly` и `NotManaged` страница НЕ SHALL читать локальный конфиг и файлы определений, НЕ SHALL показывать блоков режима, effort и таблицы определений и SHALL показывать InfoBar уровня `warning` `agents-modes-read-only`: `Read-only: this agent runs on <scheme://host:port>. Change its modes and agents on that host: codelab config set, .codelab/agents.` или `Agent settings are managed by <agentName>.` (решение пользователя 2026-11-16, Q5 (а)).

Если `config.yaml` не разбирается или нарушает схему (в том числе `permissions.mode: autopilot` в файле), страница SHALL показывать проблемы загрузчика с путём ключа (`agents-modes-unreadable`) и НЕ SHALL предлагать запись.

#### Scenario: WebSocket-агент
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp`, а в локальном `$CODELAB_HOME/agents/` есть `reviewer.md`
- **THEN** страница показывает InfoBar `agents-modes-read-only` с `wss://devbox:7420` без `/acp`, радиогруппы режима, effort и таблицы `agents-definitions-table` нет; локальный конфиг и `reviewer.md` не читались

#### Scenario: autopilot в файле
- **WHEN** `$CODELAB_HOME/config.yaml` содержит `permissions.mode: autopilot`, а профиль окна — встроенный агент
- **THEN** страница показывает `agents-modes-unreadable` с путём `permissions.mode` и не предлагает записи; файл не изменён

### Requirement: Режим разрешений новой сессии на странице «Agents & modes»
Блок «Default permission mode» SHALL показывать радиогруппу `plan`, `ask`, `standard`, `accept-edits`, `bypass` с выбранным итоговым режимом снимка и его источником (`agents-modes-mode-source`: `default`, `user`, `project`, `local` и т. п.) и неактивную строку `autopilot` с текстом `Only as a launch flag of the agent (codelab-agent serve --permission-mode autopilot); never saved in config.` Значение `autopilot` НЕ SHALL записываться никогда.

Выбор режима, кроме `bypass`, SHALL записывать `SetValue('permissions.mode', <id>)` одним `AgentConfigStore.apply` в цель переключателя `agents-modes-target` (требование «Цель записи на странице «Agents & modes»»). Выбор `bypass` SHALL сначала открывать `ContentDialog` `agents-modes-bypass-confirm` с заголовком `Use bypass for new sessions?` и текстом `Only critical commands, changes to the agent's configuration and network tools still ask. Commands run without asking and can reach the network too. Use bypass only in a disposable checkout.` (решение пользователя 2026-11-16, Q13 (а); design.md, D15); запись SHALL выполняться только после «Use bypass»; «Cancel» и Esc SHALL возвращать выбор к итоговому режиму без записи (решение пользователя 2026-11-16, Q4 (б)).

Подтверждение SHALL быть привязано к состоянию на момент открытия диалога: номеру загрузки и цели записи (design.md, D17). Если к «Use bypass» сменились загрузка, доступ, папка или цель, запись НЕ SHALL выполняться, а страница SHALL показывать баннер `agents-modes-banner` `Settings changed while the dialog was open; bypass was not saved.` и писать `agents_modes.save_failed` с `outcome: stale`. Если цели записи нет в снимке, запись любого режима и effort НЕ SHALL выполняться, страница SHALL показывать баннер `Cannot save: the target config file is not available.` и НЕ SHALL подменять цель на `user`.

После `ConfigSaved` с `permissions.mode` в `restartRequiredKeys` страница SHALL перечитывать снимок и строить баннер `agents-modes-banner` по действующему значению нового снимка (design.md, D16): если оно равно записанному — `Saved. New sessions use <mode> after Restart agent.`, когда агент профиля подключён, иначе `Saved. New sessions use <mode> when the agent starts.`; если оно перекрыто другим слоем или сужено недоверенным проектом — баннер уровня `warning` `Saved to <target>; <source> overrides it: new sessions use <effective>` с тем же хвостом про перезапуск. Баннер НЕ SHALL утверждать, что новые сессии получат записанное значение, если действующее от него отличается. Страница НЕ SHALL менять режим открытых сессий и НЕ SHALL отправлять агенту `session/set_mode` или `session/set_config_option` (решение пользователя 2026-11-16, Q2 (а)).

Если итог загрузки содержит предупреждение `config.project.untrusted_key` для `permissions.mode`, страница SHALL показывать InfoBar `agents-modes-mode-narrowed` уровня `warning` с итоговым режимом: `This project is not trusted, so its config can only make the mode stricter. New sessions here use <effective>.` Итог «`ask` с запретом `write` и `exec`» SHALL показываться как `ask (edits and commands blocked by plan)`.

Конфликт записи (`ConfigConflict`) SHALL давать баннер и перечитывание снимка без автоповтора (SETUP-6); пока запись идёт, повторные выборы SHALL игнорироваться.

#### Scenario: Выбор accept-edits
- **WHEN** встроенный агент подключён, `permissions.mode` нигде не задан, и пользователь выбирает `accept-edits`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `permissions.mode: accept-edits`, баннер `agents-modes-banner` содержит `after Restart agent`, источник режима — `user`; агенту не отправлено ни одного запроса

#### Scenario: Отказ от bypass
- **WHEN** пользователь выбирает `bypass` и нажимает «Cancel» в `agents-modes-bypass-confirm`
- **THEN** файл конфига не изменён, выбран прежний итоговый режим, журнал содержит `agents_modes.bypass_cancelled`

#### Scenario: Подтверждённый bypass
- **WHEN** пользователь выбирает `bypass` и нажимает «Use bypass»
- **THEN** цель записи содержит `permissions.mode: bypass`, журнал содержит `agents_modes.mode_changed` с `mode: bypass`

#### Scenario: Текст подтверждения bypass
- **WHEN** пользователь выбирает `bypass`
- **THEN** `agents-modes-bypass-confirm` содержит `Commands run without asking and can reach the network too.` и `Use bypass only in a disposable checkout.`, файл конфига ещё не изменён

#### Scenario: Смена доступа при открытом диалоге bypass
- **WHEN** диалог `agents-modes-bypass-confirm` открыт, подключение переходит на профиль `wss://devbox:7420/acp` (или папка сессии в фокусе меняется), и пользователь нажимает «Use bypass»
- **THEN** ни один файл конфига не изменён, диалог закрыт, журнал содержит `agents_modes.save_failed` с `outcome: stale`, `agents_modes.mode_changed` нет

#### Scenario: Смена цели при открытом диалоге bypass
- **WHEN** диалог открыт при цели «All projects», цель переключается на «This project only», и пользователь нажимает «Use bypass»
- **THEN** записи нет, баннер `agents-modes-banner` содержит `bypass was not saved`

#### Scenario: Нет целевого слоя
- **WHEN** цель записи «This project only», но слоя `projectLocal` этой папки нет в снимке, и пользователь выбирает `plan`
- **THEN** ни `<project>/.codelab/config.local.yaml`, ни `$CODELAB_HOME/config.yaml` не изменены, баннер содержит `Cannot save`, журнал содержит `agents_modes.save_failed` с `outcome: rejected`

#### Scenario: Перекрытое значение после записи
- **WHEN** выбран проект `/work/demo`, его `.codelab/config.local.yaml` задаёт `permissions.mode: plan`, цель — «All projects», агент подключён, и пользователь выбирает `accept-edits`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `permissions.mode: accept-edits`, баннер уровня `warning` содержит `Saved to All projects;`, `overrides it: new sessions use plan` и `after Restart agent`, но не содержит `New sessions use accept-edits`

#### Scenario: Суженное значение после записи
- **WHEN** папка проекта не в `trusted_projects`, её `config.local.yaml` задаёт `plan`, цель — «All projects», и пользователь выбирает `ask`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `permissions.mode: ask`, баннер уровня `warning` содержит `the untrusted project overrides it: new sessions use ask (edits and commands blocked by plan)`, InfoBar `agents-modes-mode-narrowed` показан

#### Scenario: Недоверенный проект не смягчает режим
- **WHEN** пользовательский слой задаёт `ask`, папка проекта не в `trusted_projects`, а `<project>/.codelab/config.local.yaml` задаёт `bypass`
- **THEN** выбран `ask`, показан `agents-modes-mode-narrowed` с `New sessions here use ask`

#### Scenario: Сочетание ask и plan
- **WHEN** пользовательский слой задаёт `ask`, а недоверенный проект — `plan`
- **THEN** итоговый режим показан как `ask (edits and commands blocked by plan)`

### Requirement: Уровень рассуждения новой сессии на странице «Agents & modes»
Блок «Default reasoning effort» SHALL показывать ComboBox `agents-modes-effort` со значениями `low`, `medium`, `high`, выбранным итоговым `agent.effort` и его источником. Выбор SHALL записывать `SetValue('agent.effort', <value>)` в цель переключателя `agents-modes-target`. После `ConfigSaved` страница SHALL перечитывать снимок; без `agent.effort` в `restartRequiredKeys` баннер SHALL быть `Saved. New sessions use <effort>.`, с ним — как у режима; если действующий effort отличается от записанного — баннер `warning` по правилу режима (design.md, D16). Подпись блока SHALL говорить, что значение отправляется опцией сессии, только если модель поддерживает рассуждение, а одну сессию меняет композер.

#### Scenario: Смена effort
- **WHEN** встроенный агент подключён и пользователь выбирает `high`
- **THEN** цель записи содержит `agent.effort: high`, баннер `Saved. New sessions use high.` без `Restart agent`

### Requirement: Цель записи на странице «Agents & modes»
Режим и effort SHALL записываться по правилу «Default model»: в слой, где ключ определён сейчас, если он редактируемый, иначе в `user` (решение пользователя 2026-11-16, Q3 (б)). Переключатель `agents-modes-target` SHALL предлагать «All projects» (`user`) и «This project only» (`projectLocal(<папка>)`); второй вариант SHALL быть только при известной папке и цели `projectLocal` у `EditableSettings`. Переключатель SHALL быть один на оба блока: выбранная цель SHALL применяться и к записи режима, и к записи effort (решение пользователя 2026-11-16, Q10 (а)). Начальное положение SHALL соответствовать редактируемому слою источника `permissions.mode`, иначе `user`. Слой `project` и файл `--config` НЕ SHALL записываться (SETUP-3).

#### Scenario: Без папки нет цели проекта
- **WHEN** проект не выбран и пользователь открывает «Agents & modes»
- **THEN** переключатель `agents-modes-target` не содержит «This project only», файлы `/.codelab/` не читаются

#### Scenario: Только этот проект
- **WHEN** выбран проект `/work/demo` и пользователь переключает цель на «This project only» и выбирает `plan`
- **THEN** `/work/demo/.codelab/config.local.yaml` содержит `permissions.mode: plan`, `$CODELAB_HOME/config.yaml` не изменён, `.codelab/config.yaml` не изменён

#### Scenario: Одна цель для режима и effort
- **WHEN** выбран проект `/work/demo`, цель переключена на «This project only», и пользователь выбирает effort `low`
- **THEN** `/work/demo/.codelab/config.local.yaml` содержит `agent.effort: low`, `$CODELAB_HOME/config.yaml` не изменён

### Requirement: Таблица определений агентов на странице «Agents & modes»
Блок «Agent definitions» SHALL показывать таблицу `agents-definitions-table` только для чтения со строками моста (spec client-agent-setup «Строки определений агентов в мосте») и колонками Name, Description, Source, Available in, Tools, Model, Status: строка `default`, встроенные типы субагентов `general`, `explore`, `review`, `plan`, затем определения из файлов (решение пользователя 2026-11-16, Q6 (б)). Статус SHALL быть тегом с текстом: `Available`, `Model not configured`, `Error · line N` или `Error`, `Not loaded: duplicate name`, `Shadowed by project`, `Overridden by <путь>`, `Subagents off`.

У строк отклонённых файлов (`Model not configured`, `Not loaded: duplicate name`, `Shadowed by project`, `Error…`) ячейки «Available in», «Tools» и «Model» SHALL быть `—`. «Model» SHALL быть `session model` у `default`, встроенных типов и рабочих определений без модели (design.md, D7, D19).

Ключ строки SHALL быть `agents-definitions-row-<name>` для первой строки имени в порядке таблицы и `agents-definitions-row-<name>#<n>` (`n` с 2) для следующих строк того же имени; разделитель `#` не встречается в именах принятых определений (`^[a-z][a-z0-9-]{0,47}Ключ строки SHALL быть `agents-definitions-row-<name>` для первой строки имени в порядке таблицы и `agents-definitions-row-<name>#<n>` (`n` с 2) для следующих строк того же имени; ; у строки отклонённого файла имя — имя файла и теоретически может содержать `#`, такой редкий конфликт ключей допустим), поэтому ключ следующей строки не совпадает с ключом другого имени; два виджета строк с одним ключом НЕ SHALL появляться (design.md, D9, D19).

Для каждого файла с диагностикой уровня `error` — прочий `error`, `Model not configured` и `duplicate` (в ядре уровень `error`) — страница SHALL показывать InfoBar `agents-definitions-error-<n>` уровня `error` с путём (`~` вместо домашнего каталога), строкой и фиксированным сообщением кода и кнопкой «Open file» (`agents-definitions-open-file-<n>`); для `duplicate` текст SHALL быть `Not loaded: another definition has the same name.` Сообщение НЕ SHALL содержать имени неизвестного ключа, значений, фрагментов файла и путей других файлов. Файл с `shadowed` (уровень `info`) НЕ SHALL получать InfoBar (design.md, D7). Недоверенный проект SHALL давать InfoBar `agents-definitions-untrusted` уровня `info`; признак — явный `projectTrusted` результата моста при известной папке, а не наличие диагностики `untrusted_project` (design.md, D19); загрузка дольше 5 с — `agents-definitions-timeout`; непредвиденная ошибка чтения — InfoBar `agents-definitions-failed` уровня `error` `Agent definitions could not be read.` без имени типа и пути (имя типа — только в журнал, design.md, D7).

«Reload» (`agents-definitions-reload`) SHALL перечитывать снимок и определения; результат прежней загрузки, пришедший после нового «Reload», смены доступа или закрытия страницы, НЕ SHALL применяться. Подпись блока SHALL говорить, что определения читаются при создании сессии, а выбор для одной сессии — в меню агента композера.

#### Scenario: Битое определение
- **WHEN** `$CODELAB_HOME/agents/migrator.md` содержит в строке 4 `tools: read` (строка вместо списка), а `reviewer.md` валиден
- **THEN** таблица содержит строку `reviewer` со статусом `Available` и строку `migrator` со статусом `Error · line 4`; InfoBar `agents-definitions-error-0` содержит `~/.codelab/agents/migrator.md` и `Open file`, но не содержит `read`

#### Scenario: Модель вне каталога
- **WHEN** `docs-writer.md` задаёт `model: openai/gpt-x`, а провайдера `openai` в конфиге нет
- **THEN** строка `docs-writer` имеет статус `Model not configured`, и для `docs-writer.md` показан InfoBar `agents-definitions-error-<n>` уровня `error` с путём и кнопкой «Open file»

#### Scenario: Определения не прочитаны
- **WHEN** загрузчик определений завершается непредвиденным исключением
- **THEN** страница показывает InfoBar `agents-definitions-failed` с текстом `Agent definitions could not be read.` без имени типа исключения и пути, блоки режима и effort доступны, журнал содержит `agents_modes.definitions_failed` с `reason: error`

#### Scenario: Встроенные типы и выключенные субагенты
- **WHEN** конфиг задаёт `subagents.enabled: false`
- **THEN** строки `general`, `explore`, `review`, `plan` с `Available in` = `subagent` видны и имеют статус `Subagents off` (решение пользователя 2026-11-16, Q12 (а)), строка `default` — `Available`

#### Scenario: Повторяющиеся имена строк
- **WHEN** `$CODELAB_HOME/agents/review.md` валиден со `scope: both`, а доверенный проект и `$CODELAB_HOME/agents` оба содержат валидный `reviewer.md`
- **THEN** встроенная строка `review` имеет ключ `agents-definitions-row-review`, строка файла `review.md` — `agents-definitions-row-review#2`; строки `reviewer` имеют ключи `agents-definitions-row-reviewer` и `agents-definitions-row-reviewer#2` в порядке таблицы; дубликатов ключей нет

#### Scenario: Ячейки отклонённого файла
- **WHEN** `docs-writer.md` задаёт `model: openai/gpt-x` и `tools: [read]`, а провайдера `openai` в конфиге нет
- **THEN** у строки `docs-writer` ячейки «Available in», «Tools» и «Model» — `—`, а не `session model` и не `read`; у строки `default` «Model» — `session model`

#### Scenario: Дубликат имени и затенённый файл
- **WHEN** `$CODELAB_HOME/agents/a.md` и `$CODELAB_HOME/agents/b.md` оба задают `name: helper`, а пользовательский `reviewer.md` затенён проектным `reviewer.md` доверенного проекта
- **THEN** для `a.md` и `b.md` показаны InfoBar `agents-definitions-error-<n>` уровня `error` с текстом `Not loaded: another definition has the same name.` и кнопкой «Open file», без пути другого файла; для пользовательского `reviewer.md` со статусом `Shadowed by project` InfoBar нет

#### Scenario: Доверие по признаку моста
- **WHEN** порт загрузки возвращает для известной папки `projectTrusted: false` без диагностики `untrusted_project` (например, при тайм-ауте чтения)
- **THEN** страница считает проект недоверенным: меню «Open folder» не содержит `This project (.codelab/agents)`

#### Scenario: Поздний результат после Reload
- **WHEN** первая загрузка определений не завершилась, пользователь нажимает «Reload», и вторая завершается раньше первой
- **THEN** таблица показывает результат второй загрузки, а поздний результат первой отброшен (`agents_modes.load_discarded`)

### Requirement: Открытие файла и каталога определений
«Open file» и «Open folder» SHALL открывать путь в приложении ОС через порт `PathOpener` (`apps/codelab_desktop/lib/core/platform/`), а не через `ExternalLinkOpener` (решение пользователя 2026-11-16, Q8 (б)). Порт SHALL получать только путь файла строки текущего состояния страницы или каталоги `$CODELAB_HOME/agents` и `<project>/.codelab/agents` (последний — только для доверенного проекта); иначе исход `notAllowed` без вызова платформы. Доверие проекта страница SHALL брать из `projectTrusted` результата моста (design.md, D19). Сам порт SHALL открывать через `open` только обычный файл с окончанием `.md`, а через `openDirectory` — только каталог, определяя вид пути без следования по символической ссылке; ссылка, файл другого вида или расширения SHALL давать `notAllowed` без вызова платформы (ревью безопасности итерации 2, design.md, D8, D19). «Open folder» SHALL быть меню из пунктов `User definitions (~/.codelab/agents)` и `This project (.codelab/agents)`. Сбой открытия (`failed`) и отказ (`notAllowed` порта или Cubit-а) SHALL давать InfoBar `agents-definitions-open-failed` `Could not open <label>.` без причины отказа (design.md, D8, D19).

Если `$CODELAB_HOME/agents` нет, «User definitions» SHALL создавать каталог (вместе с недостающими родителями) и открывать его; сбой создания — тот же InfoBar. Если `<project>/.codelab/agents` нет, пункт «This project» SHALL быть неактивен с подсказкой `Create .codelab/agents in the project to add definitions.`, и app НЕ SHALL создавать каталоги в папке проекта (решение пользователя 2026-11-16, Q11 (а) + (б)).

#### Scenario: Open file
- **WHEN** пользователь нажимает «Open file» у InfoBar битого `migrator.md`
- **THEN** порт получает путь `migrator.md` из состояния, журнал содержит `agents_modes.open_path` с `kind: file` и `outcome: opened` без пути

#### Scenario: Проект без доверия
- **WHEN** папка проекта не в `trusted_projects`
- **THEN** меню «Open folder» не содержит `This project (.codelab/agents)`

#### Scenario: Пользовательского каталога нет
- **WHEN** во временном `CODELAB_HOME` нет каталога `agents`, и пользователь выбирает «Open folder» → «User definitions»
- **THEN** каталог `$CODELAB_HOME/agents` создан и открыт, журнал содержит `agents_modes.open_path` с `kind: user_dir` и `outcome: created`

#### Scenario: Проектного каталога нет
- **WHEN** папка проекта доверенная, а `<project>/.codelab/agents` нет
- **THEN** пункт «This project (.codelab/agents)» неактивен с подсказкой `Create .codelab/agents in the project to add definitions.`, каталог в проекте не создан

#### Scenario: Ссылка вместо файла определения
- **WHEN** `$CODELAB_HOME/agents/reviewer.md` — символическая ссылка (на файл или пакет приложения), и порт получает её путь в `open`
- **THEN** исход — `notAllowed`, платформа не вызвана, журнал содержит `agents_modes.open_path` с `outcome: not_allowed` без пути

#### Scenario: Файл не определения
- **WHEN** порт получает в `open` путь обычного файла `run.command` или каталога
- **THEN** исход — `notAllowed`, платформа не вызвана

#### Scenario: Каталог-ссылка
- **WHEN** `$CODELAB_HOME/agents` — символическая ссылка на каталог, и пользователь выбирает «Open folder» → «User definitions»
- **THEN** порт возвращает `notAllowed`, платформа не вызвана, каталог по ссылке не создаётся и не открывается; страница показывает InfoBar `agents-definitions-open-failed` с текстом `Could not open ~/.codelab/agents.`

### Requirement: События журнала страницы «Agents & modes» без путей и значений
Страница SHALL писать события `agents_modes.{loaded,unreadable,load_discarded,definitions_failed,mode_changed,bypass_cancelled,effort_changed,save_failed,open_path}` в логгер `codelab_desktop.settings` с полями design.md change `add-settings-agents-modes`, D12. События НЕ SHALL содержать путей, имён файлов определений, описаний и тел определений, значений конфига, кроме `mode` и `effort`, и текстов исключений — только имя типа.

#### Scenario: Сбой записи без текста исключения
- **WHEN** запись режима завершается исключением, чей `toString()` содержит `/Users/demo/.codelab/config.yaml`
- **THEN** журнал содержит `agents_modes.save_failed` с `outcome: error` и именем типа, но не содержит `/Users/demo`
