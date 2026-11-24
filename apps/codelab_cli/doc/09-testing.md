# Тестирование клиента

Глава описывает, как проверяется `codelab_cli`: какие бывают тесты, какие помощники в `test/support/`, как устроены процессные и PTY-тесты, как агент выбирается переменной `CODELAB_E2E_AGENT` и какие проверки запускать после правки. Общие уровни тестов проекта — [`docs/architecture/testing.md`](../../../docs/architecture/testing.md); требования — спецификация [`testing-quality`](../../../openspec/specs/testing-quality/spec.md). Как запустить тесты первый раз — [глава 00](00-getting-started.md#тесты). Оглавление руководства — [README](README.md).

## Принципы

- **TDD.** Пары «тест → реализация»; красный тест коммитится отдельно до кода (`AGENTS.md` приложения, §3). Коммит — только по явной просьбе.
- **Логика без процессов.** Решения, коды выхода, рендер, декодер клавиш, редактор строки, политика одобрений и ядро экрана — чистые и проверяются без процесса и терминала. Процесс нужен только для того, что видно снаружи: реальные потоки, сигналы, PTY.
- **Настоящий клиентский слой.** Раннеры CLI в модульных тестах работают поверх настоящих `ClientWorkspace` и `AcpClientApplication`, а не фейка клиентского слоя: так тест проверяет то же, что увидит процесс. Фейком служит только транспорт и агент.
- **Изолированный `CODELAB_HOME`.** Каждый тест, запускающий REPL или TUI, получает свой временный каталог: интерактивные режимы пишут историю и недавние проекты.
- **Интеграционные тесты только на Dart VM.** На устройстве и симуляторе CLI не тестируется (корневой [`AGENTS.md`](../../../AGENTS.md), §21).

## Уровни

| Уровень | Каталог | Что проверяет | Чем |
|---|---|---|---|
| Чистая логика | `test/*_test.dart`, `test/input/`, `test/render/`, `test/headless/` | разбор флагов, коды выхода, клавиши, редактор, рендер, политика одобрений | прямые вызовы функций |
| Команда `runCodelab` | `test/run_test.dart`, `config_command_test.dart`, `secret_command_test.dart`, … | выбор режима, stdout, stderr и код выхода | `runCodelab(args, environment: …, io: FakeCliIo())` |
| REPL | `test/repl/` | цикл, клавиши, команды, одобрения, очередь | `ReplHarness`: `Repl` на `FakeAgent` и `FakeTerminal` |
| Ядро экрана TUI | `test/tui/` | `reduce`, кадр, оверлеи | цепочка сообщений и строки кадра, без терминала |
| Адаптер TUI | `test/tui/tui_app_test.dart`, `tui_effects_test.dart`, … | `TuiApp`, `TuiEffects`, `TuiCommandContext` | `Program` с `withInput`, `withOutput`, `withWindowSize`, `withoutSignalHandler` |
| Мастер и настройки | `test/setup/` | мастер, первый запуск, строки настроек | фейки портов `setup_fakes.dart` |
| Драйвер фикстур | `test/scenario/` | `test-scenario`, пропуск фикстур, JUnit | процесс-повторитель в kernel |
| Процессные e2e | `test/e2e/` | CLI как процесс: потоки, коды, сигналы | `CliProcess`, kernel |
| PTY-e2e | `test/e2e/` — файлы, которые используют `PtyProcess` (`repl_turn_test`, `repl_interaction_test`, `tui_smoke_test`, `tui_setup_test`, `provider_setup_test`, `status_line_usage_test`, `recent_projects_test`) | интерактив: raw-режим, клавиши, кадр | `PtyProcess` на системной утилите `script` |

## Помощники

Все лежат в `test/support/` и `test/e2e/support/`; в рабочий код не попадают.

| Помощник | Для чего |
|---|---|
| `FakeCliIo` | stdout, stderr и признаки терминала в памяти для `runCodelab`: `stdoutText`, `stderrText`; `stdinIsTerminal`, `stdoutIsTerminal` задают режим |
| `FakeTerminal` | порт `Terminal`: `type`, `press` подают байты клавиш, `text` — весь вывод, `rawEnabled`, `restoreCount` — что REPL сделал с режимом |
| `FakeAgent` | агент на `FakeAcpTransport` с настоящим `ClientWorkspace`: `next(method)` ждёт запрос клиента, `respond`, `chunk`, `update`, `fail` отвечают от имени агента; `restartAgent` — новый «процесс» |
| `ReplHarness` | REPL на `FakeAgent` и `FakeTerminal`: `start`, `line(text)` (ввод и Enter), `waitText`, `lastOutput`, `sentMethods`, `exit()` (Ctrl+D) |
| `setup_repl_harness.dart`, `setup_fakes.dart` | REPL и фейки портов для `/provider` и `/settings` |
| `tui_overlay_fixtures.dart` | заготовки ядра экрана для тестов оверлеев |
| `MemoryProfileStore` | `ProfileStore` в памяти; `broken` читает битый файл |
| `FakeModelsServer` | сервер `GET …/models` на `127.0.0.1` для проверки провайдера: сеть наружу не нужна |
| `CliProcess` | процесс `codelab` из kernel: `run(args, environment:, stdin:)`, `start` для тестов с сигналами и stdin |
| `PtyProcess` | процесс в псевдотерминале (`script`): `write`, `waitFor`, `exitCode`; команду собирает по ОС (BSD `script` на macOS, util-linux на Linux) |
| `E2eCliAgent` | агент e2e по `CODELAB_E2E_AGENT`: `launch(dir, mode:)` даёт значение `--agent` и ожидания, которые у агентов различаются |
| `replayAgentProfile` | процесс-повторитель фикстур для `test-scenario` |

`FakeAgent` и `ReplHarness` — основной способ проверить поведение, не поднимая процесс:

```dart
test('/queue drop <n> removes the n-th prompt', () async {
  repl.line('/queue drop 1');
  await repl.waitText('Dropped');

  repl.agent.respond(running, {'stopReason': 'end_turn'});
  final next = await repl.agent.next(sessionPromptMethod);
  expect(promptTextOf(next), 'third');
});
```

Этот фрагмент — из `test/repl/commands/queue_test.dart`: после команды агент отвечает на первый ход, и следующий `session/prompt` несёт промпт `third`, а не удалённый `second`.

Чистое ядро TUI проверяется цепочкой сообщений (`test/tui/tui_update_test.dart`):

```dart
(TuiModel, List<TuiCmd>) _run(TuiModel model, List<TuiMsg> messages) {
  final cmds = <TuiCmd>[];
  for (final msg in messages) {
    final (next, out) = reduce(model, msg);
    model = next;
    cmds.addAll(out);
  }
  return (model, cmds);
}

// Enter отправляет промпт и сохраняет историю.
final (model, cmds) = _run(_model(), [_text('hi'), _key(Key.enter)]);
expect(cmds, [const SaveHistoryCmd(['hi']), const SubmitCmd('hi')]);
```

Команды сравниваются по значению: поэтому `TuiCmd` — данные, а не замыкания.

## Матрица e2e и теги

Процессные и PTY-тесты запускают CLI против агента, который выбирает переменная `CODELAB_E2E_AGENT`. Одни и те же тесты `cli/*` проверяют клиент против разных агентов; тексты ответов у агентов разные, поэтому ожидания берутся из одного помощника `E2eCliAgent`, а не из текстов конкретного агента в тестах.

| Значение | Агент | Как запускается CLI | Скрипт Melos |
|---|---|---|---|
| `scripted` (по умолчанию) | scripted stdio-агент из `codelab_acp_testing` | kernel `bin/codelab.dart` | `test:e2e:cli` |
| `dart` | `codelab-agent serve --stdio` со сценарием `--llm-script` из `test/e2e/llm_scripts/` | kernel `bin/codelab.dart` | `test:e2e:cli:dart-agent` |
| `embedded` | встроенный агент | kernel тестовой точки входа `test/e2e/support/embedded_cli_main.dart` со сценарием модели | `test:e2e:cli:embedded` |
| `python` | Python-агент `codelab serve --stdio` с провайдером `mock` | kernel `bin/codelab.dart` | `test:e2e:cli:python-agent` (только локально, в `check` не входит) |

Теги (`dart_test.yaml`):

- `scripted-only` — тест проверяет поведение только scripted-агента или не зависит от агента. Прогоны `dart` и `embedded` идут с `--exclude-tags scripted-only`. Без исключения в варианте `embedded` такие тесты падают с `embedded_cli_main: CODELAB_E2E_LLM_SCRIPT is not set`.
- `python-agent` — тесты обычного хода, которые идут и против Python-агента (его mock-провайдер отвечает текстом, без инструментов).

Python-агент не входит в monorepo и заморожен; тест против него пропускается с сообщением, если `codelab serve --help` не отвечает как Python-агент.

Kernel компилируется один раз на прогон: `dart run` компилирует точку входа при каждом запуске, а тестам нужно много процессов. Файлы называются `codelab.dill`, `embedded_codelab.dill`: тесты сигналов ищут процесс CLI по `pkill -f '.*codelab\.dill --agent …'` в любом варианте прогона, поэтому имя нельзя менять. `CliProcess.start` запускает процесс с пустым окружением (кроме `PATH`) и несуществующим `HOME`: тест не видит настоящий `~/.codelab`. Точка входа выбирается параметром `entry`: `CliEntry.variant` (по `CODELAB_E2E_AGENT`), `production` (всегда `bin/codelab.dart`), `scriptedEmbedded` (всегда сценарная).

### Имена тестов — доказательства матрицы целей

Имена e2e — идентификаторы критериев матрицы целей `docs/architecture/proposals/agent-parity-goals.md`: тест называется `cli/<id>: …`. Тест `parity_evidence_test.dart` сторожа проверяет, что для строки Must с критерием `cli/<id>` в `apps/codelab_cli/test/e2e/` есть вызов `test(` или `group(` (не вложенный в другой `group(`), первый строковый литерал которого начинается с `cli/<id>`, а за id идёт конец литерала, `:` или пробел. Упоминание id в комментарии тестом не считается. В отчётах (`CODELAB_TEST_REPORT_DIR`) тест, исключённый тегом, получает статус `not-run`: если у критерия единственный тест помечен `scripted-only`, доказательства для варианта `dart` у него нет. Поэтому новый e2e-тест называют по критерию, а не придумывают имя (spec `testing-quality`, «Проверка доказательств матрицы целей»).

### PTY

Интерактивные сценарии идут через псевдотерминал утилиты `script`: своего FFI-пакета PTY в репозитории нет, а новая зависимость — архитектурное решение. В `main` теста:

```dart
final skip = await PtyProcess.unavailableReason();
```

Без `script` и в Windows тест пропускается с сообщением, а не падает. Переводы строк PTY нормализуются к `\n` перед сравнением. PTY не отвечает на запросы терминала (DECRQM, kitty), поэтому `cli/tui-smoke` проверяет путь без synchronized output и без kitty; путь с ними проверяет тест адаптера `tui_app_test.dart`.

## Что запускать после правки

Перед pull request — проверки затронутого (корневой [`AGENTS.md`](../../../AGENTS.md), §21): `fvm dart format --set-exit-if-changed`, `fvm dart analyze` в пакете, тесты изменённых файлов. Для CLI дополнительно:

| Что изменено | Что запустить |
|---|---|
| `pubspec.yaml`, импорты между пакетами | `fvm dart run melos run guard` |
| любой код CLI, видимый процессу | `fvm dart run melos run test:e2e:cli:embedded`, `test:e2e:cli:dart-agent` |
| `codelab_embedded`, встроенный агент, `test-scenario` | `fvm dart run melos run conformance:embedded`, `test:e2e:cli:embedded` |
| клиентский слой, через который работает CLI | то же и `conformance:client` |

Если проверка не запускалась, об этом нужно сказать явно; зелёный `melos run check` не заменяет их по затронутому.

## Смотрите также

- [Глава 06: `test-scenario`](06-test-scenario.md) — проигрыватель корпуса из рабочего бинаря
- [`docs/architecture/testing.md`](../../../docs/architecture/testing.md), [`codelab_acp_testing`](../../../packages/dart/codelab_acp_testing/README.md)
