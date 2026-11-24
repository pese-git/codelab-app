# Начало работы с пакетом

Эта глава для разработчика, который впервые открыл `codelab_setup`. Она отвечает на практические вопросы: как подготовить репозиторий, как запустить тесты, как проверить код без настоящего провайдера модели и в какой файл идти с задачей. Устройство пакета объясняют остальные главы; сюда они ссылаются по месту.

## Подготовка репозитория

Пакет — чистый Dart. Для его тестов не нужны ни Flutter, ни сгенерированный код. Достаточно поставить SDK и связать пакеты; команды выполняются из корня репозитория.

```bash
fvm install
fvm flutter pub get
fvm dart run melos bootstrap
```

Подробные шаги и генерацию кода для запуска бинарей описывает [запуск из исходников](../../../../docs/user/run-from-source.md#1-подготовка). Для `codelab_setup` генерация нужна, только если вы запускаете `codelab` или приложение, которые его используют.

## Запуск тестов

Тесты лежат в `test/` и идут на Dart VM.

```bash
cd packages/dart/codelab_setup
fvm dart test
```

Полный прогон занимает около 10 секунд. Последний запуск на текущей ветке: 608 тестов, все прошли. Можно запустить один файл или одну группу:

```bash
fvm dart test test/provider_setup_flow_test.dart
fvm dart test test/mcp_server_commit_test.dart --name "откат"
```

Тесты не ходят в сеть, не читают `~/.codelab` и не трогают хранилище секретов ОС. Что именно они используют вместо этого — в [главе 07](07-testing.md).

Статический анализ пакета:

```bash
fvm dart analyze
```

Две проверки границ запускаются из корня репозитория и относятся к этому пакету напрямую:

```bash
fvm dart run melos run guard
fvm dart run melos run web-compile
```

- `guard` — сторож импортов и зависимостей (`packages/dart/codelab_architecture_tests`). Он падает, если основной барель импортирует `dart:io`, `package:codelab_agent_io/` или `package:http/io_client.dart`, а также если в `pubspec.yaml` появилась лишняя зависимость.
- `web-compile` собирает `test/web_smoke/main.dart` в JS и Wasm. Он доказывает, что основной барель остаётся web-безопасным.

## Как проверить код без настоящего провайдера

Пакет не запускает агента и не говорит с моделью. Его части принимают порты: хранилище конфига, ключи, проверку `/models`. Поэтому проверять их можно тремя способами.

1. **Фейки портов.** Каталог `test/support/` содержит готовые `FakeProviderCheck`, `FakeProviderKeys`, `FakeConfigStore` и фабрики снимков `snapshotOf`, `mcpSnapshot`. Мастер провайдера с ними проходит весь путь без файлов и сети (пример — ниже).
2. **Настоящие файлы во временном каталоге.** `RealHome` из `test/support/real_home.dart` создаёт временный `CODELAB_HOME` и настоящий `FileAgentConfigStore`. Снимок тогда строит загрузчик ядра, а не тест.
3. **Loopback-сервер.** Проверка `/models` тестируется на `HttpServer`, привязанном к `127.0.0.1`, и на `MockClient` из `package:http/testing.dart` (`test/http_provider_check_test.dart`).

К настоящим провайдерам моделей не обращайтесь ни в тестах, ни в примерах.

### Пример: мастер провайдера на фейках

Следующий код — временный файл в каталоге пакета. Он гоняет мастер от пресета до записи и печатает состояния. Запуск: `fvm dart run <файл>` из `packages/dart/codelab_setup`; после проверки файл нужно удалить.

```dart
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart' show pumpEventQueue;

import 'test/support/provider_setup_fakes.dart';

Future<void> main() async {
  final journal = <String>[];
  final check = FakeProviderCheck();
  final keys = FakeProviderKeys();
  final config = FakeConfigStore(journal);
  final snap = snapshotOf();
  config.snapshotValue = snap;
  final flow = ProviderSetupFlow(
    check: check,
    committer: ProviderSetupCommitter(config: config, keys: keys),
    keys: keys,
    snapshot: snap,
    access: const EditableSettings(
      ConfigPaths(codelabHome: '/h', projectDir: '/work/project'),
    ),
    environment: const {},
    isLocalHost: (h) => h == 'localhost',
    logger: RecordingLogger(),
    entry: ProviderWizardEntry.app,
  );
  flow.states.listen((s) => print('state: $s'));

  Future<void> send(ProviderSetupEvent e) async {
    flow.dispatch(e);
    await pumpEventQueue();
  }

  await send(const PresetChosen('openrouter'));
  await send(const BaseUrlSubmitted('https://openrouter.ai/api/v1/'));
  await send(KeySubmitted(StoreSecret(SecretValue('sk-test-0000'))));
  check.respond(
    const CheckOk([RemoteModel('acme/model-1', contextWindow: 128000)]),
  );
  await pumpEventQueue();
  await send(const ModelChosen('acme/model-1'));
  await send(const ConfirmSave());
  await flow.dispose();
}
```

Вывод (запуск на текущей ветке; тот же сценарий идёт в `test/provider_setup_flow_test.dart`, группа «От пресета до записи»):

```text
state: EnteringBaseUrl(openrouter)
state: ChoosingKey(openrouter, ready: false)
state: ChoosingKey(openrouter, ready: true)
state: Checking(#1)
state: ChoosingModel(1, checked: true)
state: Reviewing(ProviderSetupPlan(openrouter, StoreSecret, acme/model-1, user))
state: Saving(ProviderSetupPlan(openrouter, StoreSecret, acme/model-1, user))
state: Done(ProviderSetupPlan(openrouter, KeepStoredSecret, acme/model-1, user))
```

Обратите внимание на три вещи:

- Шаг ключа сначала выдаёт `ready: false`. Автомат спрашивает порт `ProviderKeys.stored` и до ответа не принимает `KeySubmitted`.
- В `Done` ключ заменён на `KeepStoredSecret`: значение секрета автомат сбрасывает при завершении ([глава 03](03-provider-wizard.md)).
- Значение `sk-test-0000` нигде не напечатано: `SecretValue.toString()` даёт `***`.

## Подробный лог

Мастер и проверка `/models` пишут события в `Logger` ядра (`codelab_agent_core`). В тестах подставляйте `RecordingLogger` из `package:codelab_agent_core/testing.dart` и читайте `logger.records`. В настоящих клиентах логгер приходит из composition root. Для того же сценария записаны три события:

```text
info provider_wizard.started {mode: add, entry: app}
info provider_wizard.check_finished {operation_id: 1, preset: openrouter, endpoint: https://openrouter.ai, outcome: ok}
info provider_wizard.saved {provider_id: openrouter, key: secret, target: user, make_default: true, skipped_check: false}
```

Полный список событий — в [главе 09](09-troubleshooting.md#события-журнала). Общие правила журнала описывает [руководство ядра](../../codelab_agent_core/doc/10-observability-and-errors.md).

## Что изменить — куда смотреть

| Задача | Файл | Глава |
|---|---|---|
| выбрать, чьи настройки правит клиент | `lib/src/access/settings_access.dart` | [02](02-config-store.md) |
| поменять снимок конфига, источники ключей | `lib/src/config/agent_config_store.dart` | [02](02-config-store.md) |
| изменить запись файла, перевод исходов | `lib/src/io/file_agent_config_store.dart` | [02](02-config-store.md) |
| добавить шаг или событие мастера провайдера | `lib/src/provider/provider_setup_flow.dart`, `provider_setup_state.dart` | [03](03-provider-wizard.md) |
| изменить пресет провайдера | `lib/src/provider/provider_presets.dart` | [03](03-provider-wizard.md) |
| изменить правки, которые пишет мастер | `lib/src/provider/provider_setup_plan.dart` | [03](03-provider-wizard.md) |
| изменить проверку `/models` | `lib/src/provider/http_provider_check.dart` | [03](03-provider-wizard.md) |
| изменить порядок «секрет, затем конфиг» | `lib/src/provider/provider_setup_committer.dart` | [03](03-provider-wizard.md) |
| изменить удаление провайдера | `lib/src/provider/provider_remover.dart` | [03](03-provider-wizard.md) |
| изменить проверки формы MCP-сервера | `lib/src/mcp/mcp_server_draft.dart` | [04](04-mcp-servers.md) |
| изменить запись, удаление MCP-сервера, очистку секретов | `lib/src/mcp/mcp_server_committer.dart`, `mcp_server_remover.dart`, `mcp_secret_cleanup.dart` | [04](04-mcp-servers.md) |
| изменить страницу навыков и шаблонов | `lib/src/extensions/`, `lib/src/io/agent_extensions_reader.dart` | [05](05-agent-extensions.md) |
| изменить таблицу определений агентов | `lib/src/views/agent_definition_row_view.dart`, `lib/src/io/agent_definition_rows_at.dart` | [05](05-agent-extensions.md) |
| изменить строки провайдеров, настроек, режимов | `lib/src/views/` | [06](06-views.md) |
| понять, почему пакет импортирует именно это | `AGENTS.md` пакета, `rules.dart` сторожа | [01](01-overview.md) |

## Куда дальше

- Зачем пакету столько кода и из каких подсистем он состоит — [обзор](01-overview.md).
- Как добавить поле настройки, шаг мастера или вид — [рецепты](08-extending.md).
- Если что-то не работает — [частые проблемы](09-troubleshooting.md).
