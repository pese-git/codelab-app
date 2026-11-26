# Документация CodeLab CLI

Оглавление всех документов терминального клиента `codelab` (`apps/codelab_cli`). Документы разделены по тому, кто их читает: пользователь, тот, кто собирает и сопровождает, и разработчик, который меняет код. Короткий вход в приложение — [README приложения](../README.md).

## Для пользователя

- [Руководство пользователя](user-guide.md) — оглавление глав: диалог, полноэкранный режим, один запрос без диалога, выбор папки, модели и агента, провайдеры, секреты, MCP-серверы, проверка настроек, справочник флагов. Главы лежат в каталоге [`user/`](user/00-overview.md), по одной на тему.

## Для DevOps

- [Эксплуатация](operations.md) — сборка, запуск без человека в скриптах и CI, файлы и переменные окружения, коды выхода.

## Для разработчика

[Разработка](development.md) — короткий вход: как собрать, запустить и проверить, и в какой главе искать остальное. Руководство по главам объясняет, как устроен клиент: как программа выбирает режим, как собирает клиентский слой, как работают построчный режим, полноэкранный режим, headless `-p` и драйвер фикстур, как подключаются настройки агента и профили. Прочитав его, вы найдёте точку входа любого поведения и знаете, куда добавить команду, флаг или клавишу.

Руководство описывает код как он есть. Проектные документы в [`docs/architecture/proposals/dart-agent-and-clients/`](../../../docs/architecture/proposals/dart-agent-and-clients/) объясняют, почему решения приняты так, но писались до кода и местами расходятся с ним: если они спорят, прав код. Нормы лежат в спецификациях [`openspec/specs/`](../../../openspec/specs/) и в [`AGENTS.md`](../AGENTS.md) приложения.

### Порядок чтения

Для первого знакомства читайте подряд:

0. [Начало работы](00-getting-started.md): подготовка репозитория, запуск из исходников, бинарь, `--verbose`, тесты, «что изменить — куда смотреть».
1. [Обзор](01-overview.md): место приложения в слоях, зависимости, карта `lib/src/`, словарь, швы для тестов.
2. [Запуск и composition root](02-startup-and-composition.md): `runCodelab`, выбор режима, `buildCliRuntime`, встроенный агент, коды выхода, сигналы.
3. [Построчный режим](03-repl.md): цикл `Repl`, ввод, маршрутизатор `/…`, блок одобрения, вывод хода.

Остальные главы читайте по нужной теме, в любом порядке.

### Главы

| Глава | О чём |
|---|---|
| [00. Начало работы](00-getting-started.md) | подготовка, три способа запуска, `--verbose`, один тест, e2e-скрипты Melos, карта «что изменить — куда смотреть» |
| [01. Обзор](01-overview.md) | слои и зависимости, карта кода, словарь, швы `CliIo`, `Terminal`, `SignalSeam` и другие |
| [02. Запуск и composition root](02-startup-and-composition.md) | `parseCliArgs`, `runCodelab`, выбор режима, `buildCliRuntime`, резолверы транспортов, встроенный агент, коды выхода, сигналы |
| [03. Построчный режим](03-repl.md) | `Repl` и `ReplSession`, состояния ввода, клавиши, редактор и история, маршрутизатор и команды, блок одобрения, рендер |
| [04. Полноэкранный режим](04-tui.md) | чистое ядро `tui/core` (модель, сообщения, `reduce`, кадр) и адаптер к `dart_tui`, оверлеи, восстановление терминала |
| [05. Режим `-p`](05-headless.md) | источник промпта, политика `--approve`, вывод, исход хода и код выхода, таймаут и сигналы |
| [06. `test-scenario`](06-test-scenario.md) | драйвер фикстур: выбор агента, пропуск фикстур, вывод, JUnit |
| [07. Настройка агента](07-config-and-setup.md) | `config`, `provider`, `mcp`, `secret` через мост `codelab_setup`, мастер провайдера, первый запуск, `/provider` и `/settings` |
| [08. Профили и домашний каталог](08-profiles-and-home.md) | формы `--agent`, `profiles`, `CodelabHome`, история, недавние проекты, алиас `serve` |
| [09. Тестирование](09-testing.md) | уровни тестов, помощники, матрица e2e и теги, какие проверки запускать |
| [10. Расширение](10-extending.md) | рецепты: слэш-команда, флаг, подкоманда, клавиша и сообщение TUI |
| [11. Частые проблемы](11-troubleshooting.md) | симптом, причина, что сделать |
| [Туториал: новая слэш-команда](tutorial-new-command.md) | сквозной пример `/where`: тест, код, регистрация, проверка в REPL и TUI |

