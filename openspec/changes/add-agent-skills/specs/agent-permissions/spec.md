## MODIFIED Requirements

### Requirement: Критические пути правок конфигурации агента
Вызовы `write` и `edit` с нормализованной целью из списка §7.6.1 SHALL быть критическими. Список: `.codelab/config.yaml`, `.codelab/config.local.yaml`, `.codelab/cli.yaml`, `.codelab/agents/**`, `.codelab/skills/**`, `.codelab/prompts/**`, `.codelab/hooks/**`, `.agents/skills/**` (корень навыков проекта, design.md change `add-agent-skills`, D9; решение пользователя Q16). Критическими SHALL быть и правки **всех корней навыков** сессии с поддеревом — существующих или нет, независимо от доверия проекту (решение пользователя Q27): корни проекта на уровнях выше рабочей папки до корня git-репозитория (`<уровень>/.codelab/skills/**`, `<уровень>/.agents/skills/**`) и относительные элементы `skills.extra_roots`, разрешённые от `cwd` (`.claude/skills/**`). Эти корни зависят от `cwd` сессии, поэтому они SHALL быть **путями сессии**: рантайм при открытии сессии добавляет их к защищаемым путям политики этой сессии той же функцией списка корней, что даёт их загрузчику навыков; поле хоста `agentConfigPaths` (ниже) действует на весь процесс и их не содержит. Для путей сессии действуют те же правила сравнения, канонизации и `exec`, что для путей от хоста.

Критическими SHALL быть и правки путей конфигурации агента, которые хост передаёт полем `AgentCoreServices.agentConfigPaths: AgentConfigPaths {paths, expansions, caseInsensitive}` (design.md change `add-config-writer-and-reload`, D8; OQ2 (а)):
- состав — файлы, которые наблюдает `ConfigWatcher`: `$CODELAB_HOME/config.yaml`, файл `--config`/`CODELAB_CONFIG`, `<корень запуска>/.codelab/config.yaml` и `config.local.yaml`; `$CODELAB_HOME/secrets.yaml` — при любом `secrets.backend`, хотя наблюдатель следит за ним только при `file` (R5-1); а также каталоги `$CODELAB_HOME/agents`, `$CODELAB_HOME/prompts` и `$CODELAB_HOME/skills` с поддеревом; корни навыков `~/.agents/skills` и абсолютные элементы `skills.extra_roots` с поддеревом (design.md change `add-agent-skills`, D9; решения пользователя Q9, Q16, Q27);
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
- текст команды `sh -c`, `bash -c`, `dash -c` SHALL определяться по порядку разбора опций оболочки: `-o`, `+o`, `-O`, `+O` забирают следующее слово, в том числе после `-c`; в кластере каждая `o`/`O` забирает по слову (`-co pipefail`, `-oc`, `-ceo x`, `-cO x`); `--rcfile` и `--init-file` — со значением; `--` и `-` завершают опции; неизвестная длинная опция оболочки делает команду неразбираемой — критической (fail closed; design.md change `add-agent-skills`, D17, ревью безопасности 2026-11-13);
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

