## Context

- **Задача.** 6.10 этапа 6 (`09-11-stage-6-cli-mvp.md`) и критерий выхода M2 (`delivery-roadmap.md` §4.3): e2e `codelab_cli` проходят против Python-, scripted- и Dart-агента.
- **Сейчас.** `apps/codelab_cli/test/e2e/` (42 теста `cli/*`) запускает только scripted-агента из `codelab_acp_testing` (`scriptedAgent()` в `test/support/cli_process.dart`). Тексты его ответов зашиты в проверки:
  - `hello from compatible stdio agent`;
  - `Permission: Run test command`;
  - `approved: allow_once`;
  - модели `gpt-5`/`gpt-4`.
- **Образец.** У тестов app есть `E2eAgent` (`apps/codelab_desktop/integration_test/support/e2e_agent.dart`, change `add-codelab-agent-binary`, D9):
  - выбор агента — `--dart-define=CODELAB_E2E_AGENT=scripted|dart`;
  - ожидания, которые у агентов различаются, собраны в `E2eLaunch`;
  - тег `scripted-only`;
  - сценарии `--llm-script` по имени режима `CodelabCompatibleStdioAgentMode.wireName`.
- **Dart-агент.** Умеет сценарный LLM: `--llm-script`, шаги `expect`/`reply`/`stopReason`/`error`/`delayMs`/`waitForCancel`. Он хранит сессии (`--sessions-dir`) и принимает режимы разрешений (`--permission-mode`) и модели (`--model`).
- **Python-агент** (`codelab serve --stdio`):
  - читает `$CODELAB_HOME/codelab.toml`;
  - с `[llm] provider = "mock"` отвечает `Mock response` без сети. Это проверено: `codelab -p hello -a 'stdio:codelab serve --stdio'` с временным `CODELAB_HOME` даёт `Mock response`, код `0`;
  - инструментов mock-провайдер не вызывает.
- **Ограничения:**
  - сторож импортов: клиентам запрещён `package:codelab_agent_*`, поэтому агент запускается как процесс по пути к файлу;
  - `AGENTS.md` §21: интеграционные тесты в `feature/*` — только Dart VM, это выполняется.

## Goals / Non-Goals

**Goals:**
- Одни и те же тесты `cli/*` идут против scripted- и Dart-агента, а тесты обычного хода — ещё и против Python-агента.
- Различия агентов собраны в одном помощнике, тесты не знают текстов конкретного агента.
- e2e против Dart-агента входят в `check` и CI; без Python-агента прогон зелёный с пропусками и причиной.

**Non-Goals:**
- Изменения `lib/` CLI или агента.
- `embedded`-профиль (этап 7).
- Python-агент в CI.
- Одобрение и инструменты на Python-агенте: mock-провайдер их не вызывает.
- `cli/headless-stream-json-*` — их ещё нет (change `add-cli-stream-json`).

## Decisions

### D1. Выбор агента — переменная окружения процесса тестов

`CODELAB_E2E_AGENT=scripted|dart|python`, по умолчанию `scripted`. Неизвестное значение — `ArgumentError` при первом обращении.

Почему переменная окружения, а не `--dart-define`: e2e CLI — тесты Dart VM под `dart test` и `flutter test` (`melos run test`). Окружение доступно в обоих без флагов компиляции. У app `--dart-define`, потому что тесты собираются как приложение.

### D2. Помощник `E2eCliAgent` в `test/e2e/support/e2e_agent.dart`

```dart
enum E2eAgentKind { scripted, dart, python }

final class E2eCliAgent {
  static final E2eCliAgent current;          // из CODELAB_E2E_AGENT
  final E2eAgentKind kind;
  String? get unavailable;                    // причина пропуска (Python не установлен)
  Future<E2eCliLaunch> launch(Directory dir, {CodelabCompatibleStdioAgentMode mode});
}

final class E2eCliLaunch {
  final String agent;                         // значение --agent: stdio:'…' …
  final Map<String, String> environment;      // CODELAB_HOME для Python и т. п.
  final String answer;                        // текст ответа на обычный промпт
  final String permissionTitle;               // заголовок вызова в «Permission: …»
  final String permissionCommand;             // «command: …» блока одобрения
  final String allowedMarker, rejectedMarker; // итог хода после y / n
  final List<String> models;                  // значения опции model: текущее первым
}
```

