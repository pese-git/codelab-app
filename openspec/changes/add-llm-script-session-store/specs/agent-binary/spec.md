## MODIFIED Requirements

### Requirement: Минимальный конфиг из флагов
До этапа 8 бинарь НЕ SHALL читать файлы конфига (документ ядра §15.6). Конфиг SHALL собираться из флагов и переменных окружения, флаг сильнее переменной:
- `--provider openai-compatible|anthropic`, `--base-url <url>` — провайдер с id `cli`; `--model <id>` повторяемый: первое значение — модель по умолчанию, все — модели каталога `cli/<id>`; `CODELAB_MODEL` — значение `--model`, если флага нет; форма `provider/model` допустима только с провайдером этого запуска (`cli/<id>` или `scripted/<id>`): других провайдеров до конфига этапа 8 нет, поэтому `--model openai/gpt-5` без `--provider` — ошибка использования;
- ключ провайдера — только переменная `CODELAB_API_KEY`;
- `--permission-mode` / `CODELAB_PERMISSION_MODE` — `plan`, `ask`, `standard`, `accept-edits`, `bypass`, `autopilot`;
- `--log-level` / `CODELAB_LOG_LEVEL`, `--log-file` / `CODELAB_LOG_FILE`;
- остальные ключи — значения по умолчанию §15.4.

Ошибки использования — неизвестный флаг, неизвестный режим, `--provider` вместе с `--llm-script`, ни модели, ни сценария, `--sessions-dir` без `--llm-script` — SHALL завершать процесс кодом `64` с текстом в stderr. Неизвестная переменная `CODELAB_*` SHALL давать предупреждение в лог. Значение `CODELAB_API_KEY` НЕ SHALL попадать в лог, текст ошибок и строковое представление опций.

С провайдером из флагов сессии SHALL храниться в `JsonlSessionStore` под `$CODELAB_HOME/sessions` (`CODELAB_HOME` по умолчанию `~/.codelab`), и `initialize` объявляет `loadSession: true`.

#### Scenario: Ключ не попадает в лог
- **WHEN** бинарь запущен с `CODELAB_API_KEY=sk-test-secret`, `--log-level debug` и `--log-file <tmp>`
- **THEN** ни stderr, ни файл лога не содержат строки `sk-test-secret`

#### Scenario: Провайдер вместе со сценарием
- **WHEN** бинарь запущен с `--provider anthropic --llm-script hello.json`
- **THEN** процесс завершается с кодом `64` и сообщением о взаимоисключающих флагах

#### Scenario: Каталог журналов без сценария
- **WHEN** бинарь запущен с `--provider anthropic --model claude --sessions-dir /tmp/sessions`
- **THEN** процесс завершается с кодом `64` и сообщением, что `--sessions-dir` требует `--llm-script`

#### Scenario: Повторяемый --model
- **WHEN** бинарь запущен с `--provider openai-compatible --base-url http://localhost:4000 --model gpt-5 --model gpt-4`
- **THEN** опция `model` новой сессии содержит `cli/gpt-5` и `cli/gpt-4`, а текущее значение — `cli/gpt-5`

### Requirement: Сценарий --llm-script
Флаг `--llm-script <file.json>` SHALL заменять провайдера `ScriptedStreamFunction` из файла `{"llm": {"model": {...}, "steps": [...]}}` — формата блока `llm` фикстуры (документ ядра §14.7). Флаг SHALL быть скрыт в справке. Провайдер — `scripted`; модели каталога — `scripted/<id>` для каждого `--model`, без `--model` — модель из `llm.model`. Шаги SHALL быть общими для всех сессий процесса и расходоваться по порядку запросов, а новый процесс SHALL начинать их с первого шага; `${cwd}` SHALL подставляться рабочей папкой сессии запроса — в том числе сессии, загруженной `session/load`, — `${sessionId}` — её id. Невалидный файл — ошибка использования, код `64`, с путём поля.

Без флага `--sessions-dir` сессии SHALL храниться в памяти: capability `sessionPersistence` сужена, `initialize` объявляет `loadSession: false` без `sessionCapabilities.list`.

Скрытый в справке флаг `--sessions-dir <path>` SHALL включать журнал сессий на диске: `JsonlSessionStore` с корнем `<path>`, capability `sessionPersistence` включена, `initialize` объявляет `loadSession: true` и `sessionCapabilities.list`, а сессии, созданные одним процессом, SHALL отдаваться `session/list` и загружаться `session/load` следующим процессом с тем же `<path>`.

С `--llm-script` бинарь НЕ SHALL создавать и читать `$CODELAB_HOME` ни с `--sessions-dir`, ни без него.

#### Scenario: Рабочая папка сессии в ответе
- **WHEN** сценарий отвечает `cwd was: ${cwd}`, а клиент создаёт сессию с `cwd: "/work/demo"`
- **THEN** `agent_message_chunk` несёт `cwd was: /work/demo`

#### Scenario: Ничего не пишется в CODELAB_HOME
- **WHEN** бинарь с `--llm-script` и `CODELAB_HOME=<tmp>` проводит ход
- **THEN** каталог `<tmp>` не создан, а `initialize` объявляет `loadSession: false`

#### Scenario: Сессии сценария переживают перезапуск процесса
- **WHEN** процесс с `--llm-script` и `--sessions-dir <dir>` создаёт сессию в `<cwd>` и проводит ход, затем завершается, и новый процесс с теми же флагами получает `session/list` с `cwd: <cwd>`
- **THEN** `initialize` нового процесса объявляет `loadSession: true` и `sessionCapabilities.list`, список содержит id прежней сессии, `session/load` повторяет её историю, `$CODELAB_HOME` не создан

#### Scenario: Рабочая папка загруженной сессии
- **WHEN** новый процесс с `--sessions-dir <dir>` загружает `session/load` сессию прошлого процесса из `<cwd>`, а сценарий отвечает `cwd was: ${cwd}`
- **THEN** `agent_message_chunk` хода в этой сессии несёт `cwd was: <cwd>`
