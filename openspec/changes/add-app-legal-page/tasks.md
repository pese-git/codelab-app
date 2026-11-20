## Исполнители

- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, тест `packages/dart/codelab_architecture_tests/test/legal_documents_test.dart` и корневые правовые документы. Тексты документов и пользовательскую документацию пишет `docs-writer` (стандарт `.claude/skills/codelab-docs/SKILL.md`) в задачах с пометкой `docs-writer`.
- `[protocol]`, `[agent]`, `[client]` — задач нет: ACP, Dart-пакеты агента и клиента, CLI не меняются.
- `[site]` — задач нет: публикация на сайте отложена до решения о домене (proposal, «Не входит»).

TDD (`packages/dart/codelab_agent_core/AGENTS.md` §2): красный тест — отдельная задача и отдельный коммит до кода. Коммит — только по просьбе пользователя. Задача реализации ссылается на свой красный тест. Красный тест может опираться на заглушки сигнатур без поведения.

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm flutter analyze` / `fvm dart analyze` пакета;
- тесты пакета;
- `l10n:check` — при правке ARB.

`guard` — один раз в 7.2: меняется `pubspec.yaml` app (ресурсы), зависимости не меняются. `web-compile` не нужен: web-безопасные пакеты не меняются. Интеграционный тест app в `feature/*` только компилируется (§21).

`CHANGELOG.md` в этом change не правится: раздел выпуска, в том числе записи «Privacy» и «Terms» (§12.7.8), пишет ветка `release/<version>` (`AGENTS.md` §22, формат `CHANGELOG.md`).

## 0. Документы

- [x] 0.1 `[desktop]` `12-7-release-and-distribution.md`: §12.7.7 — «Языки» (схема `<ИМЯ>.md` и `<ИМЯ>.ru.md`, выбор по языку интерфейса) и «Перечень сетевых запросов — по текущей сборке»; §12.7.7а — язык показа, ассеты, сайт и состав change; §12.7.10 — `legal_documents_test` на четыре файла, имя интеграционного теста (D2, D3, D4).
- [x] 0.2 `[desktop]` `12-4-first-run-and-settings.md`: строка «Legal» §12.4.9, SETUP-17 — «Legal» видна всегда (D1).
- [x] 0.3 `[desktop]` `11-assumptions-and-open-questions.md` (язык решён, приоритет редакций открыт), `agent-parity-goals.md` D-18 и D-29, `09-14-stage-9-switch-default.md`: имя change `add-app-legal-page`.
- [x] 0.4 `[desktop]` `docs/architecture/l10n-glossary.md`, подраздел «Страница «Legal»». Термины: «Legal» — «Правовая информация», «Privacy policy» — «Политика конфиденциальности», «Terms of use» — «Условия использования», «License» — «Лицензия», «Third-party notices» — «Сторонние уведомления» (уже есть), «Search packages» — «Поиск пакетов», «Clear search» — «Очистить поиск», «No packages match» — «Нет подходящих пакетов», «No telemetry» — «Без телеметрии», «Package licenses» (уже есть), «Notices register» — «Реестр уведомлений». Строка таблицы «Юридические тексты» — `PRIVACY`/`TERMS` по языку интерфейса, `LICENSE` и реестр как есть (D2). Выполняется до ARB в 4.5.

## 1. Итерация 1 — документы и ресурсы

- [x] 1.1 `[desktop]` Красный: `packages/dart/codelab_architecture_tests/test/legal_documents_test.dart` (D3; spec licensing-and-attribution «Политика конфиденциальности и условия использования», сценарии «Нет русской редакции», «Даты редакций разошлись», «Раздел пропущен или переставлен», «Ссылки в README»). Проверяет:
  - есть все четыре файла;
  - первая строка соответствует формату своего языка, у пары одна дата;
  - обязательные заголовки второго уровня из таблицы D3 идут первыми и в порядке;
  - нет слов согласия;
  - `README.md` ссылается на `PRIVACY.md` и `TERMS.md`.

  Сообщение называет файл и ожидаемый заголовок. Красный: файлов нет.
- [ ] 1.2 `[desktop]` Реализация 1.1, `docs-writer`: черновики `PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md` в корне по D3:
  - дата редакции, заголовок, пометка о черновике;
  - разделы §12.7.7 и §12.7.7а; раздел 2 политики — только запросы текущей сборки (D3);
  - заполнители `<site>` и `<contact>`;
  - относительные ссылки на `LICENSE`, `THIRD_PARTY_NOTICES.md` и друг на друга (D8);
  - тексты свои, без копирования чужих политик (`AGENTS.md` §5).

  Корневой `README.md`: ссылки на оба документа в разделе о лицензии. 1.1 зелёный.
- [x] 1.3 `[desktop]` Красный: `apps/codelab_desktop/test/app/legal_assets_test.dart` (D4; spec licensing-and-attribution «Лицензия и сторонние уведомления в сборке app», сценарии «Русская редакция разошлась с корнем», «Ресурс не объявлен»):
  - `pairs` на шесть файлов;
  - каждый ресурс объявлен в `pubspec.yaml`, сообщение называет файл;
  - каждый файл каталога `assets/legal/` объявлен.

  Красный: копий нет.
- [x] 1.4 `[desktop]` Реализация 1.3: копии четырёх файлов в `apps/codelab_desktop/assets/legal/`, записи в `pubspec.yaml` (`flutter.assets`). Комментарий над списком ссылается на D4. 1.3 зелёный.

## 2. Итерация 2 — application страницы «Legal»

- [x] 2.1 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/application/package_license_search_test.dart` (D5; spec app-settings «Страница «Legal»: поиск по пакетам», сценарии «Совпадение без учёта регистра», «Все вхождения подсвечены», «Пустой запрос», «Ничего не найдено»). Ещё:
  - пробелы по краям запроса;
  - вхождения без перекрытия (`aaa` / `aa` — одно);
  - порядок сохраняется;
  - `total` не зависит от запроса;
  - имя, у которого нижний регистр меняет длину или в котором есть не-ASCII символ (`İstanbul`), попадает в выдачу без диапазонов.
- [x] 2.2 `[desktop]` Реализация 2.1: `features/settings/application/package_license_search.dart` (`PackageLicense`, `PackageSearch`, `PackageHit`, `searchPackageLicenses`). Doc-комментарии по `AGENTS.md` §15. 2.1 зелёный.
- [x] 2.3 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/application/legal_document_routing_test.dart` (D2, D8; spec «…документы на языке интерфейса», «…ссылки внутри документов»):
  - `legalAssetOf`: `ru` → `*.ru.md`, `en`, `de` и пустой код → английские, `LICENSE` и `THIRD_PARTY_NOTICES.md` от языка не зависят;
  - `legalLinkOf`: `TERMS.md`, `./LICENSE#x`, `PRIVACY.ru.md` → вкладка; `https://…` → внешняя; `http:`, `mailto:`, `file:`, `SECURITY.md`, `../PRIVACY.md` → нет;
  - `LegalTab.slug` и `logName`.
- [x] 2.4 `[desktop]` Реализация 2.3: `features/settings/application/legal_documents.dart` (`LegalTab`, `legalAssetOf`, `LegalLink`, `legalLinkOf`). 2.3 зелёный.
- [x] 2.5 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/application/legal_page_cubit_test.dart` (D7, D8, D10, D11) на портах-двойниках `LegalPorts` и записывающем логгере:
  - `open(null, 'en')` выбирает «Privacy policy» и читает только `PRIVACY.md`;
  - `open(LegalTab.termsOfUse, 'ru')` читает `TERMS.ru.md`;
  - документ читается один раз на ресурс;
  - `setLanguage('ru')` сохраняет вкладку и запрос и показывает `*.ru.md`;
  - ответ порта для `en`, пришедший после `setLanguage('ru')`, не меняет показанный документ;
  - результат после `close()` не выпускает состояний;
  - сбой чтения → `Failed` и `legal.document_load_failed` с `tab` и `error_type`, без пути;
  - реестр лицензий собирается один раз, при первой вкладке «Third-party notices», событие `legal.licenses_collected`;
  - `setQuery` и `clearQuery` пересчитывают `search` и не пишут ни одного события (маркер `marker-query-7f3a` не встречается в журнале);
  - `onDocumentLink` на `LICENSE` выбирает «License», на `https:` вызывает порт; исход `failed` даёт заметку `linkFailed`.
- [x] 2.6 `[desktop]` Красный: `apps/codelab_desktop/test/app/legal_ports_factory_test.dart` (D10; spec «…вкладка «Third-party notices»», сценарии «Пакет из записи с двумя именами», «Сбой реестра лицензий»). Сборщик `collectPackageLicenses(Stream<LicenseEntry>)`:
  - запись с двумя пакетами относится к каждому;
  - пакеты идут по имени;
  - ошибка потока даёт собранное и `failed: true`, без исключения.
- [x] 2.7 `[desktop]` Реализация 2.5–2.6:
  - `features/settings/application/legal_ports.dart`, `legal_page_state.dart`, `legal_page_cubit.dart`;
  - `lib/app/legal_ports_factory.dart` (`buildLegalPorts`, `collectPackageLicenses`) — единственное место `rootBundle` и `LicenseRegistry` для страницы;
  - `CodeLabDependencies.legalPorts`, шов `CodeLabTestBinding(legalPorts:)`.

  2.5 и 2.6 зелёные.

## 3. Итерация 3 — кит

- [x] 3.1 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_selector_bar_test.dart` (D6; spec «Страница «Legal»: видимость и вкладки», сценарий «Узкое окно на русском»):
  - ключи вкладок от вызывающего;
  - нажатие и Enter/Space вызывают `onChanged`, повторное нажатие на выбранную — нет;
  - семантика: подпись группы, `selected` у выбранной вкладки;
  - в ширину 400 px с длинными русскими подписями нет многоточия и переполнения, есть горизонтальная прокрутка;
  - цвета из `FluentTheme` в светлой и тёмной теме.
- [x] 3.2 `[desktop]` Реализация 3.1: `packages/flutter/codelab_ui/lib/src/molecules/codelab_selector_bar.dart`, экспорт через `molecules.dart`, пример в `codelab_molecule_previews.dart` (один экран — на `ru`), `codelab_previews_test.dart`. 3.1 зелёный.

## 4. Итерация 4 — страница «Legal» и навигация

- [x] 4.1 `[desktop]` Красный: навигация (D1; spec app-settings «Навигация настроек», сценарий «Legal — последний пункт группы «App»»; «Страница «Legal»: видимость и вкладки», сценарии «Последняя страница без вкладки», «Поиск страницы по ключевому слову»):
  - `test/app/navigation/navigation_cubit_test.dart`: `selectSettingsPage(legal, legalTab: termsOfUse)` выпускает `SettingsDestination` с вкладкой; `last_page` хранит `legal`; повторное открытие даёт `legalTab: null`;
  - тест оболочки настроек: `settings-nav-legal` последний в «App», поиск `privacy` и `конфиденциальность` (на `ru`);
  - `defaultSettingsPages` содержит `legal`.
- [ ] 4.2 `[desktop]` Реализация 4.1:
  - `SettingsPage.legal`;
  - `SettingsDestination.legalTab`, `NavigationCubit.selectSettingsPage(…, legalTab:)`;
  - `settings_titles.dart` (заголовок и ключевые слова), значок в `settings_shell.dart`, запись в `settingsPageBuilders`;
  - ARB `settingsPageLegal`, `settingsSearchKeywordsLegal`.

  4.1 зелёный.
- [x] 4.3 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/presentation/legal_page_test.dart` (spec «Страница «Legal»: видимость и вкладки», «…документы на языке интерфейса», «…ссылки внутри документов», «…вкладка «License»», «…вкладка «Third-party notices»» — все сценарии, кроме поиска). Плюс:
  - подпись `settings-legal-source` для каждой вкладки;
  - InfoBar `settings-legal-load-failed` и `settings-legal-link-failed` без пути и адреса;
  - на странице нет ключей кнопок артбордов из D12.

  Порты — двойники с фиктивными текстами ресурсов и реестра.
- [x] 4.4 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/presentation/legal_notices_search_test.dart` (spec «Страница «Legal»: поиск по пакетам», все сценарии; D6). Проверяет:
  - подсветку через `TextSpan` (жирные диапазоны), видимый текст и `Semantics` имени без изменений;
  - крестик только при непустом запросе;
  - блок `settings-legal-packages-empty` с экранированным запросом (bidi-символ показан как `‮`);
  - раскрытие пакета при запросе;
  - счётчик на `en` и `ru` (`5 из 21 пакета`);
  - записи реестра видны при каждом запросе;
  - «Запрос не сохраняется и не пишется в журнал»: уход со страницы и возврат через `NavigationCubit`, записывающий логгер, `SharedPreferences.setMockInitialValues`.
- [ ] 4.5 `[desktop]` Реализация 4.3–4.4:
  - `features/settings/presentation/legal_page.dart` (`buildLegalPage`, `LegalPage`): вкладки `CodeLabSelectorBar`, документы `CodeLabMarkdown` под `CodeLabMarkdownScope` страницы, «License» — `CodeLabKeyValueList` и `CodeLabMonospaceBlock`, «Third-party notices» — записи, InfoBar, поле, счётчик, список, пустой блок;
  - язык из `AppLanguageCubit` → `LegalPageCubit.setLanguage`;
  - ARB `en`/`ru` с `@description` и ICU `plural`.

  4.3 и 4.4 зелёные, `l10n:check` зелёный.

## 5. Итерация 5 — ссылки «General» и удаление диалога

- [x] 5.1 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/presentation/general_page_test.dart` (D9; spec «Страница «General»: состав и порядок» — сценарии «Порядок блоков», «No telemetry» ведёт на политику»; «Раздел «About» страницы «General»» — «Ссылки «About» открывают вкладки Legal», «Диалога сторонних уведомлений нет»; «События журнала страницы «General»» — «Переход на Legal в журнале»). Ожидания прежнего диалога `settings-general-third-party-dialog` в тесте заменяются ожиданием вкладки. Остальные сценарии «About» (версии, диагностика, сбои) зелёные без изменений.
- [ ] 5.2 `[desktop]` Реализация 5.1:
  - `general_page.dart` — блок «Privacy» и колбэк `onOpenLegal`;
  - `about_section.dart` — кнопки «Privacy policy», «Terms of use», ссылка `MIT`, «Third-party notices» на вкладку; `_ThirdPartyDialog` и импорт `LicenseRegistry` удалены;
  - `about_ports.dart` и `lib/app/about_ports_factory.dart` — без текста уведомлений в `AboutInfo`;
  - хост «General» связывает колбэк с `NavigationCubit` и пишет `settings.legal_link`;
  - `settingsSearchKeywordsGeneral` + `telemetry`/`телеметрия`; ARB.

  Ненужные сообщения ARB диалога (`settingsGeneralAboutClose`) удаляются, подпись реестра и `Package licenses` переходят на страницу «Legal». 5.1 зелёный. `test/app/dark_theme_sweep_test.dart` проходит страницу «Legal» через `defaultSettingsPages` без правки.

## 6. Итерация 6 — документация (`docs-writer`)

- [ ] 6.1 `[desktop]` `apps/codelab_desktop/doc/user-guide.md`:
  - раздел о странице «Legal»: вкладки, язык документов, офлайн, поиск по пакетам, почему список лицензий шире сборки;
  - раздел «General»: блок «Privacy», ссылки «About», диалога больше нет.

  Скриншот — пометка `<!-- screenshot: … -->` по образцу.
- [ ] 6.2 `[desktop]` `apps/codelab_desktop/AGENTS.md`:
  - новый раздел «Страница «Legal»» (D1–D11): Cubit и время жизни, ресурсы по языку, `legal_ports_factory.dart` — единственное место `rootBundle`/`LicenseRegistry`, поиск — чистая функция, запрос не пишется в журнал, события, тесты;
  - раздел «Страница «General»»: блок «Privacy», диалога нет, `settings.legal_link`.
- [ ] 6.3 `[desktop]` `packages/flutter/codelab_ui/AGENTS.md` §4 и `packages/flutter/codelab_ui/README.md` — `CodeLabSelectorBar` (D6).
- [ ] 6.4 `[desktop]` `docs/user/README.md` — ссылка на `PRIVACY.md` и `TERMS.md` рядом с перечнем документов (документы общие для CLI и app). Сверка ARB с глоссарием 0.4: новые термины, найденные при реализации, дописываются в глоссарий.

## 7. Итерация 7 — приёмка

- [ ] 7.1 `[desktop]` `apps/codelab_desktop/integration_test/settings_legal_flow_test.dart` и скрипт `test:e2e:app:legal` в `melos:` корневого `pubspec.yaml` по образцу `test:e2e:app:appearance` (§12.7.10). Сценарий:
  - «General» → «About» → «Terms of use»: вкладка с текстом `assets/legal/TERMS.md`;
  - переход на «License» и «Third-party notices»;
  - поиск `flutter` → `M of N`, затем `reqwest` → «No packages match» → «Clear search»;
  - русский интерфейс: `TERMS.ru.md`.

  В `feature/*` только компилируется, запускается в `release/*` (§21).
- [ ] 7.2 `[desktop]` Проверки затронутого (`AGENTS.md` §21):
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm flutter analyze` в `apps/codelab_desktop` и `packages/flutter/codelab_ui`, `fvm dart analyze` в `codelab_architecture_tests`;
  - тесты трёх пакетов;
  - `melos run l10n:check`, `melos run guard`;
  - `openspec validate add-app-legal-page --strict`;
  - `cd site && npm ci && npm run verify`, если установлен Node: правится опубликованный `README.md`.
- [ ] 7.3 `[desktop]` Ручная проверка app на macOS:
  - четыре вкладки на `en` и `ru`;
  - смена языка при открытой странице;
  - минимальное окно 800 px на русском;
  - тёмная тема;
  - VoiceOver: группа вкладок и выбранная вкладка, крестик «Clear search»;
  - ссылки `TERMS.md` → «License»;
  - поиск по пакетам и пустой блок;
  - ссылки «General» и «About»;
  - запрос не появился в журнале отладки.
- [ ] 7.4 `[desktop]` PR в `develop` — только по просьбе пользователя. В описании:
  - запущенные проверки и что полный `check` не запускался;
  - документы — черновики до юридической проверки;
  - порядок архивации после `add-app-general-page` (design.md).