Исключения для навыков (design.md change `add-agent-skills`, D9; решения пользователя Q24, Q25, Q29 и их уточнения Q33–Q38) применяются к каждой простой команде строки отдельно (`cd`, `pushd` и `popd` меняют рабочий каталог последующих команд, но не снимают их критичность). «Внутри каталога навыка» везде проверяется по **каноническому** пути — после разрешения ссылок тем же резолвером путей политики, поэтому `scripts/run -> /bin/cp`, аргумент-ссылка наружу или ссылка на `SKILL.md` исключения не получают. Имя `SKILL.md` сравнивается с базовым именем канонического пути без учёта регистра (на нечувствительной к регистру ФС `skill.md` — тот же файл). Исключения не убирают срабатывание там, где путь записи в корень навыков явно виден в команде; запись, которую разбор не видит (скрипт из файла и другие известные пределы ниже), исключения не создают и не закрывают:
- **E1 — скрипт навыка** (Q25, уточнено Q34, Q36, Q37). Исполняемый файл SHALL NOT делать команду критической при любом рабочем каталоге, только если: (1) это существующий обычный файл под `<dir>/scripts/` загруженного навыка (имя каталога — по `specification.md`), в пути после `scripts/` нет сегментов, начинающихся с `.`, и сегментов `node_modules`, `site-packages`, `vendor`; не `SKILL.md`; (2) он стоит первым словом команды и это слово содержит `/` (слово без `/` оболочка ищет в `PATH`, а не в рабочем каталоге: `cd <dir> && run.sh` под E1 не подпадает), или он — первый позиционный аргумент интерпретатора, узнанного по **голому базовому имени** из `PATH`: `python`, `python3`, `node`, `tsx`, `bash`, `sh`, `zsh`, `pwsh`, `ruby`, `perl`, `deno run`, `bun run`, `uv run`, `pipx run`; интерпретатор с путём под E1 не подпадает; (3) у интерпретатора перед путём скрипта **нет ни одной опции**, кроме `pwsh -File`/`-f` (Q34: allowlist безопасных опций не заводится; опции кода, модуля и stdin — `-c`, `-e`, `-E`, `-p`, `-n`, `-i`, `-m`, `-M`, `-r`, `-s`, `-`, `--eval`, `--print`, `--require`, `--import`, `--loader`, `--preload`, `-Command`, `-EncodedCommand`, `--with`, `--spec` — частные случаи этого правила); (4) скрипт или интерпретатор стоит **первым словом** простой команды: перед ним нет ни префиксного присваивания (`NAME=… python3 …`), ни лаунчера — любой программы, запускающей следующую за ней команду (`env` в любой форме, `sudo`, `doas`, `time`, `nohup`, `timeout`, `command`, `exec`, `nice`, `ionice`, `stdbuf`, `xargs` и другие); и **все сегменты, исполненные раньше в той же оболочке, а для вложенной строки — и на всех охватывающих уровнях, взяты из разрешённого списка**: `cd`, `pushd`, `popd`, `:` и команды белого списка чтения без опций, задающих переменную (`printf -v` исключён). Любая другая команда раньше скрипта — в том числе другой вызов скрипта навыка (в `python3 <p1> && python3 <p2>` второй вызов критичен, fail closed), присваивание, `export`, `declare`, `read`, `mapfile`, `set`, `trap`, `source`/`.`, `alias`, `hash`, `enable`, определение функции, — а также зарезервированные слова оболочки (`if`, `then`, `elif`, `else`, `fi`, `for`, `select`, `while`, `until`, `do`, `done`, `case`, `esac`, `function`, `{`, `}`, `[[`, `]]`, `!`; `[` и `test` — команды белого списка чтения, они E1 не отключают) и `eval` на том же уровне отключают E1 (решение Q47: разрешённый список вместо перечня запретов, по образцу Q34 — неизвестное отключает; fail closed: переменные окружения, функции, псевдонимы и ловушки меняют исполняемый код). Вложенная строка `-c` получает E1, только если оболочка — `sh`, `bash` или `dash` по голому имени, вызванная с `-c` и, кроме него, лишь с `-e`, `-u`, `-x`, `-o pipefail`, без `-l`, `--login`, `-i`, `--rcfile`, `--init-file` (startup-файлы исполняют неизвестный код); опции проверяются на всём отрезке между именем оболочки и текстом команды, в том числе после `-c` (`bash -c -l "…"`, `bash -c -i "…"`, `sh -c -i "…"` — без E1); `zsh -c`, `env -S` и `eval` E1 не дают. Файл навыка, названный как интерпретатор (`<dir>/scripts/…/tsx`, `<dir>/scripts/bin/node`), подчиняется для своих аргументов тем же правилам (3) и (4): любая его опция перед первым позиционным аргументом, в том числе опции кода, модуля и stdin Q34, отключает E1; файл навыка с именем раннера `deno`, `bun`, `uv`, `pipx` требует подкоманду `run`, и опции до скрипта отключают E1 (Q36, Q47).
- **E2 — рабочий каталог навыка** (Q24, сужено Q33). Рабочий каталог (`ExecOptions.cwd`, `cd <dir>`, `pushd <dir>`) в каталоге загруженного навыка SHALL NOT делать простую команду критической, **только если** её исполняемый файл — скрипт навыка по E1 или команда из белого списка чтения. Любая другая команда с таким рабочим каталогом — критическая, даже без единого слова-пути: `tar -x`, `unzip -o`, `7z x`, `cpio -i`, `jar x`, `git pull`, `git merge`, `npm install`, `find -delete` и подобные пишут в рабочий каталог неявно. `env -C DIR` и опция `-C DIR` под E2 сознательно не подпадают и проверяются как прежде (безопасная сторона).
- **E3 — ресурс навыка аргументом его скрипта** (Q29, уточнено Q35, Q38). Слово-аргумент или значение опции SHALL NOT делать критической простую команду, **только если** её исполняемый файл — скрипт навыка по E1 и слово по каноническому пути — существующий обычный файл под `<dir>/assets/` **того же** навыка с расширением не `.md`. Файлы под `references/` и `scripts/`, сам `SKILL.md` любого навыка (по Q30 это доверенные инструкции и исполняемый код), файлы другого навыка (в том числе через `..`), слова с маской или фигурными скобками (`*`, `?`, `[…]`, `{…}` — каждый вариант раскрытия проверяется как отдельное слово) исключения E3 не получают никогда. Дополнительная эвристика — значения опций вывода исключения не получают и для `assets/`: `-o`, `-o<path>`, `-O`, `--output`, `--output=…`, `--out`, `--out=…`, `--outfile`, `--output-file`, `--out-file`, `--outdir`, `--dest`, `--target`, `--write`, `-w`, `of=…`; опцией вывода считается и короткий кластер, кончающийся на `o`, `O` или `w` (`-vo <path>`, `-vo<path>`, `-xw <path>`), и сокращение длинной опции вывода из списка, которое принимает GNU getopt (`--outp`, `--outf=…`, `--wri`) — уточнение ревью итерации 2. Жёсткие ссылки E3 не различает: `FileStat` порта окружения не отдаёт число ссылок (`nlink`), поэтому ограничение `nlink == 1` не вводится — известный предел.
Пишущие команды (`cp`, `mv`, `rm`, `sed -i`, `ln`, `tee`, `curl -o`, `wget -O`, `install`, `rsync`, `truncate`, `dd of=` и другие команды не из белого списка чтения, не подпадающие под E1), цели перенаправления (`>`, `>>`) в каталог навыка, ещё не существующие пути в каталоге навыка и прочие слова, попадающие в защищаемые пути, проверяются по правилу белого списка чтения, как выше, и остаются критическими. Команда, подпадающая под исключения, идёт по обычной политике уровня `exec`, в том числе с `allow_always`. Остаточные риски: скрипт навыка сам пишет в свой каталог или исполняет переданный ему код (`<dir>/scripts/run.sh "rm …"`) — политика не разбирает содержимое программ; проверка идёт в `beforeToolCall`, а исполнение — позже (TOCTOU: файл или ссылка могут смениться между проверкой и запуском).

