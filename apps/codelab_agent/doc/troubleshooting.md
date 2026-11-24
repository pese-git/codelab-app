# `codelab-agent`: частые проблемы разработчика

Формат: симптом, причина, что сделать. Проблемы эксплуатации (порты, права на файлы, значения кодов выхода для оператора) — в [эксплуатации](operations.md); здесь — что мешает при разработке и тестах. Тексты ошибок и события лога — из кода или из реального запуска.

## Сборка и запуск из исходников

| Симптом | Причина | Что сделать |
|---|---|---|
| `fvm dart run` или `dart test` падают ошибками компиляции в `codelab_acp_protocol`, `codelab_agent_acp` (например, `The getter 'meta' isn't defined`) | не сгенерирован код (`*.freezed.dart` в git не хранится) | выполнить генерацию из [запуска из исходников](../../../docs/user/run-from-source.md#1-подготовка); дождаться конца, не запуская тесты во время генерации |
| `fvm dart run` вне репозитория берёт глобальный SDK и падает | `fvm` ищет `.fvmrc` вверх от текущей папки | запускать из корня репозитория или положить копию `.fvmrc` в рабочую папку |
| `codelab-agent serve --stdio` ничего не печатает и не завершается | так и задумано: агент читает кадры ACP из stdin, лог идёт в stderr; на EOF он завершается кодом `0` | подайте `initialize` (см. пример в [эксплуатации](operations.md#serve---stdio)) или закройте stdin: `Ctrl+D` |
| `codelab-agent serve --ws` завершился кодом `64`: `--ws needs a Bearer token in CODELAB_AGENT_TOKEN; the server does not start without it` | токен пуст или переменная не передана процессу; проверка идёт после сборки ядра, поэтому в логе уже есть `host.config.loaded` и `host.plan` | задать `CODELAB_AGENT_TOKEN` (или переменную из `--token-env`); если запускаете через `env -u`, не сбрасывайте её |
| `--llm-script /…/x.json: No such file or directory` и код `64` | путь сценария относителен текущей папки процесса | передать абсолютный путь или запускать из каталога приложения (`test/llm_scripts/hello.json`) |
| `--provider and --llm-script are mutually exclusive` | флаги взаимоисключающие | оставить один |
| `--model needs <provider>/<model> without --provider` | без `--provider` модель называют как в конфигурации: `провайдер/модель` | `--model local/test` или добавить `--provider` |
| `serve.ws.bind_failed`, код `1` | порт занят или адрес недоступен | другой `--port` или `--port 0` (система выберет свободный, реальный — в `serve.ws.listening`) |
| в stderr `info config.watch.fallback {path: …/.codelab/config.yaml, reason: PathNotFoundException}` | наблюдатель за конфигурацией не нашёл каталог `.codelab` и перешёл на опрос файлов | это сообщение, а не ошибка: файлы проекта ещё не созданы |
| в stderr `secrets.backend.selected {backend: env, … reason: OS keychain backends are not available in this version; …}` | выбран бэкенд `env`, потому что `secrets.backend` не задан, а хранилища ОС в этой версии нет | норма; для файла секретов — `secrets.backend: file` |

## Тесты

| Симптом | Причина | Что сделать |
|---|---|---|
| первый процессный тест долго стоит | компилируется kernel бинаря в `apps/codelab_agent/.dart_tool/codelab_test_kernels/` | дождаться; дальше каждый тестовый изолят компилирует его заново, поэтому правка кода не использует устаревший файл |
| `StateError: stdout closed before the response 1; stderr: …` | бинарь завершился раньше ответа: видно по stderr в тексте ошибки | прочитать stderr из сообщения; чаще всего ошибка использования (код `64`) или невалидная конфигурация |
| `TimeoutException: stderr has no "…"` | ожидаемого события нет в stderr за 20 секунд | проверить уровень лога (`--log-level`): `debug`-события при `info` не пишутся |
| тест читает конфигурацию из своего каталога | `AgentHost.build` вызван с `cwd` по умолчанию, а в каталоге запуска есть `.codelab/` | брать `buildHost` из `test/support/build_host.dart`: он передаёт временный `cwd` |
| тест видит ключи разработчика | в процесс попало окружение разработчика | `AgentProcess.start` заменяет окружение целиком, кроме `PATH` и `HOME`; в тестах хоста передавайте свой `environment` в `parseServeArgs` |
| процессный тест под `flutter test` не находит `dart` | `Platform.resolvedExecutable` — не `dart` | `dartExecutable()` из `test/support/agent_process.dart`: ищет SDK Flutter, затем FVM-копию |
| после падения теста остался процесс бинаря | тест не закрыл stdin и не убил процесс | в `tearDown` вызывать `kill` или закрывать stdin; тест остановки по сигналу идёт в `stdio_process_test.dart` |
| `melos run test:e2e:cli:dart-agent` красный, а `fvm dart test` приложения зелёный | e2e гоняет `codelab` (через PTY) против бинаря; расхождение в справке, коде выхода или кадрах | запустить один файл: `CODELAB_E2E_AGENT=dart fvm dart test apps/codelab_cli/test/e2e/<файл>.dart --exclude-tags scripted-only` |

## Поведение

| Симптом | Причина | Что сделать |
|---|---|---|
| клиент ACP не может разобрать кадр: в потоке stdout есть строка, которая не JSON-RPC | в stdout попало лишнее: `print`, `stdout.write` или лог | убрать; лог — только через `Logger` (stderr и `--log-file`), `--log-file` на stdout отвергается кодом `64` |
| `codelab-agent: invalid arguments for secret` вместо причины | так задумано: ошибка разбора argv у `secret`, `provider`, `mcp`, `config set\|unset` не цитирует присланные слова, среди них может быть значение секрета | смотреть справку под сообщением; точную причину увидите, если убрать значение из команды |
| `serve.config.invalid` и код `64`, транспорт не открылся | конфигурация невалидна | `codelab-agent config check` на той же папке: покажет слои и проблемы ([эксплуатация](operations.md#конфигурация)) |
| правка `config.yaml` не доходит до работающего `serve` | со `--llm-script` источника конфигурации нет; либо `config.watch: false` | снять флаг сценария или `config.watch: false`; процессный тест — `config_reload_process_test.dart` |
| `--ws`: нет `/config`, MCP-серверов, файлов проекта | профиль сужен намеренно: клиент по сети может быть на другой машине | это не дефект; причины видны в `host.plan` (`off`) и `project_files.skipped`; таблица режимов — в [устройстве](internals.md#сборка-хоста-agenthost) |
| при остановке по `SIGTERM` код не `143` | на Windows `SIGTERM` не обрабатывается | на Windows завершайте по `Ctrl+C` (`130`) |
| второй `Ctrl+C` оборвал остановку сразу | так задумано: второй сигнал во время остановки вызывает `exit(code)` | дождаться штатной остановки (до 5 секунд) |
| файл лога не создаётся | он не создаётся по умолчанию | задать `--log-file`, `CODELAB_LOG_FILE` или `logging.file` |
| в stderr `warning log.file.write_failed` | запись в файл лога упала (диск, права); файл отключён до конца процесса | исправить причину и перезапустить; агент продолжает работу со stderr |
| `embeddedAgentVersion` встроенного агента и `agentVersion` бинаря разошлись | две отдельные константы: пакет не импортирует приложение | править обе; проверяет `test/embedded_agent_version_test.dart` в `codelab_embedded` и фикстура `initialize-capabilities` |

## Границы

| Симптом | Причина | Что сделать |
|---|---|---|
| `melos run guard` красный после нового импорта | в `lib/` или `bin/` появился `package:flutter/`, `package:fluent_ui/`, `package:codelab_client_acp/` или `package:codelab_ui/` | убрать импорт; сообщение сторожа называет файл и правило (`packages/dart/codelab_architecture_tests/test/support/rules.dart`) |
| `host_assembly_guard_test.dart` красный | в `lib/` или `bin/` появилось `ToolRegistry(`, `Agent(` или `AgentRuntime(` | собирать ядро только через `buildAgentCore` (HOST-6) |
| `pubspec_allowlist_test.dart` красный | в `dependencies` приложения новая зависимость | убрать; расширение allowlist — только через OpenSpec change |

## Смотрите также

- [Разработка](development.md);
- [устройство](internals.md);
- [тестирование](testing.md);
- [эксплуатация](operations.md);
- [частые проблемы ядра](../../../packages/dart/codelab_agent_core/doc/13-troubleshooting.md).
