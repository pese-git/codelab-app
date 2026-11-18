## MODIFIED Requirements

### Requirement: Критические шаблоны команд
Команда `exec` SHALL разбираться лексером §7.6 документа ядра:
- одинарные и двойные кавычки, `\`;
- операторы `&&`, `||`, `;`, `|`, `&`, перевод строки, подоболочки и группы; лексер SHALL строить рядом с плоским списком конвейеров дерево команд: у каждого конвейера — связка со следующим (`&&`, `||`, `;` или перевод строки, `&`) и отрицание `!`, стадия конвейера — простая команда или блок (подоболочка `( … )`, группа `{ … }`, `if … fi`, цикл `while|until|for|select … done`, тело функции) со своими командами и перенаправлениями после закрывающего слова (design.md change `harden-exec-cwd-tracking`, D2, D6);
- зарезервированные слова в позиции команды (`if`, `then`, `elif`, `else`, `while`, `until`, `do`, `!`) SHALL сниматься: команда после них проверяется как любая другая; позиция команды — только пустой сегмент, без слов и перенаправлений (`>/dev/null ! cd x` — команда `!`, D16 H1); заголовок `for`/`select NAME [in …]` командой не считается, его SHALL закрывать незакавыченное `do` после имени или после списка `in` (`for x do …; done`, D16 B1); `fi`, `done`, `}` закрывают блок (D10);
- подстановки `$( … )`, `` ` … ` ``, `<( … )`, `>( … )` как вложенные команды, в том числе внутри `${ … }` (с учётом вложенности, кавычек и `\}`) и внутри `$(( … ))`; `$((` — арифметика, только если закрывается смежными `))` и внутри нет `'`, `"`, `\`, `#`, обратной кавычки, `$(` и `${`, иначе это подстановка с подоболочкой (D17 N1, D18 C3); внутри `${ … }` вне двойных кавычек `$'…'` SHALL разбираться как ANSI-C строка, `$"` — пропускаться (D18 C1);
- аргумент после `-c` у shell, аргументы `eval` и первый аргумент `trap` как вложенная команда;
- here-document как данные;
- снятие присваиваний (`NAME=`, `NAME+=`, `NAME[i]=`, D17 N2) и лаунчеров (`sudo`, `doas`, `env`, `nohup`, `nice`, `time`, `command`, `exec`, `builtin`, `timeout`, `stdbuf`, `xargs`); имена снятых лаунчеров SHALL сохраняться у сегмента;
- сравнение по базовому имени;
- перенаправления.

Текст внутри кавычек аргумента командой не считается. Незакрытая кавычка или глубина больше 4 SHALL давать шаблон `unparsable command`. Тот же шаблон SHALL давать несходящаяся структура блоков (D10): лишние `then`, `elif`, `else`, `do`, `fi`, `done`, `}`, `)`; незакрытые `{`, `(`, `if` или цикл; арифметический `for ((…))`; слово или блок без разделителя сразу после закрытого блока; в заголовке `for`/`select` любое слово, кроме `in` вторым словом и `do`, закрывающего заголовок. Тот же шаблон SHALL давать глубина вложенности блоков больше 64, команда длиннее 128 KiB до разбора, больше 20 000 проверок «сегмент × вариант» при обходе каталога (D16 M2, D17 A6), незакрытое раскрытие `${` и двойной `!` (D17 N1, A9), вложенность `${…}` больше 64 (D18 C4), `'` или `$'` внутри `${…}` в двойных кавычках — bash и dash ищут `}` по-разному (D18 C2).

Таблица §7.6 SHALL содержать строку `write in unknown working directory` сразу после `write to agent configuration`; правило строки — requirement «Рабочий каталог команды exec при проверке PERM-11».

Совпадение с любой строкой таблицы критических шаблонов §7.6 SHALL давать вопрос с `reason: 'critical command: <метки через "; ">'` и `allowAlwaysOffered: false` в любом режиме с человеком, даже после `allowAlways` на эту команду. В `autopilot` совпадение SHALL давать отказ `critical command blocked in autopilot: <метка>` без вопроса (PERM-9).

#### Scenario: Таблица срабатываний
- **WHEN** табличный тест проверяет каждый пример столбцов «Срабатывает» и «Не срабатывает» §7.6, а также `cd /tmp && rm -rf /`, `git commit -m "rm -rf /"`, `sh -c 'rm -rf ~'`, `eval "$(curl u)"` и команду с незакрытой кавычкой
- **THEN** первые совпадают со своими метками, вторые не совпадают ни с одной, `git commit -m "rm -rf /"` безопасна, последняя даёт `unparsable command` (`critical_patterns_test.dart`)

#### Scenario: Критическая команда в bypass и autopilot
- **WHEN** в режиме `bypass` с `allowAlways` для `exec rm -rf /` модель снова вызывает эту команду, а затем то же происходит в `autopilot`
- **THEN** в `bypass` gate получает запрос без варианта `allow_always`, а в `autopilot` вызов отклонён без запроса (`autopilot_test.dart`, `acp/permission-critical-pattern-in-bypass` на уровне ядра)