#### Scenario: Подложить навык командой
- **WHEN** в режиме `bypass` модель вызывает `exec` с `mkdir -p ~/.agents/skills/x && cat > ~/.agents/skills/x/SKILL.md`
- **THEN** вызов — критический шаблон `write to agent configuration`: вопрос пользователю, без `allow_always`

#### Scenario: Правка навыка проекта
- **WHEN** в режиме `accept-edits` модель вызывает `write` с целью `.agents/skills/pdf/SKILL.md`
- **THEN** вызов критический: вопрос задаётся, `allow_always` не предлагается

#### Scenario: Скрипт навыка не критичен
- **WHEN** в режиме `standard` модель вызывает `exec` с `python3 scripts/extract.py /work/demo/a.pdf` и `cwd` — каталог навыка `<cwd>/.codelab/skills/pdf`
- **THEN** вопрос — обычный для уровня `exec`, с вариантом `allow_always`

#### Scenario: Запись в каталог навыка из скрипта-команды
- **WHEN** с тем же `cwd` модель вызывает `exec` с `python3 scripts/extract.py > notes.md`
- **THEN** цель перенаправления `notes.md` лежит в каталоге навыка — вызов критический

#### Scenario: Скрипт навыка по абсолютному пути из рабочей папки
- **WHEN** в режиме `bypass` модель вызывает `exec` с `python3 /home/u/.codelab/skills/release-notes/scripts/x.py --out notes.md` и `cwd` рабочей папки
- **THEN** вызов не критический (решение Q25): выполняется по обычной политике режима; с `--out /home/u/.codelab/skills/release-notes/notes.md` — критический

