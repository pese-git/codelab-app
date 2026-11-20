## Context

Источники:
- `dart-agent-and-clients` §12.7.7 (политика, языки, перечень сетевых запросов), §12.7.7а (условия, страница «Legal», поиск по пакетам), §12.7.10 (`legal_documents_test`, `app:legal_page_test.dart`), §12.4.9 (строка «Legal», SETUP-17); `agent-parity-goals.md` D-18, D-29, E-21;
- артборды `docs/design/claude-design/`: `Legal` (32), `Terms` (33), `License` (34), `Notices` (35), `NoticesSearch` (35a), `NoticesMatch` (35b), `NoticesEmpty` (35c), граф `NavApp`, артборд `General` (блок «Privacy» и «About») и их `*-dark` копии. Это reference: тексты и раскладка взяты оттуда, разметка не копируется;
- design.md change `add-app-general-page`: D11 (порты «About»), D13 (ассеты, `thirdPartyRecordsOf`, `LicenseRegistry`, язык реестра), D17 (порядок блоков «General»);
- design.md change `add-app-keyboard-page`: D6 (поиск страницы — чистая функция), D7 (страница, содержимое которой задаёт сборка, видна всегда);
- `docs/architecture/state-management.md` (Cubit, неизменяемое состояние), `observability.md` (что не пишется в журнал), `concurrency.md` (поздние результаты);
- вложенные `AGENTS.md`: `apps/codelab_desktop` (страницы «General», «Keyboard», тесты), `packages/flutter/codelab_ui` (нет логики, новый виджет — при необходимости, превью и тест).

Состояние `develop` на 2026-11-20 (проверено по коду):
- `apps/codelab_desktop/lib/features/settings/` содержит страницы General, Appearance, Keyboard и Skills. Changes `add-app-general-page`, `add-app-keyboard-page`, `add-app-appearance-page` и `add-app-skills-page` реализованы и ещё не архивированы. У General не сделаны задачи 4.1–4.2 («Show ignored files»), у остальных — приёмка и PR;
- в `SettingsPage` 11 значений, последнее — `keyboard`;
- `AboutSection` показывает диалог `settings-general-third-party-dialog` (`_ThirdPartyDialog`): записи через `thirdPartyRecordsOf`, лицензии через `LicenseRegistry.licenses` прямо из presentation;
- `assets/legal/` содержит `LICENSE` и `THIRD_PARTY_NOTICES.md`, их сверяет `test/app/legal_assets_test.dart`;
- `PRIVACY.md`, `TERMS.md` и `SECURITY.md` в корне нет;
- онбординга в app нет;
- web-инструментов и проверки обновлений в коде нет. Сетевые вызовы: провайдер модели (ядро), проверка `/models` провайдера (`codelab_setup`, `http_provider_check.dart`), MCP streamable HTTP (`codelab_agent_mcp`), транспорты ACP stdio и WebSocket к внешнему агенту;
- `fluent_ui` 4.17.0: виджета `SelectorBar` нет, есть только `TabView` (вкладки браузерного типа). В ките есть `CodeLabSegmentedControl` (`molecules/codelab_form.dart`);
- `CodeLabMarkdown` (`gpt_markdown`) рисует таблицы. Политику ссылок и изображений он получает из `CodeLabMarkdownScope`.

**Goals:** документы D-18 и D-29 на двух языках с тестом разделов; страница «Legal» с четырьмя вкладками офлайн; поиск по пакетам по §12.7.7а; ссылки «General»; один текст уведомлений в одном месте.

**Non-Goals:** публикация на сайте и в релизе, `codelab --help`, установщик, `network-inventory.yaml`, onboarding, кнопки артбордов без поведения (D12), юридическая проверка, изменения ACP.

## Затронутые пакеты и зависимости

| Пакет (ADR-0002) | Что меняется | Исполнитель |
|---|---|---|
| `apps/codelab_desktop` | `features/settings/application/` (`legal_documents.dart`, `package_license_search.dart`, `legal_ports.dart`, `legal_page_state.dart`, `legal_page_cubit.dart`, `about_ports.dart`), `presentation/` (`legal_page.dart`, `general_page.dart`, `about_section.dart`, `settings_shell.dart`, `settings_titles.dart`), `lib/app/` (`navigation/*`, `legal_ports_factory.dart`, `about_ports_factory.dart`, сборка зависимостей), `assets/legal/`, `pubspec.yaml`, ARB | `[desktop]` |
| `packages/flutter/codelab_ui` | `molecules/codelab_selector_bar.dart`, барель, превью, тест | `[desktop]` |
| `packages/dart/codelab_architecture_tests` | только тест `legal_documents_test.dart` | `[desktop]` |
| корень репозитория | `PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md`, `README.md` | `[desktop]` (текст — `docs-writer`) |

