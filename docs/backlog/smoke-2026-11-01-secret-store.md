# Backlog: находки smoke-теста хранилища секретов 2026-11-01

Ручной smoke-тест сборки `develop` @ `8c8e15f` (после итерации 5 change `add-agent-secret-store`, этап 8.9;
архив change — PR [#206](https://github.com/pese-git/codelab-app/pull/206)). Агент — `codelab-agent serve --stdio`,
модель `qwen/qwen3.5-9b` в LM Studio (`openai-compatible`). `CODELAB_HOME` и `HOME` изолированы во временном
каталоге, значение ключа фиктивное (LM Studio ключ не проверяет). Прогнаны: подкоманды `secret set|delete|list`
у `codelab-agent` и `codelab`, `config check` обоих бинарей, headless `codelab -p` с `--debug-secrets`, переменная
`CODELAB_SECRET_*`, отказ `secrets.yaml` с правами `0644`, `secrets.backend: keychain`, `${secret:…}` вне
`env`/`headers`, шаблон заголовка провайдера (значение проверено отдельным HTTP-сервером), поиск значения в логах
уровня `trace` и в `$CODELAB_HOME`.

Сценарии прошли по спецификации `agent-secrets`: `auto` выбирает `env`, `file` — `0600` и `.secrets-tmp` `0700`,
`Stored`/`Updated`, коды `64` для неверного имени и значения аргументом, `source: file|env` в `secrets.lookup`,
ошибка хода `auth` с подсказкой `codelab secret set`, `secrets.file.refused`, значение не попадает ни в вывод,
ни в логи. Не проверялись: скрытый ввод с терминала (проверен вручную в итерации 3), секреты в `env`/`headers`
живого MCP-сервера, режим `--ws`.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| SMK-20 | P3 | bug | agent | Ошибка в провайдере даёт ложную вторую ошибку «default_model is not in the model catalog» | нет | — |

## Карточки

### SMK-20. Ложная вторичная ошибка `agent.default_model` при отклонённом провайдере (P3)

**Где:** `packages/dart/codelab_agent_core/lib/src/config/resolve.dart` (проверка `agent.default_model`,
текст `is not in the model catalog; declare it in providers.<id>.models`).

**Шаги:** в `$CODELAB_HOME/config.yaml` провайдер `lms` с моделью `qwen/qwen3.5-9b` в `models`,
`agent.default_model: lms/qwen/qwen3.5-9b`, но `base_url: ${secret:codelab/lms}` → `codelab-agent config check`.

**Факт:** две ошибки, `Config: invalid (issues: 2)`:
- `providers.lms.base_url: secret references ${secret:…} are allowed only in env and headers values` — верно;
- `agent.default_model: lms/qwen/qwen3.5-9b is not in the model catalog; declare it in providers.lms.models` —
  модель объявлена; она выпала из каталога вместе с отклонённым провайдером.

**Ожидание:** если провайдер из `agent.default_model` объявлен, но отклонён своими ошибками, вторая ошибка не
выдаётся (или говорит, что провайдер `lms` невалиден, вместо совета объявить модель). Подсказка «declare it in
providers.lms.models» не должна вести пользователя к правке, которая уже сделана. То же, вероятно, касается любой
ошибки провайдера, а не только `${secret:…}`.

**Риск:** нет — конфиг невалиден в любом случае, поведение fail-closed. Лишняя ошибка с неверным советом
сбивает при разборе.