#### Scenario: Ресурс навыка аргументом
- **WHEN** в режиме `bypass` модель вызывает `exec` с `python3 /home/u/.codelab/skills/pdf/scripts/fill.py --schema /home/u/.codelab/skills/pdf/assets/schema.json /work/demo/a.pdf`, файл `schema.json` существует
- **THEN** вызов не критический (решения Q29, Q38: `assets/`, не `.md`); если вместо `schema.json` указан ещё не существующий `/home/u/.codelab/skills/pdf/assets/new.json` или в команде есть `> /home/u/.codelab/skills/pdf/assets/schema.json` — критический

#### Scenario: Пишущие команды на существующий файл навыка критичны
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди с `sed -i 's/a/b/' /home/u/.codelab/skills/pdf/SKILL.md`, `cp /tmp/evil.md /home/u/.codelab/skills/pdf/SKILL.md`, `rm /home/u/.codelab/skills/pdf/SKILL.md` и `curl -o /home/u/.codelab/skills/pdf/SKILL.md https://example.com/x`; файл `SKILL.md` существует
- **THEN** каждый вызов — критический шаблон `write to agent configuration`: вопрос пользователю, без `allow_always` (решение Q29 в суженной формулировке)

#### Scenario: cd в каталог навыка не снимает критичность
- **WHEN** в режиме `bypass` модель вызывает `exec` с `cd /home/u/.codelab/skills/pdf && rm SKILL.md`
- **THEN** вызов критический: `rm` — не скрипт навыка, его аргумент разрешается от нового каталога в защищаемый путь

#### Scenario: Ресурс навыка аргументом чужой программе
- **WHEN** в режиме `bypass` модель вызывает `exec` с `python3 /work/demo/tool.py /home/u/.codelab/skills/pdf/assets/schema.json`
- **THEN** вызов критический: исполняемый файл — не скрипт навыка

#### Scenario: Неявная запись в рабочий каталог навыка критична
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди с `cd /home/u/.agents/skills/pdf && tar -xf /work/e.tar`, `cd /home/u/.agents/skills/pdf && unzip -o /work/e.zip`, `cd /home/u/.agents/skills/pdf && git pull`, `cd /home/u/.agents/skills/pdf && npm install`, `cd /home/u/.agents/skills/pdf && find . -name '*.md' -delete`; во втором варианте — те же команды без `cd`, с `ExecOptions.cwd` `/home/u/.agents/skills/pdf`
- **THEN** каждый вызов — критический шаблон `write to agent configuration` (решение Q33): исполняемый файл — не скрипт навыка и не команда белого списка чтения

#### Scenario: Чтение из рабочего каталога навыка не критично
- **WHEN** в режиме `bypass` модель вызывает `exec` с `cd /home/u/.agents/skills/pdf && cat references/FORMS.md`
- **THEN** вызов не критический: `cat` — команда белого списка чтения (E2, Q33)

#### Scenario: Код интерпретатору вместо скрипта критичен
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди с `perl -pi -e 's/a/b/' /home/u/.agents/skills/pdf/SKILL.md`, `python3 -c "open('/home/u/.agents/skills/pdf/SKILL.md','w')" /home/u/.agents/skills/pdf/scripts/x.py`, `node -e "…" /home/u/.agents/skills/pdf/scripts/x.js`, `bash -c '…' /home/u/.agents/skills/pdf/scripts/x.sh`, `python3 - /home/u/.agents/skills/pdf/scripts/x.py <<EOF … EOF` и `python3 -m zipfile -c /home/u/.agents/skills/pdf/SKILL.md /tmp/a`
- **THEN** каждый вызов критический (решение Q34): опция кода, модуля или stdin отключает E1

