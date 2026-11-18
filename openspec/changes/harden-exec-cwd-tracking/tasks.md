Порядок: 0 → 1 → 2 → 3 → 4. Внутри 1 и 2 — пары «красный тест → реализация». Все задачи — `[agent]`, пакет `packages/dart/codelab_agent_core`.

TDD (`codelab_agent_core/AGENTS.md` §2): красный тест каждой пары коммитится отдельно до кода — только по явной просьбе пользователя. Тесты — чистый Dart через `findCritical(command, cwd: '/work/demo', commandCwd: …, agentConfig: …)`. Пути хоста — `AgentConfigScope.resolve(AgentConfigPaths(…), null)`, как в `config_exec_whitelist_test.dart`. Политика целиком — через `policy_harness.dart`. Каталог навыка в тестах — проектный `/work/demo/.codelab/skills/pdf`: он защищён в `develop` без change `add-agent-skills`.

## 0. Документы

- [x] 0.1 `[agent]` Документ ядра до кода (выполнено архитектором 2026-11-13; `codelab_agent_core/AGENTS.md`, «сначала документ»). Файл — `docs/architecture/proposals/agent-core/07-permissions.md`:
  - §7.6, правило разбора 9 — зарезервированные слова, `trap`, связки, блоки, лаунчеры, происхождение вложенного текста;
  - строка таблицы `write in unknown working directory`;
  - ссылка в пункте `exec` «Сравнения» §7.6.1 на §7.6.2;
  - новый §7.6.2 «Рабочий каталог команды» — модель, таблица блоков и вложенных текстов, правило «неизвестно», метка, стыковка с E1–E3, известные пределы, допущение «новый `/bin/sh -c`»;
  - пункт §7.11 про `exec_working_dir_test.dart`.

## 1. Лексер (`lib/src/permissions/shell_lexer.dart`)

- [x] 1.1 `[agent]` Красные тесты разбора, `test/permissions/shell_lexer_test.dart` (spec «Критические шаблоны команд»; design.md, D2, D6–D8, D10):
  - связка конвейера: `a && b`, `a || b`, `a; b`, `a & b`, перевод строки; `! a` — отрицание;
  - зарезервированные слова сняты: `if a; then b; elif c; else d; fi`, `while a; do b; done`, `until a; do b; done`; у сегментов команды `a`, `b`, `c`, `d`, а не `then`/`do`/`else`;
  - заголовок `for f in x y; do cat "$f"; done` — не команда;
  - дерево `ShellScript.commands` (D2, D6): блок `ShellBlock(kind, body)` — стадия `ShellStage` рядом с `ShellSimple`; виды — подоболочка `(a; b)`, группа `{ a; }`, `if`, цикл, тело функции `f(){ a; }` и `function f { a; }`;
  - блок стадией конвейера: `{ a; } | c`, `( a ) | c`, `if a; then b; fi | c` — один `ShellCommand` из двух стадий;
  - перенаправление после `done`/`}` принадлежит блоку (`ShellBlock.redirections`);
  - несходящиеся блоки — `ShellParseException`: лишние `then`/`do`/`fi`/`done`/`}`, незакрытые `{`/`if`/цикл, `for ((…))`, слово после закрытого блока (D10);
  - снятые лаунчеры: `env cd x`, `command cd x`, `builtin cd x`, `time cd x`, `sudo -D d cd x`;
  - происхождение вложенного текста: подстановка, `sh -c`, `env -S`, `eval`, `git -c core.pager=…`, `GIT_PAGER=…`, `find -exec`/`-execdir`, `trap 'x' EXIT`;
  - `case` по-прежнему `ShellParseException`.
