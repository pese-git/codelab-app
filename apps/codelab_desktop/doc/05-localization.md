# Локализация интерфейса

Глава для тех, кто добавляет или меняет текст интерфейса, строит текст внутри Cubit-а или отвечает за смену языка. Рецепт «как добавить строку» — в [главе 09](09-extending.md#рецепт-3-новая-строка-интерфейса); здесь — устройство каталогов, путь языка до экрана и защита от строк, которые остались на прежнем языке. Правила приложения — раздел «Локализация» в [`AGENTS.md`](../AGENTS.md), требования — [app-settings](../../../openspec/specs/app-settings/spec.md), «Локализация интерфейса app» и «Язык интерфейса app».

## Что переводится

Приложение показывает интерфейс на английском (`en`) и русском (`ru`). Язык меняется сразу, без перезапуска. Английский текст — эталон: он совпадает со спецификациями символ в символ, а русский берётся из [глоссария](../../../docs/architecture/l10n-glossary.md).

Не переводится и при любом языке показывается как есть:

- всё, что пришло от агента и модели: ответы, размышления, заголовки и вывод вызовов, тексты ошибок агента, имена и описания команд, режимов и опций;
- протокольные значения (`stopReason`, `kind`, имена методов ACP), ключи и значения конфигурации, пути, URL, имена переменных и секретов, команды и slash-команды внутри фраз;
- названия продуктов и провайдеров (`CodeLab`, `MCP`, `ACP`, `WebSocket`), обозначения клавиш, числа usage;
- журналы, их события и содержимое панелей «Debug log» и «Inspector»;
- названия языков: `English` и `Русский` — эндонимы.

Такие значения подставляются в переведённую фразу плейсхолдером, а не склеиваются из кусков. Полный перечень — в глоссарии, §2. Клиентское ядро (`codelab_client_core`) языконезависимо: приложение строит текст по типизированным данным ядра (кодам, видам, причинам) и не разбирает английскую строку ядра.

## Каталоги и сгенерированный код

Настройки `gen-l10n` — `l10n.yaml` в корне приложения:

| Параметр | Значение | Смысл |
|---|---|---|
| `arb-dir` | `lib/l10n` | где лежат каталоги и сгенерированный код |
| `template-arb-file` | `app_en.arb` | шаблон: из него берутся ключи, типы и плейсхолдеры |
| `output-localization-file` | `app_localizations.dart` | базовый класс `AppLocalizations` |
| `nullable-getter` | `false` | `AppLocalizations.of(context)` возвращает не `null` |
| `required-resource-attributes` | `true` | у каждого сообщения шаблона должен быть `@ключ` |
| `untranslated-messages-file` | `build/l10n_untranslated.json` | сюда `gen-l10n` пишет ключи без перевода |

Файлы в `lib/l10n/`:

| Файл | Что это | Правится рукой |
|---|---|---|
| `app_en.arb` | шаблон: тексты `en` и `@ключ` с описанием и плейсхолдерами | да |
| `app_ru.arb` | перевод: только ключи и русский текст, без `@`-блоков | да |
| `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_ru.dart` | сгенерированный код | нет, коммитится |
| `l10n.dart` | расширение `context.l10n` | да |

Сгенерированный код хранится в git, чтобы `dart analyze` работал без шага генерации. После правки `.arb` выполните в `apps/codelab_desktop`:

```bash
fvm flutter gen-l10n
```

и закоммитьте изменённые `app_localizations*.dart`. Забытая генерация — тихий дефект: приложение остаётся со старым текстом, а `gen-l10n` расхождения не замечает. Ловит его скрипт `l10n:check` (раздел «Проверки» ниже).

### Анатомия сообщения

Один и тот же ключ в обоих каталогах. Шаблон (`app_en.arb`) несёт описание для переводчика и типы плейсхолдеров:

```json
"providersModelCount": "{count, plural, one{{count} model} other{{count} models}}",
"@providersModelCount": {
  "description": "Число моделей провайдера в подписи строки.",
  "placeholders": {
    "count": {
      "type": "int"
    }
  }
},
```

Перевод (`app_ru.arb`) — одна строка с четырьмя формами русского `plural`:

```json
"providersModelCount": "{count, plural, one{{count} модель} few{{count} модели} many{{count} моделей} other{{count} модели}}",
```

Из них `gen-l10n` строит метод `String providersModelCount(int count)` на `AppLocalizations`; русская реализация вызывает `intl.Intl.pluralLogic` с формами `one`, `few`, `many`, `other` (`app_localizations_ru.dart`). Вызов: `context.l10n.providersModelCount(3)` даёт «3 модели».

Правила каталога:

1. **Ключ** — camelCase `<экран><элемент><смысл>`: `settingsLanguageTitle`, `providersModelCount`, `onboardingStepWelcome`.
2. **`@описание`** на русском: контекст для переводчика, какой плейсхолдер что значит и что не переводить. Сообщения, от смысла которых зависит безопасность (предупреждение о ключах, открытие корня диска), помечаются в описании словом `security`: перевод не должен смягчать смысл, и такой перевод вычитывает человек.
3. **Количество — только ICU `plural`**, одним сообщением с плейсхолдером. Склейка фраз и `n == 1 ? … : …` запрещены: у `ru` четыре формы. Формы `one`, `few`, `many`, `other` обязательны в `app_ru.arb`.
4. **Выбор варианта — ICU `select`**, а не склеенный хвост. Например, баннер записи режима `agentsBannerSaved` выбирает фразу по аргументу `when` (`now`, `afterRestart`, `whenAgentStarts`), и все три фразы целые.
5. **Одинаковый набор** ключей и плейсхолдеров в `en` и `ru`.
6. Названия продуктов и значения, которые остаются как есть, передаются плейсхолдерами.

## Как язык доходит до экрана

Единственный владелец языка — `AppLanguageCubit` (`lib/app/language/app_language_cubit.dart`), singleton корневого scope. Его состояние `AppLanguageState`:

| Поле | Смысл |
|---|---|
| `preference` | выбор пользователя: `AppLanguagePreference.system`, `en` или `ru` |
| `locale` | применённый язык: `resolveAppLocale(preference, системные языки)` |
| `strings` | каталог `AppLocalizations` этого языка |
| `saveFailed` | последняя запись выбора не удалась (язык при этом остаётся применённым) |

Путь языка:

1. **До первого кадра.** `main` читает сохранённый выбор (`SharedPreferencesAppLanguagePreferences`, ключ `shared_preferences` `codelab.app.language`; для `system` ключа нет) и вместе с языками системы получает `AppLanguageStart`. Он идёт в `createCodeLabRootScope(language:)`, поэтому первый кадр уже на нужном языке. Чтение не бросает: незнакомое значение и сбой хранилища дают `system`, ключ не перезаписывается; диагностику пишет модуль после настройки журнала.
2. **`system`** выбирает `ru`, если `languageCode` первого языка системы — `ru`, иначе `en`; остальные языки списка и регион не учитываются. Смена языка ОС применяется при следующем старте или при повторном выборе пункта «System».
3. **Корень дерева.** `CodeLabApp` (`lib/app/codelab_app_widget.dart`) читает `AppLanguageCubit` одним `BlocBuilder` с `buildWhen` по `locale` и меняет только параметр `locale` у `FluentApp`. `FluentApp` не пересоздаётся, поэтому `State` виджетов (ввод композера, фокус, прокрутка) сохраняется. В `localizationsDelegates` рядом стоят делегаты app (`AppLocalizations.localizationsDelegates`) и делегат кита `CodeLabLocalizations.delegate`: без него кит остаётся на английском.
4. **Виджет.** В `build` текст берётся как `context.l10n.<ключ>` (расширение `AppL10nContext` в `lib/l10n/l10n.dart`). Смена языка пересобирает такие виджеты через `Localizations`, подписок не нужно. Расширение — только для presentation: Cubit-ы `BuildContext` не знают.
5. **Cubit с текстом.** Он узнаёт о смене языка через порт `AppStrings` (следующий раздел).
6. **Выбор пользователя.** Строка «Language» страницы «General» вызывает `AppLanguageCubit.select`: язык применяется синхронно (`emit`), затем идёт запись ключа. Записи стоят в очереди, побеждает последний выбор; обогнанная запись состояние не публикует. Сбой записи не откатывает язык, а ставит `saveFailed`: страница показывает ошибку и кнопку повтора.

При закрытии `AppLanguageCubit.close()` ждёт запись в полёте до 3 секунд (отдельный шаг `language` выхода из приложения), чтобы последний выбор дошёл до хранилища; зависшая запись видна в событии `app.exit_timeout` ([composition root](02-composition-root.md)).

## Три вида текста

Единой схемы «положить текст в состояние» нет, потому что текст бывает трёх видов. Выбор вида — главное решение при добавлении строки.

| Вид | Когда | Где живёт текст | Пример |
|---|---|---|---|
| 1. Текст виджета | подпись, заголовок, подсказка, определённые в `build` | `context.l10n` в `presentation/` | `Text(context.l10n.settingsLanguageTitle)` |
| 2. Производный текст в состоянии Cubit | подпись зависит от входов и языка | функция `(входы, язык)`; язык — явный вход проекции | строки ленты и строка статуса сессии в `ActiveSessionCubit` |
| 3. Разовое сообщение об исходе | результат действия: «не удалось записать профиль», баннер после записи | типизированное значение (`sealed`-класс с аргументами); текст строит функция по `l10n` | `AddProfileFailure`, `ProviderMessage`, `McpMessage` |

Что следует из этого для вида 2: Cubit не хранит переведённую строку, которую нельзя пересобрать из входов. Он хранит входы (снимки сессий, профили, типизированные причины) и собирает текст при каждом изменении и при смене языка. Поэтому после смены языка лента равна ленте, которую построило бы новое `session/update`: `ActiveSessionCubit._handleLanguage` вызывает тот же `_rowsOf`, что и `show`.

Вид 3 нужен потому, что исход действия не восстановить из входов: «запись профиля не удалась» нельзя вывести из текущего состояния. Тип и аргументы хранятся в состоянии, а текст собирает функция, которой передают каталог:

```dart
String addProfileFailureText(
  AppLocalizations l10n,
  AddProfileFailure failure,
) => switch (failure) {
  ProfileWriteFailed() => l10n.addProfileFailureProfile,
  SecretWriteFailed() => l10n.addProfileFailureSecret,
  OrphanedTokenFailure(:final backendId, :final secretName) =>
    l10n.addProfileFailureOrphanedToken(backendId, secretName),
  SecretStoreReadOnlyFailure() => l10n.secretStoreReadOnly,
};
```

(`lib/features/settings/application/add_profile_state.dart`). Пользовательский текст от хранилища секретов (`SecretStoreReadOnlyFailure.reason`) в каталог не попадает: он показывается как есть под переведённым заголовком отдельной функцией `addProfileFailureDetail`. Тот же приём у других страниц: `providerMessageText` (`application/provider_messages.dart`), `mcpMessageLines`, `skillsMessageText` и `agentsModesMessageText` (`presentation/*_texts.dart`). Функция лежит либо рядом с типом исхода в `application/`, либо в `presentation/`; общее у них одно: вход — типизированное значение и `AppLocalizations`, выход — строка, а в состоянии строки нет. Исчерпывающий `switch` заставляет добавить текст для каждого нового варианта.

## Порт `AppStrings`

Cubit-ам с текстом нужны только текущий каталог и событие смены, поэтому они получают не весь `AppLanguageCubit`, а узкий порт `AppStrings` (тот же файл):

```dart
abstract interface class AppStrings {
  AppLocalizations get current;
  Stream<AppLocalizations> get changes;
}
```

`AppLanguageCubit` реализует его. `changes` — широковещательный поток: ровно одно событие на смену языка (повторный выбор того же языка события не даёт), он закрывается вместе с владельцем. Порт даёт независимое тестирование: в тестах вместо Cubit языка стоит `FixedAppStrings` (язык не меняется) или `TestAppStrings` (`test/support/app_strings.dart`: управляемая смена языка и счётчик подписок).

Правила подписки Cubit-а на `AppStrings.changes` (корневой `AGENTS.md` §9):

- подписка одна, создаётся в конструкторе и не зависит ни от соединения, ни от смены сессии;
- отменяется в `close()`; событие после `close` игнорируется (`if (isClosed) return`);
- по событию пересобирается вся проекция из последних входов, остальное состояние (ввод, очередь, ответы в полёте) не трогается;
- `AppStrings.current` читается только внутри проекции.

Cubit-ы с текстом в состоянии — восемь файлов; список проверяет тест (см. ниже):

| Группа | Cubit-ы |
|---|---|
| Рабочее место | `ConnectionCubit`, `SessionsCubit`, `ActiveSessionCubit`; фасад `CodeLabShellCubit` — своей подписки нет, палитра команд берёт каталог из `parts.strings.current` при пересчёте за частями |
| Страницы настроек | `ConnectionSettingsCubit`, `AddProfileCubit`, `ProviderSettingsCubit`, `ProviderWizardCubit` |

Остальные Cubit-ы на `AppStrings` не подписаны. `McpSettingsCubit`, `AgentsModesCubit`, `SkillsSettingsCubit`, `SecretMigrationCubit` и другие вообще не хранят текст, зависящий от языка: их состояние типизировано (виды, причины, `ConfigSourceKind?`, `McpServerState`, `AgentRowStatus`, sealed-сообщения), а текст собирает presentation. `features/usage/application` и `features/terminal/application` отдают числа и типизированные значения без Flutter. Подробности по состояниям — в [главе про путь состояния](03-state-flow.md).

### Типизированные исходы вместо строк мостов

Тексты ядра и мостов (`codelab_setup`) приложение показывает по типу, а не по готовой строке:

- ошибки мастера провайдера — по `errorCode` и `refusal` (`wizardErrorText`), пресеты — по `ProviderPreset.id` (`wizardPresetLabel`), статус ключа — по виду `KeyStatusView` (`keyStatusLabel`);
- проблемы черновика MCP — по `McpDraftProblem.code` и аргументу; подписи навыков — по `overridesScope` и `extraEntry`;
- заметки ленты — по `NoticeItem.reason` (`EmptyTurnReason`, `TurnStoppedReason`, `SessionRestoreReason`), а не по английскому `NoticeItem.text` ядра; `text` остаётся запасным значением;
- отказы токена — по статусу 401 или 403 и признаку «токен ушёл».

Сравнивать готовые строки ядра, моста или агента запрещено (в том числе чтобы скрыть дубль сообщения): строка может смениться без изменения смысла. Дубль «ключ уже есть» скрывает `isKeyAlreadyStoredError`, проверка идёт по коду. Строки без типа (причина хранилища секретов, `ConfigIssue.message`, `ExtensionDiagnostic.message`, `lastError` MCP-сервера, ответ агента на `/mcp`) показываются как есть под переведённым заголовком.

## Каталог кита `codelab_ui`

У `codelab_ui` свой каталог: `codelab_ui_en.arb` и `codelab_ui_ru.arb` в `packages/flutter/codelab_ui/lib/src/l10n/`, класс `CodeLabLocalizations`. Приложение подключает его делегат в `FluentApp` (см. выше) и от кита получает названия панелей дока, подписи риска одобрения и другие тексты, которые рисует сам виджет. Как кит принимает параметры с текстом по умолчанию и как менять его каталог — [README `codelab_ui`, раздел «Локализация»](../../../packages/flutter/codelab_ui/README.md#локализация). Проверка актуальности кода кита — тот же скрипт `l10n:check`.

## Проверки

| Проверка | Что ловит | Как запускать |
|---|---|---|
| `melos run l10n:check` | сгенерированный `app_localizations*.dart` устарел относительно `.arb` (и то же для `codelab_ui`) | `fvm dart run melos run l10n:check` |
| `test/l10n/l10n_catalogs_test.dart` | наборы ключей `en` и `ru` расходятся, плейсхолдеры не совпадают, у русского `plural` нет форм `one`, `few`, `many`, `other` | `fvm flutter test test/l10n` в `apps/codelab_desktop` |
| `ui_literals_test` (`codelab_architecture_tests`) | английский литерал интерфейса в `presentation/` и в `codelab_ui` мимо каталога | `fvm dart run melos run guard` |
| `test/l10n/cubit_text_list_test.dart` | Cubit с `AppStrings` вне списка из восьми файлов, Cubit из списка без `strings.changes.listen(`, `AppStrings` в Cubit-е, где его быть не должно (MCP, Agents & modes, Skills, перенос секретов) | `fvm flutter test test/l10n` |
| `test/l10n/language_switch_sweep_test.dart` | экран или страница остались на прежнем языке после `en → ru → en` | `fvm flutter test test/l10n` |

### Скрипт `l10n:check`

Определён в корневом `pubspec.yaml` (секция `melos`): `fvm dart run tool/l10n_check.dart`. Он проверяет `apps/codelab_desktop` и `packages/flutter/codelab_ui`, а `--package <каталог>` ограничивает проверку одним пакетом. Для каждого пакета:

1. копирует во временный каталог `pubspec.yaml`, `l10n.yaml` и `.arb`;
2. запускает там `fvm flutter gen-l10n`;
3. прогоняет свежий и закоммиченный код через `dart format`: форматирование `gen-l10n` в разных версиях Dart отличается одними переносами, и без этого проверка давала бы ложные срабатывания;
4. сравнивает файлы построчно и печатает первую отличающуюся строку.

Рабочее дерево скрипт не меняет. Успех — код выхода 0 без вывода (так отработал локальный запуск при подготовке главы); расхождение, лишний или отсутствующий файл — код 1 и путь файла. Скрипт входит в `melos run check`, а перед pull request его запускают, если менялись `l10n.yaml`, `.arb` или сгенерированный код.

Скрипт не проверяет перевод: `gen-l10n` при отсутствии ключа в `ru` не падает, а берёт английский текст, поэтому за полноту перевода отвечает `l10n_catalogs_test`.

### Сторож литералов `ui_literals_test`

Тест лежит в `packages/dart/codelab_architecture_tests/test/ui_literals_test.dart`, сканер — `test/support/ui_literals.dart`. Он не разбирает AST, а ищет регулярными выражениями строки, которые начинаются с буквы, в позициях `Text('…')`, `CodeLabText('…')` и в именованных параметрах `label`, `tooltip`, `placeholder`, `title`, `message`, `content`, `description`. Сканируются `lib/app`, `lib/features/**/presentation` и `lib/src` кита; `application/`, превью (`*_previews.dart`) и каталоги `l10n/` пропускаются, их проверяет ревью.

Если строка должна остаться литералом (название продукта, значение из конфигурации, пример значения поля), занесите её в `packages/dart/codelab_architecture_tests/test/support/ui_literals_allowlist.txt` одной строкой:

```text
apps/codelab_desktop/lib/features/settings/presentation/mcp_page.dart | stdio | значение транспорта MCP из конфигурации, показывается как есть
```

Формат — `путь | литерал | причина`, причина обязательна. Запись, которой в коде больше нет, роняет тест: allowlist не копит мёртвых исключений. Переводимая строка в allowlist не попадает: её место — каталог.

### Тесты с языком

Локаль по умолчанию в тестах — `en` (`CodeLabTestBinding(locale:)`, `localizedFluentApp` в `test/support/l10n_app.dart`), поэтому `find.text` на английском остаются верными, а для проверки перевода передают `locale: const Locale('ru')`. Для смены языка на живом экране — `AppLanguageCubit.select`, затем `await expectNoStaleLanguage(tester, from: …, to: …)` (`test/support/l10n_mix.dart`): он собирает из каталогов app и кита значения, которые различаются между языками, и падает, если среди видимых строк осталась строка прежнего языка. `integration_test/` запускается на `en` (`integration_test/flutter_test_config.dart` кладёт `codelab.app.language = en`). Новый Cubit с текстом в состоянии добавляется в `_withText` теста `cubit_text_list_test` и получает тест смены языка на `TestAppStrings`; общее устройство тестов — [тесты приложения](08-testing.md).

## Добавление строки

Шаги и примеры — в [расширении приложения](09-extending.md#рецепт-3-новая-строка-интерфейса). Выбор вида текста (виджет, проекция в Cubit, типизированный исход) описан выше и в рецепте не повторяется. Новый термин, которого нет в глоссарии, добавляется в [глоссарий](../../../docs/architecture/l10n-glossary.md) в том же изменении.
