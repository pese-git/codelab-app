# Backlog: находки smoke-теста живой перезагрузки конфига 2026-11-03

Smoke-тест сборки из ветки `feature/add-config-writer-and-reload-live` @ `a79506b` (итерация 5 change
`add-config-writer-and-reload`, D7, D8; PR [#227](https://github.com/pese-git/codelab-app/pull/227)).
Бинари `codelab` и `codelab-agent` собраны `fvm dart compile exe`. codelab-app собран `fvm flutter build macos --debug`.
Всё запускалось с изолированным `CODELAB_HOME` и `secrets.backend: file`. Значение ключа фиктивное. Модели — LM Studio
(`openai-compatible`, `qwen/qwen3.5-9b`).

Прогнаны:
- `codelab-agent serve --stdio` с клиентом на Python, протокол ACP:
  - добавление модели в файл даёт `config_option_update` через 0,4 с;
  - `permissions.mode` на лету не меняется (R0-1);
  - невалидная правка не даёт ни одного кадра, в stderr `config.reload.failed`;
  - после закрытия stdin процесс выходит с кодом `0`.
- codelab-app, тип подключения «Embedded agent»:
  - удаление и добавление модели в `config.yaml` применяются без Reconnect;
  - `permissions.mode` каждый раз уходит в `restart_required`;
  - правка, совпадающая с применённым снимком, — `config.reload.noop`;
  - замена значения в `secrets.yaml` (`codelab secret set`) подхватывается;
  - невалидный `agent.default_model` — `config.reload.failed`, агент продолжает работать, после возврата приходит `applied`.
- REPL `codelab`: стартовый `/config` показывает модели и режим из файла.
- Поиск значения ключа в логе приложения и в stderr агента: значение не найдено.

Сценарии прошли по спецификациям `agent-runtime`, `agent-configuration` и `embedded-agent`, дефектов в итерации 5 не найдено.

Не проверялись:
- живая перезагрузка в REPL и TUI `codelab` (`--ui line` и `--ui tui`) во время работы: правки сделаны до запуска REPL;
- палитра моделей codelab-app визуально, только по логу;
- PERM-11 на реальной модели (`codelab -p … --mode bypass --approve allow-all` с просьбой записать `.codelab/config.local.yaml`):
  запуск отклонил классификатор Claude Code; случай покрыт тестами ядра;
- перезагрузка с проектным слоем `.codelab/` и `trusted_projects`, symlink на `config.yaml`, MCP-серверы.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| SMK-34 | P3 | bug | desktop | При старте codelab-app грузит сессию прежнего `CODELAB_HOME` и пишет `ERROR session/load … Session not found` | нет | — |
| SMK-35 | P3 | observability | agent | Смена ключа в `secrets.yaml` видна в журнале только как `config.reload.applied keys: []` | да | — |
| SMK-36 | P3 | observability | agent | Одна запись файла даёт 2–3 события `config.watch.debounce` | нет | — |

## Карточки

### SMK-34. codelab-app грузит сессию прежнего `CODELAB_HOME` и пишет `ERROR` (P3)

**Где:** восстановление последнего проекта и сессии при старте `apps/codelab_desktop` (недавние проекты и последняя сессия
хранятся в настройках приложения, вне `CODELAB_HOME`), `ClientWorkspace` → `session/load`.

**Шаги:** запустить codelab-app с одним `CODELAB_HOME`, открыть проект и сессию. Закрыть приложение и запустить его с
другим `CODELAB_HOME`.

**Факт:**
- приложение открывает прежнюю папку проекта (`…/smoke_cli/proj`), а не текущую;
- оно пытается загрузить сессию, которой в новом `CODELAB_HOME` нет;
- в журнал пишутся `ERROR: ACP request session/load failed: Session not found: <id>` и
  `ERROR: Failed to load ACP session <id>`;
- затем открывается новая сессия, пользователь видит пустой транскрипт.

**Ожидание:** отсутствующая у агента сессия при восстановлении — штатный исход. Её нужно молча пропустить или записать в
журнал как `info`/`warning` (`session.restore.missing`), а не как ошибку протокола. Если сессия встроенного агента
привязана к `CODELAB_HOME`, его стоит учитывать в ключе восстановления.

**Риск:** нет для данных. Ложные `ERROR` мешают разбирать журналы (`AGENTS.md` §16).

### SMK-35. Смена ключа в `secrets.yaml` в журнале не отличить от пустой перезагрузки (P3)

**Где:** `AgentRuntime.reloadConfig` (`codelab_agent_core`), события `config.reload.*`, `SecretResolver.invalidate()`.

**Шаги:** работающий встроенный агент, `secrets.backend: file` →
`printf '<новое значение>\n' | codelab secret set codelab/lm`.

**Факт:** наблюдатель видит `secrets.yaml` (`config.watch.debounce path: …/secrets.yaml`), затем пишет
`config.reload.applied {keys: [], restart_required: [...]}`. По журналу не видно, что кэш секретов сброшен и следующий ход
пойдёт с новым ключом. Пустой `keys` выглядит так же, как перезагрузка без изменений.

**Ожидание:** при смене файла секретов перезагрузка пишет имя источника без значений. Например, отдельное событие
`config.reload.secrets_invalidated {source: secrets.yaml}` или поле `secrets_reloaded: true` в `config.reload.applied`.
Значения и имена секретов в журнал не попадают. Новое поле или событие меняет таблицу событий D14, поэтому нужна правка
спеки `agent-runtime`.

**Риск:** нет для безопасности. Сложнее разбирать, подхватил ли агент новый ключ.

### SMK-36. Одна запись файла даёт несколько событий `config.watch.debounce` (P3)

**Где:** `packages/dart/codelab_agent_io/lib/src/config/config_watcher.dart` (`_schedule`).

**Шаги:** работающий агент → `codelab config set …` (одна запись `ConfigWriter`).

**Факт:** в журнале 2–3 события `DEBUG config.watch.debounce` с одним и тем же `path` подряд. Это события `rename` и
`modify` одного файла. Перезагрузка одна, debounce работает правильно.

**Ожидание:** событие пишется при первом запуске таймера debounce, а не при каждом его перезапуске. Либо в событии есть
счётчик склеенных событий. Уровень `debug`, на поведение не влияет.

**Риск:** нет. Шум в отладочном журнале.