- [x] 1.2 `[agent]` Реализация 1.1. Лексер:
  - дерево `ShellScript.commands` рядом с плоскими `pipelines` (D2): `ShellCommand(stages, next: ShellConnector, negated)`, sealed `ShellStage` — `ShellSimple(segment)` и `ShellBlock(kind, body)` с `redirections` (D6); стек `_Frame` открытых блоков — только в построителе; оба вида делят одни объекты `ShellSegment`;
  - `ShellSegment.launchers`;
  - происхождение `ShellScript.origin` (`ShellOrigin`: `root`, `substitution`, `command`, `eval`, `foreign`; D8);
  - снятие зарезервированных слов и ошибки несходящихся блоков (D10);
  - `trap`.

  Doc-комментарии новых типов — по-русски, «почему / для чего / как» (корневой `AGENTS.md` §15), со ссылками на D2, D6–D8, D10. Комментарий библиотеки — без «`cd` не меняет каталог» в старом смысле: каталог ведёт обход.
- [x] 1.3 `[agent]` Красные тесты таблицы, `test/permissions/critical_patterns_test.dart`. Сценарии «Зарезервированные слова не прячут команду» и «Заголовки составных команд не считаются командами»:
  - `if true; then rm -rf /; fi`, `if false; then :; else rm -rf ~; fi`, `while true; do rm -rf /; done`, `for d in a b; do sudo reboot; done`, `! rm -rf /`, `trap 'rm -rf /' EXIT` — со своими метками;
  - `for f in a.txt b.txt; do cat "$f"; done`, `if test -f a; then echo yes; fi`, `while read l; do echo "$l"; done < in.txt` — `null`.
- [x] 1.4 `[agent]` Реализация 1.3: обход `_checkSegment` видит команду после снятия слов. Если 1.2 уже даёт зелёный — только проверка.

## 2. Модель каталога (`critical_patterns.dart`, `agent_config_rules.dart`)

- [x] 2.1 `[agent]` Красные тесты примеров 1–6, новый `test/permissions/exec_working_dir_test.dart` (spec «Рабочий каталог команды exec при проверке PERM-11»):
  - «cd - после смены каталога» — уровень `findCritical`; `bypass` и `autopilot` — через `policy_harness.dart`;
  - «popd возвращает в каталог навыка»;
  - «CDPATH в строке команды», включая `CDPATH=/x cd ./build && make` → `null`;
  - «Путь конфигурации хоста через cd - и popd»;
  - «Неизвестная цель cd»;
  - «Неудачный cd оставляет прежний каталог».

  Точный список меток — `CriticalMatch.labels`.
- [x] 2.2 `[agent]` Реализация 2.1:
  - новый `lib/src/permissions/shell_dir_state.dart`: значение `ShellDirState` (каталог, `OLDPWD`, стек), множество `DirVariants` с ⊤ и пределом 32, `DirFlow` (успех/неуспех), признаки строки `DirContext` (D1, D4, D5);
  - переход `dirCommandFlow` для `cd`/`pushd`/`popd`/`dirs` (D3) вместо `ConfigCheck.cdTarget`;
  - новый `lib/src/permissions/exec_dir_walk.dart`: обход `ExecDirWalk` по дереву `ShellScript.commands` со связками и отрицанием (D2) вместо `_walk`; правила таблицы он получает от `findCritical` функцией проверки сегмента;
  - `launcherDir` с ⊤ (D4).

  `ExecDirWalk` проверяет сегмент для каждого известного варианта; `_walk` и его doc-комментарий удалены (расхождение из design.md, «Context»).
- [x] 2.3 `[agent]` Красные тесты блоков, лаунчеров и вложенных текстов, `exec_working_dir_test.dart`:
  - сценарии «Подоболочка, конвейер, фон и внешний лаунчер не меняют каталог», «eval меняет каталог текущей оболочки», «Составные команды, функции и чужой каталог вложенной команды»;
  - `time cd /tmp && touch SKILL.md` после `cd <навык>;` — критично;
  - `command cd /tmp && touch SKILL.md` после `cd <навык> &&` — `null`;
  - `cd <навык> && cd /tmp && sh -c 'cd -; touch SKILL.md'` — `write in unknown working directory` (`OLDPWD` в `sh -c` неизвестен);
  - `cd <навык>; echo "$(cd /tmp)"; touch SKILL.md` — критично (подстановка не выходит наружу; закрепление, зелёный и до change).
