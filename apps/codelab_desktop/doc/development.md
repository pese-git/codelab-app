# CodeLab app: разработка

Короткий вход для тех, кто меняет код настольного приложения: как собрать, запустить и проверить, и в какой главе искать остальное. Устройство, таблицы и рецепты — в [главах руководства](README.md#главы); здесь их нет. Правила изменений — в [`AGENTS.md`](../AGENTS.md) приложения.

## Собрать и запустить

Подготовка репозитория (FVM, `melos bootstrap`, генерация кода) и запуск — в [главе 00](00-getting-started.md). Без сгенерированного кода (`*.freezed.dart`) тесты и запуск падают; как его создать — в [запуске из исходников](../../../docs/user/run-from-source.md#1-подготовка). Коротко:

```bash
cd apps/codelab_desktop
fvm flutter run -d macos
```

Запуск с временным `CODELAB_HOME` и управление запущенным приложением через `flutter_driver` — в [главе 00](00-getting-started.md#изолированный-запуск-с-codelab_home).

## Проверить

```bash
cd apps/codelab_desktop
fvm dart format --set-exit-if-changed <файлы>
fvm flutter analyze
fvm flutter test
```

Какие ещё проверки (`guard`, `l10n:check`, тесты `codelab_ui`, скрипты `test:e2e:app:*` только в `release/<version>`) нужны при том или ином изменении — таблица в [главе 08](08-testing.md#какие-проверки-затрагивает-изменение). Уровни тестов — [testing.md](../../../docs/architecture/testing.md).

## Куда смотреть

| Что нужно | Глава |
|---|---|
| где приложение стоит среди пакетов, из каких фич состоит, карта `lib/`, словарь | [01. Обзор](01-overview.md) |
| как собирается граф зависимостей, путь от `main` до первого кадра и выхода | [02. Composition root](02-composition-root.md) |
| как состояние клиентского слоя доходит до виджетов | [03. Путь состояния](03-state-flow.md) |
| страницы настроек, переходы, приветственные шаги | [04. Навигация и настройки](04-navigation-and-settings.md) |
| текст интерфейса, язык | [05. Локализация](05-localization.md) |
| порты ОС, оформление, системный акцент | [06. Платформа и оформление](06-platform-and-appearance.md) |
| встроенный агент, профили, провайдеры, MCP | [07. Встроенный агент и подключения](07-embedded-agent-and-connections.md) |
| тесты и двойники | [08. Тестирование](08-testing.md) |
| рецепты: новая фича, страница настроек, строка, сочетание клавиш, порт | [09. Расширение](09-extending.md) |
| сбои при запуске, выходе, тестах | [10. Частые проблемы](10-troubleshooting.md) |

## Правила

Главное: Cubit-ы и виджеты не обращаются к файлам, процессам и хранилищу секретов напрямую — только через порты, реализации которых собирает `lib/app/`; пакеты `codelab_agent_*` не импортируются, агента приложение получает через мосты `codelab_embedded` и `codelab_setup`. Полный список — в [`AGENTS.md`](../AGENTS.md) приложения; правила слоёв проверяет сторож (`fvm dart run melos run guard`).

## Смотрите также

- Спецификации: [agent-workbench-ui](../../../openspec/specs/agent-workbench-ui/spec.md), [app-settings](../../../openspec/specs/app-settings/spec.md), [embedded-agent](../../../openspec/specs/embedded-agent/spec.md), [client-agent-setup](../../../openspec/specs/client-agent-setup/spec.md), [approval-safety](../../../openspec/specs/approval-safety/spec.md).
- Устройство приложения: [отображение в app](../../../docs/architecture/proposals/dart-agent-and-clients/12-3-desktop-display.md), [этап 7, встроенный агент](../../../docs/architecture/proposals/dart-agent-and-clients/09-12-stage-7-embedded.md), [разрешения](../../../docs/architecture/permissions.md), [платформа](../../../docs/architecture/platform-integration.md).
- [Руководство пользователя CodeLab app](user-guide.md), [эксплуатация](operations.md).
