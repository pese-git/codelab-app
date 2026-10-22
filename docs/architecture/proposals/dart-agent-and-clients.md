# Proposal: CodeLab Agent на Dart — встраиваемое ядро + ACP-клиенты

Status: Proposed

Date: 2026-10-21

Решение: [ADR-0001](../adr/0001-embed-dart-agent-core-behind-acp.md)

> Это **предложение и руководство к действию**, а не описание текущей архитектуры. Текущее
> устройство ACP Client описано в остальных документах `docs/architecture/`. После принятия
> ADR-0001 эти документы обновляются по чек-листу `docs/architecture/adr/README.md`.
>
> Пути вида `apps/...` и `packages/...` указаны относительно этого репозитория. Пути вида
> `codelab-agent/...` указывают на соседний репозиторий Python-агента и даются только как
> необязательные подсказки: всё, что нужно для работы, описано в этом документе словами.

Документ отвечает на три вопроса:

1. Можно ли переписать codelab-agent на Dart так, чтобы основным был интерфейс внутри процесса,
   а сетевой протокол ACP — надстройкой?
2. Как при этом устроить два клиента — codelab-app (Flutter) и codelab_cli (терминал)?
3. В каком порядке, какими изменениями и с какими проверками это делать?

**Короткий ответ: да.** Обе предпосылки уже есть: ACP Client написан на Dart, а пакет
`acp_protocol` сериализует модели ACP в обе стороны, поэтому агент может переиспользовать те же
модели.

**Архитектура ядра — собственная.** Контракты, инварианты, алгоритмы, форматы и способы проверки
ядра описаны в [agent-core-architecture.md](agent-core-architecture.md) (дальше — «документ
ядра», разделы §0–§17). Этот документ на него опирается и не повторяет его: здесь — пакеты,
клиенты, режимы работы и пошаговый план.

**Цели** — каталог целевых возможностей агента и обоих клиентов с приоритетами Must / Should /
Could / Won't и сценариями приёмки: [agent-parity-goals.md](agent-parity-goals.md) (дальше —
«матрица целей»). Наработки Python codelab-agent — второй этап: их берём, только если понадобятся
(§7б). Эталон поведения — спецификация ACP, golden ACP-фикстуры и интеграционные тесты клиентов
(§9.3).

## Связанные документы

* `AGENTS.md` — обязательные правила репозитория; новые пакеты подчиняются им без исключений.
* `docs/architecture/acp-boundary.md` — граница ACP в клиенте; остаётся в силе для обоих клиентов.
* `docs/architecture/layers-and-dependencies.md` — правила зависимостей; дополняется новыми пакетами (§4.1).
* `docs/architecture/permissions.md` — модель одобрения клиента **не меняется**: для `fs/*` и `terminal/*` одобрение по-прежнему за агентом, клиент ограничивает пути (`AGENTS.md` §10). Новый агент запрашивает одобрение всегда (§6.2).
* `docs/architecture/state-management.md` — `CodeLabShellCubit` разделяется (§4.4, этап 5); правила §80–§81 этого документа определяют, что уходит в `acp_client_kit`.
* `docs/architecture/platform-integration.md` — адаптеры fs и terminal переезжают в `acp_client_io` (этап 5).
* `docs/architecture/testing.md` — добавляются golden ACP-фикстуры и conformance агента (§9.3).
* [agent-core-architecture.md](agent-core-architecture.md) — архитектура ядра агента: единственный источник для его реализации.
* [agent-parity-goals.md](agent-parity-goals.md) — матрица целей, блок «не регрессировать», критерий вывода Python-агента.
* [delivery-roadmap.md](delivery-roadmap.md) — дорожная карта PoC → первый полезный результат → MVP → продукт 1.0: вехи, срез P0, выбор Should для 1.0.

## Содержание

Каждый раздел — отдельный файл в каталоге [`dart-agent-and-clients/`](dart-agent-and-clients/); план миграции (§9) и спецификации клиентов после MVP (§12) разбиты по подразделам. Номера разделов (§N) и якоря сохранены: ссылка «dart-agent-and-clients §9.11» означает файл этапа 6 из таблицы ниже.

