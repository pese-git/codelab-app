## MODIFIED Requirements

### Requirement: Критические пути правок конфигурации агента
Вызовы `write` и `edit` с нормализованной целью из списка §7.6.1 SHALL быть критическими. Список: `.codelab/config.yaml`, `.codelab/config.local.yaml`, `.codelab/cli.yaml`, `.codelab/agents/**`, `.codelab/skills/**`, `.codelab/prompts/**`, `.codelab/hooks/**`.

Критическими SHALL быть и правки путей конфигурации агента, которые хост передаёт полем `AgentCoreServices.agentConfigPaths: AgentConfigPaths {paths, expansions, caseInsensitive}` (design.md change `add-config-writer-and-reload`, D8; OQ2 (а)):
- состав — файлы, которые наблюдает `ConfigWatcher`: `$CODELAB_HOME/config.yaml`, файл `--config`/`CODELAB_CONFIG`, `<корень запуска>/.codelab/config.yaml` и `config.local.yaml`; `$CODELAB_HOME/secrets.yaml` — при любом `secrets.backend`, хотя наблюдатель следит за ним только при `file` (R5-1); а также каталоги `$CODELAB_HOME/agents` и `$CODELAB_HOME/prompts` с поддеревом;
- хост SHALL передавать пути абсолютными и каноническими: `~` раскрыт, символические ссылки раскрыты по самому глубокому существующему предку пути;
- `expansions` — значения `HOME` и `CODELAB_HOME` окружения хоста для раскрытия в командах `exec`; `caseInsensitive` — признак файловой системы без учёта регистра, его определяет хост;
- цель `write`/`edit` SHALL сравниваться после канонизации `BoundedEnv` (тот же результат, что для containment), без учёта регистра при `caseInsensitive`;
- каноническая форма защищаемых путей SHALL пересчитываться на каждой проверке `write`/`edit` — асинхронно в `beforeToolCall` политики тем же вызовом `ExecutionEnv`, которым `BoundedEnv` канонизирует цель для containment, — чтобы подмена каталога-предка ссылкой после старта не выводила путь из-под защиты;
- резолвер путей политики (пересчёт защищаемых путей и второй проход `exec`) SHALL быть окружением сессии, только если оно реализует `PathResolver`, иначе — окружением хоста `AgentCoreServices.baseEnv`: у сессий `serve` окружение — клиент ACP, который ссылок не раскрывает, а защищаемые пути — пути хоста (для `--ws` клиент на loopback, та же машина);
- `ln` без `-s` и `cp -l`/`cp --link`, у которых защищаемый путь стоит в любой позиции (источник или цель), SHALL совпадать с критическим шаблоном: жёсткая ссылка позволила бы править защищаемый файл через другой путь;
- каталоги-предки защищаемых путей SHALL быть защищены от создания, переименования, удаления и подмены ссылкой; каталогом-предком считается любой предок каждой формы защищаемого пути, кроме `/`. Предки делятся на два вида (R5-4):
  - **широкий предок** — корень запуска, `cwd` сессии, `~` и любой их предок. Команда с ним критична, только если разрушает, перемещает или подменяет сам этот каталог: `rm`, `rmdir`, `mkdir` с ним — всегда; `mv`/`ln` с ним в роли источника — всегда; `mv`/`ln` с ним в роли назначения — пока этого каталога нет на диске (в существующий каталог файл кладётся внутрь, и такую запись ловит сравнение пути `<каталог>/<имя>` с защищаемыми). Прочие команды с широким предком в аргументах (`make`, `cp -r src dst`, `mv a .`) по этому правилу НЕ SHALL быть критическими; исключения — распаковка архива и `rsync` с назначением в широком предке, патчи и git-подкоманды, стирающие дерево (ниже);
  - **близкий предок** — остальные предки: `<корень сессии или запуска>/.codelab`, `$CODELAB_HOME`, каталог файла `--config` и предки между ними и широкими предками. Близкий предок в аргументах — то же, что защищаемый путь: критична любая команда не из белого списка чтения (ниже);
