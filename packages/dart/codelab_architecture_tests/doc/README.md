# Руководство по сторожу репозитория

Руководство для разработчика объясняет, как устроен `codelab_architecture_tests`: пакет без кода, только тесты. Они читают исходники и `pubspec.yaml` всех пакетов monorepo и падают, если нарушена граница из [`AGENTS.md`](../../../../AGENTS.md) §5. Прочитав руководство, вы знаете, откуда каждый тест берёт данные, как читать сообщение о нарушении и как добавить правило.

Руководство описывает код как он есть. Нормы лежат в [`AGENTS.md`](../../../../AGENTS.md), спецификации [`workspace-architecture`](../../../../openspec/specs/workspace-architecture/spec.md) («Автоматический сторож границ пакетов») и [ADR-0002](../../../../docs/architecture/adr/0002-name-packages-codelab-side-layer.md). Краткий обзор и порядок добавления правила — в [README пакета](../README.md).

## Главы

| Глава | О чём |
|---|---|
| [00. Начало работы](00-getting-started.md) | запуск `melos run guard`, один файл и один тест, как читать нарушение (реальные сообщения), как воспроизвести нарушение, частые проблемы |
| [01. Устройство и расширение](01-rules-and-extending.md) | сканер и поля `PackageRule`, таблица правил по пакетам, allowlist зависимостей, имена пакетов, HOST-6, литералы интерфейса, правовые документы, доказательства матрицы, охват CI, как проверен сам сторож, рецепты со скелетами кода |

## Кому что читать

| Задача | Где |
|---|---|
| упал `melos run guard`, нужно понять почему | [00, «Как читать нарушение»](00-getting-started.md#как-читать-нарушение) и [«Частые проблемы»](00-getting-started.md#частые-проблемы) |
| понять, какие правила действуют для пакета | [01, «Таблица правил по пакетам»](01-rules-and-extending.md#таблица-правил-по-пакетам) |
| добавить пакет в monorepo | [01, «Как добавить правило для нового пакета»](01-rules-and-extending.md#как-добавить-правило-для-нового-пакета) |
| разрешить строку в интерфейсе | [01, «Как разрешить литерал интерфейса»](01-rules-and-extending.md#как-разрешить-литерал-интерфейса) |
| написать новую проверку | [01, «Как добавить новый тест-правило»](01-rules-and-extending.md#как-добавить-новый-тест-правило) |
| понять, почему CI запустил полный прогон | [00](00-getting-started.md#ci-посчитал-полный-прогон-хотя-изменён-один-пакет) и [01, «Охват CI»](01-rules-and-extending.md#охват-ci) |

## Смежные документы

- Границы пакетов и их обоснование: [`docs/architecture/layers-and-dependencies.md`](../../../../docs/architecture/layers-and-dependencies.md) (§42 — что сторож проверяет и чего нет, §43 — добавление пакета).
- Уровни проверок и CI: [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md) (§71, §74, §74.1).
- Пакеты, которые сторож защищает: [`codelab_agent_core`](../../codelab_agent_core/README.md), [`codelab_embedded`](../../codelab_embedded/README.md), [`codelab_setup`](../../codelab_setup/README.md), [`codelab_client_core`](../../codelab_client_core/README.md), [`codelab_client_io`](../../codelab_client_io/README.md), [`codelab_agent_mcp`](../../codelab_agent_mcp/README.md).
- Руководство ядра агента, где описаны `buildAgentCore` и хосты (HOST-6): [`codelab_agent_core/doc`](../../codelab_agent_core/doc/README.md).