`scriptedAgent()` из `test/support/cli_process.dart` остаётся для модульных тестов, которые не входят в матрицу. e2e переходят на `E2eCliAgent.current.launch`.

### D3. Dart-агент — kernel и свои сценарии CLI

- **Kernel.** `apps/codelab_agent/bin/codelab_agent.dart` компилируется в kernel один раз на прогон, как CLI (`CliProcess.kernel()`, design.md change `add-codelab-cli`, D11). Агент запускается `dart <agent>.dill serve --stdio --llm-script <сценарий> [флаги режима]`.
  - Почему не `build/bin/codelab-agent`: AOT-сборка — отдельный шаг вне `check` (`build:agent`), а kernel не требует шага до тестов.
- **Сценарии** — `apps/codelab_cli/test/e2e/llm_scripts/<wireName>.json`.
  - Свои, а не сценарии app: промпты тестов CLI другие (`run it`, `hello`, `slow`), а файлы app принадлежат их тестам.
  - Загрузку каждого сценария проверяет `apps/codelab_agent/test/llm_scripts_load_test.dart` — расширяется каталогом CLI, как для app. Так битый сценарий ловится и без прогона матрицы.
- **Флаги режима** — как `_dartFlags` у app:

  | Режим | Флаги |
  |---|---|
  | `withPermissionRequest` | `--permission-mode standard` |
  | `withConfigOptions` | `--model gpt-5 --model gpt-4` |
  | `withSessionList` и `--continue` | `--sessions-dir <tmp>/agent-sessions` |
  | `hangsUntilCancel` | шаг `waitForCancel` |
  | ошибка провайдера | шаг `error` |
  | `withToolCalls` | шаги `toolCall` `read` и `exec` в режиме `bypass` |

- **Ожидания Dart-агента:**
  - заголовок одобрения `exec` — сама команда (`echo hello`);
  - модели — `scripted/gpt-5` и `scripted/gpt-4`;
  - итог одобрения — строка вызова `✓ echo hello` после `y` и отказ после `n`, а не текст `approved: …` scripted-агента.

### D4. Python-агент — mock-провайдер и тег `python-agent`

- **Запуск.** Агент — `codelab` из `PATH`. Признак Python-агента — `codelab serve --help` с кодом `0` и строкой `--stdio`. Иначе `unavailable` — `Python agent (codelab serve) is not installed`, и тест пропускается с этой причиной.
- **Окружение.** Временный `CODELAB_HOME` с `codelab.toml`:

  ```toml
  [llm]
  provider = "mock"
  model = "mock/mock"
  ```

  Своя папка на тест: Python-агент держит `codelab-stdio.lock` в `CODELAB_HOME`.
- **Объём.** Только тесты с тегом `python-agent`: ответ на промпт, без инструментов и одобрений.
  - `cli/headless-print-basic` — ответ в stdout и код `0`;
  - `cli/repl-prompt-streaming` — в PTY и в pipe;
  - `cli/tui-smoke` — промпт и выход.

  Ожидаемый ответ — `Mock response`.

### D5. Теги и прогоны

- **Теги** объявляются в `apps/codelab_cli/dart_test.yaml`:
  - `scripted-only` — поведение, которое есть только у scripted-агента;
  - `python-agent` — тесты, которые идут и против Python-агента.
- **Прогоны:**

  | Агент | Команда | Кто гоняет |
  |---|---|---|
  | scripted | `melos run test:e2e:cli` и `melos run test` — как сейчас, все тесты | `check`, CI |
  | Dart | `CODELAB_E2E_AGENT=dart fvm dart test apps/codelab_cli/test/e2e --exclude-tags scripted-only` (`test:e2e:cli:dart-agent`) | `check`, CI (джоб `e2e-cli-dart`) |
  | Python | `CODELAB_E2E_AGENT=python fvm dart test apps/codelab_cli/test/e2e --tags python-agent` (`test:e2e:cli:python-agent`) | локально; без агента — пропуск |

