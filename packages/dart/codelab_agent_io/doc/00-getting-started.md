# Начало работы с кодом `codelab_agent_io`

Эта глава для разработчика, который впервые открыл пакет. Она отвечает на практические вопросы: как подготовить репозиторий, как прогнать тесты, как увидеть работу пакета без запуска агента и модели, куда смотреть при отладке и в какой файл идти с задачей. Устройство модулей объясняют следующие главы; сюда они ссылаются по месту.

Пакет не запускается сам: у него нет `bin/`. Его вызывают хосты (`codelab-agent`, встроенный агент) и приложения. Поэтому «запустить» пакет значит одно из трёх: прогнать его тесты, вызвать подкоманды `config`, `provider`, `mcp`, `secret` через бинарь агента или написать короткий тест с нужным вызовом.

## Подготовка репозитория

Шаги подготовки описаны в [запуске из исходников](../../../../docs/user/run-from-source.md#1-подготовка). Конспект для разработчика; команды выполняются из корня репозитория.

1. Установите [FVM](https://fvm.app). Версия Flutter SDK лежит в `.fvmrc`; все команды Dart идут через `fvm`.
2. Поставьте SDK и свяжите пакеты:

   ```bash
   fvm install
   fvm flutter pub get
   fvm dart run melos bootstrap
   ```

3. Чтобы собрать бинарь агента, создайте сгенерированный код. Его нет в git. Для тестов самого пакета шаг не понадобился: в проверенном рабочем дереве они прошли сразу после `bootstrap`.

   ```bash
   fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"
   ```

## Тесты пакета

Пакет — чистый Dart с `dart:io`. Тесты идут на реальных файлах во временных каталогах и на реальных процессах `/bin/sh`.

```bash
cd packages/dart/codelab_agent_io
fvm dart test                                  # весь пакет
fvm dart test test/config/config_loader_test.dart
fvm dart test test/secrets -n "permissions"    # по части названия теста
```

Пример прогона на момент написания (macOS): 1310 тестов, около 25 секунд. Число зависит от версии кода. Конец вывода:

```text
00:25 +1310: All tests passed!
```

Тест не читает настоящий `~/.codelab` и не зависит от окружения разработчика: `CODELAB_HOME` и словарь окружения передаются явно. Подробности — в [главе 12](12-testing.md).

## Подкоманды без модели

Самый быстрый способ увидеть работу пакета — подкоманды бинаря агента. Им не нужны ни провайдер, ни сеть. Соберите бинарь один раз и работайте в изолированном каталоге состояния:

```bash
fvm dart compile exe apps/codelab_agent/bin/codelab_agent.dart -o /tmp/codelab-agent-demo
export CODELAB_HOME=/tmp/codelab-demo/home        # изолированный CODELAB_HOME
mkdir -p /tmp/codelab-demo/home /tmp/codelab-demo/proj
cd /tmp/codelab-demo/proj && git init -q .
```

Запускайте с чистым окружением, чтобы ключи провайдеров и переменные `CODELAB_SECRET_*` вашей оболочки не попали в вывод:

```bash
env -i PATH=/usr/bin:/bin HOME=/tmp/codelab-demo/fakehome CODELAB_HOME=$CODELAB_HOME /tmp/codelab-agent-demo config check --cwd .
```

Дальше в примерах команда сокращена до `codelab-agent`, а пути в выводе заменены на `~/demo/home` и `~/demo/proj`. Вывод получен реальным запуском бинаря, собранного из этого дерева.

Пустой каталог: конфигурации нет, и `check` называет первую проблему.

```text
$ codelab-agent config check --cwd .
Sources: defaults
defaults: agent.default_model: no model is configured; add a provider with at least one model
Config: invalid (issues: 1)
```

Где лежат файлы слоёв (`path` ничего не создаёт):

```text
$ codelab-agent config path --cwd .
user: ~/demo/home/config.yaml (missing)
project: ~/demo/proj/.codelab/config.yaml (missing)
local: ~/demo/proj/.codelab/config.local.yaml (missing)
```

Добавим провайдера со ссылкой на секрет и проверим:

```text
$ codelab-agent provider add gw --kind openai-compatible --base-url https://llm.example.com/v1 \
    --model m1 --context-window 32768 --api-key-secret codelab/gw --default
Updated providers.gw in ~/demo/home/config.yaml

$ codelab-agent config check --cwd .
Sources: defaults, ~/demo/home/config.yaml
note: secrets backend: env (OS keychain backends are not available in this version; set secrets.backend: file or CODELAB_SECRET_* variables)
warning: ~/demo/home/config.yaml:5:5: providers.gw.api_key_secret: secret codelab/gw is not set; set CODELAB_SECRET_CODELAB_GW or add 'secrets.backend: file' and run: codelab secret set codelab/gw
Default model: gw/m1 (config)
Config: valid
```

`provider add` отказывается сохранять ключ, пока хранилище только читает. Пример на бэкенде `env`:

```text
$ printf 'sk-test-123\n' | codelab-agent provider add gw ... --api-key-stdin
secret store env is read-only. Add 'secrets.backend: file' to ~/demo/home/config.yaml to store secrets in ~/demo/home/secrets.yaml (plaintext, 0600), or set CODELAB_SECRET_CODELAB_GW in the environment
```

Полный набор подкоманд и их тексты — в [главе 9](09-subcommands.md); формат файлов и коды — в [главах 3–5](03-config-loading.md).

## Вызов из кода: загрузчик и писатель

Чтобы понять, что делает пакет, не нужен хост. Короткий тест собирает конфигурацию из временных каталогов и правит файл. Он проверен запуском; поместите его в `test/scratch_test.dart` пакета и не коммитьте.

```dart
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

void main() {
  test('loader and writer', () async {
    final root = Directory.systemTemp.createTempSync('io_example_');
    addTearDown(() => root.deleteSync(recursive: true));
    final base = root.resolveSymbolicLinksSync();
    final home = '$base/home';
    final cwd = '$base/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    File('$home/config.yaml').writeAsStringSync('''
# мой конфиг
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {context_window: 32768}
agent:
  default_model: p/m
''');
    final environment = {'CODELAB_HOME': home};

    final loaded = ConfigLoader().load(cwd: cwd, environment: environment);
    print('issues: ${loaded.issues.length}, model: ${loaded.config!.defaultModel}');

    final writer = ConfigWriter(
      codelabHome: home,
      environment: environment,
      loader: ConfigLoader(),
      logger: RecordingLogger(clock: FakeClock()),
      processRunner: const IoSecretProcessRunner(),
      clock: const SystemClock(),
      random: Random.secure(),
      cwd: cwd,
    );
    final snapshot = await writer.read(const ConfigTarget.user());
    await writer.apply(snapshot, [const SetValue('budget.max_steps', 8)]);
    print(File('$home/config.yaml').readAsStringSync());
  });
}
```

Вывод:

```text
issues: 0, model: ModelRef(p/m)
# мой конфиг
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {context_window: 32768}
agent:
  default_model: p/m
budget:
  max_steps: 8
```

Комментарий и порядок ключей остались: писатель правит документ, а не сериализует дерево заново ([глава 4](04-config-writing-and-reload.md)). Повторный `apply` со старым снимком даёт `ConfigConflictException`.

## Отладка

Пакет не пишет журнал сам: логгер приходит от хоста. Что искать, когда нужен подробный вывод:

| Что нужно увидеть | Как |
|---|---|
| предупреждения загрузки конфигурации | `codelab-agent config check` печатает их строками `warning:`; `serve` пишет те же события через `logConfigWarnings` |
| подробный журнал хоста | `codelab-agent serve --stdio --log-level debug --log-file <файл>` ([эксплуатация агента](../../../../apps/codelab_agent/doc/operations.md)) |
| события наблюдателя конфигурации | `config.watch.debounce` (debug), `config.watch.fallback` (info), `config.watch.failed` (warning) |
| выбор бэкенда секретов | событие `secrets.backend.selected` (info) |
| ремонт журнала сессии | события `session.quarantined` и `session.leaf.healed` (warning) |
| поиск секрета | флаг `--debug-secrets` у `serve`: пишет `secrets.lookup` без значения |

В тестах те же записи отдаёт `RecordingLogger` из `package:codelab_agent_core/testing.dart` ([глава 12](12-testing.md)). Полная таблица событий пакета — в [главе 13](13-troubleshooting.md#события-журнала-пакета).

## Что изменить — куда смотреть

| Задача | Файл | Глава |
|---|---|---|
| новая переменная окружения для ключа конфигурации | `lib/src/config/environment_layer.dart` | [3](03-config-loading.md), [11](11-extending.md) |
| изменить порядок или чтение слоёв, лимиты файла | `lib/src/config/config_loader.dart` | [3](03-config-loading.md) |
| запретить ещё одну конструкцию YAML | `lib/src/config/yaml_reader.dart` | [3](03-config-loading.md) |
| правка файла конфигурации, блокировка, атомарная замена | `lib/src/config/config_writer.dart`, `config_write_lock.dart` | [4](04-config-writing-and-reload.md) |
| перезагрузка на лету, наблюдение за файлами | `lib/src/config/config_watcher.dart`, `file_config_source.dart` | [4](04-config-writing-and-reload.md) |
| какие файлы защищает политика разрешений | `lib/src/config/agent_config_paths.dart` | [4](04-config-writing-and-reload.md) |
| формат или права файла секретов | `lib/src/secrets/file_secret_store.dart` | [5](05-secrets.md) |
| выбор бэкенда секретов | `lib/src/secrets/open_secret_store.dart`, `secrets_backend_problem.dart` | [5](05-secrets.md) |
| перенос литеральных секретов | `lib/src/secrets/secret_migrator.dart` | [5](05-secrets.md) |
| раскладка журнала сессий на диске, `fsync`, ремонт | `lib/src/session/jsonl_session_store.dart` | [6](06-sessions-and-state.md) |
| память последней модели | `lib/src/state/last_model_file.dart` | [6](06-sessions-and-state.md) |
| `AGENTS.md`, шаблоны команд, агенты, навыки | `lib/src/project/project_files_loader.dart` | [7](07-project-files.md) |
| запуск stdio-сервера MCP | `lib/src/mcp/stdio_process_transport.dart` | [8](08-mcp-stdio.md) |
| файлы и процессы инструментов | `lib/src/env/local_execution_env.dart` | [2](02-environment-and-processes.md) |
| тексты и коды выхода подкоманд | `lib/src/cli/*.dart` | [9](09-subcommands.md) |
| сценарий модели для тестов | `lib/src/scripted/`, `lib/testing.dart` | [10](10-scripted-model.md) |

## Перед правкой кода

1. Прочитайте [`AGENTS.md` пакета](../AGENTS.md) и [`AGENTS.md` ядра](../../codelab_agent_core/AGENTS.md): границы пакетов, TDD, комментарии на русском.
2. Найдите спецификацию темы в [`openspec/specs/`](../../../../openspec/specs/) ([список в README глав](README.md#спецификации-и-нормы)). Код соответствует спецификации, а не наоборот.
3. Напишите красный тест, затем код. Сначала запускайте тесты пакета, потом проверки затронутой границы: `melos run guard` (импорты и allowlist), `conformance:embedded` и `test:e2e:cli:embedded`, если менялся путь встроенного агента ([`AGENTS.md` репозитория, §21](../../../../AGENTS.md)).
