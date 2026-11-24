# Тестирование

Глава объясняет, как тестируется `codelab_setup`: какие бывают тесты, какие приёмы и помощники в них применяются, какие границы проверяют сторож и web-сборка. Общие уровни тестов проекта описывает [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md); TDD для пакетов агентской стороны — раздел 2 [`AGENTS.md` ядра](../../codelab_agent_core/AGENTS.md). Здесь — то, что специфично для моста.

## Правила

- **Красный тест раньше кода.** Исключения те же, что у ядра: рефакторинг (сначала характеризационные тесты), UI, фейки вместо реальных провайдеров и хранилищ ОС.
- **Без сети, настоящего `~/.codelab` и хранилища ОС.** Данные во временных каталогах, ключи — фиктивные маркеры.
- **Маркер утечки.** Секрет в тестах — строка вида `sk-test-leak-0123456789`. Тест подаёт её на вход и проверяет, что её нет ни в `toString()`, ни в журнале, ни в состоянии, ни в исходах. Так устроены `provider_setup_flow_test`, `provider_setup_commit_test`, `mcp_server_commit_test`, `mcp_server_draft_test`, `setting_field_view_test`, `file_agent_config_store_test` и другие.
- **Синхронизация без таймеров.** Асинхронные шаги мастера ждут через `pumpEventQueue()` (`package:test/test.dart`), а ответы портов отдаёт тест. Реальных `Future.delayed` в тестах автомата нет.

## Три уровня

| Уровень | Что используется | Примеры файлов |
|---|---|---|
| Логика на фейках портов | `FakeProviderCheck`, `FakeProviderKeys`, `FakeConfigStore`, `snapshotOf`, `mcpSnapshot` | `provider_setup_flow_test.dart`, `provider_setup_commit_test.dart`, `mcp_server_commit_test.dart`, `provider_remove_test.dart` |
| Настоящие файлы | временный `CODELAB_HOME`, `FileAgentConfigStore`, `RealHome` | `io/file_agent_config_store_test.dart`, `provider_readiness_test.dart`, `views/setting_field_view_test.dart`, `io/read_agent_extensions_test.dart` |
| Сеть на loopback | `MockClient` из `package:http/testing.dart` и `HttpServer` на `127.0.0.1` | `http_provider_check_test.dart`, `io/io_provider_check_redirect_test.dart` |

Интеграции с настоящими провайдерами нет и быть не должно.

## Помощники `test/support/`

| Файл | Что даёт |
|---|---|
| `provider_setup_fakes.dart` | `FakeProviderCheck` (каждый вызов ждёт `respond(...)` теста; хранит `calls`), `FakeProviderKeys` (журнал `stored`/`write`/`delete`/`read`, `storedGate` и `storedAnswers` для гонок, `onWrite`, `throwOnDelete`), `FakeConfigStore` (`outcome`, `throwOnApply`, список `applied`), `snapshotOf({user, projectLocal, backend})` |
| `mcp_snapshots.dart` | `mcpSnapshot({user, project, projectLocal, untrustedProject, backend})`, `freshMcpSnapshot` (все три слоя прочитаны — как после записи), `httpServer(...)`, `stdioServer(...)` |
| `real_home.dart` | `RealHome.create(prefix)`: временный `home` и `project`, `writeConfig(text)`, `load([extraEnv])` — снимок через настоящий `FileAgentConfigStore`, `dispose()`; константа `gatewayProvider` |

`snapshotOf` строит снимок вручную через `AgentConfigSnapshot.fromLayers` с пустым `ConfigLoadResult`, поэтому проблем загрузчика в нём нет. Нужен настоящий итог загрузки (проблемы, `config`, предупреждения о доверии) — берите `RealHome`.

Фейки сознательно выставляют внутренности: журналы вызовов позволяют проверять **порядок** — «секрет раньше конфига», «`apply` раньше `delete`».

## Что где проверяется

| Область | Файлы тестов |
|---|---|
| доступ к настройкам | `settings_access_test.dart` |
| снимок и запись | `io/file_agent_config_store_test.dart` (585 строк), `agent_config_rejections_test.dart` |
| мастер провайдера | `provider_setup_flow_test.dart` (1731 строка), `provider_setup_error_code_test.dart`, `provider_setup_commit_test.dart` |
| готовность | `provider_setup_needed_test.dart`, `provider_readiness_test.dart` |
| проверка `/models` | `http_provider_check_test.dart` (663 строки), `io/io_provider_check_redirect_test.dart`, `io/provider_check_classifier_test.dart` |
| ключи и секреты | `io/provider_keys_test.dart`, `io/secret_deleter_test.dart` |
| удаление провайдера | `provider_remove_test.dart` |
| MCP | `mcp_server_draft_test.dart`, `mcp_draft_problem_code_test.dart`, `mcp_server_commit_test.dart`, `mcp_server_remove_test.dart`, `mcp_restart_test.dart` |
| расширения | `extensions/*`, `io/read_agent_extensions_test.dart`, `io/read_agent_extensions_consents_test.dart`, `io/extensions_host_paths_test.dart`, `io/agent_definition_rows_at_test.dart` |
| виды | `views/*` (провайдеры, MCP, настройки, правила правки, режимы, определения) |
| реэкспорт | `exports_test.dart`, `config_write_exports_test.dart`, `secret_exports_test.dart`, `secret_migrate_exports_test.dart`, `client_secret_access_exports_test.dart` |
| web-безопасность | `web_smoke_test.dart`, `web_smoke/main.dart` |