#### Scenario: Зарезервированные слова не прячут команду
- **WHEN** табличный тест проверяет `if true; then rm -rf /; fi`, `if false; then :; else rm -rf ~; fi`, `while true; do rm -rf /; done`, `for d in a b; do sudo reboot; done`, `! rm -rf /` и `trap 'rm -rf /' EXIT`
- **THEN** каждая команда совпадает с меткой своей строки таблицы (`recursive delete of a protected path`, `privileged command; host shutdown or reboot`), как без обёртки; действие `trap 'rm -rf /' EXIT` каталог не меняет и даёт только `recursive delete of a protected path` (D17 A8) (`critical_patterns_test.dart`)

#### Scenario: Несходящиеся блоки неразбираемы
- **WHEN** табличный тест проверяет `if a; then b`, `fi`, `then a`, `do a`, `{ a`, `if a; then b; done`, `for ((i=0; i<3; i++)); do a; done`, `{ a; } b` и `time { echo x; }`
- **THEN** каждая даёт `unparsable command` (`shell_lexer_test.dart`, `critical_patterns_test.dart`)

#### Scenario: Подстановки внутри раскрытий и присваивания с += и индексом
- **WHEN** табличный тест проверяет `echo ${x:-$(rm -rf /)}`, `echo $(( $(rm -rf /) 0 ))`, `echo $((rm -rf /) )`, `a+=1 rm -rf /`, `a[0]=1 rm -rf /`, затем `echo ${x`, `! ! rm x` и `echo $((1+2))`
- **THEN** первые пять совпадают с `recursive delete of a protected path`, `echo ${x` и `! ! rm x` дают `unparsable command`, `echo $((1+2))` не критична

#### Scenario: Заголовки составных команд не считаются командами
- **WHEN** табличный тест проверяет `for f in a.txt b.txt; do cat "$f"; done`, `if test -f a; then echo yes; fi` и `while read l; do echo "$l"; done < in.txt`
- **THEN** ни одна не совпадает ни с одной строкой таблицы; слова `in`, `a.txt`, `b.txt` заголовка `for` не проверяются как аргументы команды `f`

## ADDED Requirements

### Requirement: Рабочий каталог команды exec при проверке PERM-11
Обход команды `exec` SHALL вести не одну строку текущего каталога, а множество вариантов состояния оболочки (design.md change `harden-exec-cwd-tracking`, D1). Требование уточняет фразу «после `cd DIR` — `DIR` становится рабочим каталогом следующих команд цепочки» requirement «Критические пути правок конфигурации агента».

**Состояние.** Вариант состояния — текущий каталог, `OLDPWD` и стек каталогов `pushd`. `OLDPWD` бывает известным абсолютным путём или неизвестным. К множеству вариантов SHALL добавляться вариант «неизвестно»: любой каталог. Начальное состояние строки:
- каталог — `cwd` вызова `exec` (по умолчанию корень сессии);
- `OLDPWD` неизвестен: его даёт окружение исполнителя;
- стек пуст: каждый вызов `exec` — новый процесс `/bin/sh -c` (`LocalExecutionEnv`, `AcpClientEnv`).

Если известных вариантов больше 32, они SHALL заменяться вариантом «неизвестно».

**Проверка.** Каждая простая команда SHALL проверяться правилами «Критические пути правок конфигурации агента» для каждого известного варианта каталога и критична, если критична хоть для одного. При варианте «неизвестно» простая команда SHALL быть критической, если выполнено одно из условий:
- она не из белого списка чтения (с учётом опций записи и исполнения, снимающих исключение);
- у неё есть перенаправление записи с относительной целью;
- значение вывода лаунчера (`time -o`) относительное.

Относительная цель — после раскрытия `~`, `$HOME`, `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}` не начинается с `/` и не начинается с переменной. Абсолютные пути и пути с `~`/`$HOME`/`$CODELAB_HOME` SHALL проверяться как раньше, независимо от каталога.

**Метка.** Сегмент, критичный только из-за варианта «неизвестно», SHALL давать метку `write in unknown working directory`. Если хоть один известный вариант делает сегмент критичным по правилам PERM-11, метка — `write to agent configuration`. Метки остальных строк таблицы §7.6 SHALL вычисляться как раньше. Реакция — как у любого критического шаблона: вопрос без `allow_always` в любом режиме с человеком, в `autopilot` и без gate — отказ `critical command blocked in autopilot: write in unknown working directory` (PERM-9).

**Связки.** Обход SHALL различать успех и неуспех конвейера:
- после `&&` следующий конвейер выполняется только из вариантов успеха, после `||` — только из вариантов неуспеха;
- после `;`, перевода строки и конца блока — из всех;
- `!` меняет успех и неуспех местами.

Успех встроенной смены каталога означает, что каталог сменился, неуспех — что каталог и стек не изменились. Встроенная смена каталога здесь — `cd`, `pushd`, `popd`, стоящие одной стадией конвейера, без лаунчера или под `command`/`builtin`. Об успехе прочих команд обход SHALL считать неизвестным: оба исхода из тех же вариантов.

