## MODIFIED Requirements

### Requirement: Профили подключения CLI
Значение `--agent` (`-a`) SHALL разбираться так:
- `embedded` — `EmbeddedProfile(hostProfile: 'embedded-cli')`: встроенный агент в процессе CLI (требование «Встроенный агент в CLI»);
- `stdio:<команда> [аргументы]` — `StdioProfile` с разбором аргументов как в shell (кавычки, экранирование);
- `ws://…` или `wss://…` — `WebSocketProfile`, токен которого читается из переменной `CODELAB_AGENT_TOKEN` через `SecretSource`;
- иначе — id профиля из `$CODELAB_HOME/profiles.json` (`CODELAB_HOME` по умолчанию — `~/.codelab`), хранимого `JsonFileProfileStore`.

Без `--agent` SHALL использоваться профиль `default` из `profiles.json`, если он там есть; иначе — встроенный агент, как с `-a embedded` (design.md change `add-embedded-agent-mode`, D13, п. 1). Правило одно для REPL, `--ui tui`, `-p` и `test-scenario` (D13, п. 7). О неявном выборе встроенного агента CLI НЕ SHALL печатать отдельной строки: выбранный профиль виден с `--verbose` и командой `/profile` (D13, п. 8). Битый `profiles.json` — не JSON или JSON неверной структуры — SHALL давать код `64` с причиной, а не тихий переход на встроенного агента и не необработанное исключение. Внешний агент выбирается явно: `-a stdio:…`, `-a ws://…` или `-a <id>`.

Команда `codelab profiles list|show <id>|add <id> <значение --agent>|remove <id>` SHALL работать без запуска агента; значение токена в `profiles.json` НЕ SHALL записываться. `embedded` в `profiles add` — ни как id, ни как значение — SHALL давать код `64` и `embedded is built in; use --agent embedded`. Ошибка подключения SHALL давать понятное сообщение в stderr и код `1` (U-06).

#### Scenario: Без профиля по умолчанию запускается встроенный агент
- **WHEN** CLI из тестовой точки входа со сценарием модели (design.md change `add-embedded-agent-mode`, D8) запускается как `codelab -p hi` с временным `CODELAB_HOME` без `profiles.json`
- **THEN** ход проводит встроенный агент, дочерний процесс агента не запускается, stdout содержит ответ сценария, код `0`