#### Scenario: Скрипт-ссылка наружу и интерпретатор с путём
- **WHEN** `/home/u/.agents/skills/pdf/scripts/run` — ссылка на `/bin/cp`, и модель вызывает `exec` с `/home/u/.agents/skills/pdf/scripts/run /tmp/x /home/u/.agents/skills/pdf/assets/a.json`; во втором варианте — `/tmp/python3 /home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json`
- **THEN** оба вызова критические: канонический путь исполняемого файла вне каталога навыка; интерпретатор с путём не узнаётся (E1, Q34)

#### Scenario: Вывод скрипта навыка в SKILL.md критичен
- **WHEN** в режиме `bypass` модель вызывает `exec` с `python3 /home/u/.agents/skills/pdf/scripts/fill.py --output /home/u/.agents/skills/pdf/SKILL.md`, во втором варианте — `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/pdf/SKILL.md`, в третьем — `python3 /home/u/.agents/skills/pdf/scripts/fill.py -o/home/u/.agents/skills/pdf/assets/schema.json`
- **THEN** все три вызова критические (решение Q35): `SKILL.md` и значения опций вывода под E3 не подпадают

#### Scenario: Ресурс другого навыка, через .. и чужой SKILL.md
- **WHEN** в режиме `bypass` модель вызывает `exec` с `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/notes/assets/a.json`, во втором варианте — `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/pdf/assets/../../notes/assets/a.json`, в третьем — `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/notes/SKILL.md`
- **THEN** все три вызова критические (E3: только `assets/` того же навыка по каноническому пути; Q38)

#### Scenario: Ресурсы вне assets и опции вывода
- **WHEN** в режиме `bypass` модель вызывает `exec` с `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/pdf/references/a.md`, во втором варианте — `python3 /home/u/.agents/skills/pdf/scripts/fill.py --out=/home/u/.agents/skills/pdf/assets/a.json`, в третьем — `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/pdf/assets/*.json`
- **THEN** все три вызова критические (Q38, Q35: `references/` не получает E3; `--out=…` — опция вывода; маска — без E3)

#### Scenario: Ссылка на SKILL.md и регистр имени
- **WHEN** `/home/u/.agents/skills/pdf/assets/x.json` — ссылка на `../SKILL.md`, и модель вызывает `exec` с `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/pdf/assets/x.json`; во втором варианте на нечувствительной к регистру ФС — `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/pdf/skill.md`
- **THEN** оба вызова критические: сравнение идёт по каноническому пути и по базовому имени без учёта регистра

#### Scenario: Первое слово без косой черты
- **WHEN** в режиме `bypass` модель вызывает `exec` с `cd /home/u/.agents/skills/pdf/scripts && run.sh /home/u/.agents/skills/pdf/assets/a.json`, во втором варианте — `/home/u/.agents/skills/pdf/scripts/run.sh /home/u/.agents/skills/pdf/assets/a.json`
- **THEN** первый вызов критический (слово без `/` ищется в `PATH`, E1 не действует, E2 — тоже), второй — нет

#### Scenario: Переменные окружения перед интерпретатором
- **WHEN** в режиме `bypass` модель вызывает `exec` с `NODE_OPTIONS=--require=/tmp/x.js node /home/u/.agents/skills/pdf/scripts/x.js /home/u/.agents/skills/pdf/assets/a.json`, во втором варианте — `export PYTHONPATH=/tmp; python3 /home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json`, в третьем — `env -S 'python3 -c …' /home/u/.agents/skills/pdf/scripts/x.py`
- **THEN** все вызовы критические (Q37, fail closed)

