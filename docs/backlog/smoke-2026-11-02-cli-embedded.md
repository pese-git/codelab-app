# Backlog: находки smoke-теста CLI со встроенным агентом 2026-11-02

Smoke-тест бинарей `codelab` и `codelab-agent`, собранных из ветки `feature/add-embedded-agent-mode-cli` @ `6d10b34`
(итерация 3 change `add-embedded-agent-mode`, этап 7; PR [#215](https://github.com/pese-git/codelab-app/pull/215)).
Модель — `qwen/qwen3.5-9b` в LM Studio (`openai-compatible`). `CODELAB_HOME` и `HOME` изолированы во временном
каталоге, значение ключа фиктивное (LM Studio ключ не проверяет).

Автоматически (headless) прогнаны:
- без конфига — код `64` с подсказкой;
- без ключа — `1`;
- встроенный агент по умолчанию;
- `--debug-secrets` без значений;
- чтение разрешено, запись по умолчанию отклонена политикой;
- `--approve allow-all`;
- `profiles add embedded` — `64`;
- профиль `default` → внешний агент, `-a embedded` его перебивает;
- битый `profiles.json` и невалидный конфиг — `64`;
- `test-scenario` со встроенным агентом и без `--agent`, пустой фильтр — `1`;
- `SIGTERM` во время хода — `143`, журнал сессии дописан;
- значение ключа не найдено вне `secrets.yaml`.

Вручную прогнаны:
- REPL со встроенным агентом: `/new`, `/profile`, ответ, одобрение `y`, отказ `n`, Esc в диалоге одобрения, `/exit`;
- `--ui tui` со встроенным агентом: те же шаги, плюс Ctrl+C во время ответа, resize, код выхода `0`, восстановление терминала;
- REPL с внешним агентом `-a stdio:…/codelab-agent serve --stdio`: `/profile`, одобрение `y`, `/exit`.

Все сценарии прошли по спецификациям `codelab-cli` и `codelab-tui`. В автоматическом прогоне через `expect` ответ на
одобрение не принимался. Ручная проверка показала, что это артефакт `expect`, а не дефект CLI. Не проверялись:
профиль `--ws`, `--ui tui` с внешним агентом, `--resume`/`--continue` встроенного агента.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| SMK-21 | P3 | bug | cli | REPL склеивает текст ответа и следующий блок мыслей без перевода строки | нет | — |
| SMK-22 | P3 | ux | client | Эвристика риска одобрения ищет слова в содержимом файла: запись нового файла помечается `destructive` | да | — |
| SMK-23 | P3 | ux | cli | `/profile` повторяет данные профиля | нет | — |
| SMK-24 | P3 | ux | cli | Диалог одобрения записи показывает путь как `command:` | нет | — |
| SMK-25 | P3 | docs | cli | Справка `test-scenario` показывает `--agent` обязательным | нет | — |
| SMK-26 | P3 | ux | client | Ошибка разбора `profiles.json` (не JSON) не называет файл | нет | — |
| SMK-27 | — | note | agent | Модель выдаёт вызов инструмента сырым текстом, он попадает в транскрипт | нет | — |

## Карточки

### SMK-21. REPL склеивает ответ и следующий блок мыслей (P3)

**Где:** рендер транскрипта REPL, `apps/codelab_cli/lib/src/repl/`. В `--ui tui` похожее исправлено в `acdc429`
(«пустая строка после мыслей»).

**Шаги:** REPL, встроенный или внешний агент →
`Create a file named repl.txt with content R using your write tool, then reply DONE` → `y`.

**Факт:** `DONEThe user wants me to reply with exactly "DONE" after I created the file…`. Текст сообщения агента
после вызова инструмента и следующий блок мыслей выводятся в одну строку. С внешним агентом то же самое
(`DONEThe file was created successfully…`), поэтому дело в рендере клиента, а не во встроенном режиме.

**Ожидание:** при смене вида блока (сообщение → мысли и обратно) рендер начинает новую строку, как в TUI.

**Риск:** нет. Страдает только читаемость.

### SMK-22. Риск одобрения завышается по словам в содержимом файла (P3)

**Где:** `packages/dart/codelab_client_acp/lib/src/domain/approval_policy.dart` (`_classifyToolAction`,
`_riskForString`).

**Шаги:** REPL, встроенный агент. Модель пишет новый файл `lib/pong_game.dart` с Dart-кодом игры.

**Факт:** две предыдущие записи (`index.html`, `style.css`) шли как `(local write)`, а эта — как
`Permission: Write lib/pong_game.dart (destructive)`. Политика повышает уровень по подстрокам (`reset `,
`remove `, `delete `, `migrate`, `wipe`, …) в `title`, `locations`, `rawInput` и `rawOutput`. В `rawInput` входит
и записываемое содержимое, поэтому комментарий вроде «Reset ball» в коде делает создание файла «разрушительным».

**Ожидание:** риск считается по виду инструмента (`ToolKind`) и по полям действия: путь, команда, URL. Свободный
текст содержимого (`content`, `newText`) уровень не поднимает. Эвристика по строкам остаётся только для команд
`execute`. Это меняет классификацию одобрений, поэтому нужен OpenSpec change.

**Риск:** ошибка в безопасную сторону: риск завышается, а не занижается (`AGENTS.md` §2, п. 1). Но метка вводит в
заблуждение и меняет решение режима (`ApprovalPolicy.decidePermission`): в `autoEdits` обычная запись (`localWrite`)
проходит без вопроса, а ложный `destructive` требует явного одобрения. Пользователь привыкает к ложным
`destructive` и перестаёт им верить.

### SMK-23. `/profile` повторяет данные профиля (P3)

**Где:** `apps/codelab_cli/lib/src/repl/commands/profile.dart`.

**Факт:**
- встроенный: `Profile embedded (Embedded agent): embedded embedded-cli`;
- inline-профиль из `-a stdio:…`: `Profile inline (stdio:<путь> serve --stdio): stdio <путь> serve --stdio` — команда агента выводится дважды.

**Ожидание:** каждая часть выводится один раз, например `Profile embedded: embedded agent (host profile embedded-cli)`
и `Profile inline: stdio <путь> serve --stdio`.

**Риск:** нет.

### SMK-24. Диалог одобрения записи показывает путь как `command:` (P3)

**Где:** `apps/codelab_cli/lib/src/repl/approval_prompt.dart` (`block`, строка `'  command: $command'`).

**Факт:** для записи файла выводится `command: repl.txt`, хотя это путь, а не команда. Для `execute` метка `command:`
верна (`command: echo $?`).

**Ожидание:** для `edit`/`delete`/`move` строка называется `path:`, `command:` остаётся для `execute`.

**Риск:** нет.

### SMK-25. Справка `test-scenario` показывает `--agent` обязательным (P3)

**Где:** `apps/codelab_cli/lib/src/cli_args.dart` (строка использования
`codelab test-scenario <file-or-dir>... --agent <profile>`) и `lib/src/scenario/test_scenario_command.dart`.

**Факт:** после D13, п. 7 change `add-embedded-agent-mode` без `--agent` агент выбирается как во всём CLI. Справка же
показывает `--agent <profile>` без скобок, то есть как обязательный параметр.

**Ожидание:** `[--agent <profile>]` и строка о выборе по умолчанию (профиль `default`, иначе встроенный агент).

**Риск:** нет.

### SMK-26. Ошибка разбора `profiles.json` не называет файл (P3)

**Где:** `packages/dart/codelab_client_io/lib/src/stores/json_file.dart` (`jsonDecode` без перехвата).

**Шаги:** записать в `$CODELAB_HOME/profiles.json` текст `{broken` → `codelab -p hi`.

**Факт:** код `64`, но в сообщении только текст `FormatException` (`Unexpected character …`) без пути. Для
`[1,2]` (неверная структура) сообщение называет файл: `Expected a JSON object in <path>.`

**Ожидание:** оба случая называют файл, например `<path>: invalid JSON (Unexpected character at 1:2)`.

**Риск:** нет. Код и fail-closed верны: тихого перехода на встроенного агента нет.

### SMK-27. Вызов инструмента сырым текстом в транскрипте (наблюдение)

**Где:** провайдер `openai-compatible` ядра агента и шаблон модели в LM Studio.

**Факт:** qwen3.5-9b иногда выдаёт вызов инструмента текстом (`<parameter=path> … </function></tool_call>`) вместо
структурного `tool_calls`. Агент передаёт его клиенту как обычный текст сообщения.

**Ожидание:** не дефект CodeLab, пока провайдер присылает текст. Если повторяется на других моделях, нужно отдельно
решить, распознавать ли такие вызовы. Это решение о поведении ядра, через OpenSpec, а не правка по месту.

**Риск:** нет. Текстовый «вызов» не исполняется.
