# Проверка агента фикстурами: `test-scenario`

`codelab test-scenario` нужна тем, кто разрабатывает или принимает агента. Обычному пользователю она не нужна. Команда проигрывает записанные сценарии обмена клиента и агента (фикстуры ACP) против выбранного агента и сравнивает ответы. Сеть и настоящий провайдер модели не нужны: встроенному агенту ответы модели подставляет сам сценарий. Оглавление руководства — [руководство пользователя](../user-guide.md).

## Запустить

Команде нужны файлы фикстур или каталоги с ними. Корпус фикстур лежит в репозитории, в `packages/dart/codelab_acp_testing/fixtures/acp`; запускайте команду из корня репозитория:

```bash
codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --filter 'acp/prompt-*' --junit build/scenario.xml
```

```text
PASS acp/prompt-anthropic-tool-call (0.2s)
PASS acp/prompt-cancel-during-terminal (0.2s)
PASS acp/prompt-cancel-mid-stream (0.4s)
PASS acp/prompt-cancel-mid-tool (0.2s)
PASS acp/prompt-failed-provider-auth (0.2s)
SKIP acp/prompt-max-turn-requests (0.0s)
    embedded: setup.config cannot be played by the embedded agent
…
21 passed, 0 failed, 6 skipped
```

На каждую фикстуру — строка `PASS`, `FAIL` или `SKIP`. `SKIP` значит, что этому агенту сценарий сыграть нельзя; причина стоит под строкой.

## Флаги

| Флаг | Что делает |
|---|---|
| `--agent <профиль>` (`-a`) | агент для проверки; по умолчанию встроенный. Внешний агент: `stdio:…`, `ws://…` или id профиля |
| `--filter <glob>` | играть только фикстуры, id которых подходит под шаблон (`*` — любые символы, `?` — один) |
| `--timeout <длительность>` | сколько ждать кадр агента; по умолчанию `30s` |
| `--junit <файл>` | записать отчёт JUnit XML |

`--junit` проверяется до запуска агента: если записать файл нельзя, команда завершается с кодом `64`. Отчёт пишется и при `FAIL`.

## Коды выхода

| Код | Когда |
|---|---|
| `0` | нет `FAIL` |
| `1` | есть `FAIL` или не сыграна ни одна фикстура (`codelab: no fixtures were played`) |
| `64` | ошибка использования: нет путей, путь не существует, битая фикстура, нельзя записать отчёт |

Для CI и для проверки своего агента команду запускают через Melos: `fvm dart run melos run conformance:embedded` — [эксплуатация](../operations.md#проверка-агента-фикстурами-test-scenario). Формат фикстур и способ добавить свою — в [документации `codelab_acp_testing`](../../../../packages/dart/codelab_acp_testing/README.md) и [главе для разработчика](../06-test-scenario.md).

## Смотрите также

- [Справочник флагов и команд](11-reference.md)
- [Если что-то пошло не так](12-troubleshooting.md)