- обычные операции, не затрагивающие предков и защищаемые пути (`rm -rf build`, `mkdir -p src/x`, `mv a b`, `mv a .`), SHALL NOT быть критическими;
- символическая ссылка НА защищаемый файл из другого места (`ln -s ~/.codelab/config.yaml /tmp/x`) критична по белому списку чтения (R5-4): `ln` не читает, а защищаемый путь — его аргумент. Запись по уже существующей ссылке SHALL быть критической по канонизации цели: `write`/`edit` — канонизацией `BoundedEnv`, `exec` — канонизацией проверенных путей команды через резолвер путей политики, если ссылка и её цель существуют;
- защита действует для сессии с любым `cwd`, в том числе вне корня запуска.

Для таких вызовов:
- вопрос задаётся в любом режиме, включая `bypass` и `accept-edits`;
- `allow_always` не предлагается;
- выданные ранее «разрешить всегда» на этот путь не действуют;
- в `autopilot` и без gate — отказ `Editing agent configuration requires a human: <path>` (PERM-11).

Команда `exec` SHALL совпадать с критическим шаблоном `write to agent configuration` по правилу белого списка чтения (R5-4, решение пользователя 2026-11-03):
- разбор SHALL охватывать каждую простую команду строки: в цепочках (`&&`, `||`, `;`), в конвейерах (`|`), внутри `sh -c`/`bash -c`, после `env` (в том числе `env -C DIR`) и после `cd DIR` — `DIR` становится рабочим каталогом следующих команд цепочки;
- у простой команды проверяются слова-аргументы и значения опций (`-o FILE`, `-C DIR`, `--output=FILE`, `-d DIR`, `of=FILE`), а также рабочий каталог, заданный `cd`, `env -C` или `-C DIR`. Путь сравнивается после раскрытия `~`, `$HOME`, `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}` (значения — из `expansions`) и разрешения относительно рабочего каталога команды (включая `../`);
- если хотя бы одно такое значение разрешается в защищаемый путь, путь внутри защищаемого каталога или близкий каталог-предок, команда SHALL быть критической, кроме команд только чтения: `cat`, `less`, `more`, `head`, `tail`, `grep`/`egrep`/`fgrep`, `rg`, `ag`, `ls`, `stat`, `file`, `wc`, `diff`, `cmp`, `sha256sum`/`shasum`/`md5sum`, `jq`/`yq`, `git diff|log|show|status|blame`, `test`/`[`, `realpath`, `readlink`, `dirname`, `basename`, `echo`/`printf`;
- исключение белого списка SHALL NOT действовать при опциях записи и исполнения — такая команда проверяется как любая команда не из списка: `jq`/`yq` с `-i`, `--in-place*`, `--inplace*`, `-s` или `--split-exp`; `rg`/`ag` с `--pre`, `--pre-glob`, `--search-zip` (`-z`); `less` с `-o`, `-O`, `--log-file`; `file` с `-C`, `--compile`; `git` с глобальными опциями `-c`, `--config-env`, `--exec-path`, `--git-dir`, `--work-tree`; `git diff` с `--output`, `--ext-diff`, `--textconv`;
- значение опции, которое программа исполняет как команду, SHALL разбираться как вложенный текст команды, как строка `sh -c`: `git -c` с ключами `core.pager`, `core.fsmonitor`, `core.sshCommand`, `core.editor`, `core.askpass`, `core.gitProxy`, `interactive.diffFilter`, `diff.external`, `diff.<драйвер>.textconv|command`, `sequence.editor`, `alias.<имя>=!…`, `credential.helper`, `gpg.*program`, `merge.<драйвер>.driver`, `filter.<имя>.clean|smudge|process`, `pager.<команда>`, `web.browser`, `difftool|mergetool|browser.<имя>.cmd`, `receive.procReceive`; `rg --pre`; `find -exec`, `-execdir`, `-ok`, `-okdir`; строка команды `watch` и `script -c`;
- значение переменной окружения с командой (`GIT_PAGER`, `PAGER`, `GIT_EXTERNAL_DIFF`, `GIT_EDITOR`, `EDITOR`, `VISUAL`, `GIT_SEQUENCE_EDITOR`, `GIT_SSH_COMMAND`, `GIT_SSH`, `GIT_ASKPASS`, `SSH_ASKPASS`, `LESSOPEN`, `LESSCLOSE`) SHALL разбираться так же, если переменная задана префиксным присваиванием, `env NAME=…` или `export|declare|typeset|readonly|local NAME=…` (последние — для следующих команд цепочки);
- критическими всегда SHALL быть: `git --config-env`; `git -c` с `core.hooksPath`, `include.path`, `includeIf.*`; сегмент, где те же формы присваивания задают `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>`, `GIT_CONFIG_VALUE_<n>`, `GIT_CONFIG_PARAMETERS`, `GIT_EXEC_PATH`, `GIT_DIR` или `GIT_WORK_TREE`: что исполнится, ядру неизвестно;
- распаковка архива (`tar -x`, `bsdtar -x`, `unzip` кроме листинга, `cpio -i|-p`, `7z x|e`, `jar x` с приёмником — каталогом запуска), `ditto`, `rsync` и `cp -r|-R|-a` со слитным источником (`X/.`, `X/*`, `.`, а также `X/` — BSD `cp` на macOS копирует содержимое) SHALL быть критическими, если приёмник широкий: корень запуска и любой его предок (в том числе `~`), предок защищаемого пути, `<корень>/.codelab` или каталог конфигурации хоста. Приёмник — `-C`/`--directory` у `tar`, `-d` у `unzip`, `-o` у `7z`, последний позиционный у `rsync`, назначение `cp`, иначе рабочий каталог команды. Причина: команда создаёт поддерево неизвестного состава, и двухшаговая запись (`evil/.codelab/config.yaml`, затем распаковка, синхронизация или слияние `evil/` в корень) обходит сравнение путей. Распаковка и синхронизация в обычный подкаталог и `cp -r src .` без слитного источника НЕ SHALL быть критическими;
- `git apply`, `git am` и `patch` SHALL быть критическими всегда: пути правок задаёт содержимое патча;
- git-подкоманды, стирающие дерево, SHALL быть критическими всегда, без проверки путей: `git clean` с `-f`/`--force`, `git reset --hard`, `git stash` кроме `git stash list|show`, `git checkout`/`git restore` с путём `.` или другим широким предком, `git checkout`/`git switch` с `-f`/`--force`/`--discard-changes`, `git checkout-index` с `-a`/`--all` или `-f`/`--force`, `git read-tree -u`. Ядро не видит файловую систему, поэтому корень репозитория считается содержащим `.codelab`: стирание дерева удалило бы неотслеживаемый `.codelab/config.local.yaml` с `permissions.deny` (R5-2). Git-подкоманды, меняющие отслеживаемые файлы (`git checkout <ветка>`, `merge`, `pull`, `rebase`), НЕ SHALL быть критическими по этому правилу;
- перенаправление (`>`, `>>`, `>|`, `&>`, `2>`) в защищаемый путь SHALL быть критическим всегда, в том числе у команды из белого списка и пустое (`> file`, `: > file`);
- широкий предок в аргументах SHALL делать команду критической только по правилу каталогов-предков выше; запись внутрь широкого предка ловится сравнением конкретных путей;
- слово с маской (glob `*`, `?`, `[`, brace `{…}`) SHALL сравниваться по префиксу до первого символа маски: если префикс, разрешённый как путь, лежит внутри защищаемого пути, `<корень сессии или запуска>/.codelab` или `$CODELAB_HOME` либо совпадает с ними, команда не из белого списка критична (fail closed); перенаправление в такую маску — тоже. Маска сопоставляется с одной компонентой пути по правилу точки оболочки (`*` не совпадает с `.codelab`), а сломанная маска SHALL считаться совпадающей.