#### Scenario: Лаунчер перед скриптом навыка
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди с `time python3 /home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json`, `nohup python3 /home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json`, `sudo /home/u/.agents/skills/pdf/scripts/run.sh /home/u/.agents/skills/pdf/assets/a.json`, `timeout 5 python3 /home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json` и `echo /home/u/.agents/skills/pdf/assets/a.json | xargs python3 /home/u/.agents/skills/pdf/scripts/x.py`
- **THEN** каждый вызов — критический шаблон `write to agent configuration`: лаунчер перед скриптом отключает E1 (fail closed, Q37)

#### Scenario: Окружение и код оболочки перед скриптом навыка
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди с `X=1; python3 <p>`, `export X; python3 <p>`, `set -a; python3 <p>`, `set -o allexport; python3 <p>`, `. /tmp/env.sh; python3 <p>`, `source /tmp/env.sh; python3 <p>`, `alias python3=/tmp/x; python3 <p>`, `hash -p /tmp/x python3; python3 <p>`, `enable -n echo; python3 <p>`, `python3() { :; }; python3 <p>` и `X=1 sh -c 'python3 <p>'`, где `<p>` — `/home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json`
- **THEN** каждый вызов критический (Q37, Q47): раньше скрипта — сегменты вне разрешённого списка, а для вложенной строки — и во внешней, что отключает E1

#### Scenario: Только разрешённые сегменты перед скриптом навыка
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди, где `<p>` — `/home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json`: (1) управляющие конструкции — `for i in 1; do export X=1; done; python3 <p>` и `if true; then python3 <p>; fi`; (2) `eval` — `eval "export X=1"; python3 <p>` и `eval python3 <p>`; (3) переменные командами — `read PATH < /tmp/p; python3 <p>`, `printf -v PATH /tmp; python3 <p>` и `mapfile -t A < /tmp/a; python3 <p>`; (4) оболочки со startup-файлами — `bash -lc "python3 <p>"`, `bash --rcfile /tmp/rc -c "python3 <p>"`, `bash -i -c "python3 <p>"` и `zsh -c "python3 <p>"`; (5) прочие команды раньше скрипта — `trap 'rm -f /tmp/x' DEBUG; python3 <p>` и `mkdir -p /tmp/x; python3 <p>`
- **THEN** каждый вызов — критический шаблон `write to agent configuration` (решение Q47)

#### Scenario: Второй скрипт, двойные скобки и опции после -c
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди с `python3 /home/u/.agents/skills/pdf/scripts/a.py && python3 <p>`, `[[ -f /tmp/x ]] && python3 <p>`, `bash -c -l "python3 <p>"`, `bash -c -i "python3 <p>"` и `sh -c -i "python3 <p>"`; затем — `[ -f /tmp/x ] && python3 <p>` и `test -f /tmp/x && python3 <p>`
- **THEN** первые пять вызовов критические (решение Q47): скрипт навыка в разрешённый список не входит, `[[` — зарезервированное слово, опции оболочки после `-c` проверяются так же; последние два не критичны — `[` и `test` из белого списка чтения

#### Scenario: Разрешённые сегменты и простая вложенная оболочка
- **WHEN** в режиме `bypass` модель вызывает `exec` с `sh -e -c "python3 <p>"`, во втором варианте — `cd /work/demo && cat notes.txt && python3 <p>`, в третьем — `bash -o pipefail -c "cd /work/demo; python3 <p>"`
- **THEN** ни один вызов не критичен (решение Q47): `sh`/`bash` вызваны только с `-c` и допустимыми опциями, сегменты раньше скрипта — из разрешённого списка

#### Scenario: Раннер с именем файла навыка
- **WHEN** в режиме `bypass` модель вызывает `exec` с `/home/u/.agents/skills/pdf/scripts/bin/deno /home/u/.agents/skills/pdf/scripts/x.ts /home/u/.agents/skills/pdf/assets/a.json`, во втором варианте — `/home/u/.agents/skills/pdf/scripts/bin/uv --with x run /home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json`
- **THEN** оба вызова критические (Q36, Q47): раннеру нужна подкоманда `run`, опции до скрипта отключают E1