Направление зависимостей не меняется: `presentation → application`, `lib/app` собирает порты. `rootBundle` и `LicenseRegistry` страница получает только через порт `LegalPorts` из `lib/app/legal_ports_factory.dart`; в application нет `package:flutter/widgets.dart` и `BuildContext`. Новых пакетов, рёбер графа и записей allowlist нет (D13).

## Decisions

### D1. Страница «Legal» и модель вкладок

- `SettingsPage.legal(SettingsGroup.app, 'legal')` — последнее значение enum. Порядок §12.4.9 сохраняется, комментарий «одиннадцати страниц» исправляется. Composition root включает страницу в `SettingsPages.available` всегда. Содержимое страницы задают ресурсы сборки, а не конфигурация (SETUP-17, как «Keyboard» D7). Если документ не читается, это сбой сборки: его показывает InfoBar на вкладке, а страница не прячется.
- Вкладки — `enum LegalTab { privacyPolicy, termsOfUse, license, thirdPartyNotices }` в `application/legal_documents.dart`. У каждого значения есть `slug` (`privacy-policy` …) для ключей теста и `logName` (`privacy_policy` …) для журнала.
- **Вкладку при открытии задаёт навигация.** `SettingsDestination` получает необязательное поле `LegalTab? legalTab`, оно входит в равенство. `NavigationCubit.selectSettingsPage(page, {LegalTab? legalTab})` передаёт его только для `SettingsPage.legal`. Пункт навигации, поиск и `last_page` дают `null`, а `null` означает «Privacy policy». Значение `codelab.settings.last_page` остаётся `legal` без вкладки.
- Внутри страницы вкладку меняет `LegalPageCubit` (D7), навигация в этом не участвует.

Альтернативы:
- *четыре страницы настроек вместо вкладок* — отклонено: §12.4.9 и артборды задают одну страницу «Legal»;
- *вкладка в `last_page` (`legal/terms-of-use`)* — отклонено: новая семантика хранения ради экрана, который открывают редко. Возврат к политике предсказуем;
- *строковый «якорь раздела» в `SettingsDestination` для всех страниц* — отклонено: второго употребления нет (AGENTS.md §13), а строка теряет проверку типов;
- *app-scoped `LegalTabCubit`, в который «About» пишет вкладку перед переходом* — отклонено: тогда нужны два шага без атомарности и состояние, которое живёт дольше страницы.

### D2. Языки документов и выбор ресурса

**Схема имён** (решение пользователя 2026-11-20 — оба языка). `<ИМЯ>.md` — английская редакция, `<ИМЯ>.<код языка ISO 639-1>.md` — перевод: `PRIVACY.md` и `PRIVACY.ru.md`, `TERMS.md` и `TERMS.ru.md`. Почему английская без суффикса:
- адреса из §12.7.7 и §12.7.7а (`<сайт>/privacy`, каталог релиза, `codelab --help`, README) остаются прежними;
- GitHub и другие инструменты находят `PRIVACY.md` по общепринятому имени;
- третий язык добавляется файлом `PRIVACY.<код>.md` без переименований.

Выбор: `legalAssetOf(LegalTab tab, String languageCode)` — чистая функция. `ru` даёт `assets/legal/PRIVACY.ru.md` и `assets/legal/TERMS.ru.md`, любой другой код — английские файлы. `LICENSE` и `THIRD_PARTY_NOTICES.md` от языка не зависят. Язык — языковой код действующей локали `AppLanguageCubit` (язык интерфейса app), а не системы: документ не должен быть на другом языке, чем подписи вокруг него. Страница передаёт язык Cubit-у при сборке (`setLanguage`); смена языка подменяет документ текущей вкладки, а вкладка и запрос остаются.

