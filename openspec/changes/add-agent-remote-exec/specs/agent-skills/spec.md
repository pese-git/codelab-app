## MODIFIED Requirements

### Requirement: Навыки в хостах
`codelab-agent serve --stdio` и открыватели встроенного агента `codelab_embedded` (`localEmbeddedAgentOpener`, `scriptedEmbeddedAgentOpener`) SHALL передавать ядру `skillFiles` — тот же объект `ProjectFilesLoader`, что `projectFiles`, — и `hostFiles` (файловую систему процесса агента) (design.md change `add-agent-skills`, D19). Пользовательский уровень — `$CODELAB_HOME` и домашний каталог процесса (`userHomeOf` окружения хоста). Мост `codelab_embedded` получает их полями `EmbeddedHostServices.skillFiles` и `EmbeddedHostServices.hostFiles`; основной барель моста SHALL оставаться web-безопасным. `serve --stdio` и `localEmbeddedAgentOpener` SHALL передавать `agentConfigPathsFor` абсолютные и `~`-элементы `skills.extra_roots` корня запуска (capability `agent-permissions`, PERM-11).

`codelab-agent serve --ws` без `--local-exec` НЕ SHALL передавать ни `skillFiles`, ни `hostFiles`: по WebSocket навыки не читаются по той же причине, что файлы проекта (agent-binary «Файлы проекта в бинаре»). `codelab-agent serve --ws --local-exec` SHALL передавать `skillFiles` и `hostFiles` по правилам `--stdio`, включая правила `--llm-script`: файлы и команды сессии и так исполняются на машине агента, а `cwd` ограничен корнями `--workspace-root` (design.md change `add-agent-remote-exec`, D5). Команда `exec` с `cwd` в каталоге навыка (`execOnHost`) в этом режиме запускается вне корней `--workspace-root`, как и во встроенном агенте. С `--llm-script` и в сценарном открывателе пользовательский уровень (`$CODELAB_HOME/skills`, `~/.agents/skills`) НЕ SHALL читаться; навыки проекта — только доверенного проекта, как везде. Абсолютные элементы `skills.extra_roots` из `--config` у `--llm-script` SHALL читаться. У сценарного открывателя конфигурации нет: проект не доверен, `extra_roots` нет, поэтому навыков он фактически не видит — порт подключён ради одинаковой проводки (design.md change `add-agent-skills`, D19).

#### Scenario: Навык пользователя по stdio
- **WHEN** `AgentHost.build` для `--stdio` получает временный `CODELAB_HOME` с `skills/release-notes/SKILL.md` и создаёт сессию
- **THEN** `session.commands` содержит `skill:release-notes`, системный промпт содержит секцию каталога

#### Scenario: WebSocket без навыков
- **WHEN** `AgentHost.build` для `--ws` без `--local-exec` получает тот же `CODELAB_HOME`
- **THEN** `AgentCoreServices.skillFiles` и `AgentCoreServices.hostFiles` равны `null`, команд `skill:*`, секции каталога и лога `skills.loaded` нет; `read` файла из `$CODELAB_HOME/skills/release-notes` — ошибка `Path is outside the workspace: <path>`

#### Scenario: WebSocket с локальным исполнением видит навыки
- **WHEN** `AgentHost.build` для `--ws --local-exec --workspace-root <tmp>` получает тот же `CODELAB_HOME` и создаёт сессию в `<tmp>`
- **THEN** `AgentCoreServices.skillFiles` и `AgentCoreServices.hostFiles` заданы, `session.commands` содержит `skill:release-notes`, системный промпт содержит секцию каталога, `read` файла навыка возвращает его текст

#### Scenario: Сценарий модели без пользовательского уровня
- **WHEN** `AgentHost.build` для `--stdio --llm-script` получает `CODELAB_HOME` и `HOME` с навыками и `--config` с абсолютным `skills.extra_roots`, где лежит навык `extra-skill`
- **THEN** команды сессии из навыков — только `skill:extra-skill`; навыков `$CODELAB_HOME/skills`, `~/.agents/skills` и недоверенного проекта нет

#### Scenario: Встроенный агент
- **WHEN** `localEmbeddedAgentOpener` получает окружение с `CODELAB_HOME` и `HOME`, где есть навыки `$CODELAB_HOME/skills/release-notes` и `~/.agents/skills/agents-skill`
- **THEN** `available_commands_update` содержит `skill:release-notes` и `skill:agents-skill`, системный промпт — секцию каталога, `read` файла навыка возвращает его текст без `fs/read_text_file`