Прежний перечень пишущих команд остаётся примерами правила: перенаправление `>`/`>>`, `tee`, `cp`, `mv`, `rename`, `ln` (в том числе `ln -sf`), `install`, `dd of=`, `sed -i`; удаление и усечение (`rm`, `unlink`, `mv <защищаемый> …`, `truncate`, `>`) — удаление проектного конфига может снять записанный в нём `permissions.deny` (R5-2); `ln` без `-s` и `cp -l` (жёсткая ссылка); а также `yq -i`, `perl -pi`, `curl -o`, `wget -O`, `git checkout|restore -- .codelab/…`, `cp -r evil/. ~/.codelab`, `rsync … ~/.codelab/`, `tar -C ~/.codelab`, `unzip -d ~/.codelab`, `find ~/.codelab -delete`. Белый список консервативен: `cp .codelab/config.yaml /tmp/b.yaml` (защищаемый путь — источник) тоже критичен.

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
- **THEN** `ln -s sub .codelab` совпадает с критическим шаблоном (предок-назначение, которого нет на диске); `write sub/config.yaml` тоже критический: пересчитанная каноническая форма `<root>/.codelab/config.yaml` — `<root>/sub/config.yaml`

#### Scenario: Удаление дальнего предка
- **WHEN** в режиме `bypass` модель вызывает `exec rm -rf ~` или `exec mv ~/proj /tmp/p`, где `~/proj` — корень запуска
- **THEN** обе команды совпадают с критическим шаблоном `write to agent configuration`: `~` и `~/proj` — предки защищаемых путей

