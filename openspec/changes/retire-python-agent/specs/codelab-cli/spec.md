## ADDED Requirements

### Requirement: Алиас codelab serve
Если первое слово argv `codelab` — `serve`, CLI SHALL обрабатывать вызов как переходный алиас `codelab-agent serve` (план этапа 9, задача 9.9; design.md change `retire-python-agent`, D6–D12). Алиас SHALL распознаваться до разбора флагов `codelab` и потому не подчиняется правилу `Unknown flag` / `Unknown command` требования «Команда codelab и разбор флагов». `serve` не на первом месте (`codelab -v serve`, `codelab -- serve`) алиасом НЕ SHALL считаться: это первое сообщение REPL, как прежде.

**Поиск бинаря.** Имя — `codelab-agent`, на Windows — `codelab-agent.exe`. Сначала SHALL проверяться каталог исполняемого файла `codelab` (`Platform.resolvedExecutable`), затем каталоги `PATH` по порядку. Относительные и пустые записи `PATH` SHALL пропускаться. Найденный файл, канонический путь которого совпадает с путём самого `codelab`, SHALL считаться ненайденным.

**Запуск.** CLI SHALL:
- до запуска записать в stderr ровно одну строку `codelab: "codelab serve" is deprecated and will be removed in a future release; use "codelab-agent serve" instead.`;
- запустить найденный бинарь с аргументами `serve` и всеми словами argv после `serve` без изменений и в том же порядке;
- запустить его с общими stdin, stdout и stderr (`ProcessStartMode.inheritStdio`) и окружением процесса `codelab`.

CLI НЕ SHALL писать в stdout, читать stdin и разбирать сообщения ACP. Профили, `profiles.json`, `cli_history` и `sessions/` CLI НЕ SHALL читать или создавать.

**Код выхода.** CLI SHALL выходить с кодом `codelab-agent`. Если агент завершён сигналом с номером `N` — с кодом `128 + N`. Бинарь не найден SHALL давать код `1`, stdout пуст, в stderr — предупреждение и строка `codelab: codelab-agent was not found next to codelab or in PATH; install it or run "codelab-agent serve" directly`. Сбой запуска процесса SHALL давать код `1` и текст ОС без аргументов.

**Сигналы.** Пока агент работает, `codelab` НЕ SHALL завершаться раньше него. `SIGTERM` SHALL пересылаться агенту. `SIGINT` CLI SHALL перехватывать, но НЕ SHALL пересылать: терминал доставляет его всей группе процессов, а повторный сигнал завершил бы `codelab-agent` немедленно (agent-binary «Жизненный цикл процесса»). Сигнал, пришедший до старта агента, SHALL пересылаться сразу после старта. На Windows `SIGTERM` не отслеживается.

Алиас НЕ SHALL упоминаться в `codelab --help`. Переход описан в пользовательской документации.

#### Scenario: Агент по stdio через алиас
- **WHEN** `codelab-agent` лежит в каталоге из `PATH`, запускается `codelab serve --stdio --llm-script <сценарий>`, клиент пишет в stdin строку `initialize` с `protocolVersion: 1` и закрывает stdin
- **THEN** stdout содержит только ответ агента с `protocolVersion: 1`, первая строка stderr — предупреждение об алиасе, код выхода `0`

#### Scenario: Аргументы передаются без изменений
- **WHEN** запускается `codelab serve --stdio --bogus` при найденном `codelab-agent`
- **THEN** в stderr — предупреждение, затем ошибка и справка `codelab-agent`, код выхода `64`, stdout пуст

#### Scenario: serve без флагов
- **WHEN** запускается `codelab serve` при найденном `codelab-agent`
- **THEN** REPL не открывается, в stderr — предупреждение и справка `codelab-agent serve`, код выхода `64`

#### Scenario: Сообщение serve в REPL
- **WHEN** запускается `codelab -- serve`
- **THEN** алиас не срабатывает: открывается REPL с первым сообщением `serve`

#### Scenario: codelab-agent не найден
- **WHEN** рядом с `codelab` и в абсолютных каталогах `PATH` нет `codelab-agent`, а `PATH` содержит `.` и в текущей папке лежит исполняемый `codelab-agent`
- **THEN** процесс не запускается, код выхода `1`, stdout пуст, в stderr — предупреждение и `codelab: codelab-agent was not found next to codelab or in PATH; install it or run "codelab-agent serve" directly`

#### Scenario: Бинарь рядом важнее PATH
- **WHEN** `codelab-agent` лежит и в каталоге `codelab`, и в каталоге из `PATH`
- **THEN** запускается бинарь из каталога `codelab`

#### Scenario: Алиас не вызывает сам себя
- **WHEN** единственный найденный `codelab-agent` — символическая ссылка на исполняемый файл `codelab`
- **THEN** он считается ненайденным: код выхода `1`, процесс не запускается

#### Scenario: SIGTERM через алиас
- **WHEN** процессу `codelab serve --stdio --llm-script <сценарий>` приходит `SIGTERM` во время работы агента
- **THEN** агент получает `SIGTERM` и завершается, `codelab` выходит с кодом агента `143` не раньше завершения агента
