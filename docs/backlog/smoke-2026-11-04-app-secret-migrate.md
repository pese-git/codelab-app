# Backlog: находки smoke-теста переноса секретов в codelab-app 2026-11-04

Smoke-тест сборки из ветки `feature/add-config-literal-secrets-and-migrate-app` @ `03982f0` (итерация 4 change
`add-config-literal-secrets-and-migrate`, задача 8.11; PR [#237](https://github.com/pese-git/codelab-app/pull/237)).
Приложение собрано `fvm flutter build macos --debug` и запущено с изолированным `CODELAB_HOME`, тип подключения
«Embedded agent». В `config.yaml` лежал фиктивный литеральный ключ `sk-smokeFAKE…` (40 символов, сгенерирован для
прогона), `secrets.backend: file`. Модель `qwen/qwen3.5-9b` в LM Studio (`openai-compatible`), LM Studio ключ не
проверяет.

Прогнаны:
- подключение: над транскриптом `InfoBar` `Secrets are stored in the agent config file.` и кнопка `Migrate secrets`;
- `Migrate secrets`: план из одной строки `…/home/config.yaml: providers.lm.api_key -> api_key_secret: codelab/lm (new)`,
  без значения, кнопки `Migrate` и `Cancel`;
- `Migrate`: `Secrets moved. Restart the embedded agent to use them.`, кнопки `Restart agent` и `Close`;
  - `config.yaml`: `api_key` заменён на `api_key_secret: codelab/lm`, комментарий файла сохранён;
  - `secrets.yaml` создан с правами `0600`, ключ лежит в нём;
- `Restart agent`: переподключение, предупреждения нет;
- ход `Reply with the single word: pong`: ответ `pong`, ключ взят из хранилища;
- поиск значения ключа: нет в логе приложения, в `CODELAB_HOME` (кроме `secrets.yaml`) и в данных приложения в
  `~/Library/Application Support/com.example.codelabApp` и `~/Library/Containers/com.example.codelabApp`;
- лог: `secret_migration.planned {items: 1, can_apply: true}`, `secret_migration.applied {moved: 1, backend: file}` —
  без путей и значений; после записи конфиг подхватила живая перезагрузка (`config.watch.debounce`).

Поведение совпало со спецификациями `agent-workbench-ui` («Перенос секретов встроенного агента»), `embedded-agent` и
`agent-secrets`.

Не проверялись:
- бэкенд `env`, конфликт имени с хранилищем, находки только в `CODELAB_CONFIG`, частичный сбой — покрыты тестами
  задач 4.2–4.4;
- `Restart agent` во время хода и смена агента во время переноса (тесты Cubit и виджетов);
- закрытие `InfoBar` крестиком и его возврат при следующем подключении;
- проектный слой: в проекте `proj` не было `.codelab/config.yaml`.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| SMK-40 | P3 | obs | client | Маскер лога app прячет `secrets.backend: file` в `reason` события `secrets.backend.selected` | нет | — |
| SMK-41 | P3 | ux | desktop | Строка плана переноса начинается с полного абсолютного пути к конфигу | нет | — |

## Карточки

### SMK-40. Маскер лога прячет `secrets.backend: file` в `reason` (P3)

**Где:** `packages/dart/codelab_client_acp/lib/src/domain/secret_redaction.dart` (`_assignmentSecretPattern`: имя со
словом `secret` перед `:`/`=` маскирует значение после него); событие — `packages/dart/codelab_agent_io/lib/src/secrets/open_secret_store.dart`
(`reason = 'configured: secrets.backend: file'`).

**Шаги:** `secrets.backend: file` в `$CODELAB_HOME/config.yaml` → codelab-app, подключение к встроенному агенту → лог.

**Факт:** `secrets.backend.selected {"backend":"file", …, "reason":"configured: secrets.backend: <redacted>"}`.

**Ожидание:** `reason` остаётся читаемым (`configured: secrets.backend: file`): имя бэкенда — не секрет, и оно же
открыто стоит в поле `backend` того же события. Варианты: сузить шаблон присваивания (не маскировать известные несекретные
ключи вроде `secrets.backend`) или писать в `reason` без `key: value` (`configured`).

**Риск:** нет. Маскирование избыточно, а не недостаточно; мешает диагностике выбора бэкенда.

### SMK-41. Строка плана переноса начинается с полного абсолютного пути (P3)

**Где:** `packages/dart/codelab_agent_io/lib/src/secrets/secret_migrator.dart` (`describe()` пунктов плана — путь файла
целиком), диалог `apps/codelab_desktop/lib/features/workbench/presentation/widgets/secret_migration_banner.dart`.

**Шаги:** `CODELAB_HOME` с длинным путём (например, во временном каталоге) → `Migrate secrets`.

**Факт:** строка плана занимает три строки диалога, из них две — путь до `home/config.yaml`; ключ и имя секрета —
в конце.

**Ожидание:** путь короче: `~` вместо домашнего каталога, `$CODELAB_HOME/config.yaml` или имя слоя (`user`, `project`,
`local`) с полным путём в подсказке. Правка затрагивает и вывод `codelab secret migrate`: строки общие (D7), поэтому
менять их нужно в обоих бинарях сразу.

**Риск:** нет.