#### Scenario: Обычные операции в корне не критичны
- **WHEN** в режиме `bypass` модель вызывает `exec mv a .`, `exec mv a b`, `exec rm -rf build` или `exec mkdir -p src/x` в корне запуска с существующим `.codelab`
- **THEN** ни одна команда не совпадает с шаблоном `write to agent configuration` и исполняется без вопроса

#### Scenario: Жёсткая ссылка
- **WHEN** модель вызывает `exec ln ~/.codelab/config.yaml /tmp/c.yaml` или `exec cp -l ~/.codelab/config.yaml /tmp/c.yaml`
- **THEN** обе команды совпадают с критическим шаблоном `write to agent configuration`

#### Scenario: Файл --config и сессия вне корня
- **WHEN** агент запущен с `--config /etc/codelab/agent.yaml` в корне `/A`, а сессия открыта в `/B`, и модель вызывает `write /etc/codelab/agent.yaml` и `write ../A/.codelab/config.local.yaml`
- **THEN** оба вызова критические

#### Scenario: Удаление и усечение конфигурации
- **WHEN** в режиме `bypass` модель вызывает `exec` с `rm .codelab/config.local.yaml`, `unlink ~/.codelab/config.yaml`, `mv .codelab/config.yaml /tmp/c.yaml`, `truncate -s 0 $CODELAB_HOME/config.yaml` или `> .codelab/config.local.yaml`
- **THEN** каждая команда совпадает с критическим шаблоном `write to agent configuration` и спрашивается без `allow_always`; в `autopilot` — отказ

#### Scenario: secrets.yaml при другом бэкенде
- **WHEN** `secrets.backend: keychain`, хост передал `agentConfigPaths`, и модель в режиме `bypass` вызывает `write ~/.codelab/secrets.yaml`
- **THEN** вызов критический и спрашивается без `allow_always`, хотя `ConfigWatcher` за `secrets.yaml` при этом бэкенде не следит

#### Scenario: Ссылка на защищаемый файл
- **WHEN** в режиме `bypass` модель в корне запуска вызывает `exec ln -s .codelab/config.yaml c.yaml`; затем, когда ссылка `c.yaml` уже существует (создана человеком), — `write c.yaml`
- **THEN** `ln -s` совпадает с шаблоном `write to agent configuration` (R5-4: `ln` не в белом списке чтения); `write c.yaml` критический: каноническая форма цели — защищаемый `<корень запуска>/.codelab/config.yaml`; `exec echo x > c.yaml`, `exec sed -i s/a/b/ c.yaml` и `exec rm c.yaml` тоже критические