Альтернативы:
- *каталоги `legal/en/`, `legal/ru/`* — отклонено: §12.7.7 фиксирует `PRIVACY.md` в корне;
- *один двуязычный файл* — отклонено: решение пользователя, и тест разделов пришлось бы писать по двум половинам файла;
- *`PRIVACY_ru.md`* — отклонено: точка перед кодом языка — распространённая схема, она не путается с частью имени.

Какая редакция действует при расхождении — вопрос юридической проверки (открытые вопросы). До ответа документы этого не утверждают.

### D3. Содержание документов и `legal_documents_test`

Формат каждого файла:

```text
Last revised: 2026-11-20            ← в русской редакции: «Редакция от 2026-11-20»

# CodeLab Privacy Policy            ← «# Политика конфиденциальности CodeLab»

Draft pending legal review. …       ← «Черновик до юридической проверки. …»

## 1. No telemetry
…
```

Обязательные заголовки второго уровня (тексты фиксирует тест, порядок — §12.7.7 и §12.7.7а; английские взяты из артбордов 32, 33):

| Документ | `en` | `ru` |
|---|---|---|
| политика | `1. No telemetry` | `1. Телеметрии нет` |
| | `2. Network requests` | `2. Сетевые запросы` |
| | `3. What is stored on this computer` | `3. Что хранится на компьютере` |
| | `4. Third-party policies` | `4. Сторонние политики` |
| | `5. Contact and changes` | `5. Контакт и изменения` |
| условия | `1. Status and the license` | `1. Статус условий и лицензия` |
| | `2. Your use and responsibility` | `2. Использование и ответственность пользователя` |
| | `3. Services you connect` | `3. Сторонние сервисы` |
| | `4. No warranty, limited liability` | `4. Отказ от гарантий и ограничение ответственности` |
| | `5. Model output` | `5. Содержимое, сгенерированное моделью` |
| | `6. Changes and contact` | `6. Изменения и контакт` |

Другие заголовки второго уровня допускаются после обязательных (например, «применимое право» после юридической проверки). Тест проверяет, что обязательные заголовки идут первыми и в своём порядке.

- **Раздел 2 политики — по текущей сборке.** Перечислены: провайдер модели (каждый ход), проверка ключа провайдера (`GET /models` при настройке провайдера), MCP-серверы (вызов инструмента), внешний ACP-агент, которого подключил пользователь (stdio-процесс или WebSocket). Web-инструменты и проверка обновлений не описываются, пока их нет в коде. Политика, которая описывает несуществующий запрос, так же неверна, как политика, которая молчит о существующем (REL-9). Строку добавляет change самой функции. Этот принцип записан в §12.7.7 («Перечень сетевых запросов — по текущей сборке»). Ссылки, которые пользователь открывает сам («Release notes», `https:` в документах), открывает браузер, а не app. Политика говорит об этом одной фразой.
- **Заполнители.** `<site>` — адрес сайта, `<contact>` — адрес для вопросов. `SECURITY.md` нет, и `<contact>` в §12.7.7 берётся из него. Реальные значения не выдумываются.
- **Пометка о черновике** стоит в самом тексте, поэтому видна и на GitHub, и в app. Снимает её юридическая проверка. Тест пометку не требует: после проверки её удаляют без правки теста.
- **Тест** `packages/dart/codelab_architecture_tests/test/legal_documents_test.dart` (место из §12.7.10; пакет уже читает файлы репозитория в `parity_evidence_test.dart`). Он читает корневые файлы и проверяет:
  1. все четыре файла есть;
  2. первая строка соответствует `^Last revised: \d{4}-\d{2}-\d{2}$` или `^Редакция от \d{4}-\d{2}-\d{2}$`, а дата у пары одинаковая;
  3. обязательные заголовки — первые заголовки второго уровня, в порядке таблицы;
  4. в тексте нет слов согласия вроде `I agree`, `accept these terms`, `--accept-terms`, `Принимаю` (§12.7.7а, «без принятия»).

  Сверку копий тест не делает: её делает `legal_assets_test.dart` (D4, «второго теста сверки нет»).

Альтернатива — *тест в app* — отклонена: документы общие для CLI и app, и проверка не должна зависеть от Flutter.

### D4. Ассеты и сверка копий