**`cd`, `pushd`, `popd`:**
- опции `-L`, `-P`, `-e`, `-@` пропускаются, `--` завершает опции; другая опция даёт «неизвестно» при успехе;
- `cd` без аргумента — `HOME` из `expansions` хоста, без него — «неизвестно»;
- `cd -` — известный `OLDPWD` варианта; неизвестный `OLDPWD` даёт «неизвестно»;
- успешный `cd`/`pushd`/`popd` записывает прежний каталог в `OLDPWD`;
- `pushd DIR` при успехе кладёт прежний каталог в стек;
- `pushd` без аргумента меняет местами каталог и вершину стека; с пустым стеком это неуспех;
- `popd` переходит в вершину стека и снимает её; с пустым стеком это неуспех;
- `pushd +N`/`-N`, `popd +N`/`-N` и `dirs` с опциями дают «неизвестно» в каталоге (`dirs` — в стеке).

**Цель становится «неизвестно» при успехе**, если:
- в ней есть переменная, кроме `HOME`/`CODELAB_HOME`, подстановка `$(…)`/`` `…` `` или `~user`;
- строка где-либо упоминает `CDPATH`, а цель относительная и не начинается с `./`, `../` и не равна `.` или `..`;
- строка упоминает `OLDPWD`, а это `cd -`;
- это `cd -P` или `pushd -P` с компонентой `..`, либо строка содержит `set -P`, `set -o physical` или `set` с нелитеральным аргументом;
- в ней `..` стоит после обычной компоненты (`sub/../b`); ведущие `..` (`../b`) точны (D17 A5).

Каталог `env -C DIR` или `sudo -D DIR` с такой целью SHALL давать «неизвестно» для этой простой команды.

**Лаунчеры и блоки:**
- `cd`, `pushd`, `popd` под внешним лаунчером (`env`, `sudo`, `doas`, `nohup`, `nice`, `timeout`, `stdbuf`, `xargs`, `exec`, а также `command` и `time`, вызванные по пути: `/usr/bin/command`) каталог текущей оболочки SHALL NOT менять;
- под `time` — объединение прежних и новых вариантов без сужения по `&&`/`||`;
- подоболочка `( … )` SHALL оставлять состояние после себя таким же, как до;
- `&` уводит в фон весь and-or список (`A && B &` — это `{ A && B; } &`): состояние после него SHALL быть таким же, как до начала списка (D16 B2);
- `-v` или `-V` у любого снятого `command` (`command -p command -v cd`) — команда только ищется: каталог SHALL NOT меняться (D16 H2, D17 A3);
- стадия конвейера из двух и более стадий (в том числе группа или блок в такой стадии) SHALL давать объединение прежних и новых вариантов;
- группа `{ … }` вне конвейера выполняется в текущей оболочке;
- после `if … fi` состояние SHALL быть объединением состояния до блока и состояния в его конце;
- тело цикла SHALL обходиться один раз; если состояние после тела отличается от входа или тело определило функцию, `alias`, поставило меняющий состояние `trap` либо записало переменную-команду (D18 W2), тело SHALL обходиться повторно от «вход ∪ конец ∪ неизвестно»; после цикла состояние — «вход ∪ конец» (тело может не выполниться ни разу); признак берётся из состояния, а не из имён команд (D17 A1);
- тело функции (`name()`, `function name`) SHALL проверяться с копией состояния и вариантом «неизвестно», и его смены каталога после определения не действуют; с определения функции, с команды `alias` и с `trap`, действие которого меняет состояние оболочки (может сменить каталог, определяет функцию или `alias`, пишет переменную-команду или переменную с динамическим именем; D18 W3), до конца оболочки к вариантам SHALL добавляться «неизвестно»: любая следующая команда может оказаться вызовом, а действие `trap` (сигнал, `EXIT`, `DEBUG`, `ERR`, `RETURN`) исполняется позже в той же оболочке (D16 H3); такое действие SHALL сразу проверяться как вложенный текст `foreign`; действие `trap`, которое состояние не меняет, SHALL проверяться в конце оболочки во всех состояниях, в которых строка побывала, включая состояние после последней команды, без варианта «неизвестно» (D17 A8);
- сегмент «может сменить каталог», если это `cd`, `pushd`, `popd`, `dirs`, `eval`, `trap` с действием или команда с динамическим именем; внешний лаунчер, поиск `command -v` и сегмент без слов каталог не меняют (D17);
- после простой команды с динамическим именем, после `eval` с нелитеральным текстом и после скрытого текста (`fc`, `history -s`, `mapfile`/`readarray -C`; D18 W4) к вариантам SHALL добавляться «неизвестно»: оболочка может исполнить любую встроенную, в том числе `cd` (D16 H4). Имя динамическое, если в первом слове после лаунчеров есть незакавыченные `*`, `?`, `[`, `{` (кроме слов `[` и `[[`), либо `$` или обратная кавычка, а слово не путь к файлу. Путь к файлу — буквальная `/` стоит до первого раскрытия или сразу после раскрытия в двойных кавычках (`"$d"/run`) или после `$HOME`, `$CODELAB_HOME`, `~` (`$HOME/bin/tool`); незакавыченное `$d/run` и `${d}/run` — динамические: разбиение на слова может дать `cd` (D17 A2).

