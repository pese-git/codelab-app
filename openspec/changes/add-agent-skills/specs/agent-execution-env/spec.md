## ADDED Requirements

### Requirement: Корни только для чтения
`BoundedEnv.wrap(inner, root, {readOnlyRoots, readOnlyFs, execInReadOnlyRoots})` SHALL принимать необязательные корни только для чтения, файловую систему для них и признак, что внутренний env исполняет команды на той же машине, что `readOnlyFs` (`agent-core-architecture` §4.4, §17.2.3; design.md change `add-agent-skills`, D5; решения пользователя Q4, Q17, Q23; SKL-9):
1. корни `readOnlyRoots` SHALL нормализоваться и разрешаться `realpath` через `readOnlyFs` один раз при создании обёртки;
2. операции чтения (`readText`, `readBytes`, `stat`, `listDir`) SHALL принимать путь, если его разрешённая форма лежит в `root` **или** в одном из `readOnlyRoots` по правилу сегментов §4.4; путь в `readOnlyRoots` SHALL уходить в `readOnlyFs`, а не во внутренний env;
3. запись, правка и удаление SHALL приниматься только в `root`; путь в `readOnlyRoots` для них — `Err(FileError(outsideWorkspace, p))` до обращения к любому env (ENV-3);
4. `ExecOptions.cwd` в `readOnlyRoots` SHALL приниматься и передаваться внутреннему env, только если `execInReadOnlyRoots == true`; иначе — `Err(FileError(outsideWorkspace, p))` до обращения к env. Содержимое команды, как и прежде, не проверяется (запись командой ловит политика разрешений, PERM-11);
5. без `readOnlyFs` `readOnlyRoots` SHALL игнорироваться: поведение — как у `wrap(inner, root)`;
6. ссылка из корня только для чтения, ведущая за его пределы, SHALL отклоняться так же, как ссылка из `root`.

Обёртка SHALL реализовывать опциональную возможность, только если её реализует внутренний env (ENV-4); для путей в `readOnlyRoots` — только если её реализует и `readOnlyFs`.

В `readOnlyRoots` рантайм SHALL класть только канонические каталоги загруженных навыков, лежащие вне `root` и не содержащие его: каталог навыка внутри рабочей папки остаётся обычной частью `root`, и правку в нём решает PERM-11, а сессия, открытая внутри каталога навыка, правит его как рабочую папку (design.md change `add-agent-skills`, D17). Рантайм SHALL ставить `execInReadOnlyRoots: true`, только если env сессии исполняет команды на машине агента (локальное окружение встроенного агента, `AcpServerConfig.localEnv`); у env клиента ACP (`AcpClientExecutionEnv`) — `false`: клиент ограничивает `cwd` `terminal/create` рабочей папкой сессии (`AGENTS.md` §10), и запрос с `cwd` в каталоге агента он отклонит. Подсказку SHALL давать инструмент `exec` до вызова env: он сравнивает `cwd` с `readOnlyRoots` сессии и при `execInReadOnlyRoots == false` возвращает модели ошибку инструмента с подсказкой запустить скрипт по абсолютному пути с `cwd` рабочей папки (capability `agent-skills`, «Сопутствующие файлы и скрипты навыка»; решение Q23 (а)); `BoundedEnv` при этом остаётся последним рубежом и различать причины `outsideWorkspace` не обязан. Клиенту запрос не отправляется, containment клиента не меняется.

#### Scenario: Чтение и запись в корне только для чтения
- **WHEN** при корне `/proj` и `readOnlyRoots: [/home/u/.codelab/skills/notes]` выполняются `readText` и `writeText` по пути `/home/u/.codelab/skills/notes/ref.md`
- **THEN** чтение возвращает содержимое из `readOnlyFs`, внутренний env вызова не получил; запись — `outsideWorkspace`, ни один env вызова не получил

#### Scenario: Соседи корня только для чтения недоступны
- **WHEN** при тех же корнях читаются `/home/u/.codelab/config.yaml` и `/home/u/.codelab/skills/other/SKILL.md`
- **THEN** оба — `outsideWorkspace`

#### Scenario: cwd команды в каталоге навыка
- **WHEN** `exec` получает `ExecOptions.cwd` `/home/u/.codelab/skills/notes`; в первом варианте `execInReadOnlyRoots: true`, во втором — `false`
- **THEN** в первом варианте (локальное исполнение, решение Q17) команда передана внутреннему env с этим `cwd`; во втором (env клиента ACP) — `outsideWorkspace` до обращения к внутреннему env, `terminal/create` не отправляется

#### Scenario: Ссылка наружу из корня только для чтения
- **WHEN** `/home/u/.codelab/skills/notes/link` ведёт на `/etc`, и читается `link/passwd`
- **THEN** результат — `outsideWorkspace`

#### Scenario: Сессия внутри каталога навыка
- **WHEN** сессия открыта в `/home/u/.codelab/skills/notes/scripts`, а навык `notes` загружен из `/home/u/.codelab/skills/notes`
- **THEN** этот каталог не входит в `readOnlyRoots`, и `writeText('/home/u/.codelab/skills/notes/scripts/a.py', …)` уходит во внутренний env как запись в рабочей папке (критичность правки решает PERM-11)
