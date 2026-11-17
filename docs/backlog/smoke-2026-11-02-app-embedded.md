# Backlog: находки smoke-теста codelab-app со встроенным агентом 2026-11-02

Smoke-тест сборки из ветки `feature/add-embedded-agent-mode-desktop` @ `fe0b69d` (итерация 4 change
`add-embedded-agent-mode`, этап 7; PR [#217](https://github.com/pese-git/codelab-app/pull/217)). Приложение
собрано `fvm flutter build macos --debug` и запущено с изолированным `CODELAB_HOME`. Модель `qwen/qwen3.5-9b`
в LM Studio (`openai-compatible`), значение ключа фиктивное (LM Studio ключ не проверяет).

Прогнаны:
- регрессия headless CLI на бинарях той же ветки — 12 сценариев, как в [smoke-2026-11-02-cli-embedded.md](smoke-2026-11-02-cli-embedded.md), без изменений;
- codelab-app, тип подключения «Embedded agent»:
  - диалог подключения;
  - Connect, список сессий агента;
  - ход;
  - одобрение Allow и отказ Reject;
  - два Reconnect подряд;
  - выход через Quit — код `0`;
  - отсутствующий `config.yaml` — баннер без префикса `EmbeddedAgentConfigException:`;
- поиск значения ключа в логе приложения и в `$CODELAB_HOME`.

Сценарии прошли по спецификациям `agent-workbench-ui` и `embedded-agent`, значение ключа никуда не попало.

Не проверялись:
- гонка повторного Connect во время долгого `open`: `open` встроенного агента занимает около 70 мс, поэтому второй Reconnect стартовал после первого. Гонку покрывают тесты задачи 4.7;
- таймаут закрытия 10 с, запуск из Finder (`secrets.backend: file`), MCP-серверы встроенного агента.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| SMK-28 | P3 | bug | protocol | Плановый Reconnect встроенного агента пишет `ERROR` и проводит соединение через `Failed` | нет | — |
| SMK-29 | P3 | ux | desktop | Подсказка `codelab config check` в баннере обрезается длинным путём | нет | — |
| SMK-30 | P3 | ux | client | После Reconnect у карточек инструментов пропадает решение пользователя | да | — |

## Карточки

### SMK-28. Плановый Reconnect пишет `ERROR` и проходит через `Failed` (P3)

**Где:**
- `packages/dart/codelab_acp_transports/lib/src/in_process_acp_transport.dart` (`In-process client transport peer closed the connection`);
- переход `ClientConnectionReady → ClientConnectionFailed` в `codelab_client_acp`.

**Шаги:** codelab-app, Embedded agent, Connected → палитра команд → Reconnect.

**Факт:** перед новым поколением соединения в журнал приложения пишется:
- `ERROR: In-process client transport peer closed the connection` (`code: disconnected`);
- `WARNING: connection_state_changed from=ClientConnectionReady to=ClientConnectionFailed`.

Причина: резолвер освобождает прежнего агента, его конец `InProcessAcpLink` закрывается, и клиентский транспорт
видит это как обрыв. В UI баннер `failed` не появляется: состояние сразу уходит в `Disconnected` → `Ready`
нового поколения.

**Ожидание:** закрытие, которое начал сам клиент (Reconnect, Connect, закрытие scope), не логируется как ошибка
транспорта и не проводит соединение через `Failed`. Уровень `info`, причина — «replaced by reconnect». Нужно
проверить, ведёт ли себя так же stdio при Reconnect: если да, правка общая для клиентского слоя.

**Риск:** нет для данных. Ложные `ERROR` мешают разбирать журналы (`AGENTS.md` §16), а `Failed` в автомате
соединения может задеть подписчиков, которые реагируют на этот переход.

### SMK-29. Подсказка в баннере ошибки конфига обрезается (P3)

**Где:** карточка подключения на главном экране codelab-app (`apps/codelab_desktop`, презентация `ConnectionFailed`);
текст — `packages/dart/codelab_embedded/lib/src/embedded_agent_config.dart:103`.

**Шаги:** убрать `$CODELAB_HOME/config.yaml` → Embedded agent → Connect.

**Факт:** баннер показывает `defaults: agent.default_model: required` и начало подсказки
`Configure the embedded agent in /private/tmp/…/e59a7315-fa2e-48b0-8…`. Текст обрезается многоточием, поэтому не
видно главного: `check it with: codelab config check`.

**Ожидание:** текст ошибки в карточке переносится, либо карточка раскрывается полностью. Как вариант, путь стоит
сократить (`~` вместо домашнего каталога) или поставить подсказку `codelab config check` перед путём.

**Риск:** нет. Пользователь не видит, как починить конфиг; в журнале приложения полный текст есть.

### SMK-30. После Reconnect у карточек инструментов пропадает решение пользователя (P3)

**Где:** перезагрузка сессии после Reconnect (`ClientWorkspace._reattachSessions` → `session/load`), проекция карточек
tool call в `codelab_client_core`, журнал сессии встроенного агента.

**Шаги:** в сессии одобрить одну запись (Allow) и отклонить другую (Reject) → Reconnect.

**Факт:**
- до Reconnect у карточек есть метки решения: `Allow once` + `Done`, `Reject` + `Failed`;
- после перезагрузки сессии остаются только `Done` и `Failed`, решение пользователя не показано.

**Ожидание:** решите, должна ли перезагруженная сессия показывать, кто разрешил или запретил вызов. Если должна,
`session/load` (или расширение `_meta`) должен нести исход одобрения, а журнал — хранить его. Это поведение
продукта и ACP-проекции, поэтому нужен OpenSpec change. Нужно проверить, так ли ведёт себя внешний `codelab-agent`.

**Риск:** нет для безопасности: решение принято и исполнено. Теряется аудит: после перезапуска не видно, что
запись прошла с явного разрешения пользователя.