**Признаки строки (дополнение к правилам `CDPATH`/`OLDPWD`, D16 H5, H6):**
- признаки `CDPATH`, `OLDPWD` и `DIRSTACK` SHALL ставиться также при `declare -n NAME` без `=` (D18 W4), при `eval` с нелитеральным текстом и при `export`, `declare`, `typeset`, `local`, `readonly`, `read`, `printf -v`, `getopts`, `mapfile`, если имя переменной содержит `$`, обратную кавычку или подстановку; `shopt` с нелитеральным аргументом SHALL ставить признак `CDPATH` (может включить `cdable_vars`) (D17 A5);
- `enable` как имя команды после снятия лаунчеров где угодно в строке, включая вложенные тексты: `cd`, `pushd`, `popd` SHALL давать «неизвестно» при успехе; подстрока `enable` в других словах (`--enable-shared`) признак SHALL NOT ставить; после динамической команды, нелитерального `eval` или скрытого текста последующие `cd`, `pushd`, `popd` той же оболочки SHALL давать «неизвестно» (D18 W5);
- стек `pushd` длиннее 64 SHALL становиться неизвестным, каталог длиннее 4096 символов — «неизвестно» (D18 W7);
- `DIRSTACK` в строке: стек всех вариантов SHALL считаться неизвестным;
- `cdable_vars` в строке: относительная цель без `./`, `../` и не `.`/`..` SHALL давать «неизвестно».

**Оболочки** (D18 W1). Корень строки, подоболочка, подстановка, фоновый and-or список (`{ …; } &`, `A && B &`) и новый процесс (`sh -c`, `env -S`, текст `foreign`, `eval` под внешним лаунчером) SHALL иметь каждая свои: признак «неизвестно до конца» после функции, `alias` или `trap`, признак `enable`, ожидающее значение переменной-команды, отложенные действия `trap` и множество побывавших состояний. Подоболочка, фоновый список и подстановка SHALL наследовать признаки «неизвестно до конца» и `enable` родителя, новый процесс SHALL начинать без них. На выходе из оболочки её отложенные `trap` и непотреблённые значения SHALL проверяться в её состояниях и её конечном состоянии; наружу они не выходят; снаружи фонового списка состояние SHALL оставаться входом списка. `eval` без внешнего лаунчера — та же оболочка.

**Вложенные команды:**
- подстановка `$(…)`, `` `…` ``, `<(…)`, `>(…)` SHALL получать копию всех вариантов, и её смены каталога наружу не выходят;
- текст `sh -c`/`bash -c`, `env -S`, `watch`, `script -c`, `find -exec`/`-ok`, `rg --pre` — копию каталогов с пустым стеком и неизвестным `OLDPWD`;
- текст `eval` (без внешнего лаунчера) SHALL продолжать текущее состояние, и его смены каталога действуют на следующие команды;
- текст из опций и переменных `git` (`-c …`, `alias.*=!…`), из переменных-команд (`GIT_PAGER`, `PAGER`, `EDITOR` и другие §7.6.1), `find -execdir`/`-okdir` и `trap` SHALL проверяться с известными вариантами каталога (как у `sh -c`) и вариантом «неизвестно»: эти программы запускают его в корне репозитория, в найденном каталоге или позже;
- объявления `export`, `declare`, `typeset`, `readonly`, `local` сами ничего не исполняют и SHALL NOT быть критичными только из-за значения переменной-команды; это значение SHALL проверяться, как в предыдущем пункте, на первой следующей простой команде, которая не объявление, кем бы она ни была; если такой команды в строке нет, значение не проверяется. Префиксное присваивание (`EDITOR=vim git commit`) проверяется у своей команды;
- сегмент из одних присваиваний с литеральным значением (`GIT_EDITOR=true`, `PAGER=cat`) SHALL проверяться у себя, значение — как вложенный текст, и SHALL NOT делать следующую команду потребителем (D18 F1);
- если переменную-команду пишут способом, значение которого строка не показывает, — присваивание с нелитеральным значением (`EDITOR=$V`), `NAME+=`, `NAME[i]=`, `${NAME:=…}`, `read`, `mapfile`, `readarray`, `getopts`, `printf -v`, `declare -n`, переменная заголовка `for`/`select`, — её неизвестное значение SHALL считаться командой не из белого списка чтения, запущенной с известными вариантами и вариантом «неизвестно», на первой следующей простой команде, которая не объявление (метка `write in unknown working directory`), даже если сама эта команда — только чтение (D16 L1, D17 A5);
- если в строке был `trap` с действием, отложенное значение переменной-команды, которое никто не потребил, SHALL проверяться в конце строки со всеми состояниями строки и вариантом «неизвестно» (D17 A7).

**Белый список чтения.** `true`, `false` и `:` SHALL считаться командами только чтения; их перенаправления проверяются как у любой команды.

**Метки складываются.** Сегмент SHALL получать метки всех совпавших строк таблицы, включая `write in unknown working directory` (`sudo -D "$X" make` — `privileged command; write in unknown working directory`).

**Недостижимое состояние.** Если вход команды пуст (`popd && …` при пустом начальном стеке), вместо него SHALL браться вход предыдущей команды того же уровня; команда, в том числе `cd`, идёт от него (D16 M1, D17 A4).

**`~+`, `~-`, `~user`** (D17 N9). `~+` SHALL раскрываться в каталог варианта, `~-` — в `OLDPWD` варианта. При варианте «неизвестно» `~+` и `~-` SHALL считаться относительными целями правила «неизвестно» (в том числе у `time -o`; D18 W6). Слово с `~user` или с `~-` при неизвестном `OLDPWD` SHALL быть критичным с меткой `write to agent configuration` как цель записи и как аргумент команды не из белого списка чтения; у команды белого списка чтения такое слово не критично.

