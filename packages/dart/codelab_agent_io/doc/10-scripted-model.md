# Сценарий модели и помощники тестов: `testing.dart`

Глава про второй барель пакета, `package:codelab_agent_io/testing.dart`. Он даёт детерминированный агент без сети: модель отвечает по заранее записанному сценарию. Сам сценарий и его формат (`ScriptedStreamFunction`) принадлежат ядру ([глава 12 ядра](../../codelab_agent_core/doc/12-testing.md)); пакет добавляет то, что требует `dart:io` и конфигурацию.

Нормы: [`embedded-agent`](../../../../openspec/specs/embedded-agent/spec.md) («Сценарий модели для тестов»). Код: `lib/testing.dart`, `lib/src/scripted/`, `lib/src/testing/`.

## Зачем отдельный барель

Основной барель `codelab_agent_io.dart` попадает в граф импортов рабочей сборки клиентов через `codelab_embedded/io.dart`. Если бы сценарий лежал там, его вычищал бы только tree-shaking, то есть гарантия компилятора, а не структуры. В `testing.dart` он недостижим из рабочего кода: основной барель сценарий **не экспортирует** и на `src/scripted/` не ссылается.

Импорт `package:codelab_agent_io/testing.dart` по замыслу разрешён только перечисленным ниже; сторож (`melos run guard`) запрещает его в `lib/` мостов `codelab_embedded` (кроме `src/testing/`) и `codelab_setup`, а бинарь и тесты правилом не охвачены:

- `apps/codelab_agent` — флаг `serve --llm-script`;
- `packages/dart/codelab_embedded/lib/src/testing/` — `scriptedEmbeddedAgentOpener`;
- тестам.

Клиенты `codelab_desktop` и `codelab_cli` пакет напрямую не импортируют вообще; драйвер фикстур CLI (`lib/src/scenario/`) получает сценарий через `codelab_embedded/testing.dart`, а в `lib/` desktop этого импорта нет: сценарий модели не должен попасть в релизную сборку. Код один у бинаря и у встроенного агента, поэтому оба разбирают сценарий и пишут ошибки одинаково.

## Состав

| Что | Файл | Роль |
|---|---|---|
| `LlmScript` | `scripted/llm_script.dart` | разбор файла `--llm-script` или блока `llm` фикстуры в `ScriptedStreamFunction` и список моделей |
| `LlmScriptException` | там же | ошибка сценария; бинарь переводит её в `UsageError` с кодом `64`, а `scriptedEmbeddedAgentOpener` пробрасывает как есть |
| `withScriptedProviders` | `scripted/scripted_providers.dart` | кладёт модели сценария в слой флагов конфигурации |
| `CwdTrackingStore` | `scripted/cwd_tracking_store.dart` | обёртка `SessionStore`, помнящая `cwd` сессий для `${cwd}` в сценарии |
| `rewriteUntil` | `testing/rewrite_until.dart` | прогрев записи для тестов с настоящим `Directory.watch` |

## `LlmScript`

Формат файла сценария — JSON `{"llm": {"model": {...}, "steps": [...]}}`, как блок `llm` фикстуры ACP (чтобы сценарии писались так же, как фикстуры). Что делает `LlmScript`:

- `LlmScript.load(path, models:, clock:, cwdOf:)` читает файл; `LlmScript.fromJson(llm, …)` — готовый блок без обёртки; `LlmScript.modelsOf(path, models:)` отдаёт только модели, без построения функции: хост просит их **до** загрузки конфигурации, чтобы описать провайдера сценария слоем флагов.
- Функцию модели строит `ScriptedStreamFunction.fromJson` ядра; её `FormatException` превращается в `LlmScriptException('<источник>: <текст>')`.
- Модели: `scripted/<id>` из `--model` (параметр `models`), иначе модель `llm.model` (по умолчанию `scripted/scripted-1`, окно контекста 32768, лимит ответа 4096). Каждая получает адрес `http://scripted.invalid/v1`: в сеть сценарий не ходит.
- Цены `llm.model.cost` (доллары за 10⁶ токенов: `input`, `output` обязательны, `cacheRead` и `cacheWrite` — нет): нет поля — цен нет; объект неверного вида, нечисло, отрицательное или бесконечное значение — `LlmScriptException` (`llm.model.cost.input: must be a finite number not less than 0`). Молчаливое «нет цен» скрыло бы опечатку, правила совпадают с проверкой `cost_*` в конфигурации.
- Тексты ошибок файла начинаются с `--llm-script <путь>:` — прежний контракт бинаря: `…: invalid JSON: …`, `…: the file must be {"llm": {"model": {...}, "steps": [...]}}`.

## `withScriptedProviders`