#### Scenario: Без профиля и без конфига
- **WHEN** рабочий `codelab -p hi` запускается с пустым временным `CODELAB_HOME` (нет `profiles.json` и `config.yaml`)
- **THEN** код `64`, stdout пуст, stderr содержит проблему конфигурации встроенного агента и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`; ни один процесс агента не запущен

#### Scenario: profiles.json неверной структуры
- **WHEN** `profiles.json` — корректный JSON неверной структуры (например, массив вместо объекта или профиль без обязательного поля), и запускается `codelab -p hi` без `--agent`
- **THEN** код `64`, stderr содержит причину чтения профилей, stdout пуст, агент не запускается

#### Scenario: Профиль default сильнее встроенного агента
- **WHEN** `profiles.json` содержит профиль `default` со `stdio:<scripted-агент>`, и запускается `codelab -p hi` без `--agent`
- **THEN** ход проводит процесс из профиля `default`

#### Scenario: Встроенный агент явно
- **WHEN** запускается `codelab -a embedded -p hi` при профиле `default` в `profiles.json`
- **THEN** ход проводит встроенный агент, процесс из `default` не запускается

#### Scenario: embedded нельзя сохранить профилем
- **WHEN** выполняется `codelab profiles add x embedded` или `codelab profiles add embedded stdio:x`
- **THEN** код `64`, в stderr — `embedded is built in; use --agent embedded`, `profiles.json` не изменён

#### Scenario: Профиль stdio с кавычками
- **WHEN** выполняется `codelab profiles add py 'stdio:python -m "codelab agent" --stdio'`, затем `codelab profiles show py`
- **THEN** профиль хранит команду `python` и аргументы `-m`, `codelab agent`, `--stdio`

#### Scenario: Агент не запускается
- **WHEN** `--agent 'stdio:/nonexistent/agent'`
- **THEN** в stderr — сообщение об ошибке подключения с командой, код выхода `1`

## ADDED Requirements

### Requirement: Встроенный агент в CLI
Composition root CLI SHALL регистрировать `EmbeddedTransportResolver` рядом с `ioTransportResolver`. Этот резолвер открывает встроенного агента через `localEmbeddedAgentOpener` из `package:codelab_embedded/io.dart` с профилем хоста `embedded-cli`, окружением процесса `codelab` и `cwd` = рабочая папка сессии (`-C`/`--cwd`, иначе текущий каталог; design.md change `add-embedded-agent-mode`, D2, D6). Импортировать `package:codelab_embedded/io.dart` SHALL только `lib/src/composition_root.dart`. Пакеты `package:codelab_agent_*` CLI по-прежнему НЕ SHALL импортировать.

Требования к резолверу и режимам:
- **Невалидный конфиг** встроенного агента (`EmbeddedAgentConfigException`) — код `64`. Текст исключения идёт в stderr, stdout остаётся пустым. В REPL и в `-p` сообщение одно.
- **Флаг `--debug-secrets`** (без значения) SHALL включать `secrets.lookup` встроенного агента и выводить эти события в stderr даже без `--verbose`: поля `name`, `purpose`, `source`, `found`, без значений секретов. Остальной лог агента от флага не появляется. Флаг действует только со встроенным агентом, на внешнего не влияет; `CODELAB_DEBUG_SECRETS=1` работает так же (design.md change `add-agent-secret-store`, D15; change `add-embedded-agent-mode`, D13, п. 9).
- **Логи встроенного агента** SHALL идти в логгер CLI: с `--verbose` — в stderr, иначе — никуда, кроме `secrets.lookup` при `--debug-secrets`. stdout headless не засоряется.
- **Выход** CLI (конец REPL, `--ui tui`, конец `-p`, `SIGINT`/`SIGTERM` по требованию «Сигналы CLI») SHALL дожидаться `dispose` встроенного агента до завершения процесса: журнал сессии дописан. Коды выхода `-p` встроенного агента — те же, что у внешнего. Подробности (design.md change `add-embedded-agent-mode`, D6, «Выход CLI»):
  - ожидание ограничено таймаутом CLI, большим grace `server.shutdown` агента (5 s). По истечении CLI пишет событие `embedded.close_timeout` уровня `warning` в логгер CLI, а в stderr — всегда, независимо от `--verbose` и `--debug-secrets`, одну строку `codelab: the embedded agent did not stop in <N> s` (<N> — таймаут; без текста ошибки), и завершается с прежним кодом;
  - обработчики `SIGINT`/`SIGTERM` снимаются только после `dispose` агента. Сигнал, пришедший, пока идёт `dispose` (в REPL, `--ui tui` и `-p`), завершает процесс сразу с кодом `130` (`SIGINT`) или `143` (`SIGTERM`), как у внешнего агента; повторный сигнал во время отмены хода — тоже;
  - ошибка сборки или работы режима не пропускает `dispose`: закрытие резолвера выполняется в `finally`.
- **Одобрения** встроенного агента SHALL идти тем же путём, что у внешнего: вопрос REPL `y / a / n`, политика `--approve` в `-p` (по умолчанию `reject`).

#### Scenario: Невалидный конфиг встроенного агента
- **WHEN** запускается `codelab -a embedded -p hi -C <dir>`, где `<dir>/.codelab/config.yaml` содержит `budget.max_steps: 0`
- **THEN** код `64`, stdout пуст, stderr содержит проблему `budget.max_steps` с файлом и строкой и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`

#### Scenario: Отказ по умолчанию в headless
- **WHEN** `codelab -a embedded -p "write file"` идёт со сценарием, где модель зовёт `write`, без `--approve`
- **THEN** вызов отклонён, в stderr — строка решения `codelab: permission "<title>": reject_once (policy)` (формат cli-headless, SJ-11), файл не изменён

#### Scenario: Журнал дописан при SIGTERM
- **WHEN** во время хода встроенного агента процессу `codelab -p` приходит `SIGTERM`
- **THEN** код выхода `143`, журнал сессии в `$CODELAB_HOME/sessions` содержит итоговую запись хода со `stopReason: aborted` (итог хода в ACP — `cancelled`)

#### Scenario: Второй сигнал при зависшем dispose
- **WHEN** после первого `SIGTERM` `dispose` встроенного агента не завершается, и процессу приходит второй `SIGTERM`
- **THEN** процесс завершается сразу с кодом `143`, не дожидаясь `dispose`

#### Scenario: Отладка секретов
- **WHEN** запускается `codelab -a embedded --debug-secrets -p hi` без `--verbose` с ключом провайдера в `CODELAB_SECRET_CODELAB_P`
- **THEN** stderr содержит событие `secrets.lookup` с именем `codelab/p` и источником `env`, но не значение ключа и не другие события лога агента; stdout содержит только ответ

#### Scenario: Без --debug-secrets лог агента молчит
- **WHEN** запускается `codelab -a embedded -p hi` без `--verbose` и без `--debug-secrets`
- **THEN** stderr не содержит ни `secrets.lookup`, ни других событий лога встроенного агента