**Исключения навыков.** Исключения навыков (change `add-agent-skills`, E1–E3) SHALL применяться только к известным вариантам каталога. Исключение по рабочему каталогу навыка (E2) для варианта «неизвестно» SHALL NOT действовать. Исключение по скрипту навыка (E1) SHALL NOT снимать срабатывание из-за варианта «неизвестно»: неизвестный каталог может быть `~/.codelab`. Группа `{ … }`, `if … fi`, цикл и `!` SHALL отключать E1 для следующих сегментов, как зарезервированные слова в разрешённом списке Q47; подоболочка `( … )` E1 не отключает.

**Известные пределы.** Пределами SHALL оставаться:
- `CDPATH` и `OLDPWD` из окружения исполнителя, не упомянутые в строке;
- переменная вместо пути (`f=…; echo > $f`);
- переприсваивание `HOME`/`CODELAB_HOME` в строке;
- `source`/`.` со скриптом из файла;
- подстановка в теле here-document без кавычек (`cat <<EOF` … `$(…)` … `EOF`) — пробел всей таблицы §7.6, вне этого change;
- shell через stdin (`sh <<X`, `. /dev/stdin`) — вне этого change;
- данные, которые оболочка исполняет как код (`PS4='$(…)'; set -x`, `x='a[$(…)]'; echo $((x))`);
- `SHELLOPTS`, `BASHOPTS`, `BASH_FUNC_cd%%` из окружения клиента;
- `.`/`source` как значение переменной-команды (`GIT_EDITOR=. git commit -e -F m`) — класс «скрипт из файла»;
- расхождение bash и dash для `$'…'` внутри `${…}` вне двойных кавычек: разбор следует bash (D18 C1);
- относительные цели `rm` и других строк таблицы §7.6 вне PERM-11 (`cd / && rm -rf usr`) — от корня сессии, а не от каталога варианта (было до change);
- обходы, найденные после третьего раунда ревью (D18), кроме находок CRITICAL и регрессий относительно `develop`: их закрывает запрет записи на уровне ОС (change `add-exec-os-write-sandbox`).

#### Scenario: cd - после смены каталога
- **WHEN** сессия открыта в `/work/demo`, и в режиме `bypass` модель вызывает `exec cd /work/demo/.codelab/skills/pdf; cd /tmp; cd -; touch SKILL.md`; затем то же в `autopilot`
- **THEN** в `bypass` gate получает запрос без `allow_always` с `reason: 'critical command: write to agent configuration'`; в `autopilot` вызов отклонён с `critical command blocked in autopilot: write to agent configuration` (`exec_working_dir_test.dart`)

#### Scenario: popd возвращает в каталог навыка
- **WHEN** в режиме `bypass` модель вызывает `exec pushd /work/demo/.codelab/skills/pdf; pushd /tmp; popd; touch SKILL.md`
- **THEN** команда совпадает с меткой `write to agent configuration`

#### Scenario: CDPATH в строке команды
- **WHEN** в режиме `bypass` модель вызывает `exec` с `CDPATH=/work/demo/.codelab/skills cd pdf; touch SKILL.md` или `export CDPATH="$ROOT"; cd pdf && touch SKILL.md`
- **THEN** обе команды совпадают с меткой `write in unknown working directory`; `CDPATH=/x cd ./build && make` — не совпадает: цель с `./` от `CDPATH` не зависит

#### Scenario: Путь конфигурации хоста через cd - и popd
- **WHEN** хост передал `agentConfigPaths` с `/home/u/.codelab/config.yaml` и `/home/u/.codelab/agents`, `expansions` с `HOME=/home/u`, и в режиме `bypass` модель вызывает `exec` с `cd ~/.codelab; cd /tmp; cd -; echo x > config.yaml` или `pushd ~/.codelab/agents; pushd /tmp; popd; tee x.md`
- **THEN** обе совпадают с меткой `write to agent configuration`

#### Scenario: Неизвестная цель cd
- **WHEN** в режиме `bypass` модель вызывает `exec` с `cd $X && touch SKILL.md`, `cd "$(dirname "$F")" && sed -i s/a/b/ SKILL.md`, `cd ~bob && make`, `env -C "$X" touch SKILL.md` или `sudo -D "$X" make`
- **THEN** каждая совпадает с меткой `write in unknown working directory`; у последней есть и `privileged command`

#### Scenario: Неудачный cd оставляет прежний каталог
- **WHEN** в режиме `bypass` модель вызывает `exec cd /work/demo/.codelab/skills/pdf; cd /nonexistent; touch SKILL.md`; затем `cd /work/demo/.codelab/skills/pdf && cd /nonexistent && touch SKILL.md`
- **THEN** первая совпадает с меткой `write to agent configuration`: если `cd /nonexistent` упадёт, `touch` пишет в каталог навыка; вторая не критическая: `touch` выполнится, только если оба `cd` удались, и тогда каталог — `/nonexistent`