| § | Раздел | Файл | Строк |
|---|---|---|---|
| 1 | [Исходные решения и требования](dart-agent-and-clients/01-decisions-and-requirements.md) | `dart-agent-and-clients/01-decisions-and-requirements.md` | 42 |
| 2 | [Факты о текущей системе](dart-agent-and-clients/02-current-system.md) | `dart-agent-and-clients/02-current-system.md` | 33 |
| 3 | [Рассмотренные варианты](dart-agent-and-clients/03-options-considered.md) | `dart-agent-and-clients/03-options-considered.md` | 22 |
| 4 | [Целевая архитектура](dart-agent-and-clients/04-target-architecture.md) | `dart-agent-and-clients/04-target-architecture.md` | 277 |
| 5 | [Контракты ядра](dart-agent-and-clients/05-core-contracts.md) | `dart-agent-and-clients/05-core-contracts.md` | 51 |
| 6 | [Режимы работы и потоки](dart-agent-and-clients/06-modes-and-flows.md) | `dart-agent-and-clients/06-modes-and-flows.md` | 91 |
| 7 | [Источники решений](dart-agent-and-clients/07-decision-sources.md) | `dart-agent-and-clients/07-decision-sources.md` | 79 |
| 8 | [Сквозные аспекты](dart-agent-and-clients/08-cross-cutting.md) | `dart-agent-and-clients/08-cross-cutting.md` | 21 |
| 9 | [План миграции](dart-agent-and-clients/09-00-migration-plan.md) | `dart-agent-and-clients/09-00-migration-plan.md` | 199 |
| 9.5 | [Этап 0 — Фундамент](dart-agent-and-clients/09-05-stage-0-foundation.md) | `dart-agent-and-clients/09-05-stage-0-foundation.md` | 372 |
| 9.6 | [Этап 1 — LLM](dart-agent-and-clients/09-06-stage-1-llm.md) | `dart-agent-and-clients/09-06-stage-1-llm.md` | 109 |
| 9.7 | [Этап 2 — Цикл, инструменты, разрешения](dart-agent-and-clients/09-07-stage-2-loop-tools-permissions.md) | `dart-agent-and-clients/09-07-stage-2-loop-tools-permissions.md` | 86 |
| 9.8 | [Этап 3 — Сессии и сжатие](dart-agent-and-clients/09-08-stage-3-sessions.md) | `dart-agent-and-clients/09-08-stage-3-sessions.md` | 89 |
| 9.9 | [Этап 4 — ACP-адаптер и codelab-agent](dart-agent-and-clients/09-09-stage-4-acp-adapter.md) | `dart-agent-and-clients/09-09-stage-4-acp-adapter.md` | 216 |
| 9.10 | [Этап 5 — Общий клиентский слой](dart-agent-and-clients/09-10-stage-5-client-kit.md) | `dart-agent-and-clients/09-10-stage-5-client-kit.md` | 467 |
| 9.11 | [Этап 6 — codelab_cli MVP](dart-agent-and-clients/09-11-stage-6-cli-mvp.md) | `dart-agent-and-clients/09-11-stage-6-cli-mvp.md` | 421 |
| 9.12 | [Этап 7 — Встроенный режим в обоих клиентах](dart-agent-and-clients/09-12-stage-7-embedded.md) | `dart-agent-and-clients/09-12-stage-7-embedded.md` | 319 |
| 9.13 | [Этап 8 — MCP, конфигурация, AGENTS.md](dart-agent-and-clients/09-13-stage-8-mcp-config.md) | `dart-agent-and-clients/09-13-stage-8-mcp-config.md` | 150 |
| 9.14 | [Этап 9 — Цели Must и переключение по умолчанию](dart-agent-and-clients/09-14-stage-9-switch-default.md) | `dart-agent-and-clients/09-14-stage-9-switch-default.md` | 145 |
| 9.15 | [Этап 10 — Мобильные и web](dart-agent-and-clients/09-15-stage-10-mobile-web.md) | `dart-agent-and-clients/09-15-stage-10-mobile-web.md` | 52 |
| 10 | [Риски](dart-agent-and-clients/10-risks.md) | `dart-agent-and-clients/10-risks.md` | 31 |
| 11 | [Допущения и открытые вопросы](dart-agent-and-clients/11-assumptions-and-open-questions.md) | `dart-agent-and-clients/11-assumptions-and-open-questions.md` | 63 |
| 12 | [Отображение и настройка в клиентах: спецификации после MVP](dart-agent-and-clients/12-0-clients-post-mvp.md) | `dart-agent-and-clients/12-0-clients-post-mvp.md` | 35 |
| 12.1 | [Общая модель отображения в `acp_client_kit`](dart-agent-and-clients/12-1-view-model.md) | `dart-agent-and-clients/12-1-view-model.md` | 776 |
| 12.2 | [CLI: отображение и ввод](dart-agent-and-clients/12-2-cli-display-and-input.md) | `dart-agent-and-clients/12-2-cli-display-and-input.md` | 848 |
| 12.3 | [Десктоп-приложение: отображение](dart-agent-and-clients/12-3-desktop-display.md) | `dart-agent-and-clients/12-3-desktop-display.md` | 864 |
| 12.4 | [Первый запуск и настройки](dart-agent-and-clients/12-4-first-run-and-settings.md) | `dart-agent-and-clients/12-4-first-run-and-settings.md` | 1109 |
| 12.5 | [Headless-формат stream-json](dart-agent-and-clients/12-5-stream-json.md) | `dart-agent-and-clients/12-5-stream-json.md` | 579 |
| 12.6 | [Удобства CLI и десктопа](dart-agent-and-clients/12-6-cli-desktop-extras.md) | `dart-agent-and-clients/12-6-cli-desktop-extras.md` | 1609 |
| 12.7 | [Выпуск и распространение](dart-agent-and-clients/12-7-release-and-distribution.md) | `dart-agent-and-clients/12-7-release-and-distribution.md` | 403 |

---

Связанный черновик ADR: [ADR-0001](../adr/0001-embed-dart-agent-core-behind-acp.md).