#### Scenario: Скрипт навыка с именем интерпретатора
- **WHEN** в режиме `bypass` модель вызывает `exec` с `/home/u/.agents/skills/pdf/scripts/tsx --import /tmp/x.js /home/u/.agents/skills/pdf/assets/a.json`
- **THEN** вызов критический (Q36): опция перед первым позиционным аргументом отключает E1 и у файла навыка, названного как интерпретатор

#### Scenario: Кластер и сокращения опций вывода
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди с `python3 /home/u/.agents/skills/pdf/scripts/fill.py -vo /home/u/.agents/skills/pdf/assets/a.json`, `python3 /home/u/.agents/skills/pdf/scripts/fill.py --outp=/home/u/.agents/skills/pdf/assets/a.json` и `python3 /home/u/.agents/skills/pdf/scripts/fill.py --wri /home/u/.agents/skills/pdf/assets/a.json`
- **THEN** каждый вызов критический: значение опции вывода исключения E3 не получает (Q35, Q38, уточнены ревью итерации 2)

#### Scenario: Исполняемый файл вне scripts/
- **WHEN** в режиме `bypass` модель вызывает `exec` с `/home/u/.agents/skills/pdf/node_modules/.bin/shx cp /tmp/evil /home/u/.agents/skills/pdf/references/a.md`, во втором варианте — `/home/u/.agents/skills/pdf/.venv/bin/pip install x`, в третьем — `/home/u/.agents/skills/pdf/scripts/node_modules/.bin/prettier --write /home/u/.agents/skills/pdf/references/a.md`
- **THEN** все вызовы критические (Q36)

#### Scenario: pwsh -File
- **WHEN** в режиме `bypass` модель вызывает `exec` с `pwsh -File /home/u/.agents/skills/pdf/scripts/fill.ps1 /home/u/.agents/skills/pdf/assets/a.json`, во втором варианте — `pwsh -NoProfile -File /home/u/.agents/skills/pdf/scripts/fill.ps1`
- **THEN** первый вызов не критический (единственная допустимая опция — `-File`), второй критический (любая другая опция отключает E1)

#### Scenario: pushd в каталог навыка
- **WHEN** в режиме `bypass` модель вызывает `exec` с `pushd /home/u/.agents/skills/pdf && npm install && popd`
- **THEN** вызов критический (E2, Q33)

#### Scenario: Навыки в autopilot
- **WHEN** хост включил `autopilot`, и модель вызывает `exec` с `cd /home/u/.agents/skills/pdf && tar -xf /work/e.tar`; во втором варианте — `python3 /home/u/.agents/skills/pdf/scripts/fill.py /home/u/.agents/skills/pdf/assets/a.json`
- **THEN** первый вызов отклонён без вопроса с текстом `critical command blocked in autopilot: write to agent configuration` (критический шаблон `exec`, PERM-9; текст `Editing agent configuration requires a human` — у `write` и `edit`), второй выполнен по политике режима (E1, E3)

#### Scenario: Относительный корень extra_roots защищён в сессии
- **WHEN** глобальный конфиг задаёт `skills.extra_roots: [".claude/skills"]`, сессия открыта в `/work/demo`, а модель в режиме `accept-edits` вызывает `write` с целью `.claude/skills/lint/SKILL.md`
- **THEN** вызов критический (решение Q27); в сессии с другим `cwd` путь `/work/demo/.claude/skills` не защищается этим правилом

#### Scenario: Опции оболочки перед текстом -c
- **WHEN** в режиме `bypass` модель вызывает `exec` по очереди с `bash -O extglob -c 'rm -rf .codelab'`, `bash -co pipefail 'rm -rf .codelab'` и `bash --unknown-opt -c 'ls'`; затем — `bash -o pipefail -c "python3 /home/u/.agents/skills/pdf/scripts/x.py /home/u/.agents/skills/pdf/assets/a.json"`
- **THEN** первые два вызова совпадают с критическим шаблоном `write to agent configuration` (значение опции не принимается за текст команды), третий критичен как неразбираемая команда; последний не критичен — текст команды найден верно, и действует исключение E1