- [x] 2.4 `[agent]` Реализация 2.3: таблицы D6, D7, D8 в обходе.
- [x] 2.5 `[agent]` Красные тесты правила «неизвестно» и метки, `exec_working_dir_test.dart` и `autopilot_test.dart`:
  - «Только чтение в неизвестном каталоге»;
  - «Метка неизвестного каталога в autopilot»: `reason` в `bypass`, `allowAlwaysOffered: false`, прежний `allowAlways` не действует, текст отказа в `autopilot`;
  - «Предел числа вариантов»;
  - метка `write to agent configuration`, а не новая, если известный вариант попал в защищаемый путь (пример 1);
  - `cd "$X" && echo x > /tmp/a` — `null` (абсолютная цель);
  - `cd "$X" && echo x > ~/.codelab/config.yaml` — `write to agent configuration`;
  - `cd "$X" && time -o out ls` — `write in unknown working directory`.
- [x] 2.6 `[agent]` Реализация 2.5:
  - правило D9 в `_checkSegment` или `agent_config_rules.dart`;
  - константа `_unknownDir = 'write in unknown working directory'` в `_tableOrder` сразу после `_agentConfig`;
  - предел 32 (D1).
- [x] 2.7 `[agent]` Тест-закрепление второго прохода и времени, `exec_working_dir_test.dart` (зелёный после 2.6; design.md, «Risks / Trade-offs»):
  - ссылка `/work/demo/h -> /home/u/.codelab/agents` в фейковом `PathResolver` политики, хостовый путь `/home/u/.codelab/agents`; `exec cd /work/demo/h && cd /tmp && cd - && tee x.md` — критично после `canonicalizeSeen` (вариант после `cd -` — путь ссылки, второй проход раскрывает его);
  - строка из 200 `pushd /a<i>;` и вложенных `$(…)` глубины 4 разбирается быстрее 200 мс на VM (порог в тесте с запасом).

## 3. Регрессия

- [x] 3.1 `[agent]` Прогон `test/permissions/` целиком: `critical_patterns_test.dart`, `config_exec_whitelist_test.dart`, `agent_config_paths_test.dart`, `autopilot_test.dart`, `permission_request_fields_test.dart`, `policy_*`. Ожидаемых изменений нет. Если тест меняет исход, это либо новое верное срабатывание по D2–D9 (тест правится со ссылкой на сценарий), либо дефект реализации. Молча менять ожидание ЗАПРЕЩЕНО (корневой `AGENTS.md` §17). Список изменённых ожиданий — в описание PR.
- [x] 3.2 `[agent]` Тест-закрепление сценария «Обычная работа в корне остаётся обычной», `exec_working_dir_test.dart`: все команды сценария — `null` при `.codelab` в корне и хостовых путях из `config_exec_whitelist_test.dart`.

## 4. Проверки и стыковка