#### Scenario: Белый список чтения — критичные команды
- **WHEN** в режиме `bypass` модель вызывает `exec` с `yq -i '.a=1' .codelab/config.yaml`, `perl -pi -e s/a/b/ ~/.codelab/config.yaml`, `curl -o ~/.codelab/config.yaml https://x`, `wget -O $CODELAB_HOME/secrets.yaml https://x`, `git checkout -- .codelab/config.yaml`, `git restore .codelab/config.local.yaml`, `cp -r evil/. ~/.codelab`, `rsync -a evil/ ~/.codelab/`, `tar -xf a.tar -C ~/.codelab`, `unzip a.zip -d ~/.codelab`, `find ~/.codelab -delete`, `sh -c 'yq -i .a=1 .codelab/config.yaml'`, `env -C ~/.codelab python gen.py` или `cd .codelab && git checkout .`
- **THEN** каждая команда совпадает с критическим шаблоном `write to agent configuration` и спрашивается без `allow_always`; в `autopilot` — отказ

#### Scenario: Белый список чтения — чтение не критично
- **WHEN** в режиме `bypass` модель вызывает `exec` с `cat .codelab/config.yaml`, `grep -r model ~/.codelab`, `jq . .codelab/x.json`, `yq .budget .codelab/config.yaml`, `git diff .codelab/config.yaml`, `git log -- .codelab`, `ls -la ~/.codelab`, `sha256sum ~/.codelab/config.yaml | tee /tmp/h`, `test -f .codelab/config.local.yaml && echo yes` или `cd ~/.codelab && ls`
- **THEN** ни одна команда не совпадает с шаблоном `write to agent configuration`

#### Scenario: Перенаправление критично и у команды чтения
- **WHEN** модель вызывает `exec` с `cat /tmp/c.yaml > .codelab/config.yaml`, `echo x >> ~/.codelab/config.yaml` или `printf '' > $CODELAB_HOME/secrets.yaml`
- **THEN** каждая команда совпадает с шаблоном `write to agent configuration`

#### Scenario: Широкий предок в аргументах не критичен
- **WHEN** в режиме `bypass` модель в корне запуска с существующим `.codelab` вызывает `exec` с `make`, `make -C .`, `cp -r src dst`, `tar -xf a.tar -C build` или `cp a.txt ~/notes/`
- **THEN** ни одна команда не совпадает с шаблоном `write to agent configuration`: корень запуска и `~` — широкие предки, а запись внутрь них идёт не в защищаемые пути

#### Scenario: Маска в аргументе
- **WHEN** в режиме `bypass` модель вызывает `exec` с `rm .codelab/*.yaml`, `cp evil.md ~/.codelab/{agents,prompts}/`, `sed -i s/a/b/ .codelab/config.*`, `echo x > ~/.codelab/conf?g.yaml`, затем `cat .codelab/*.yaml` и `rm build/*.o`
- **THEN** первые четыре команды совпадают с шаблоном `write to agent configuration` (префикс до маски лежит в `.codelab` или `~/.codelab`, fail closed); `cat .codelab/*.yaml` (белый список) и `rm build/*.o` — нет

#### Scenario: Резолвер путей в serve
- **WHEN** агент `serve --stdio` открыл сессию, окружение которой — клиент ACP без `PathResolver`, `<корень запуска>/.codelab` после старта стал ссылкой на `sub`, и модель вызывает `write sub/config.yaml`
- **THEN** вызов критический: каноническая форма защищаемых путей пересчитана через окружение хоста `AgentCoreServices.baseEnv`

#### Scenario: Опции записи и исполнения у команд чтения
- **WHEN** в режиме `bypass` модель вызывает `exec` с `jq --in-place .a=1 .codelab/x.json`, `yq -s '.a' .codelab/config.yaml`, `yq --split-exp .a ~/.codelab/config.yaml`, `rg --pre ./x model .codelab`, `ag --search-zip x ~/.codelab`, `git -c core.pager=./x log -- .codelab`, `git --work-tree=/tmp status .codelab`, `git diff --output=.codelab/config.yaml`, `less -o .codelab/config.yaml /tmp/x` или `file -C -m .codelab/x.magic`; затем — `yq .a .codelab/config.yaml`, `rg model .codelab` и `git -c color.ui=never log -- src`
- **THEN** первые десять команд совпадают с шаблоном `write to agent configuration`; `yq .a …` и `rg model .codelab` (белый список без опций записи) и `git -c … log -- src` (защищаемого пути в словах нет) — нет