Схема конфигурации требует `agent.default_model` из каталога провайдеров, а у сценария каталог — его собственные модели. `withScriptedProviders(flags, models)` дополняет слой флагов провайдерами и моделью сценария: каждая модель становится моделью провайдера `openai-compatible` с адресом `scripted.invalid`, окном контекста и лимитом ответа, поэтому конфигурации не нужны ни ключ, ни сеть. Первая модель списка становится `agent.default_model`; остальные значения `flags` сохраняются, кроме `providers` и `agent`. Цены сценария попадают в ключи `cost_*`.

Проверено запуском: сценарий из одного шага (`reply: [{text: hello}]`) даёт слой флагов и загрузку без проблем.

```dart
final script = LlmScript.fromJson(
  {
    'model': {'provider': 'scripted', 'modelId': 'scripted-1', 'contextWindow': 32768},
    'steps': [
      {'reply': [{'text': 'hello'}], 'stopReason': 'stop'},
    ],
  },
  models: const [],
  clock: FakeClock(),          // из package:codelab_agent_core/testing.dart
  cwdOf: (_) => null,
);
final flags = withScriptedProviders(
  const ConfigTree(kind: ConfigLayerKind.flags, source: 'flags', values: {}),
  script.models,
);
final loaded = ConfigLoader().load(
  cwd: dir.path,
  environment: {'CODELAB_HOME': '${dir.path}/home'},
  flags: flags,
  scripted: true,               // слои 2-4 не читаются, $CODELAB_HOME не трогается
);
```

Результат прогона:

```text
issues: []
model: ModelRef(scripted/scripted-1)
sources: [defaults, flags]
{providers: {scripted: {kind: openai-compatible, base_url: http://scripted.invalid/v1, models: {scripted-1: {context_window: 32768, max_output_tokens: 4096}}}}, agent: {default_model: scripted/scripted-1}}
```

Параметр `scripted: true` у `ConfigLoader.load` нужен, чтобы сценарий не зависел от окружения разработчика: `$CODELAB_HOME` не читается и не проверяется (неверная тильда не даёт код `64`), а бэкенд секретов всегда `env`. Хост передаёт `ProjectFilesLoader(home: null)` и `userHome: null` по той же причине.

## `CwdTrackingStore`

Шаги сценария общие для сессий процесса, а `${cwd}` в тексте шага — папка сессии запроса. Сценарий узнаёт её по идентификатору сессии (`LlmContext.cacheKey`) через функцию `cwdOf`. `CwdTrackingStore` оборачивает `SessionStore` и запоминает `cwd` при `create`, `createChild` (ключ кэша запроса потомка — его идентификатор) и `open` (сессию, загруженную `session/load` после перезапуска процесса, никто не создаёт заново):

```dart
final store = CwdTrackingStore(MemorySessionStore());          // без --sessions-dir
// final store = CwdTrackingStore(JsonlSessionStore(...));      // с журналом на диске
final script = LlmScript.load(path, models: models, clock: clock, cwdOf: store.cwdOf);
```

Остальные методы просто делегируют обёрнутому хранилищу.

## `rewriteUntil`

Тесты наблюдателя на настоящем `Directory.watch` сталкиваются с задержкой подписки: у FSEvents и inotify одна запись сразу после старта может пройти мимо. `rewriteUntil(done, write)` повторяет запись с **разным** содержимым (одинаковое не даст сигнала: сравнение идёт по sha256), пока не наступит событие `done`.

```dart
final changed = watcher.changes.first;
await rewriteUntil(changed, (attempt) {
  File(path).writeAsStringSync('budget:\n  max_steps: 5\n# попытка $attempt\n');
});
```

- Шаг между попытками больше debounce (700 мс против 300 мс), иначе таймер перезапускался бы бесконечно.
- `onTick` вызывается каждые 5 мс, например чтобы сдвигать `FakeClock`, пока событие каталога идёт в реальном времени.
- Не дождались за `limit` (20 секунд по умолчанию) — `TimeoutException('no event after N writes')`.

В тестах этого пакета помощник не вызывается (`config_watcher_test.dart` проверяет `Directory.watch` без него); единственный вызов — `packages/dart/codelab_embedded/test/embedded_config_reload_test.dart`.

## Что запомнить

- `testing.dart` импортирует только тестовый и сценарный код; в рабочую сборку он не должен попадать.
- Сценарий общий у бинаря и встроенного агента, поэтому ошибки разбора — `LlmScriptException`, а не `UsageError` приложения.
- С `scripted: true` загрузчик не трогает `$CODELAB_HOME` и слои проекта.
- `rewriteUntil` пишет разное содержимое: одинаковая правка не даст сигнала.

## Смотрите также

- [Глава 12 ядра: модель-сценарий и харнессы](../../codelab_agent_core/doc/12-testing.md)
- [Глава 12: тестирование пакета](12-testing.md)
- Тесты: `test/scripted/llm_script_test.dart`