#### Scenario: Подоболочка, конвейер, фон и внешний лаунчер не меняют каталог
- **WHEN** в режиме `bypass` модель вызывает `exec` с `cd /work/demo/.codelab/skills/pdf; (cd /tmp); touch SKILL.md`, `cd /work/demo/.codelab/skills/pdf; cd /tmp | cat; touch SKILL.md`, `cd /work/demo/.codelab/skills/pdf; cd /tmp & touch SKILL.md`, `cd /work/demo/.codelab/skills/pdf; { cd /tmp; } | cat; touch SKILL.md` или `cd /work/demo/.codelab/skills/pdf && env cd /tmp && touch SKILL.md`
- **THEN** каждая совпадает с меткой `write to agent configuration`

#### Scenario: eval меняет каталог текущей оболочки
- **WHEN** в режиме `bypass` модель вызывает `exec eval 'cd /work/demo/.codelab/skills/pdf'; touch SKILL.md`
- **THEN** команда совпадает с меткой `write to agent configuration`

#### Scenario: Составные команды, функции и чужой каталог вложенной команды
- **WHEN** в режиме `bypass` модель вызывает `exec` с `if true; then cd /work/demo/.codelab/skills/pdf; fi; touch SKILL.md`, `cd /work/demo/.codelab/skills/pdf; while false; do cd /tmp; done; touch SKILL.md`, `cd /work/demo/.codelab/skills/pdf; f(){ cd /tmp; }; touch SKILL.md`, `find . -execdir touch SKILL.md \;` или `git -c alias.x='!touch SKILL.md' x`
- **THEN** первые три совпадают с меткой `write to agent configuration` (тело `while false` и тело функции могут не выполниться), последние две — с `write in unknown working directory`

#### Scenario: Обычная работа в корне остаётся обычной
- **WHEN** в режиме `bypass` модель в корне сессии `/work/demo` с существующим `.codelab` вызывает `exec` с `cd sub && make`, `cd sub; make`, `cd build && cd - && make`, `pushd sub; popd; make`, `pushd a && pushd b && popd && make`, `(cd sub && make) && ls`, `cd /tmp && rm config.yaml` или `for f in a b; do echo "$f"; done`
- **THEN** ни одна не совпадает ни с одной строкой таблицы §7.6

#### Scenario: Только чтение в неизвестном каталоге
- **WHEN** в режиме `bypass` модель вызывает `exec` с `cd "$(git rev-parse --show-toplevel)" && cat x`, `cd "$X" && git log --oneline > /tmp/log.txt`, `cd - && ls` или `cd "$(dirname "$F")" && grep -r foo . | wc -l`
- **THEN** ни одна не критическая: команды белого списка чтения без относительной записи; `cd "$(git rev-parse --show-toplevel)" && make` и `cd "$X" && cat a > out.txt` — критические с меткой `write in unknown working directory`

#### Scenario: Метка неизвестного каталога в autopilot
- **WHEN** хост включил `autopilot`, и модель вызывает `exec cd "$DIR" && npm test`
- **THEN** вызов отклонён без вопроса с текстом `critical command blocked in autopilot: write in unknown working directory`; в `bypass` тот же вызов даёт запрос без `allow_always`, а выданное ранее `allowAlways` на `exec cd "$DIR" && npm test` вопрос не снимает

#### Scenario: Переменные-команды и объявления
- **WHEN** в режиме `bypass` модель вызывает `exec` с `export EDITOR=vim; git commit`, `export EDITOR=vim && git commit`, `declare -x GIT_EDITOR=vim; git rebase --continue`, `EDITOR=vim git commit` или `LESSOPEN="|lesspipe %s" less x`
- **THEN** каждая совпадает с меткой `write in unknown working directory` (`exec_working_dir_test.dart`)

#### Scenario: Объявления и пустые редакторы не критичны
- **WHEN** в режиме `bypass` модель вызывает `exec` с `export EDITOR=vim`, `readonly EDITOR=vim`, `local EDITOR=vim`, `export EDITOR=vim GIT_PAGER=less`, `export EDITOR=true; git commit`, `GIT_EDITOR=true git rebase --continue`, `EDITOR=: git commit`, `GIT_EDITOR=false git commit` или `PAGER=less git log`
- **THEN** ни одна не совпадает ни с одной строкой таблицы §7.6

#### Scenario: Функция делает каталог неизвестным
- **WHEN** в режиме `bypass` модель вызывает `exec f() { echo hi; }; f`
- **THEN** команда совпадает с меткой `write in unknown working directory`: после определения функции каталог неизвестен, а `f` не из белого списка чтения; `f() { echo hi; }` без вызова — не критическая

#### Scenario: Недостижимая ветка не теряет метки
- **WHEN** в корне сессии `/work/demo` модель вызывает `exec popd && rm -rf /`, `exec popd && touch .codelab/config.yaml`, а затем `exec popd && make`
- **THEN** первая совпадает с меткой `recursive delete of a protected path`, вторая — `write to agent configuration` (проверка во входных вариантах `popd`), третья не критическая