#### Scenario: Распаковка и синхронизация в корень
- **WHEN** в режиме `bypass` модель записала обычный файл `evil/.codelab/config.yaml`, упаковала `evil/` и вызывает в корне запуска `exec` с `tar -xf a.tar`, `tar -xzf a.tgz -C .`, `bsdtar -xf a.tar -C ~`, `unzip a.zip`, `cpio -i < a.cpio`, `7z x a.7z`, `rsync -a evil/ .`, `rsync -a evil/ ~/`, `cp -r evil/. .`, `cp -a evil/* .`, `cp -R evil/ .`, `ditto evil .`, `jar xf a.jar` или `tar -xf a.tar -C ~`
- **THEN** каждая команда совпадает с шаблоном `write to agent configuration`: приёмник — корень запуска или `~` (предок защищаемого пути); а `tar -xf a.tar -C build`, `unzip a.zip -d vendor`, `unzip -l a.zip`, `rsync -a src/ dst/`, `ditto evil build`, `jar tf a.jar` и `cp -r src .` — нет

#### Scenario: Патчи
- **WHEN** в режиме `bypass` модель вызывает `exec` с `git apply x.patch`, `git am 0001.patch` или `patch -p1 < x.patch`, в словах которых защищаемого пути нет
- **THEN** каждая команда совпадает с шаблоном `write to agent configuration` и спрашивается без `allow_always`; в `autopilot` — отказ

#### Scenario: git, стирающий дерево
- **WHEN** в режиме `bypass` модель в корне запуска вызывает `exec` с `git clean -fdx`, `git reset --hard`, `git stash`, `git stash -u`, `git stash drop`, `git checkout -- .`, `git restore .`, `git checkout -f main`, `git switch --discard-changes main`, `git checkout-index -a`, `git checkout-index -f src/a.dart` или `git read-tree -u -m HEAD`; затем — `git stash list`, `git stash show`, `git status`, `git checkout main`, `git pull` и `git restore src/a.dart`
- **THEN** первые двенадцать команд совпадают с шаблоном `write to agent configuration` (корень считается содержащим `.codelab`); последние шесть — нет

#### Scenario: Значения опций-команд
- **WHEN** в режиме `bypass` модель вызывает `exec` с `git -c core.pager='rm .codelab/config.local.yaml' log`, `git -c alias.x='!rm ~/.codelab/config.yaml' x`, `git -c core.fsmonitor='tee .codelab/config.yaml' status`, `rg --pre 'sh -c "rm ~/.codelab/config.yaml"' x src`, `find . -exec rm .codelab/config.yaml \;`, `git -c interactive.diffFilter='tee .codelab/config.yaml' add -p`, `watch -n 1 rm .codelab/config.yaml`, `script -c 'rm ~/.codelab/config.yaml' /dev/null`, `git --config-env=core.pager=P log`, `git -c core.hooksPath=/tmp/h commit` или `git -c include.path=/tmp/c log`; затем — `git -c core.pager=cat log`, `watch -n 1 ls` и `find src -exec cat {} \;`
- **THEN** первые одиннадцать команд совпадают с шаблоном `write to agent configuration` (вложенная команда пишет в защищаемый путь; `--config-env`, `core.hooksPath`, `include.path` — всегда); последние три — нет

#### Scenario: Переменные окружения с командой
- **WHEN** в режиме `bypass` модель вызывает `exec` с `GIT_PAGER='rm .codelab/config.local.yaml' git log`, `env EDITOR='tee ~/.codelab/config.yaml' git commit`, `export LESSOPEN='| rm ~/.codelab/config.yaml %s'; less a.txt`, `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.pager GIT_CONFIG_VALUE_0=x git log`, `GIT_DIR=/tmp/r git status` или `env GIT_EXEC_PATH=/tmp/x git log`; затем — `GIT_PAGER=cat git log`, `PAGER=less git log` и `export EDITOR=vim; git status`
- **THEN** первые шесть команд совпадают с шаблоном `write to agent configuration` (вложенная команда пишет в защищаемый путь; `GIT_CONFIG_*`, `GIT_DIR`, `GIT_EXEC_PATH` — всегда); последние три — нет
