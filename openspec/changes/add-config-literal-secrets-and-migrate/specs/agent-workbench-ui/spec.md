## ADDED Requirements

### Requirement: Перенос секретов встроенного агента
Если встроенный агент открыт с `EmbeddedAgent.secretsInConfig == true`, рабочее место CodeLab SHALL показывать над транскриптом предупреждение уровня `warning` (Fluent `InfoBar`, как баннер соединения) с текстом `Secrets are stored in the agent config file.` и кнопкой `Migrate secrets` (решение пользователя 2026-11-04 R8-3; design.md change `add-config-literal-secrets-and-migrate`, D8). Подключение и работа агента при этом НЕ SHALL блокироваться. Закрытие предупреждения крестиком скрывает его до следующего подключения.

`Migrate secrets` SHALL открывать диалог с планом переноса — строками отчёта `SecretMigrator` для папки проекта (`--all`, `--dry-run`), без значений секретов:
- бэкенд только для чтения → текст `Secrets cannot be stored: the env backend is read-only. Add secrets.backend: file to <home>/config.yaml, or set CODELAB_SECRET_* variables.` и только кнопка `Close`;
- конфликт имени с хранилищем → текст конфликта и `Close`; замена существующего секрета в app НЕ SHALL предлагаться;
- все находки только в файле `CODELAB_CONFIG` → строки плана и только `Close`;
- иначе → `Migrate` и `Cancel`.

`Migrate` SHALL выполнять перенос тем же движком через порт приложения. Реализация — в composition root через `package:codelab_embedded/io.dart` с тем же `CODELAB_HOME`, `CODELAB_CONFIG` и окружением, что у открывателя встроенного агента; виджеты НЕ SHALL обращаться к файлам и хранилищу. Тексты `planFailed`/`applyFailed` и записи лога app SHALL строиться только из типизированного отчёта или имени типа исключения, НЕ из `error.toString()`. Подсказка для бэкенда `env` на Windows SHALL совпадать с веткой `secret set` (только переменные `CODELAB_SECRET_*`). После успеха диалог SHALL показывать `Secrets moved. Restart the embedded agent to use them.` и кнопку `Restart agent`, которая повторяет подключение тем же профилем; во время идущего хода она SHALL быть недоступна. Поздний результат плана или переноса после закрытия диалога или новой попытки SHALL отбрасываться.

#### Scenario: Предупреждение и перенос
- **WHEN** встроенный агент открыт с литеральным `api_key` в `<home>/config.yaml` и `secrets.backend: file`, пользователь нажимает `Migrate secrets`, затем `Migrate`
- **THEN** диалог показал строку плана для `providers.<id>.api_key` без значения; после переноса файл содержит `api_key_secret`, а `Restart agent` переподключает встроенного агента, после чего предупреждения нет

#### Scenario: Бэкенд env
- **WHEN** то же, но `secrets.backend` не задан
- **THEN** диалог показывает текст о бэкенде `env` и только `Close`; файл не изменён

#### Scenario: Поздний результат
- **WHEN** пользователь закрывает диалог, пока план ещё строится
- **THEN** результат плана не меняет состояние Cubit и не открывает диалог снова

#### Scenario: Окружение движка совпадает с агентом
- **WHEN** приложение запущено с временными `CODELAB_HOME` и `CODELAB_CONFIG`, и пользователь открывает план
- **THEN** план построен по тем же файлам, что открыватель встроенного агента (`app_scope.dart`), а не по `~/.codelab`

#### Scenario: Ошибка без текста исключения
- **WHEN** порт бросает исключение, чей `toString()` содержит `sk-test-leak-0123456789`
- **THEN** диалог и лог app показывают имя типа исключения и не содержат `sk-test-leak-0123456789`
