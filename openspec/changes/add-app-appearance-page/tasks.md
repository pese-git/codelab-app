## Исполнители

- `[client]` — `codelab_client_core`, `codelab_client_io`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, правило сторожа app;
- `[agent]` — задач нет: агент, мосты `codelab_setup` и `codelab_embedded` не меняются;
- `[protocol]` — задач нет: ACP, модели и фикстуры не меняются.

Задачи документации без метки выполняет `docs-writer` (продуктовые документы) или `codelab-architect` (`docs/architecture/`), как указано в задаче.

TDD (`packages/dart/codelab_agent_core/AGENTS.md` §2): красный тест — отдельная задача и отдельный коммит до кода (коммит — только по просьбе пользователя). Задача реализации ссылается на свой красный тест.

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` или `fvm flutter analyze` пакета;
- тесты пакета;
- `guard` — при правке `rules.dart`, импортов между пакетами и барелей;
- `l10n:check` — при правке ARB;
- `test:e2e:cli:dart-agent` — при правке бареля `codelab_client_core` (через него работает CLI).

Интеграционный тест app в `feature/*` только компилируется.

## 0. Документы и решения

- [x] 0.1 `codelab-architect`: спецификации и design приведены к решениям пользователя 2026-11-20 (Q1–Q6, раздел design.md «Решения пользователя 2026-11-20»). `12-6-cli-desktop-extras.md` §12.6.3:
  - формат и разбор — spec `client-themes`, `ThemeFile.parse` в `codelab_client_core`, порт `ThemeLibrary`; CLI считает любую проблему ошибкой;
  - `colors.code` входит в закрытый набор CLI (принимается, пока не применяется);
  - `extends` — `light | dark | high-contrast`;
  - пункт 5: выбор у каждого клиента свой, каталог и формат общие, две темы режимов app.

  `12-4-first-run-and-settings.md` §12.4.9, строка «Appearance (10)» — состав по D14, хранение по D5, `system_theme`, ссылка на change.
- [x] 0.2 `codelab-architect`: `delivery-roadmap.md` §10.1, строка 10 — ссылка на change, веха M5 (Q6 (а)); §6 и сводка вех не меняются.
- [x] 0.3 `codelab-architect`: `state-management.md` §63б «Оформление app» (D13); `concurrency.md` — ветка `appearance` в схеме §45 и в §46, новый §47б (запись, перечитывание, подписка на акцент, закрытие, старт).
- [x] 0.4 `codelab-architect`: `technology-stack.md` — строка таблицы §1 и раздел §20з `system_theme` (версия 3.3.0, BSD-3-Clause, платформы, уведомления, особенности API, правило сторожа; решение Q5 (б)). `THIRD_PARTY_NOTICES.md` не меняется: зависимости pub.dev в него не вносятся, шрифтов и ресурсов пакет в сборку не кладёт (вводная часть реестра).

## 1. Итерация 1 — формат и разбор темы (`codelab_client_core`)

- [x] 1.1 `[client]` Красный: `packages/dart/codelab_client_core/test/themes/json_spans_test.dart` (D3):
  - позиции ключей и значений (строка, колонка с 1, UTF-16) для вложенных объектов;
  - повтор ключа в одном объекте;
  - escape-последовательности и суррогатные пары;
  - глубина больше 32 — ошибка;
  - сверка значений дерева с `jsonDecode` на наборе файлов.
- [x] 1.2 `[client]` Реализация 1.1: `lib/src/themes/json_spans.dart`. 1.1 зелёный.
- [x] 1.3 `[client]` Красный: `test/themes/theme_file_test.dart`. Spec client-themes, все сценарии требований «Формат файла пользовательской темы», «Роли цветов темы», «Нестрогий разбор темы в app»:
  - «Минимальная тема», «Имя не совпадает с файлом», «Имя встроенной темы»;
  - «Палитра кода», «Роль, которой нет у клиента»;
  - «Неизвестный ключ с подсказкой» (позиция `6:5`, подсказка `accent`), «Ключ, не похожий на роль», «Справка о незаданных ролях», «Неверное значение цвета», «Битый JSON», «Терминальный цвет»;
  - каждый код ошибки из списка требования (`tooLarge`, `notUtf8`, `notAnObject`, `missingName`, `invalidName`, `invalidExtends`, `duplicateKey`);
  - подсказка: расстояние редактирования не больше 2, только роли той же области (`colors` или `colors.code`);
  - у результата нет английского текста проблемы (`ThemeIssue` — код, позиция, аргументы).
- [x] 1.4 `[client]` Реализация 1.3: `theme_role.dart`, `theme_color.dart`, `theme_issue.dart`, `theme_file.dart` (D2); экспорт из бареля `codelab_client_core`. 1.3 зелёный, `guard` зелёный.
- [x] 1.5 `[client]` Красный: `test/themes/theme_library_contract_test.dart` — контракт порта `ThemeLibrary` на `InMemoryThemeLibrary`: порядок по имени, запись с ошибкой чтения, результаты импорта `imported | replaced | unchanged | needsReplace | invalid | failed`.
- [x] 1.6 `[client]` Реализация 1.5: `theme_library.dart` — порт, `ThemeEntry`, `ThemeImportResult` и `InMemoryThemeLibrary` рядом с портом, как `InMemoryWorkspaceSnapshotStore`; экспорт из бареля. 1.5 зелёный.

## 2. Итерация 2 — каталог тем на диске (`codelab_client_io`)

- [x] 2.1 `[client]` Красный: `packages/dart/codelab_client_io/test/themes/io_theme_library_test.dart` на временной папке. Spec client-themes «Каталог пользовательских тем» и «Импорт файла темы», все сценарии:
  - «Нет каталога тем», «Большой файл» (прочитано не больше 64 КиБ + 1 байт);
  - подкаталог и не `.json` не перечисляются; ссылка на файл читается; битая ссылка — запись с ошибкой;
  - «Импорт новой темы», «Битый файл не копируется», «Замена только с подтверждением» (временных файлов не осталось);
  - путь назначения не зависит от имени исходного файла (`../x.json`, имя с пробелами).
- [x] 2.2 `[client]` Реализация 2.1: `lib/src/themes/io_theme_library.dart` на `stores/json_file.dart`; экспорт; строка в `AGENTS.md` пакета §1. 2.1 зелёный.

## 3. Итерация 3 — палитра кита (`codelab_ui`)

- [x] 3.1 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_palette_test.dart` — widget-тест пользовательской темы (доказательство D-20). Spec agent-workbench-ui «Цвета кита из палитры темы» («Палитра из расширения», «Без расширения вид прежний») и MODIFIED «Блок кода в ответе агента» («Роль пользовательской темы с низким контрастом»): тег `Done`, `Failed`, ссылка markdown, комментарий в блоке кода `#3a3650`; у `CodeLabPalette` нет поля рамки одобрения, вид `CodeLabApprovalPrompt` от палитры не зависит (решение Q8).
- [x] 3.2 `[desktop]` Реализация 3.1: `atomics/codelab_palette.dart`, тоны `codelab_icon`, `codelab_badge`, `codelab_usage_pane`, ссылки `codelab_markdown_config` — через `CodeLabPalette.of` (D4); `CodeLabApprovalPrompt` не меняется. Пример в превью атомов. AGENTS.md кита §5 — строка о палитре. 3.1 зелёный, прежние тесты кита зелёные.
- [x] 3.3 `[desktop]` Красный: `test/codelab_file_preview_test.dart` — `warningLines` выделяет строки 6 и 9 тоном `warning`, `highlightLine` работает как раньше (D10).
- [x] 3.4 `[desktop]` Реализация 3.3: `CodeLabFilePreview.warningLines`. 3.3 зелёный.

## 4. Итерация 4 — оформление app

- [x] 4.1 `[desktop]` Красный: `apps/codelab_desktop/test/core/platform/app_appearance_preferences_test.dart`. Spec app-settings «Хранение оформления»: формат документа, поля по умолчанию, «Повреждённый документ» (ключ не перезаписан), тема чужого режима в поле режима, сбой открытия хранилища — значения по умолчанию и `readFailure`.
- [x] 4.2 `[desktop]` Реализация 4.1: `core/platform/app_appearance_preferences.dart` (D5). 4.1 зелёный.
- [x] 4.3 `[desktop]` Красный: `test/app/appearance/built_in_themes_test.dart` и `contrast_checks_test.dart`. Spec app-settings «Контраст на фоне кода» («Встроенные темы проходят» — три темы, акцент выключен и три значения системного акцента), «Режим оформления и темы режимов» («Стандартная тема не меняет вид» — значения `CodeLabPalette` и `CodeLabCodeTheme` для `light` и `dark` равны выведенным китом), формула WCAG на эталонных парах (`#000000`/`#ffffff` = 21:1).
- [x] 4.4 `[desktop]` Реализация 4.3: `lib/app/appearance/built_in_themes.dart`, `fluent_theme_builder.dart` (D4, D6), `features/settings/application/contrast_checks.dart` (D8). 4.3 зелёный.
- [x] 4.5 `[desktop]` Красный: `test/app/appearance/app_appearance_cubit_test.dart` на двойниках хранилища, `InMemoryThemeLibrary` и `FakeSystemAccentSource`. Spec app-settings:
  - «Темы двух режимов», «Удалённый файл темы» (выбор не перезаписан, `fallback`);
  - «Use переключает фиксированный режим», «Reset»;
  - «Системный акцент включён», ошибка канала — `accent` темы и `appearance.system_accent_failed`;
  - «Сбой записи» (`saveFailed`, `Retry`), три выбора подряд — сохранён последний, обогнанная запись не публикует состояние;
  - «Reload применяет исправленный файл»; поздний `reloadTheme` после `useTheme` того же режима отброшен;
  - `close()` ждёт идущую запись не дольше 3 с и отменяет подписку на акцент;
  - события «События журнала оформления» без имени пользовательской темы (`recording_logger.dart`, `no_text_leak.dart`).
- [x] 4.6 `[desktop]` Реализация 4.5: `AppAppearanceCubit`, `AppAppearanceState`, `AppAppearanceStart` (D13). 4.5 зелёный.
- [x] 4.7 `[desktop]` Красный: `test/app/codelab_app_appearance_test.dart`. Spec app-settings «Режим оформления и темы режимов»:
  - «Тёмная система» через `platformDispatcher.platformBrightnessTestValue` — текст композера, фокус и прокрутка ленты сохранены, `FluentApp` не пересоздан;
  - первый кадр — в оформлении из `AppAppearanceStart`;
  - файл темы не прочитан за 1 с — встроенная тема режима и `fallback` в `app.appearance_resolved`.

  `test/app/app_exit_wiring_test.dart` — шаг `appearance` в ветке записи настроек.
- [x] 4.8 `[desktop]` Реализация 4.7: `BlocBuilder` над `FluentApp` (`theme`, `darkTheme`, `themeMode`), чтение в `main` до `runApp` через `IoThemeLibrary`, шов `createCodeLabRootScope(appearance:)`, модуль событий старта, шаг выхода в `app_exit_handler.dart` (D13). 4.7 зелёный.
- [x] 4.9 `[desktop]` Красный:
  - `test/core/platform/system_accent_source_test.dart` — адаптер `SystemThemeAccentSource` на подменённом обработчике каналов `system_theme` (`TestDefaultBinaryMessenger`): цвет → ARGB; ответ без цвета и `MissingPluginException` — маркер `Color(0x00000000)` остаётся, `read()` даёт `null`, `supported == false`; исключение канала не теряется (ошибка `read()`, а не необработанное асинхронное исключение); на macOS и Windows `changes` отображает события `onChange`, на Linux — пустой поток; `UnsupportedSystemAccentSource.supported == false`. Spec app-settings «Системный акцент»: «Плагин не отдал цвет», «Платформа без системного акцента».
  - `test/app/appearance/app_appearance_cubit_test.dart` дополняется: «Пользовательская тема и системный акцент», «Linux без уведомлений» (`refreshSystemAccent` при открытии страницы — одно чтение).
  - правило сторожа `package:system_theme/` в `apps/codelab_desktop/lib` — только `core/platform/system_accent_source.dart` (D1): `import_guard_test.dart` с фиктивным нарушением.
- [x] 4.10 `[desktop]` Реализация 4.9: `system_theme: 3.3.0` (точный пин) в `dependencies` app, `melos bootstrap`; `core/platform/system_accent_source.dart` (порт, `SystemThemeAccentSource`, `UnsupportedSystemAccentSource`; D7); первое чтение в `main` до `runApp` с ограничением 1 с, выбор реализации по платформе — в composition root; `refreshSystemAccent()` в `AppAppearanceCubit`; правило в `rules.dart` с комментарием-причиной. Нативного кода в раннерах app нет. Ручная проверка на macOS: смена акцента в «Системных настройках» применяется сразу. 4.9 зелёный, `guard` зелёный.
- [x] 4.11 `[desktop]` Красный: «тёмная проверка» `test/app/dark_theme_sweep_test.dart` — рабочее место с лентой, доки, диалог одобрения и все видимые страницы настроек в `dark` и `high-contrast`: нет исключений рендера, у текста ключевых ролей контраст не ниже 4,5:1 к своему фону (риск «Тёмный режим впервые»).
- [x] 4.12 `[desktop]` Реализация 4.11: заменить найденные зашитые цвета ролями темы (только места, на которые указал тест). 4.11 зелёный.

## 5. Итерация 5 — страница «Appearance»

- [x] 5.1 `[desktop]` Красный: правило сторожа `package:file_selector/` в `apps/codelab_desktop/lib` — только `core/platform/` (D1; второе правило, `system_theme`, — задача 4.9): `packages/dart/codelab_architecture_tests/test/import_guard_test.dart` с фиктивным нарушением.
- [ ] 5.2 `[desktop]` Реализация 5.1: правило в `test/support/rules.dart` с комментарием-причиной. `guard` зелёный.
- [x] 5.3 `[desktop]` Красный: `test/features/settings/application/appearance_settings_cubit_test.dart` на `InMemoryThemeLibrary`, двойнике `ThemeFilePicker` и `FakeLocalFolderOpener`. Spec app-settings:
  - «Выбор карточки не применяет тему», выбор по умолчанию — действующая тема;
  - «Тема с двумя предупреждениями» (данные панели: строки 6 и 9, коды, подсказка, справка ролей), тема с ошибкой — данные `error`;
  - «Поздний результат чтения» (`appearance.catalog_discarded`), результат после `close()` отброшен;
  - импорт: «Импорт и превью», «Отказ от замены», `unchanged`, `invalid`, `failed` (без текста исключения), отмена выбора файла, повторный импорт во время идущего недоступен;
  - «Open folder» — `LocalFolderOpener.open(<home>/themes, create: true)`, файл не открывается;
  - «Низкий контраст пользовательской роли» — бейдж учитывает контраст.
- [ ] 5.4 `[desktop]` Реализация 5.3: `AppearanceSettingsCubit`, `AppearanceSettingsState`, `core/platform/theme_file_picker.dart`, фабрика `CodeLabDependencies.createAppearanceSettingsCubit` (D9, D11, D13). 5.3 зелёный.
- [x] 5.5 `[desktop]` Красный: `test/features/settings/presentation/appearance_page_test.dart` на Cubit-двойнике. Spec app-settings:
  - «Страница видна», «Поиск по ключевому слову», «Узкая область»;
  - порядок блоков и ключи тестов требования «Страница «Appearance»: видимость и состав»;
  - «Платформа без системного акцента»;
  - карточки: вид, теги `Light mode`/`Dark mode`, бейдж `N warnings` (ICU), `Invalid`;
  - «Preview» в цветах выбранной темы, строки контраста с вердиктом `AA`/`Low`;
  - доступность «Use» и «Reset»; InfoBar `settings-appearance-fallback`;
  - «Управляющие символы в файле» (U+202E экранирован);
  - русский интерфейс: переводы из `app_ru.arb`, имена тем, ключи, значения и `4.8:1` — как есть; `expectNoStaleLanguage` при смене языка на странице.
- [ ] 5.6 `[desktop]` Реализация 5.5: `appearance_page.dart`, `theme_issue_texts.dart`, построитель страницы в `settingsPageBuilders`, `SettingsPage.appearance` в `defaultSettingsPages`, ключевые слова поиска, ARB `en`/`ru` (D14, D15). Пополнить `language_switch_sweep_test.dart` страницей «Appearance». 5.5 зелёный, `l10n:check` зелёный, `ui_literals_test` зелёный без новых записей allowlist.
- [x] 5.7 `[desktop]` Интеграционный тест `apps/codelab_desktop/integration_test/settings_appearance_flow_test.dart`: импорт файла во временный `CODELAB_HOME`, превью, «Use», смена «Mode», перезапуск app — тема сохранена. Скрипт `test:e2e:app:appearance` в `pubspec.yaml`; запуск — только в `release/*`, в `feature/*` тест только компилируется.

## 6. Документация и закрытие строки

- [ ] 6.1 `docs-writer`: `apps/codelab_desktop/doc/user-guide.md` — раздел «Оформление»: режим и «Match system», системный акцент (macOS и Windows — сразу, Linux — цвет выделения GTK-темы при старте и открытии страницы), встроенные темы, своя тема (формат с примером, роли, `extends`, где лежит каталог), «Import JSON…», предупреждения и контраст, «Reload», что делать, если тема не загрузилась.
- [ ] 6.2 `docs-writer`: `apps/codelab_desktop/README.md` (возможности: тёмный режим и темы), `docs/user/configuration.md` (каталог `$CODELAB_HOME/themes/`, общий с будущими темами CLI), `apps/codelab_desktop/doc/operations.md` («Где лежат данные»: `themes/`, ключ `codelab.app.appearance`), `apps/codelab_desktop/doc/development.md` (порт системного акцента и адаптер `system_theme`).
- [ ] 6.3 `[desktop]`: `apps/codelab_desktop/AGENTS.md` — раздел «Страница «Appearance»» (владельцы, хранение, «App файлов не открывает», события, правила `file_selector` и `system_theme`); `packages/dart/codelab_client_core/AGENTS.md` — строка о `src/themes/` (языконезависимые коды).
- [ ] 6.4 `codelab-architect`: `docs/architecture/l10n-glossary.md` — термины D15.
- [ ] 6.5 `codelab-architect`: `agent-parity-goals.md`, строка D-20 — доказательства: `packages/flutter/codelab_ui/test/codelab_palette_test.dart`, `packages/dart/codelab_client_core/test/themes/theme_file_test.dart`, `apps/codelab_desktop/test/features/settings/presentation/appearance_page_test.dart`, приёмка `app:settings_appearance_flow_test.dart` (`release/*`); пометка «закрыто change `add-app-appearance-page`».
- [ ] 6.6 `docs-writer`, при подготовке выпуска в `release/*`: строка в разделе выпуска `CHANGELOG.md` — тёмный режим включается по системе («Match system» по умолчанию, Q3 (а)), системный акцент — пакетом `system_theme`.
- [ ] 6.7 Сверка перед архивацией: все сценарии spec покрыты тестами задач 1–5; design D-решения совпадают с кодом; `openspec validate add-app-appearance-page --strict` зелёный.