- [x] 4.1 `[agent]` Проверка затронутого (корневой `AGENTS.md` §21):
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_agent_core`;
  - `melos run web-compile` — изменён web-безопасный пакет;
  - `melos run conformance:agent` — метки уходят в `session/request_permission`, фикстуры должны остаться зелёными;
  - `guard` не нужен: `pubspec.yaml` и импорты между пакетами не меняются.

  В PR перечислить запущенное и указать, что полный `check` не запускался.
- [x] 4.2 `[agent]` Стыковка с E1–E3 и Q47 change `add-agent-skills` (design.md, D11). Итерация 2 навыков уже в `develop` `8277295c`; этот change влился вторым:
  - E1–E3 перенесены на обход по вариантам: E2 — только для известного варианта каталога навыка, E1 не снимает правило ⊤;
  - признак «E1 отключён» (Q47) ставят группа, `if`, цикл и `!`, подоболочка — нет (D6); `cd "$(mktemp -d)" && python3 <скрипт навыка>` — `write to agent configuration`, `cd "$X" && python3 <скрипт навыка>` — `write in unknown working directory`;
  - прогон `skill_script_exceptions_test.dart` и `exec_skill_cwd_test.dart`;
  - `07-permissions.md`: абзац E1–E3 и строка E2 (`cd`, `pushd`, `popd`) ссылаются на §7.6.2.
- [x] 4.3 `[agent]` Документы и код не расходятся (`codelab_agent_core/AGENTS.md` §3 (е)): §7.6, §7.6.2, §7.11 и doc-комментарии `shell_lexer.dart`, `critical_patterns.dart`, `agent_config_rules.dart` описывают одно поведение. `openspec validate harden-exec-cwd-tracking --strict`.

## 5. Исправления по ревью (design.md, D16)

Пары «красный тест → реализация», файлы — `test/permissions/shell_lexer_test.dart`, `critical_patterns_test.dart`, `exec_working_dir_test.dart`; код — `shell_lexer.dart`, `exec_dir_walk.dart`, `shell_dir_state.dart`.

- [x] 5.1 `[agent]` Красные тесты B1 (сценарий «for без in не прячет тело»): `for x do rm -rf /; done`, `for x` + перевод строки + `do touch .codelab/config.yaml; done` — критичны; `for x y; do :; done` — `unparsable command`.
- [x] 5.2 `[agent]` Реализация 5.1: незакавыченное `do` после имени или после списка `in` закрывает заголовок `for`/`select`; иное слово в заголовке — `ShellParseException`.
- [x] 5.3 `[agent]` Красные тесты B2 (сценарий «Фон уводит весь and-or список»): `cd .codelab; cd /tmp && true & touch config.yaml` — `write to agent configuration`; `cd sub && make &` не критичен.
- [x] 5.4 `[agent]` Реализация 5.3: состояние после `&` — как до начала and-or списка.
- [x] 5.5 `[agent]` Красные тесты H1, H2 (сценарии «Зарезервированное слово не после перенаправления», «command -v не меняет каталог»).
- [x] 5.6 `[agent]` Реализация 5.5: зарезервированные слова — только в пустом сегменте; `command -v`/`-V` не вызывают `dirCommandFlow`.
- [x] 5.7 `[agent]` Красные тесты H3–H6 (сценарий «trap, динамическая команда и состояние bash»); `trap - EXIT`, `trap '' INT`, `trap -p` состояние не меняют.
- [x] 5.8 `[agent]` Реализация 5.7: `trap` с действием и динамическая команда / нелитеральный `eval` дают ⊤; признаки `CDPATH`/`OLDPWD` при косвенной записи; признаки `enable`, `DIRSTACK`, `cdable_vars` в `DirContext`.
- [x] 5.9 `[agent]` Красные тесты M1 (сценарий «Недостижимая ветка не теряет метки»): `popd && touch .codelab/config.yaml` — `write to agent configuration`; `popd && make` — `null`.
- [x] 5.10 `[agent]` Реализация 5.9: пустой исход — следующий сегмент проверяется во входных вариантах команды, давшей пустой исход, а не в `unknownWorkingDirectory`.
- [x] 5.11 `[agent]` Красные тесты M2 (сценарий «Пределы разбора»): 65 вложенных групп и строка длиннее 128 KiB — `unparsable command`, без `StackOverflowError`, время в пределах порога задачи 2.7.
- [x] 5.12 `[agent]` Реализация 5.11: пределы глубины блоков 64 и длины 128 KiB до разбора.
- [x] 5.13 `[agent]` Красные тесты L1 (сценарий «Переменная-команда через read»), а также `printf -v EDITOR …; git commit`, `declare -n R=EDITOR; git commit`.
- [x] 5.14 `[agent]` Реализация 5.13: косвенная запись переменной-команды откладывает проверку следующего сегмента как `foreign`.
- [x] 5.15 `[agent]` Doc-комментарии затронутых сущностей и `07-permissions.md` (правило 9, §7.6.2) описывают одно поведение; прогон `test/permissions/` целиком и проверки задачи 4.1; `openspec validate harden-exec-cwd-tracking --strict`. Документы синхронизированы архитектором вместе с D17; прогон тестов — задача 6.12.

## 6. Исправления по повторному ревью (design.md, D17)

Решение пользователя: N1, N2, N9 входят в этот change. Код — `shell_lexer.dart`, `shell_words.dart` (новый), `exec_dir_walk.dart`, `shell_dir_state.dart`, `agent_config_rules.dart`, `critical_patterns.dart`; тесты — `test/permissions/`.

- [x] 6.1 `[agent]` A1 и `mayChangeDirectory`: цикл по потоку (повторный обход тела от «вход ∪ конец ∪ ⊤»), общий предикат для перехода, цикла и `trap`. Сценарий «Цикл, который меняет каталог через переменную».
- [x] 6.2 `[agent]` A2: динамическое имя — маски `*?[{` в первом слове, `$`/обратная кавычка в слове-нефайле; «файл» — `/` до первого раскрытия или сразу после раскрытия в двойных кавычках либо `$HOME`/`$CODELAB_HOME`/`~`; сбалансированные `${…}` в префиксе. Красный тест: `$d/run && make` и `${d}/run && make` — `write in unknown working directory` (сейчас `null`). Сценарий «Динамическое имя команды». Маски и `"$d"/run` уже реализованы.
- [x] 6.3 `[agent]` A3: `-v`/`-V` у любого снятого `command` → `lookupOnly`; лаунчер по пути — внешняя программа. Сценарий «Лаунчер command с путём и поиск».
- [x] 6.4 `[agent]` A4: пустой вход заменяется входом предыдущей команды уровня, `cd` идёт от него; `_lastInput` удалён. Сценарий «cd после недостижимой ветки».
- [x] 6.5 `[agent]` A5: один разбор `variableWrites`; признаки `cdpath`/`oldpwd`/`dirstack`, `shopt`/`set` с нелитеральным аргументом, способы записи переменной-команды, присваивание `^NAME(\[…\])?\+?=`, `..` после обычной компоненты. Сценарии «Физический .. и нелитеральные shopt и set», «Косвенная запись переменной-команды» (кроме случаев 6.10).
- [x] 6.6 `[agent]` A6: правила без каталога — один раз на сегмент, пары (каталог, `OLDPWD`), `maxDirWalkWork = 20000`, порог времени в тестах 1 с. Сценарий «Бюджет обхода».
- [x] 6.7 `[agent]` A7, A8: `trap` даёт ⊤ только при `mayChangeDirectory` в действии, иначе действие проверяется в конце во всех состояниях строки без ⊤; непотреблённое отложенное значение при `trap` — в конце с ⊤. Сценарий «Зарезервированные слова не прячут команду» (`trap` — одна метка).
- [x] 6.8 `[agent]` A8, финальное состояние: «все состояния строки» SHALL включать состояние после последней команды. Красный тест: `trap 'touch config.yaml' EXIT; cd /work/demo/.codelab` — `write to agent configuration` (сейчас `null`; с `; true` в конце — срабатывает). Сценарий «trap без смены каталога».
- [x] 6.9 `[agent]` A9: двойной `!` — `unparsable command`.
- [x] 6.10 `[agent]` A5/L1, потребитель неизвестного значения: при косвенной записи значение неизвестно, поэтому на первой следующей команде-необъявлении оно SHALL считаться командой не из белого списка чтения (метка `write in unknown working directory`), даже если сама эта команда — только чтение. Красные тесты: `read EDITOR <<< 'touch SKILL.md'; true; git commit`, `printf -v EDITOR x; ls; git commit` (сейчас `null`: `true`/`ls` поглощают признак). Сценарий «Косвенная запись переменной-команды».
- [x] 6.11 `[agent]` N1 (`${…}` и `$((…))`), N2 (`a+=1`, `a[0]=1` в префиксе), N9 (`~+`, `~-`, `~user`). Сценарии «Подстановки внутри раскрытий и присваивания с += и индексом», «Тильды ~+, ~- и ~user».
- [x] 6.12 `[agent]` Проверка затронутого после 6.2, 6.8, 6.10: `fvm dart format`, `fvm dart analyze` и `fvm dart test` в `codelab_agent_core`, `melos run web-compile`, `melos run conformance:agent`; doc-комментарии `shell_words.dart`, `exec_dir_walk.dart` (в том числе `_fileWord` — без оговорки «разбор этого не знает» после 6.2) согласованы с §7.6.2; `openspec validate harden-exec-cwd-tracking --strict`.

## 7. Исправления третьего раунда (design.md, D18)

Последний раунд исправлений по решению пользователя: дальнейшие обходы — известные пределы (D12, §7.6.2), кроме CRITICAL и регрессий относительно `develop`. Doc-комментарии в коде ссылаются на эти правила как «D17, C1…W7, F1»; при следующей правке кода ссылки СЛЕДУЕТ привести к «D18».

- [x] 7.1 `[agent]` C1–C4: `$'…'` и `$"` внутри `${…}`, `'`/`$'` в `"${…}"` — `unparsable command`, условия арифметики `$((…))`, вложенность раскрытий ≤ 64. Сценарий «Кавычки и арифметика в раскрытиях».
- [x] 7.2 `[agent]` W1: состояние каждой оболочки (`ExecDirWalk._shell`), наследование для подоболочки и подстановки, проверка отложенных `trap` в `_seen` и конечном состоянии оболочки. Сценарий «Состояние вложенной оболочки не выходит наружу».
- [x] 7.3 `[agent]` W2, W3: повтор тела цикла при смене состояния оболочки; `trap` с `alias`, функцией или записью переменной-команды ставит ⊤ и проверяется сразу. Сценарий «trap и цикл, меняющие состояние оболочки».
- [x] 7.4 `[agent]` W4, W5: `runsHiddenText` (`fc`, `history -s`, `mapfile -C`), `declare -n R` без `=`; `enable` по имени команды, порядкозависимый `_enableSeen`. Сценарий «Скрытый текст и enable».
- [x] 7.5 `[agent]` W6: `~+`/`~-` — относительные цели правила ⊤. Сценарий «Тильды в правиле неизвестного каталога».
- [x] 7.6 `[agent]` W7: `maxKnownDirStack = 64`, `maxDirPathLength = 4096`.
- [x] 7.7 `[agent]` F1: литеральное присваивание без команды не ставит `_foreignNext`. Сценарий «Литеральное присваивание без команды».
- [x] 7.8 `[agent]` Документы синхронизированы с D18 (design, спека, `07-permissions.md`, proposal); `openspec validate harden-exec-cwd-tracking --strict`.
- [x] 7.9 `[agent]` Проверка затронутого на итоговом коде (как 6.12): format, analyze, тесты `codelab_agent_core`, `web-compile`, `conformance:agent`. Doc-комментарий поля `DirContext.enable` (`shell_dir_state.dart`) говорит «подстрока `enable`» — привести к W5; ссылки «D17, C1…W7, F1» — к «D18».
- [x] 7.10 `[agent]` W1 для фонового and-or списка (`{ …; } &`, `A && B &`): оболочка-подоболочка, наследует `_tainted`; ловушки проверяются в её конечном состоянии, снаружи — вход списка. CRITICAL-регрессия относительно `develop`. Красный тест — сценарий «Ловушка фонового списка»: `{ trap 'echo > config.yaml' EXIT; cd .codelab; } & wait` — `write to agent configuration`.