### Кому что читать

| Задача | Главы |
|---|---|
| понять, как устроен клиент | 01, 02, 03, 04 |
| начать работу с кодом, запустить и отладить | 00, 09, 11 |
| добавить слэш-команду | 03, 10, [туториал](tutorial-new-command.md) |
| добавить флаг или подкоманду | 02, 07, 10 |
| изменить полноэкранный режим | 04, 10 |
| изменить режим `-p` и его коды выхода | 02, 05 |
| проверить агента фикстурами | 06 |
| изменить мастер провайдера, `/settings`, первый запуск | 07, 04 |
| изменить профили подключения | 08, 02 |
| написать тест | 09 |
| диагностировать сбой | 00, 11 |

## Смежные документы

- Пользователь и эксплуатация: [руководство пользователя](user-guide.md), [эксплуатация](operations.md), [README приложения](../README.md).
- Клиентский слой, на котором стоит CLI: [`codelab_client_core`](../../../packages/dart/codelab_client_core/doc/README.md), [`codelab_client_acp`](../../../packages/dart/codelab_client_acp/doc/README.md), [`codelab_client_io`](../../../packages/dart/codelab_client_io/doc/README.md).
- Мосты и тесты: [`codelab_embedded`](../../../packages/dart/codelab_embedded/README.md), [`codelab_setup`](../../../packages/dart/codelab_setup/README.md), [`codelab_acp_testing`](../../../packages/dart/codelab_acp_testing/README.md); ядро агента, которое CLI запускает в процессе, — [руководство по ядру](../../../packages/dart/codelab_agent_core/doc/README.md).
- Второй клиент рядом: [документация CodeLab app](../../codelab_desktop/doc/README.md).
- Правила: [`AGENTS.md`](../AGENTS.md) приложения, [`AGENTS.md`](../../../packages/dart/codelab_client_core/AGENTS.md) клиентского слоя, корневой [`AGENTS.md`](../../../AGENTS.md) (§5, §10, §21).
- Спецификации: [`codelab-cli`](../../../openspec/specs/codelab-cli/spec.md), [`cli-headless`](../../../openspec/specs/cli-headless/spec.md), [`codelab-tui`](../../../openspec/specs/codelab-tui/spec.md), [`cli-scenario-driver`](../../../openspec/specs/cli-scenario-driver/spec.md), [`client-agent-setup`](../../../openspec/specs/client-agent-setup/spec.md), [`testing-quality`](../../../openspec/specs/testing-quality/spec.md).
- Устройство CLI в проектных документах: [этап 6, CLI MVP](../../../docs/architecture/proposals/dart-agent-and-clients/09-11-stage-6-cli-mvp.md), [отображение и ввод CLI](../../../docs/architecture/proposals/dart-agent-and-clients/12-2-cli-display-and-input.md), [первый запуск и настройки](../../../docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md), [этап 7, встроенный агент](../../../docs/architecture/proposals/dart-agent-and-clients/09-12-stage-7-embedded.md).
- Уровни тестов: [`docs/architecture/testing.md`](../../../docs/architecture/testing.md).
