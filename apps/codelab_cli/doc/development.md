# `codelab`: разработка

Короткий вход для тех, кто меняет код терминального клиента: как собрать, запустить и проверить, и в какой главе искать остальное. Устройство, таблицы и рецепты — в [главах руководства](README.md#главы); здесь их нет. Правила изменений — в [`AGENTS.md`](../AGENTS.md) приложения.

## Собрать и запустить

Подготовка репозитория (FVM, `melos bootstrap`, генерация кода без которой бинарь не собирается) и три способа запуска — в [главе 00](00-getting-started.md). Коротко, из корня репозитория:

```bash
fvm dart run apps/codelab_cli/bin/codelab.dart --version
fvm dart run melos run build:cli
```

Вторая команда собирает бинарь `build/bin/codelab`: интерактивные режимы (построчный и полноэкранный) нужны терминалу, а `fvm dart run` его процессу не отдаёт. Изоляция `CODELAB_HOME` и ключей, `--verbose` — в [главе 00](00-getting-started.md#изоляция-codelab_home-и-ключи).

## Проверить

```bash
cd apps/codelab_cli
fvm dart format --set-exit-if-changed <файлы>
fvm dart analyze
fvm dart test $(ls -d test/*_test.dart test/*/ | grep -v '^test/e2e/')
```

Процессные тесты, скрипты Melos (`test:e2e:cli:*`, `conformance:embedded`, `guard`) и что запускать после какой правки — в [главе 00](00-getting-started.md#тесты) и [главе 09](09-testing.md#что-запускать-после-правки). Уровни тестов — [testing.md](../../../docs/architecture/testing.md).

## Куда смотреть

| Что нужно | Глава |
|---|---|
| слои и зависимости, карта `lib/src/`, словарь, швы для тестов | [01. Обзор](01-overview.md) |
| `runCodelab`, выбор режима, composition root, коды выхода, сигналы | [02. Запуск и composition root](02-startup-and-composition.md) |
| построчный режим, команды `/…`, блок одобрения | [03. Построчный режим](03-repl.md) |
| полноэкранный режим | [04. Полноэкранный режим](04-tui.md) |
| режим `-p` | [05. Режим `-p`](05-headless.md) |
| драйвер фикстур | [06. `test-scenario`](06-test-scenario.md) |
| `config`, `provider`, `mcp`, `secret`, мастер провайдера | [07. Настройка агента](07-config-and-setup.md) |
| профили, `CodelabHome`, история | [08. Профили и домашний каталог](08-profiles-and-home.md) |
| тесты, помощники, матрица e2e | [09. Тестирование](09-testing.md) |
| новая команда, флаг, подкоманда, клавиша | [10. Расширение](10-extending.md), [туториал](tutorial-new-command.md) |
| сбои | [11. Частые проблемы](11-troubleshooting.md) |
| «что изменить — куда смотреть» по задачам | [таблица в главе 00](00-getting-started.md#что-изменить-куда-смотреть) |

## Правила

Главное: клиентский слой владеет состоянием сессий, `codelab` только отображает его; пакеты `codelab_agent_*` не импортируются, агента клиент получает через мосты `codelab_embedded` и `codelab_setup`; `dart:io` запрещён в `lib/src/tui/core/`. Полный список — в [`AGENTS.md`](../AGENTS.md) приложения; импорты между пакетами проверяет сторож (`fvm dart run melos run guard`).

## Смотрите также

- Спецификации и проектные документы — в [оглавлении](README.md#смежные-документы).
- [Руководство пользователя `codelab`](user-guide.md), [эксплуатация](operations.md).