#### Scenario: Скрипт навыка в неизвестном каталоге
- **WHEN** в сессии с загруженным навыком модель вызывает `exec cd "$X" && python3 <абсолютный путь скрипта навыка>`, а затем `exec cd "$(mktemp -d)" && python3 <тот же путь>`
- **THEN** первая даёт вопрос с `reason: 'critical command: write in unknown working directory'` без `allow_always`; вторая — `write to agent configuration`: подстановка в `cd` отключает E1 (Q47), и путь в корне навыков виден в команде (`skill_script_exceptions_test.dart`)

#### Scenario: Группа отключает E1, подоболочка нет
- **WHEN** в сессии с загруженным навыком модель вызывает `exec` с `{ python3 <скрипт навыка>; }`, `{ cat /dev/null; }; python3 <скрипт навыка>` и `(cat /dev/null); python3 <скрипт навыка>`
- **THEN** первые две критические; третья — нет (`skill_script_exceptions_test.dart`)

#### Scenario: for без in не прячет тело
- **WHEN** табличный тест проверяет `for x do rm -rf /; done`, `for x\ndo touch .codelab/config.yaml; done` и `for x in a b c d; do :; done`, а затем `for x y; do :; done`
- **THEN** первая совпадает с `recursive delete of a protected path`, вторая — с `write to agent configuration`, третья не критическая, последняя даёт `unparsable command`

#### Scenario: Фон уводит весь and-or список
- **WHEN** в корне сессии `/work/demo` модель вызывает `exec cd .codelab; cd /tmp && true & touch config.yaml`
- **THEN** команда совпадает с меткой `write to agent configuration`: `cd /tmp && true` ушёл в фон целиком, `touch` исполняется в `.codelab`

#### Scenario: Зарезервированное слово не после перенаправления
- **WHEN** модель вызывает `exec cd .codelab/skills/pdf && >/dev/null ! cd /tmp || touch SKILL.md`
- **THEN** команда совпадает с меткой `write to agent configuration`: `!` после перенаправления — команда (`command not found`), а не отрицание `cd /tmp`; каталог остаётся каталогом навыка, и `touch` после `||` пишет туда

#### Scenario: command -v не меняет каталог
- **WHEN** модель вызывает `exec cd .codelab/skills/pdf && command -v cd /tmp && touch SKILL.md`
- **THEN** команда совпадает с меткой `write to agent configuration`

#### Scenario: trap, динамическая команда и состояние bash
- **WHEN** в режиме `bypass` модель вызывает `exec` с `trap 'cd .codelab/skills/pdf' DEBUG; touch SKILL.md`, `$CMD /tmp; touch SKILL.md`, `eval "$X"; touch SKILL.md`, `enable -n cd; cd sub && touch SKILL.md`, `shopt -s cdable_vars; cd pdf && touch SKILL.md` или `export "${N}PATH=/x"; cd pdf && touch SKILL.md`
- **THEN** каждая совпадает с меткой `write in unknown working directory`

#### Scenario: Переменная-команда через read
- **WHEN** модель вызывает `exec read EDITOR <<< 'touch SKILL.md'; git commit`
- **THEN** команда совпадает с меткой `write in unknown working directory`

#### Scenario: Пределы разбора
- **WHEN** модель вызывает `exec` с 65 вложенными группами `{ { … } }` или с командой длиннее 128 KiB
- **THEN** обе дают `unparsable command` без исключения и за ограниченное время

#### Scenario: Цикл, который меняет каталог через переменную
- **WHEN** модель вызывает `exec cd /work/demo/.codelab/skills/pdf; for i in 1; do C=cd; $C /tmp; done; touch SKILL.md`, затем `for d in a b; do cd $d && make && cd ..; done` и `for d in packages/*; do (cd "$d" && dart test); done`
- **THEN** первая совпадает с `write to agent configuration`, вторая и третья — с `write in unknown working directory` (принятая цена D17 A1)

#### Scenario: Динамическое имя команды
- **WHEN** модель вызывает `exec` с `c[d] /tmp; make`, `{cd,x} /tmp; make`, `$d/run && make` или `${d}/run && make`, затем с `"$d"/run && make`, `$HOME/bin/tool; make`, `~/bin/tool; make` или `[ -f a ] && make`
- **THEN** первые четыре совпадают с `write in unknown working directory`, остальные не критичны

#### Scenario: Лаунчер command с путём и поиск
- **WHEN** модель вызывает `exec cd /work/demo/.codelab/skills/pdf && /usr/bin/command cd /tmp && touch SKILL.md` или `exec cd /work/demo/.codelab/skills/pdf && command -p command -v cd /tmp && touch SKILL.md`
- **THEN** обе совпадают с `write to agent configuration`

#### Scenario: cd после недостижимой ветки
- **WHEN** в корне сессии `/work/demo` модель вызывает `exec popd && cd .codelab && touch config.yaml`
- **THEN** команда совпадает с `write to agent configuration`: `cd` идёт от входа `popd`

#### Scenario: trap без смены каталога
- **WHEN** модель вызывает `exec trap 'rm -f "$tmp"' EXIT; make`, затем `exec trap 'touch config.yaml' EXIT; cd /work/demo/.codelab` и `exec trap : EXIT; export EDITOR=vim`
- **THEN** первая не критична; вторая совпадает с `write to agent configuration` (ловушка исполнится в `.codelab` при выходе); третья — с `write in unknown working directory` (непотреблённое значение исполнит ловушка, D17 A7)