`assets/legal/` получает четыре новые побайтные копии, `pubspec.yaml` перечисляет каждый файл. Существующий `test/app/legal_assets_test.dart` расширяется:
- таблица `pairs` из шести файлов;
- проверка `pubspec.yaml` для каждого ресурса, с именем файла в сообщении;
- тест «каждый файл `assets/legal/` объявлен»: лишняя копия без объявления не пропадёт из сборки молча.

Почему копии, а не ссылка на корень: Flutter не принимает ресурсы вне каталога пакета (D13 `add-app-general-page`).

### D5. Поиск по пакетам: модель и чистая функция

`application/package_license_search.dart`:
- `PackageLicense { String name; List<String> licenses }`. **Пакет** — уникальное имя из `LicenseEntry.packages`. Запись с несколькими именами добавляет свой текст каждому из них, как в нынешнем `_ThirdPartyDialogState._collect`. Список упорядочен по `name` (`compareTo`, как в диалоге) и собирается один раз. Число пакетов `N` — длина списка;
- `searchPackageLicenses(List<PackageLicense> all, String query) → PackageSearch { int total; String needle; List<PackageHit> hits }`, где `PackageHit { PackageLicense package; List<(int start, int end)> ranges }`;
- `needle = query.trim().toLowerCase()`. Пустой `needle` возвращает все пакеты без диапазонов;
- иначе пакет попадает в выдачу, если `name.toLowerCase().contains(needle)`. Диапазоны — все вхождения слева направо без перекрытия: следующий поиск идёт с конца предыдущего вхождения, поэтому `aaa` по запросу `aa` даёт одно вхождение;
- если `name.toLowerCase().length != name.length` (редкая Unicode-свёртка), пакет попадает в выдачу без подсветки. Неверная подсветка хуже её отсутствия. Имена pub — ASCII `[a-z0-9_]`, так что ветка защитная;
- порядок `all` сохраняется. Функция не бросает и не знает виджетов.

Почему не фильтр по составу сборки: D13 `add-app-general-page` (список шире сборки юридически безопасен). Поиск меняет только показ, полный список остаётся в состоянии (§12.7.7а).

### D6. Виджеты: вкладки, подсветка, поле, пустой блок

- **`CodeLabSelectorBar<T>`** — новая молекула кита (`molecules/codelab_selector_bar.dart`). Параметры: `items` (значение, подпись, ключ), `value`, `onChanged`, `semanticLabel`. Вкладки идут в ряд с полосой под выбранной и прокручиваются по горизонтали, если не помещаются; подписи не обрезаются. Семантика: контейнер с `semanticLabel`, у каждой вкладки `selected` и `button`. Фокус и Enter/Space — через `CodeLabPressable`. Логики нет: что выбрано, решает вызывающий.
  - *`CodeLabSegmentedControl`* отклонён: варианты в `Flexible` с многоточием обрезают «Политика конфиденциальности» в теле 400 px (минимальное окно 800 px), а семантика у него — взаимоисключающие кнопки, а не вкладки;
  - *Fluent `TabView`* отклонён: это вкладки документов браузерного типа (закрытие, перетаскивание), не переключатель разделов;
  - *своя `Row` в app* отклонена: правило кита «вид — в ките», и такие же вкладки нужны артбордам «Legal» смартфона и планшета (P13–P16, T7–T10).
- **Подсветка** — `Text.rich` в `presentation/legal_page.dart`: `TextSpan` по диапазонам `PackageHit.ranges`. Совпавшая часть — полужирная, на фоне цвета выделения темы (`FluentTheme`, палитра `CodeLabPalette` при наличии). Вся строка обёрнута в `Semantics(label: name)` с `excludeSemantics`, чтобы чтение с экрана не дробилось на части. Отдельный виджет кита не вводится: употребление одно (AGENTS.md кита §3, «новый атом — при втором употреблении»).
- **Поле** — Fluent `TextBox` с `prefix` (значок поиска) и `suffix`: `IconButton` очистки `settings-legal-packages-clear` с `Semantics(label: Clear search)`, только при непустом запросе. `TextEditingController` живёт в `State` поля и синхронизирован с `LegalPageCubit.state.query`: Cubit — источник истины, контроллер — механизм ввода, как в образце «Keyboard».
- **Пустой блок** `settings-legal-packages-empty`: заголовок, текст с запросом через `escapeForDisplay` (запрос — недоверенный ввод, bidi-символы в нём перевернули бы строку) и `Button` `settings-legal-packages-empty-clear`.
- **Счётчик** — ARB с ICU `plural`: `settingsLegalPackagesCount(count)` и `settingsLegalPackagesMatched(matched, total)`. В `ru` у «из N» формы `one{# пакета} few{# пакетов} many{# пакетов} other{# пакета}`.
- **Документы** рисует `CodeLabMarkdown(id: 'legal-<slug>-<lang>', text: …)` под `CodeLabMarkdownScope` страницы (D8). Полный текст `LICENSE` — `CodeLabMonospaceBlock` (текст как есть, с переносом и выделением). Краткое содержание MIT — три строки `CodeLabKeyValueList` из ARB.

