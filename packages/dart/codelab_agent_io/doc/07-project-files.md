# Файлы проекта: `ProjectFilesLoader`

Глава про то, как пакет читает файлы, которые лежат рядом с кодом проекта и в `$CODELAB_HOME`: инструкции (`AGENTS.md`, `CLAUDE.md`), шаблоны команд (`prompts/*.md`), определения агентов (`agents/*.md`) и навыки (`skills/*/SKILL.md`). Что ядро делает с этими файлами (сборка системного промпта, разбор шаблонов и агентов, каталог навыков), объясняет [глава 9 ядра](../../codelab_agent_core/doc/09-config-prompts-commands.md#файлы-проекта-libsrcproject) и [глава 6 ядра](../../codelab_agent_core/doc/06-tools.md#навыки). Здесь — чтение: границы, лимиты, диагностика.

Нормы: [`agent-project-context`](../../../../openspec/specs/agent-project-context/spec.md), [`agent-definitions`](../../../../openspec/specs/agent-definitions/spec.md), [`agent-skills`](../../../../openspec/specs/agent-skills/spec.md). Код: `lib/src/project/`.

## Зачем читает хост, а не ядро

Ядро не читает диск (PKG-1). Ходить в файловую систему через ACP нельзя: в ACP нет листинга каталога и `stat`, а `$CODELAB_HOME` лежит на машине агента. Читать файлы нужно внутри `createSession`, до ответа `session/new`, когда клиент ещё не знает `sessionId` (ACP-8). Поэтому есть порт ядра `ProjectFilesSource` и реализация `ProjectFilesLoader`. Тот же класс реализует порт навыков `SkillFilesSource`.

| Файл | Что делает |
|---|---|
| `project_files_loader.dart` | `ProjectFilesLoader`: чтение контекста, шаблонов, агентов, навыков |
| `skill_roots.dart` | `skillRootPlan`, `projectLevels`, `canonicalPath`, `hostSkillRoot`: корни навыков и подъём к корню git |
| `frontmatter.dart` | `readMarkdownFile`: отделить frontmatter от тела и разобрать его |
| `project_extensions.dart` | `loadProjectExtensions`: файлы проекта и навыки одним расчётом |
| `project_trust.dart` | `projectTrustAt`: канонический путь папки и её доверие |
| `load_agent_definitions.dart` | `loadAgentDefinitions`: определения агентов для моста `codelab_setup` |

## Создание и входы

```dart
final loader = ProjectFilesLoader(
  home: codelabHomeOf(environment),   // $CODELAB_HOME; null или '' — пользовательской области нет
  userHome: userHomeOf(environment),  // для ~/.agents/skills и ~ в skills.extra_roots
  local: LocalExecutionEnv(cwd: cwd), // именно LocalExecutionEnv, не любой ExecutionEnv
);
```

- Тип `local` сужен до `LocalExecutionEnv` намеренно: граница чтения опирается на его `realpath` (`PathResolver`). Окружение без него оставило бы границу лексической, и ссылка наружу прошла бы незамеченной (приоритет 1).
- Пустая строка вместо `home` и `userHome` считается отсутствием: `'$home/skills'` при пустом `home` указывал бы на `/skills`. `parseServeArgs` под `--llm-script` отдаёт `codelabHome == ''`; хост при этом передаёт загрузчику `home: null, userHome: null`.
- Тестовый конструктор `ProjectFilesLoader.testing(...)` (`@visibleForTesting`) принимает любое окружение и хук `beforeOpen` — для веток fail-closed, недостижимых иначе: окружение без `PathResolver` и подмена файла между проверкой и открытием.
- `load(ProjectFilesQuery)` **не бросает** на ошибках файлов. Каждая ошибка — запись `ExtensionDiagnostic` с путём, уровнем и кодом; содержимое файлов в диагностику не попадает (D14). Хост серверного режима `serve --ws` загрузчик не передаёт.

## Что читается

| Что | Где ищется | Условие |
|---|---|---|
| инструкции пользователя | `$CODELAB_HOME/AGENTS.md` | всегда, если есть `home` |
| инструкции проекта | на каждом уровне от корня git до `cwd`: `AGENTS.md`, иначе `CLAUDE.md` | всегда; бюджет — `contextMaxBytes` запроса |
| шаблоны команд | `$CODELAB_HOME/prompts/*.md`, `<cwd>/.codelab/prompts/*.md` | проектный каталог — только для доверенного проекта |
| определения агентов | `$CODELAB_HOME/agents/*.md`, `<cwd>/.codelab/agents/*.md` | то же |
| навыки | корни по приоритету, см. ниже | проект — только доверенный |

Порядок записей `context`: пользовательский файл, затем от корня к `cwd`. Если на уровне есть оба файла, читается `AGENTS.md`, а `CLAUDE.md` остаётся с диагностикой `shadowed` (уровень `info`): `CLAUDE.md is ignored: AGENTS.md exists at the same level`.

### Подъём к корню репозитория

`projectLevels(cwd)` поднимается по сегментам пути, пока не найдёт `.git` (каталог **или файл**: worktree и submodule). Ссылка маркером не считается: `.git -> куда угодно` мог бы подложить чужой репозиторий и сдвинуть корень поиска. Сам `/` (на Windows — корень диска) тоже проверяется. Предел — 64 уровня (`maxProjectLevels`); репозитория нет — единственный уровень `cwd`, а в пределе ещё диагностика `limit_exceeded` (`info`): `no git repository within 64 levels above the working directory; only the working directory is searched`. Тот же подъём использует `sessionSkillRootsFor` (защита PERM-11): списки уровней не расходятся.

## Граница: `BoundedEnv`

Каждое чтение содержимого идёт через `BoundedEnv.wrap(local, корень области)`. Путь, чей `realpath` вне корня (ссылка наружу), отклоняется **до** чтения с диагностикой `outside_root`. Корень области: `cwd` для проекта, `$CODELAB_HOME` для пользователя, реальный каталог навыка для навыка.

Чтение каталога двухступенчатое (`_readMarkdownDir`):

1. Каталог проверяется относительно корня области. `BoundedEnv.wrap` канонизирует корень, поэтому ссылка `prompts → /elsewhere` сама стала бы корнем и проверка потеряла бы смысл; нужен реальный путь каталога из внешней области.
2. Файлы читаются через окружение с корнем в **реальном** каталоге шаблонов: ссылка на файл вне каталога — `outside_root`.

Реальный `config check` на доверенном проекте с тремя «плохими» шаблонами (слишком большой, с битым frontmatter, ссылка наружу):

```text
warning: ~/demo/proj/.codelab/prompts/big.md: the file is larger than 65536 bytes and is not read
warning: ~/demo/proj/.codelab/prompts/broken.md:3:7: Expected node content.
warning: ~/demo/proj/.codelab/prompts/linked.md: the file resolves outside its root and is not read
```

Проверка выполняется последовательно для каждого файла: `realpath`, `stat` реального пути (FIFO и каталог отсекаются **до** `open`: открытие FIFO блокируется), чтение не больше предела, повторная проверка после открытия.

### Остаточный TOCTOU

После `open` путь проверяется ещё раз: `resolveSymbolicLinks` должен совпасть с проверенным реальным путём, а открытый путь — оставаться обычным файлом (`_readPrefix`). В Dart нет `O_NOFOLLOW`, поэтому подмена между повторной проверкой и `read` возможна. Её цена — чтение одного файла, который владелец каталога уже мог положить сам. Обхода контейнмента для произвольных путей она не даёт. Тот же класс остаточного риска у `BoundedEnv` ядра.

## Лимиты

| Лимит | Значение | Что происходит при превышении |
|---|---|---|
| файлов `*.md` в каталоге шаблонов или агентов | 100 (`maxTemplateFiles`) | лишние пропускаются, `limit_exceeded` (`warning`); порядок — по имени, чтобы предел был детерминирован |
| размер файла шаблона или агента | 64 КиБ (`maxTemplateFileBytes`) | файл не читается, `too_large` (`error`) |
| подкаталогов в корне навыков | 1000 (`maxSkillEntries`) | остальные не читаются, `limit_exceeded` |
| размер `SKILL.md` | 128 КиБ (`maxSkillFileBytes`) | навык пропущен: `SKILL.md is larger than 128 KiB; the skill is skipped` |
| сопутствующих файлов навыка | 50 (`maxCompanions`), глубина 3 | список усечён, `companionsTruncated` |
| просмотренных записей при обходе сопутствующих | 5000 | обход остановлен, усечение |
| файл контекста | `contextMaxBytes` запроса | читается префикс `max + 1` байт |

Подкаталоги каталога шаблонов не обходятся; точечные файлы и файлы без расширения `.md` пропускаются молча.

Файл контекста читается с запасом в один байт: этот лишний байт нужен сборщику промпта в ядре, чтобы отличить «файл ровно по бюджету» от «файл больше бюджета». Полный размер берётся из `stat`, файл целиком не читается. У префикса оборванная UTF-8-последовательность в конце не считается ошибкой: `_decode(partial: true)` отбрасывает до трёх байт хвоста.

### Коды диагностики

| Код | Уровень | Значение |
|---|---|---|
| `untrusted_project` | `info` | `the project is not in trusted_projects; its prompt templates are not read` (и `agent definitions`, `skills`) |
| `untrusted_project` | `warning` | относительный элемент `skills.extra_roots` в недоверенном проекте: `the project is not trusted; a relative skills.extra_roots entry is not read` |
| `outside_root` | `warning` | цель вне корня области; файл, каталог или корень навыков не читаются |
| `unreadable` | `warning` | окружение без `realpath`, не обычный файл, ошибка чтения, каталог не листается |
| `too_large` | `error` | шаблон или агент больше 64 КиБ; `SKILL.md` больше 128 КиБ |
| `not_utf8` | `warning` | файл не UTF-8, пропущен |
| `limit_exceeded` | `warning` / `info` | превышен предел числа файлов или уровней |
| `shadowed` | `info` | `CLAUDE.md` при наличии `AGENTS.md` |
| `unresolved_root` | `warning` | корень навыков с `~`, а домашний каталог неизвестен |
| `syntax`, `profile` | `error` | ошибки frontmatter с позицией |

Что печатает `config check`: `warning:` для `error` и `warning`, `note:` для `untrusted_project` уровня `info`; прочие `info` не печатаются. Диагностика не влияет на код выхода: файлы проекта не мешают запуску.

## Frontmatter: `readMarkdownFile`

Шаблоны, агенты и навыки — Markdown с необязательным блоком YAML вверху. `readMarkdownFile(text, path:, scope:)` отделяет блок и разбирает его тем же `readYamlTree`, что и `config.yaml`: ошибки выглядят одинаково, профиль тот же (без якорей, тегов, повторов ключей), позиции в координатах файла.

Правила:

- первая строка (после BOM) равна `---` → frontmatter до следующей строки `---`; пробелы в конце строки допустимы;
- CRLF читается как LF, тело возвращается с LF;
- первой строки `---` нет → frontmatter нет, тело — весь текст;
- закрывающей `---` нет → `syntax` на строке 1: `the frontmatter is not closed by a "---" line`;
- нарушение профиля или синтаксис YAML → `profile` или `syntax`, сообщения фиксированные (в них нет фрагментов файла).

**Починка YAML** (`repairYaml: true`, только навыки). Авторы навыков часто пишут в frontmatter `description: Use when: the user asks…` — двоеточие с пробелом ломает YAML. Если разбор не удался, строки верхнего уровня `ключ: значение` с значением без кавычек, которое содержит `: `, один раз переписываются в строки в одинарных кавычках (`'` удваивается; `\` и `"` остаются как есть), и блок разбирается снова. Успех — `repaired`, диагностику `yaml_repaired` выдаёт ядро (`parseSkills`). Неудача — диагностики первого разбора. Номера строк при починке не меняются. Шаблоны и определения агентов остаются строгими: починка им не нужна.

## Навыки

Корни навыков и их приоритет строит чистая функция `skillRootPlan`. Её результат читает загрузчик, а `loadProjectExtensions` показывает странице навыков с теми же номерами: два списка разошлись бы тихо. Порядок (номер корня — его позиция в списке, это `SkillFile.rootIndex`):

1. Уровни проекта от `cwd` вверх до корня git; на каждом `.codelab/skills`, затем `.agents/skills` — только доверенный проект. У недоверенного на каждый **существующий** каталог пишется `untrusted_project`.
2. `$CODELAB_HOME/skills`.
3. `<userHome>/.agents/skills`.
4. Элементы `skills.extra_roots`: абсолютные и `~`/`~/…` (раскрываются в `userHome`; без него — `unresolved_root`); относительные считаются от `cwd` и только для доверенного проекта; `~user/…` и `<scheme>://…` — не корни, без диагностики.

Раскрытие корней проекта и `$CODELAB_HOME/skills` идёт через `BoundedEnv` своего уровня: ссылка корня наружу — `outside_root`. Корень `~/.agents/skills` и элементы `extra_roots` назвал пользователь явно, и граница к ним не применяется.

Дальше для каждого подкаталога корня: имена на точку и файлы пропускаются, ссылки проверяет `realpath`, каталог навыка вне корня — `outside_root`, повтор по реальному пути (`seen`) пропускается. `SKILL.md` читается целиком с лимитом 128 КиБ, затем `readMarkdownFile(repairYaml: true)`. Сопутствующие файлы перечисляются **без чтения**: обычные файлы на глубине до 3, не больше 50 в байтовом порядке, без каталогов на точку, без `evals/` верхнего уровня, без самого `SKILL.md` и без записей, чей `realpath` вне каталога навыка.

## Несколько расчётов поверх загрузчика

### `loadProjectExtensions`

Файлы проекта и навыки папки одним расчётом для `config check` и страницы навыков в app. Правила:

- `cwd` канонизируется внутри (`realpath`); если не разрешился — проект недоверенный (fail-closed);
- обе фазы читаются **параллельно**, у каждой свой предел времени (по умолчанию 5 секунд — как у рантайма) и свой токен отмены;
- навыки не читаются при `skills.enabled: false` (тогда `ProjectExtensions.skills == null`);
- расчёт не пишет журнал и не бросает: таймаут (`PhaseTimedOut`), исключение порта (`PhaseFailed` с **именем типа**: текст мог бы содержать пути) и сбой подготовки (`preparationError`) — значения исхода.

Швы для тестов: `projectFiles`, `skillFiles`, `skillsTimeout`. Подмена зависшего порта проверяет таймаут; тип `ProjectExtensionsLoader` нужен `ConfigCommands` для теста «сбой подготовки».

### `projectTrustAt`

Одна функция для `config check` и страницы настроек: `(cwd, trusted)`. Путь папки раскрывается `realpath`; доверие — это совпадение с одним из `config.trustedProjects` (обратные косые в записи заменяются на `/`). Путь, который не разрешился, — недоверенный, а `cwd` остаётся абсолютным путём без канонизации.

### `loadAgentDefinitions`

Читает и разбирает определения агентов тем же путём, что `config check`, и возвращает `AgentDefinitionsReport` (определения, диагностика, `timedOut`). Разбор `parseAgentDefinitionsOf` сводит в одну функцию сборку каталога моделей из провайдеров конфигурации (`StaticModelCatalog`), чтобы `config check` и страница не расходились. Без папки (`cwd == null`) читается только `$CODELAB_HOME/agents`, а диагностика недоверенного «проекта» отбрасывается. По таймауту источник получает отменённый токен.

## Что запомнить

- Чтение содержимого — только через `BoundedEnv`; ссылка наружу не читается, а даёт диагностику.
- `load` не бросает: каждая проблема — запись диагностики без содержимого файла.
- Недоверенный проект не добавляет ни команды, ни агентов, ни навыки: пользователь видит причину.
- Лимиты (100 файлов, 64 КиБ, 128 КиБ, 50 сопутствующих) — защита ресурсов, не часть контракта пользователя.
- Корни навыков и уровни проекта строят общие функции; дублировать их нельзя.

## Смотрите также

- [Глава 9 ядра: файлы проекта, промпты, команды, агенты](../../codelab_agent_core/doc/09-config-prompts-commands.md)
- [Глава 4: пути, защищённые политикой разрешений](04-config-writing-and-reload.md#что-защищает-политика-разрешений-agentconfigpathsfor)
- Тесты: `test/project/` (15 файлов): `project_context_loader_test.dart`, `prompt_templates_load_test.dart`, `skill_files_load_test.dart`, `skill_root_plan_test.dart`, `frontmatter_repair_test.dart`, `project_files_loader_seam_test.dart`