#### Scenario: Косвенная запись переменной-команды
- **WHEN** модель вызывает `exec` с `EDITOR+=x git commit`, `EDITOR[0]=vim; git commit`, `echo ${EDITOR:=vim}; git commit`, `for EDITOR in vim; do git commit; done`, `printf -v EDITOR x; ls; git commit` или `read EDITOR <<< 'touch SKILL.md'; true; git commit`
- **THEN** каждая совпадает с `write in unknown working directory`

#### Scenario: Физический .. и нелитеральные shopt и set
- **WHEN** модель вызывает `exec cd sub/../b && make`, `exec shopt -s "$o"; cd pdf && touch SKILL.md` или `exec set "$o"; cd a/.. && touch x`, затем `exec cd ../b && make`
- **THEN** первые три совпадают с `write in unknown working directory`, последняя не критична

#### Scenario: Тильды ~+, ~- и ~user
- **WHEN** модель вызывает `exec` с `touch ~bob/.codelab/config.yaml`, `cp a ~bob/x`, `touch ~-/SKILL.md`, `cd /work/demo/.codelab/skills/pdf && cd /tmp && touch ~-/SKILL.md` или `cd /work/demo/.codelab/skills/pdf && touch ~+/SKILL.md`, затем `cat ~bob/.codelab/config.yaml` и `ls ~-`
- **THEN** первые пять совпадают с `write to agent configuration`, последние две не критичны

#### Scenario: Кавычки и арифметика в раскрытиях
- **WHEN** табличный тест проверяет `echo ${x:-$'\x27'}; rm -rf /`, `echo $(( "$(rm -rf /)" ))`, затем `echo "${x:-'d'}"`, `echo "${x:-$'a'}"`, `echo "${f%'.dart'}"`, `printf '%s\n' "${x:-$'\t'}"`, вложенность `${…}` глубже 64, и `echo $((1+2))`
- **THEN** первые две совпадают с `recursive delete of a protected path`, следующие пять дают `unparsable command`, `echo $((1+2))` не критична

#### Scenario: Состояние вложенной оболочки не выходит наружу
- **WHEN** модель вызывает `exec` с `(trap "cd /work/demo/.codelab/skills/pdf" DEBUG); touch SKILL.md`, `(f() { :; }); touch SKILL.md` или `sh -c "alias x=y"; touch SKILL.md`, затем `trap 'touch config.yaml' EXIT; cd /work/demo/.codelab`
- **THEN** первые три не критичны; последняя совпадает с `write to agent configuration`: отложенное действие проверяется и в конечном состоянии оболочки

#### Scenario: Ловушка фонового списка
- **WHEN** в корне сессии `/work/demo` модель вызывает `exec { trap 'echo > config.yaml' EXIT; cd .codelab; } & wait`
- **THEN** команда совпадает с `write to agent configuration`: ловушка фонового списка проверяется в его конечном состоянии `.codelab`, а `wait` снаружи идёт из входа списка

#### Scenario: trap и цикл, меняющие состояние оболочки
- **WHEN** модель вызывает `exec` с `trap 'f() { :; }' EXIT; touch SKILL.md`, `trap 'EDITOR=vim' EXIT; git commit` или `cd /work/demo/.codelab/skills/pdf; for i in 1 2; do touch SKILL.md; f() { cd /tmp; }; done`
- **THEN** первые две совпадают с `write in unknown working directory`, третья — с `write to agent configuration`

#### Scenario: Скрытый текст и enable
- **WHEN** модель вызывает `exec` с `fc -s; touch SKILL.md`, `history -s cd /x; touch SKILL.md`, `mapfile -C cb x < f; touch SKILL.md`, `declare -n R; git commit`, `enable -n cd; cd sub && touch SKILL.md`, `sh -c "enable -n cd"; cd sub && touch SKILL.md` или `$X; cd sub && touch SKILL.md`, затем `./configure --enable-shared && cd build && make`
- **THEN** все, кроме последней, совпадают с `write in unknown working directory`; последняя не критична

#### Scenario: Тильды в правиле неизвестного каталога
- **WHEN** модель вызывает `exec cd "$X" && echo x > ~+/a` или `exec cd "$X" && time -o ~+/out ls`
- **THEN** обе совпадают с `write in unknown working directory`

#### Scenario: Литеральное присваивание без команды
- **WHEN** модель вызывает `exec GIT_EDITOR=true; export GIT_EDITOR; git rebase --continue` или `exec PAGER=cat; git log`, затем `exec EDITOR=$V; git commit`
- **THEN** первые две не критичны, последняя совпадает с `write in unknown working directory`

#### Scenario: Бюджет обхода
- **WHEN** модель вызывает `exec` со строкой до 128 KiB, где 32 варианта каталога и тысячи сегментов дают больше 20 000 проверок
- **THEN** результат — `unparsable command` быстрее 1 с на VM

#### Scenario: Предел числа вариантов
- **WHEN** модель вызывает `exec pushd /a1; pushd /a2; pushd /a3; pushd /a4; pushd /a5; pushd /a6; touch SKILL.md` (каждый `pushd` может не удаться, стеков — 64)
- **THEN** варианты заменены вариантом «неизвестно», и команда совпадает с меткой `write in unknown working directory`; разбор завершается без ошибки