### D7. `LegalPageCubit`: состояние и время жизни

Почему Cubit, хотя у «Keyboard» запрос живёт в `State` (D6 того change): здесь есть асинхронные данные (ресурсы и поток `LicenseRegistry`), сбои с журналом, вкладка, которую задают снаружи, и смена языка во время загрузки. Это application state с переходами, которые надо проверять отдельно от виджетов (AGENTS.md §8, §12).

Состояние (`legal_page_state.dart`, неизменяемое, с `==`):

```text
LegalPageState
  tab: LegalTab
  languageCode: String
  documents: Map<String asset, DocumentLoad>      // DocumentLoad = Loading | Loaded(text) | Failed
  packages: PackagesLoad                          // NotRequested | Collecting | Collected(list, failed)
  query: String
  search → PackageSearch                          // производное: searchPackageLicenses(packages, query)
  shownAsset → legalAssetOf(tab, languageCode)
```

Методы:
- `open(LegalTab? initial, String languageCode)` — вызывается при создании;
- `selectTab(LegalTab, {source})`;
- `setLanguage(String)`;
- `setQuery(String)` и `clearQuery()`;
- `onDocumentLink(Uri)` (D8).

Правила:
- **Владелец и время жизни.** `buildLegalPage` создаёт Cubit через `BlocProvider(create:)` на каждое открытие страницы. Уход со страницы закрывает его, поэтому запрос и вкладка не переживают страницу (§12.7.7а), а ключа `shared_preferences` нет. Порты приходят из `CodeLabDependencies.legalPorts`.
- **Ленивая загрузка.** Документ читается при первом показе вкладки и кэшируется по пути ресурса. Реестр лицензий собирается один раз, при первом открытии вкладки «Third-party notices».
- **Поздние результаты.** Результат чтения кладётся в `documents[asset]`, а показ берёт `documents[shownAsset]`. Поэтому ответ для старой вкладки или прежнего языка заполняет кэш, но не попадает на экран. Номер попытки не нужен: состояние адресуется ресурсом, а не порядком запросов. После `close()` результат отбрасывается проверкой `isClosed`. Ошибки чтения не теряются: они становятся `Failed` и пишутся событием `legal.document_load_failed` (D11).
- **Поиск** — синхронный `setQuery`: пересчёт функции D5 на сотне-другой имён дешевле, чем дебаунс с таймером. Запрос и производные значения в журнал не идут.

### D8. Ссылки внутри документов

Страница оборачивает документы в `CodeLabMarkdownScope` со своей политикой (`application/legal_documents.dart`, `legalLinkOf(Uri) → LegalLink`):
- `tab(LegalTab)` — относительный путь без схемы и хоста, имя файла (после `./`, без якоря) из набора `PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`. Переключает вкладку; язык показа остаётся языком интерфейса, даже если ссылка указывает на файл другого языка;
- `external(Uri)` — схема `https`, открытие через `ExternalLinkOpener` из `LegalPorts`. Исход `failed` или `rejectedScheme` показывает InfoBar `settings-legal-link-failed` (`Couldn't open the link.`) без адреса;
- `none` — всё остальное (`http:`, `mailto:`, `file:`, `SECURITY.md`, `CHANGELOG.md`): ссылка неактивна (`canOpenLink` → `false`).

Изображения: `canLoadImage` → `false`. В правовых текстах изображений нет, а загрузка по сети нарушила бы «офлайн».

Почему относительные ссылки: документы читают и на GitHub, где `TERMS.md` → `LICENSE` работает как обычная ссылка. В app та же ссылка переключает вкладку, а не открывает репозиторий.

