## MODIFIED Requirements

### Requirement: Критические пути правок конфигурации агента
Вызовы `write` и `edit` с нормализованной целью из списка §7.6.1 SHALL быть критическими. Список: `.codelab/config.yaml`, `.codelab/config.local.yaml`, `.codelab/cli.yaml`, `.codelab/agents/**`, `.codelab/skills/**`, `.codelab/prompts/**`, `.codelab/hooks/**`.

Критическими SHALL быть и правки путей конфигурации агента, которые хост передаёт полем `AgentCoreServices.agentConfigPaths: AgentConfigPaths {paths, expansions, caseInsensitive}` (design.md change `add-config-writer-and-reload`, D8; OQ2 (а)):
- состав — файлы, которые наблюдает `ConfigWatcher`: `$CODELAB_HOME/config.yaml`, файл `--config`/`CODELAB_CONFIG`, `<корень запуска>/.codelab/config.yaml` и `config.local.yaml`, `$CODELAB_HOME/secrets.yaml`, а также каталоги `$CODELAB_HOME/agents` и `$CODELAB_HOME/prompts` с поддеревом;
- хост SHALL передавать пути абсолютными и каноническими: `~` раскрыт, символические ссылки раскрыты по самому глубокому существующему предку пути;
- `expansions` — значения `HOME` и `CODELAB_HOME` окружения хоста для раскрытия в командах `exec`; `caseInsensitive` — признак файловой системы без учёта регистра, его определяет хост;
- цель `write`/`edit` SHALL сравниваться после канонизации `BoundedEnv` (тот же результат, что для containment), без учёта регистра при `caseInsensitive`;
- каноническая форма защищаемых путей SHALL пересчитываться на каждой проверке `write`/`edit` — асинхронно в `beforeToolCall` политики тем же вызовом `ExecutionEnv`, которым `BoundedEnv` канонизирует цель для containment, — чтобы подмена каталога-предка ссылкой после старта не выводила путь из-под защиты;
- `ln` без `-s` и `cp -l`/`cp --link`, у которых защищаемый путь стоит в любой позиции (источник или цель), SHALL совпадать с критическим шаблоном: жёсткая ссылка позволила бы править защищаемый файл через другой путь;
- каталоги-предки защищаемых путей (`<корень запуска>/.codelab`, `$CODELAB_HOME`) SHALL быть защищены от создания, переименования, удаления и подмены ссылкой: `exec` с `ln`, `mv`, `rm`, `mkdir` с такой целью совпадает с критическим шаблоном;
- защита действует для сессии с любым `cwd`, в том числе вне корня запуска.

Для таких вызовов:
- вопрос задаётся в любом режиме, включая `bypass` и `accept-edits`;
- `allow_always` не предлагается;
- выданные ранее «разрешить всегда» на этот путь не действуют;
- в `autopilot` и без gate — отказ `Editing agent configuration requires a human: <path>` (PERM-11).

Команда `exec` SHALL совпадать с критическим шаблоном `write to agent configuration`, если пишет в путь из списка §7.6.1 или из `agentConfigPaths`:
- перенаправление `>`/`>>`, `tee`, `cp`, `mv`, `rename`, `ln` (в том числе `ln -sf`), `install`, `dd of=`, `sed -i`;
- путь сравнивается после раскрытия `~`, `$HOME`, `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}` и разрешения относительно `cwd` команды (включая `../`);
- команда, которая переходит в защищаемый каталог (`cd ~/.codelab && …`) и затем пишет, тоже критическая.

Чтение этих файлов не ограничено.

#### Scenario: Правка конфигурации агента
- **WHEN** в режиме `bypass` модель вызывает `edit .codelab/config.yaml`, а затем `read .codelab/config.yaml`
- **THEN** для `edit` gate получает запрос без `allow_always`, `read` исполняется без вопроса

#### Scenario: Конфигурация агента без человека
- **WHEN** gate не передан, а модель вызывает `write .codelab/agents/x.md`
- **THEN** вызов отклонён с текстом `Editing agent configuration requires a human: .codelab/agents/x.md`

#### Scenario: Глобальный конфиг в bypass и autopilot
- **WHEN** хост передал `agentConfigPaths` с `$CODELAB_HOME/config.yaml`, и модель вызывает `write ~/.codelab/config.yaml` сначала в режиме `bypass`, затем в `autopilot`
- **THEN** в `bypass` gate получает запрос без `allow_always`; в `autopilot` вызов отклонён с `Editing agent configuration requires a human` (`agent_config_paths_test.dart`)

#### Scenario: Запись через exec
- **WHEN** в режиме `bypass` модель вызывает `exec` с `echo x | tee $CODELAB_HOME/secrets.yaml`, `mv /tmp/c.yaml ~/.codelab/config.yaml`, `ln -sf /tmp/c.yaml ${HOME}/.codelab/config.yaml` или `cd ~/.codelab && echo x > config.yaml`
- **THEN** каждая команда совпадает с критическим шаблоном `write to agent configuration` и спрашивается без `allow_always`

#### Scenario: Символическая ссылка
- **WHEN** `$CODELAB_HOME/config.yaml` — символическая ссылка на `~/dotfiles/codelab.yaml`, и модель вызывает `edit ~/dotfiles/codelab.yaml`
- **THEN** вызов критический: хост передал канонический путь цели ссылки

#### Scenario: Подмена каталога ссылкой
- **WHEN** в корне запуска нет `.codelab`, модель вызывает `exec ln -s sub .codelab`, а после одобрения человеком — `write sub/config.yaml`
- **THEN** `ln -s sub .codelab` совпадает с критическим шаблоном; `write sub/config.yaml` тоже критический: пересчитанная каноническая форма `<root>/.codelab/config.yaml` — `<root>/sub/config.yaml`

#### Scenario: Жёсткая ссылка
- **WHEN** модель вызывает `exec ln ~/.codelab/config.yaml /tmp/c.yaml` или `exec cp -l ~/.codelab/config.yaml /tmp/c.yaml`
- **THEN** обе команды совпадают с критическим шаблоном `write to agent configuration`

#### Scenario: Файл --config и сессия вне корня
- **WHEN** агент запущен с `--config /etc/codelab/agent.yaml` в корне `/A`, а сессия открыта в `/B`, и модель вызывает `write /etc/codelab/agent.yaml` и `write ../A/.codelab/config.local.yaml`
- **THEN** оба вызова критические