Реэкспортные тесты проверяют только, что символы подкоманд `config`, `provider`, `mcp`, `secret` доступны через один `io.dart` и компилируются. Логика подкоманд тестируется в `codelab_agent_io`.

## Приёмы

### Мастер: события и гонки

Тест мастера шлёт событие и ждёт очередь:

```dart
Future<void> send(ProviderSetupEvent event) async {
  flow.dispatch(event);
  await pumpEventQueue();
}
```

Подписка `flow.states.listen(seen.add)` собирает состояния, а функция `kinds()` склеивает повторы, чтобы тест видел порядок состояний, а не число промежуточных снимков. Проверку отвечает `check.respond(CheckOk([...]))`. Гонки проверяются явными управляющими объектами: `FakeProviderKeys.storedGate` задерживает ответ `stored`, поэтому «до ответа порта шаг не принимает `KeySubmitted`» проверяется без таймера.

Что проверять обязательно, когда меняете автомат:

- порядок состояний пути (`kinds()`);
- `error` и `errorCode` появляются вместе;
- поздний результат устаревшей попытки не меняет состояние (`check_discarded`);
- `holdsSecret` (`@visibleForTesting`) ложно после `Done`, `Cancel` и `dispose()`;
- значение ключа не попало в `logger.records` и `toString()`.

### Порядок записи

Для коммитеров проверяют журнал портов, а не только исход. В примере из этого руководства для сервера `docs` при конфликте записи журнал был: `stored`, `write`, `delete` — секрет создан, затем откатан. Исключения хранилища в `delete` не должны скрывать исход конфликта (`throwOnDelete`).

### Проверка `/models`

`http_provider_check_test.dart` использует `MockClient` для таблицы статусов и `HttpServer` на loopback для проверок, которым нужен настоящий сокет: таймаут и закрытие соединения; редирект там проверяется только на `MockClient`. `ioProviderCheck()` тестируется отдельно (`io_provider_check_redirect_test.dart`, `provider_check_classifier_test.dart`); тест редиректа поднимает второй сервер и проверяет, что он не получил ни одного запроса: ключ на адрес из `Location` не уходит. Отдельные тесты нужны, потому что `IOClient` создаёт только `ioProviderCheck()`.

### Снимки на настоящем загрузчике

`RealHome` нужен там, где поведение зависит от настоящего итога загрузки: «нет провайдера» (`providerSetupNeeded`), порядок слияния MCP-серверов, источники ключей, `--config`, недоверенный проект. Минимальный пример:

```dart
final home = RealHome.create('setup-test-');
addTearDown(home.dispose);
home.writeConfig(gatewayProvider);
final snapshot = await home.load();
// snapshot.layers, snapshot.loaded, snapshot.origins — от настоящего загрузчика
```

## Web-smoke

`test/web_smoke/main.dart` — точка входа, которую `melos run web-compile` собирает в JS и Wasm. Она строит основной барель без файлов и сети: доступ, провайдеры, мастер до обзора, строки `/settings`, MCP-черновик, вид расширений, коды ошибок. `test/web_smoke_test.dart` запускает **тот же код** на Dart VM и сверяет отчёт.

Ожидание из теста (сокращено):

```dart
expect(report.access, 'EditableSettings');
expect(report.wizard, [
  'SetValue(providers.openrouter.kind)',
  'SetValue(providers.openrouter.base_url)',
  'SetValue(providers.openrouter.models.m.context_window)',
  'SetValue(agent.default_model)',
]);
```

Если вы добавили публичное поведение основного барелья, добавьте проверку в web-smoke: так вы заодно докажете, что оно web-безопасно.

## Сторож и сборка

Из корня репозитория:

```bash
fvm dart run melos run guard
fvm dart run melos run web-compile
```

- `guard` проверяет границы импортов (`rules.dart`) и allowlist зависимостей. Описание — [README сторожа](../../codelab_architecture_tests/README.md).
- `web-compile` собирает `test/web_smoke/main.dart` пакета вместе со smoke-входами ядра и `codelab_embedded`.

Перед pull request запускайте то, что относится к изменению (корневой `AGENTS.md` §21): для кода пакета — `fvm dart format`, `fvm dart analyze`, `fvm dart test`; при изменении `pubspec.yaml`, импортов между пакетами или правил сторожа — `guard`; при изменении основного барелья или его импортов — `web-compile`. Если изменён публичный API, прогоните ещё и тесты приложений, которые его используют (`apps/codelab_cli`, `apps/codelab_desktop`).

## Смотрите также

- Рецепты расширения с тестами — [глава 08](08-extending.md).
- Частые причины падения тестов — [глава 09](09-troubleshooting.md).