### D9. Навигация из «General» и судьба диалога

- `GeneralPage` получает колбэк `onOpenLegal(LegalTab tab, LegalLinkSource from)`. Хост страницы (`buildGeneralPage`) связывает его с `navigationCubit.selectSettingsPage(SettingsPage.legal, legalTab: tab)` и пишет `settings.legal_link`. Виджеты не знают `NavigationCubit`.
- **Блок «Privacy»** (артборд «26 General»): строка `CodeLabSettingsRow` «No telemetry» с описанием и `HyperlinkButton` «Privacy policy». Он стоит между «Startup and files» и «About». Переключателя нет: E-21 — Won't, выключать нечего. Строка не выдаёт себя за настройку, это справка со ссылкой.
- **«About»**: значение строки «License» `MIT` — `HyperlinkButton` (`settings-general-about-license`) на вкладку «License». К кнопкам добавлены «Privacy policy» и «Terms of use». «Third-party notices» сохраняет ключ `settings-general-about-third-party`, но теперь открывает вкладку.
- **Диалог удаляется**: `_ThirdPartyDialog` и чтение `LicenseRegistry` из presentation уходят. Правила D13 `add-app-general-page` (только `## Записи`, полный файл при отсутствии раздела, подпись о языке реестра, `LicenseRegistry` без фильтра, сбой не прячет уведомления) переходят на вкладку без изменений. `thirdPartyRecordsOf` переиспользуется как есть. Из `AboutInfo` уходит поле текста уведомлений, его больше никто не читает. `AboutPorts.info` по-прежнему читает `LICENSE` для строки «License».
- Событие `settings.about_action` теряет `action: third_party`: переход теперь пишет `settings.legal_link`, и двух событий на одно нажатие не будет.

Альтернатива — *оставить диалог и добавить вкладку* — отклонена: §12.7.7а прямо требует, чтобы один текст не жил в двух местах.

### D10. Вкладка «Third-party notices»

Содержимое и правила — D13 `add-app-general-page` с поиском §12.7.7а сверху. Порт `LegalPorts.packageLicenses` (`Future<CollectedLicenses> Function()`, где `CollectedLicenses = (List<PackageLicense> packages, bool failed)`) реализован в `lib/app/legal_ports_factory.dart` и обходит `LicenseRegistry.licenses`. При сбое потока он возвращает собранное с `failed: true` и не бросает. Известное ограничение (список шире сборки) показывает InfoBar `settings-legal-packages-info` словами артборда 35. Пока реестр собирается, счётчика нет, поле поиска уже доступно: запрос применяется, когда список придёт.

### D11. Наблюдаемость

Логгер — `codelab_desktop.settings`. События:
- `legal.tab_selected` (`tab`, `source: open | tab | link`, `debug`);
- `legal.document_load_failed` (`tab`, `error_type`, `warning`);
- `legal.licenses_collected` (`packages`, `failed`, `info`) — один раз за открытие;
- `legal.link_opened` (`target: tab | external`, `outcome`);
- на «General» — `settings.legal_link` (`from: privacy_block | about`, `tab`).

Никогда не пишутся:
- запрос поиска, его длина и число совпадений: по запросу видно, что пользователь искал, а пользы для диагностики нет (`observability.md`, минимизация);
- пути ресурсов и URL ссылок;
- тексты документов;
- тексты исключений, только имя типа.

Проверяет сценарий спецификации «Запрос не сохраняется и не пишется в журнал» с маркером `marker-query-7f3a` в записывающем логгере.

### D12. Отступления от артбордов

Не показываются, потому что в сборке у них нет поведения (SETUP-17):
- «Copy link» и «Open on the web» — домен `<сайт>` не решён;
- «Copy all» — копирование всех уведомлений не описано в §12.7.7а;
- «Open LICENSE» — внешнего файла нет, текст уже на вкладке;
- оглавление «On this page» — у `CodeLabMarkdown` нет прокрутки к якорю, и вводить её ради оглавления — отдельная работа;
- InfoBar «In short» — это текст документа, а не app: краткое изложение без юридической проверки на экране расходилось бы с документом.

Подпись источника берёт из артборда только то, что верно в сборке: `Bundled with CodeLab <version> as <asset> · readable offline`, без `[SITE]` и `codelab --help`.

### D13. Сторож, зависимости, граф

