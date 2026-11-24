# Рецепты расширения

Глава собирает пошаговые рецепты для типичных задач. Каждый рецепт называет файлы, порядок правок, тест и клиентов, которых правка затронет. Код в рецептах сверен с пакетом: части, которые нельзя было собрать отдельно, проверены временной правкой в `lib/` с запуском `fvm dart analyze lib` и теста (потом правка откачена). Где тело опущено, это помечено `// ...`.

Общее правило: сначала красный тест, потом код (TDD, [`AGENTS.md`](../AGENTS.md) пакета и [тестирование](07-testing.md)). Если правка меняет поведение продукта, публичное API или контракт, до кода нужен OpenSpec change (`AGENTS.md` корня §17); спецификация пакета — [`client-agent-setup`](../../../../openspec/specs/client-agent-setup/spec.md).

| Задача | Рецепт |
|---|---|
| показать новый ключ конфига в таблице настроек | [1](#1-новый-ключ-в-таблице-настроек) |
| добавить пресет провайдера | [2](#2-новый-пресет-провайдера) |
| добавить код ошибки шага мастера | [3](#3-новый-код-ошибки-шага-мастера) |
| добавить шаг мастера | [4](#4-новый-шаг-мастера) |
| добавить поле формы MCP-сервера | [5](#5-новое-поле-формы-mcp-сервера) |
| добавить проверку `/models` для нового вида провайдера | [6](#6-новый-вид-провайдера-в-проверке-models) |
| добавить вид отказа проверки | [7](#7-новый-вид-отказа-проверки) |
| добавить поле с путём в вид расширений | [8](#8-новое-поле-с-путём-в-виде-расширений) |
| открыть клиентам новый символ ядра или IO-пакета | [9](#9-новый-реэкспорт) |
| добавить новый вид (view) для страницы | [10](#10-новый-вид-view) |

## 1. Новый ключ в таблице настроек

Таблица `/settings` и страница «General» строятся по `SettingsRegistry` ядра. Строка для нового ключа появляется **без правок в мосте**, если ключ объявлен в реестре ядра с `scope: shared`. Порядок:

1. Объявите ключ в реестре ядра (рецепт «новая настройка» в [руководстве ядра](../../codelab_agent_core/doc/11-extending.md)).
2. Напишите тест в мосте, что строка видна и правится. Он идёт на настоящем загрузчике через `RealHome` (проверено запуском):

```dart
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/real_home.dart';

void main() {
  late RealHome home;
  setUp(() => home = RealHome.create('setting-row-'));
  tearDown(() => home.dispose());

  test('agent.effort виден в таблице настроек с источником user', () async {
    home.writeConfig('$gatewayProvider\nagent:\n  effort: high\n');
    final snapshot = await home.load();

    final row = settingFieldsOf(snapshot).singleWhere(
      (r) => r.key == 'agent.effort',
    );

    expect(row.displayValue, 'high');
    expect(row.sourceName, 'user');
    expect(settingEditRefusalOf(row), isNull);
  });
}
```

3. Решите, нужна ли правка правил моста:
   - ключ с секретом (`descriptor.secret` или тип `secretName`) автоматически получает отказ `SecretSetting` — правка не нужна;
   - ключ, который клиент не должен менять, как `trusted_projects`, требует ветки в `settingKeyEditRefusalOf` (`lib/src/views/setting_edit_rules.dart`) и новой ветки в `SettingEditRefusal`. Это ломает `switch` клиентов без `default` — так и задумано;
   - ключ-список, который недоверенный проект объединяет с нижними слоями (как `skills.disabled`), добавляется в `mergedByUntrustedProject` (`lib/src/config/project_trust.dart`) вместе с правилом ядра `trust.dart`;
   - ключ-семейство вида `providers.*` раскрывается только по провайдерам и моделям; другие подстановки `*` `_expand` не знает.
4. Если приложению нужна своя подпись, она живёт в клиенте (`apps/codelab_desktop`, ARB). Мост подписей не знает.

## 2. Новый пресет провайдера

Файл `lib/src/provider/provider_presets.dart`. Добавьте константу в `ProviderPresets.all` в нужном порядке (порядок виден пользователю):

```dart
ProviderPreset(
  id: 'acme',                              // для не-custom пресета это и id провайдера
  label: 'Acme',
  kind: 'openai-compatible',               // или 'anthropic'
  baseUrl: 'https://llm.acme.test/v1',
  key: KeyRequirement.required,            // required, optional или none
  suggestedEnvVar: 'ACME_API_KEY',
),
```

Что ещё поправить:

- тест `старт — выбор пресета из таблицы MVP` в `test/provider_setup_flow_test.dart` сравнивает полный список id;
- клиенты показывают `label` как есть; перевод подписей, если он нужен, — в клиенте;
- `id` провайдера должен соответствовать `[a-z0-9_-]+`: по нему строится имя секрета `codelab/<id>`.

Адреса пресетов — общеизвестные адреса API провайдеров, а не чужой код (`AGENTS.md` §5). Вид `kind` должен быть таким, чтобы проверка `/models` его поддерживала ([рецепт 6](#6-новый-вид-провайдера-в-проверке-models)).

## 3. Новый код ошибки шага мастера

Нужен, когда шаг получает новую проверку, а приложение должно перевести текст. Инвариант: `error` и `errorCode` всегда появляются вместе (`test/provider_setup_error_code_test.dart`, последний тест файла). Текст `error` остаётся английским для терминала.

1. Добавьте значение в `ProviderSetupErrorCode` (`provider_setup_state.dart`):

```dart
  /// Идентификатор модели с пробелами.
  modelIdInvalid,
```

2. Выдайте ошибку там, где шаг проверяет ввод (`_onManual` в `provider_setup_flow.dart`). Пример — такого правила в коде сейчас нет:

```dart
if (trimmed.contains(' ')) {
  _emit(
    EnteringModelDetails(
      draft,
      trimmed,
      builtinModelInfo(trimmed)?.contextWindow ?? safeDefaultContextWindow,
      error: 'The model id must not contain spaces.',
      errorCode: ProviderSetupErrorCode.modelIdInvalid,
    ),
  );
  return;
}
```

3. Тест (проверено запуском): мастер доходит до ручного ввода модели и получает код.

```dart
await send(const PresetChosen('openai'));
await send(const BaseUrlSubmitted('https://api.openai.com/v1'));
await send(const KeySubmitted(NoKey()));
check.respond(const CheckOk([]));
await pumpEventQueue();
await send(const ModelEnteredManually('my model'));

final state = flow.current as EnteringModelDetails;
expect(state.errorCode, ProviderSetupErrorCode.modelIdInvalid);
```

4. Приложение переводит коды выражением `switch` (`provider_wizard_view.dart` в `apps/codelab_desktop`). Новое значение без ветки не соберётся; ARB-ключ добавляет `desktop-engineer`. Терминал печатает `error` и менять код не обязан.

## 4. Новый шаг мастера

Состояния и события — запечатанные иерархии, поэтому компилятор сам перечислит места правки.

1. Добавьте состояние и событие в `provider_setup_state.dart`:

```dart
final class ChoosingOrganization extends ProviderSetupState {
  const ChoosingOrganization(this.draft);

  final ProviderDraft draft;

  @override
  String toString() => 'ChoosingOrganization(${draft.providerId})';
}

final class OrganizationSubmitted extends ProviderSetupEvent {
  const OrganizationSubmitted(this.organization);

  final String organization;
}
```

2. Анализатор сразу покажет первое место: `switch` в `_onBack` стал неполным (`non_exhaustive_switch_statement`, проверено запуском). Добавьте ветку `case ChoosingOrganization(): ...` — куда возвращается `Back` с нового шага.
3. Добавьте в `dispatch` ветку события: `case (final ChoosingOrganization s, final OrganizationSubmitted e): _onOrganization(s, e);`. Событие вне ветки автомат игнорирует и пишет `provider_wizard.event_ignored`, поэтому забытая ветка не падает, а молчит. Тест на событие обязателен.
4. Реализуйте переход: `_emit(...)`, обновление `_draft` через `copyWith`. Если шаг запрашивает порт, повторите приём шага ключа: счётчик `_epoch` и проверку `_disposed || epoch != _epoch` перед `_emit`, чтобы поздний ответ порта не менял актуальное состояние.
5. Если шаг хранит данные в плане, добавьте поле в `ProviderSetupPlan`, в `copyWith`, `withoutSecretValue()` и в `toEdits()`.
6. Обновите клиентов: оба должны получить ветку на новое состояние. Запечатанная иерархия сломает их сборку, пока ветка не добавлена.
7. Тесты: путь состояний через `kinds()`, `Back`, `Cancel`, сброс ссылки на секрет, журнал.

## 5. Новое поле формы MCP-сервера

Форма и строка списка читают один сырой элемент, поэтому поле нужно провести через черновик, запись и вид. Неизвестные ключи элемента форма сохраняет сама (`_extra`), так что **ключ можно писать и без правок** — поле нужно, только когда оно должно быть в форме. Пример — числовой `call_timeout` (в коде формы его нет, он сейчас идёт через `_extra`).

1. `lib/src/mcp/mcp_server_draft.dart`:
   - добавьте поле в `McpServerDraft`, в оба конструктора, `copyWith` и `fromElement`;
   - добавьте ключ в `_known` (`'call_timeout'`), иначе `..._extra` в конце элемента перезапишет значение поля старым значением из файла, и правка молча потеряется;
   - допишите ключ в `toEdits()` в нужную ветку транспорта;
   - если значение можно проверить, добавьте код в `McpDraftProblemCode` и текст в `McpDraftProblem.of` (switch выражений полон: компилятор подскажет), а в `validate()` — условие;
2. `lib/src/views/mcp_server_entry_view.dart`: если поле показывается в списке, добавьте его в `McpServerEntryView` и `_entryOf`. Если значение может нести секрет, пропустите его через `mcpDisplayValue` (правило имени ключа и шаблона значения) и учтите в `maskedValues` черновика.
3. Тесты: `test/mcp_server_draft_test.dart` (проверки, `toEdits()`), `test/mcp_draft_problem_code_test.dart` (код и текст), `test/views/mcp_server_entry_view_test.dart` (строка), `test/mcp_server_commit_test.dart` (в записанный элемент ключ попал, неизвестные не пропали).
4. Проверьте, что запись по-прежнему идёт одним `UpsertMcpServer`: форма не должна писать частичный элемент.
5. Клиент: форму и переводы текстов проблем строит приложение.

Скелет добавления в `toEdits()` (тело опущено, чтобы показать место):

```dart
McpTransportKind.stdio => {
  'command': command,
  if (args.isNotEmpty) 'args': args,
  if (env.isNotEmpty) 'env': table(env),
  // if (callTimeout != null) 'call_timeout': callTimeout,
},
```

## 6. Новый вид провайдера в проверке `/models`

Проверку знает `HttpProviderCheck._requestFor` (`http_provider_check.dart`) и функция `supportsProviderCheck` (`provider_check.dart`). Правьте их вместе, иначе страница включит «Check» для вида, который проверка отклонит.

1. В `_requestFor` добавьте ветку `case '<вид>':` со своими `suffix` и заголовками авторизации. Ключ раскрывайте только в заголовке и только если он не пуст.
2. Добавьте вид в `supportsProviderCheck`.
3. При необходимости задайте адрес по умолчанию в `defaultProviderBaseUrl`.
4. Тест на `MockClient`: проверьте путь запроса, заголовки, что тело ошибки не попадает в результат, что редирект не выполняется (`followRedirects = false`).

Без поддержки вид даёт `CheckFailure` с видом `badResponse` и текстом `the model list check is not supported for this provider kind` (проверено запуском на `gemini`).

## 7. Новый вид отказа проверки

Затрагивает мастер и все клиенты.

1. Добавьте значение в `ProviderCheckFailureKind` (`provider_check.dart`).
2. Верните его из `HttpProviderCheck._failureFor` (по статусу) или из классификатора ошибок (`classifyProviderCheckError`, `lib/src/io/classify_provider_check_error.dart`; только по типу исключения, не по тексту).
3. Решите в `ProviderSetupFlow._runCheck`, можно ли пропустить проверку (`canSkip`) и предложить `/v1` (`canUseV1`), и как работает `Back` из `CheckFailed` (`_onBack`: для `unauthorized` возврат на шаг ключа, иначе на шаг адреса).
4. Клиенты разбирают вид `switch`-ом: добавьте им ветку.
5. Тесты: `http_provider_check_test.dart` (вид по входу), `provider_setup_flow_test.dart` (переход состояния).

## 8. Новое поле с путём в виде расширений

Любое новое поле вида, хранящее путь на диске, ДОЛЖНО переводиться из формы ядра в форму хоста.

1. Добавьте поле в вид (`agent_extensions_view.dart`) и в построитель (`agent_extensions_of.dart`).
2. Добавьте перевод в `extensionsInHostForm` (`lib/src/io/extensions_host_paths.dart`): `host(path)` или `hostOrNull(path)`.
3. Добавьте проверку в `test/io/extensions_host_paths_test.dart` — тест нужен для полноты. Без него на Windows «Open» получит путь ядра.
4. Если поле — путь для промпта, а не путь диска (как `ContextFileView.path`), не переводите его и запишите это в комментарии.

## 9. Новый реэкспорт

Клиентам нельзя импортировать `package:codelab_agent_*`. Нужный им символ из ядра или IO-пакета открывается через мост.

1. Для чистого типа ядра добавьте имя в список `show` у `export 'package:codelab_agent_core/codelab_agent_core.dart'` в `lib/codelab_setup.dart`.
2. Для символа из `codelab_agent_io` или типа, нужного `io.dart`, добавьте имя в `show` в `lib/io.dart`.
3. Добавьте проверку компиляции в тест реэкспорта (`test/exports_test.dart` или специализированный `*_exports_test.dart`):

```dart
test('the main barrel re-exports the pure config types', () {
  const ConfigLoadResult? loaded = null;
  expect([loaded], everyElement(isNull));
});
```

4. Основной барель остаётся web-безопасным: проверьте `melos run web-compile`. Если новый символ из ядра тянет `dart:io`, его нельзя класть в основной барель.
5. Классы `EnvSecretStore`, `FileSecretStore` и функцию `openHostSecrets` не экспортируйте: они принадлежат хосту агента.
6. Новая зависимость в `pubspec.yaml` разрешена только через OpenSpec change и правку allowlist сторожа (`setupAllowlist` в `pubspec_allowlist_test.dart`).

## 10. Новый вид (view)

Правила — в [главе 06](06-views.md#как-добавить-новый-вид). Кратко: неизменяемый класс, чистая функция-построитель по `AgentConfigSnapshot`, `toString()` без значений, экспорт из `lib/codelab_setup.dart`, тест на `snapshotOf` или `RealHome` и проверка маркера утечки.

## Чего не делать

- **Не добавлять `dart:io`, `package:http/io_client.dart` и `package:codelab_agent_io/` в основной барель.** Всё, что требует их, идёт в `lib/src/io/` и `lib/io.dart`; сторож остановит иное.
- **Не раскрывать `SecretValue.reveal()` вне места отправки.** Результат нельзя сохранять в состоянии, событиях и текстах (SETUP-1).
- **Не повторять правила ядра.** Слияние слоёв, доверие, перезагрузку и правила навыков вызывайте из ядра (`planConfigReload`, `parseSkills`, `assembleProjectContext`), а не копируйте.
- **Не писать в слой `project` и в файл `--config`** (SETUP-3), не придумывать цели записи вне `EditableSettings.targets`.
- **Не повторять запись при `ConfigConflict`** (SETUP-6): перечитайте снимок и дайте решить пользователю.
- **Не разбирать тексты** исключений, проблем и отказов: код и тип принимаются из структур; текст зависит от ОС, SDK и версии валидатора.