- **Агентонезависимые тесты** — с тегом `scripted-only`: незачем гонять их трижды. Это неизвестный флаг, пустой `CODELAB_HOME`, недоступный бинарь и `embedded` → `64`.

### D6. Матрица тестов

| Тест | scripted | Dart | Python | Почему не везде |
|---|---|---|---|---|
| `cli/headless-print-basic`: ответ, профиль `default` | да | да | да | — |
| `cli/headless-print-basic`: пустой `CODELAB_HOME`, бинарь не запускается, неизвестный флаг | да | — | — | от агента не зависят |
| `cli/headless-exit-codes`: ошибка провайдера, пустой ответ, `--timeout`, SIGTERM, SIGINT, stdin и `-f` | да | да | — | сценарии Dart через `error`, пустой `reply` и `waitForCancel`; mock их не умеет |
| `cli/headless-permission-denied`, `cli/headless-bypass-flag` | да | да | — | у mock нет инструментов |
| `cli/resume-last-session` | да | да | — | Dart — `--sessions-dir` |
| `cli/connect-profiles-stdio-ws-embedded`: stdio | да | да | — | — |
| `cli/connect-profiles-stdio-ws-embedded`: ws, `embedded` | да | — | — | WebSocket-агент теста — scripted; `embedded` от агента не зависит |
| `cli/repl-permission-allow-once`, `-reject` | да | да | — | у mock нет инструментов |
| `cli/slash-menu-merges-agent-commands` | да | — | — | Dart-агент объявит команды на этапе 8 (R-07, R-08) |
| `cli/client-commands-smoke` (`/sessions`, `/resume`) | да | да | — | — |
| `cli/model-picker-sets-config-option` | да | да | — | у mock одна модель |
| `cli/repl-prompt-streaming` (PTY, pipe) | да | да | да | — |
| `cli/repl-prompt-streaming` с `NO_COLOR`, `cli/thought-rendered-dimmed`, `cli/tool-row-format` | да | да | — | нужны мысли и инструменты |
| `cli/esc-cancels-turn`, `cli/prompt-queue-drains-after-turn`, SIGTERM в REPL | да | да | — | нужен долгий ход |
| `cli/tui-smoke`: промпт, первое сообщение | да | да | да | — |
| `cli/tui-smoke`: SIGTERM, одобрение, `/model` | да | да | — | — |

Если сценарий Dart-агента не может воспроизвести проверку scripted-агента дословно, тест проверяет то же поведение через ожидания `E2eCliLaunch`, а не через текст. Так устроены итог одобрения и заголовок вызова. Дословное поведение scripted-агента не переносится.

## Risks / Trade-offs

- **Время.** Матрица почти удваивает e2e CLI (около 40 процессов и компиляция kernel агента). Мера — отдельный джоб CI `e2e-cli-dart`, параллельно остальным; `check` локально тоже дольше.
- **Хрупкость сценариев.** Сценарий шага `expect` завязан на текст промпта теста. Мера — загрузка сценариев в `llm_scripts_load_test.dart` и общий помощник; промпты задаются константами рядом с ожиданиями.
- **Python-агент меняется вне репозитория.** Текст mock-ответа или формат `codelab.toml` могут поменяться. Мера — только тесты обычного хода, ожидание в одном месте (`E2eCliLaunch.answer`), прогон локальный и не блокирует CI.
- **Признак Python-агента.** Другая программа `codelab` в `PATH` (будущий бинарь CLI этапа 9) не отвечает на `serve --help` как Python-агент. Тогда тест пропускается, а не падает.

## Migration Plan

Переходит только тестовый код. Тесты по одному переводятся на `E2eCliAgent`. Прогон против scripted-агента должен остаться зелёным на каждом шаге, затем включается прогон против Dart-агента. Откат — убрать джоб CI и скрипт из `check`.

## Open Questions

Нет. Решения о Python-агенте вне CI и об объёме тестов обычного хода приняты в D4 и D5.