- Новых зависимостей нет: markdown — `CodeLabMarkdown` (`gpt_markdown` уже в ките), вкладки — своя молекула на `fluent_ui`. AGENTS.md §4 не задет.
- Allowlist ядра (PKG-2) не затронут: ядро и `codelab_agent_*` не меняются. `desktopAllowlist` не меняется.
- **Новое правило сторожа не нужно.** Пакетных импортов нет, `rootBundle` и `LicenseRegistry` — внутреннее дело app. Их место (`lib/app/legal_ports_factory.dart`) записывается в `apps/codelab_desktop/AGENTS.md` и проверяется ревью. Правило на один файл без второй точки нарушения — церемония (§13).
- Граф пакетов в `README.md` не меняется: новых пакетов и рёбер нет. Веб-безопасные пакеты не меняются, `web-compile` не нужен.

## Порядок архивации и пересечения

- **`add-app-general-page`** архивируется первым. Этот change MODIFIED-ит его требования «Страница «General»: состав и порядок», «Раздел «About» страницы «General»», «События журнала страницы «General»» и «Лицензия и сторонние уведомления в сборке app». Если General ещё не в архиве на момент архивации этого change, сначала архивируется он. Его незавершённые задачи 4.1–4.2 («Show ignored files») не пересекаются с этим change: пункт 3 состава блоков перенесён без изменений.
- **`add-app-keyboard-page`**: общий только enum `SettingsPage`. Значение `legal` добавляется после `keyboard`. Требование «Навигация настроек» keyboard не меняет, конфликта дельт нет.
- **`add-app-appearance-page`**: страница «Legal» добавляется в `test/app/dark_theme_sweep_test.dart` (тёмная тема, артборды `*-dark`), если тест перечисляет страницы.
- **`add-app-skills-page`**: пересечений нет.
- **`switch-default-agent-to-dart`** упоминает рабочее имя `add-privacy-policy` в своих документах. Они не правятся: имя исправлено в `docs/architecture` (§12.7.7а, 09-14, `agent-parity-goals.md`).

## Risks / Trade-offs

- **[Черновики выглядят как действующие правила]** → пометка в первой строке после заголовка на обоих языках. Юридическая проверка до 1.0 — условие задачи 9.4 (§11).
- **[Политика расходится с кодом]** → раздел 2 по текущей сборке (D3) и ревью раздела в каждом change с сетевым вызовом. Автоматический сторож (`network-inventory.yaml`) — задача 9.4. До него риск закрыт только процессом.
- **[Редакции en и ru разошлись по смыслу]** → тест ловит только даты и разделы, смысл сверяет человек. Строка в чек-листе PR change, который правит документ.
- **[Копии отстали от корня]** → `legal_assets_test.dart` на все шесть файлов (D4).
- **[Запрос утёк в журнал или состояние]** → запрос живёт только в Cubit страницы, тест с маркером (D11).
- **[Поздний результат загрузки показан не на той вкладке или языке]** → состояние адресуется ресурсом (D7). Тест Cubit-а: смена языка до ответа порта.
- **[Строка без поведения «No telemetry»]** → это справка со ссылкой, а не настройка (D9). Если ревью решит иначе, блок сводится к одной ссылке.
- **[Русские подписи вкладок]** → горизонтальная прокрутка `CodeLabSelectorBar`, сценарий «Узкое окно на русском».

## Migration Plan

Миграции данных нет. Новых ключей хранения нет, `last_page = legal` появляется только после выбора страницы. Откат change удаляет страницу, и `SettingsPage.fromSlug('legal')` на старой сборке вернёт `null`, а значит «Connection». Это уже существующее поведение для неизвестного slug.

## Open Questions

1. Кто проводит юридическую проверку `PRIVACY*.md`, `TERMS*.md` и краткого содержания MIT, и как отмечается результат (снятие пометки, запись в `CHANGELOG.md`)?
2. Какая редакция действует при расхождении — английская или русская? Нужна ли об этом фраза в документах?
3. Домен `<сайт>` (и совпадает ли он с сайтом `project-site`) и адрес `<contact>`. Нужен ли `SECURITY.md` в этом change или отдельно?
4. Блок «Privacy» на «General»: строка «No telemetry» со ссылкой (как на артборде) или одна ссылка «Privacy policy» без строки?
