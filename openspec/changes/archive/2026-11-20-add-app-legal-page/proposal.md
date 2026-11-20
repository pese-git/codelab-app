## Why

В CodeLab нет ни политики конфиденциальности, ни условий использования (D-18, D-29). Агент получает доступ к файлам, командам и сети пользователя, а в репозитории и в сборке app не сказано, какие данные куда уходят и кто отвечает за одобренные действия агента. Правовые тексты app сейчас разбросаны. Лицензия видна одной строкой «About», а сторонние уведомления открываются отдельным диалогом. Блоков «Privacy» и ссылки «Privacy policy» на странице «General» нет: `add-app-general-page` скрыл их, пока нет `PRIVACY.md` (SETUP-17).

`dart-agent-and-clients` §12.7.7 и §12.7.7а описывают документы и страницу настроек «Legal» (артборды 32–35, 35a–35c). Решения пользователя 2026-11-20:
- имя change — `add-app-legal-page`;
- документы создаются на английском и на русском, app показывает редакцию на языке интерфейса, для остальных языков — английскую;
- тексты — черновики с пометкой о юридической проверке; кто её делает, пока не решено, домен `<сайт>` тоже не решён;
- `TERMS.md` справочный: принимать нечего;
- копии в `assets/legal/` сверяет тот же тест, что `LICENSE` и `THIRD_PARTY_NOTICES.md` (D13 change `add-app-general-page`).

## What Changes

- **Документы в корне репозитория** (черновики): `PRIVACY.md` и `TERMS.md` — английская редакция, `PRIVACY.ru.md` и `TERMS.ru.md` — русская. В первой строке — дата редакции, она общая для обеих редакций. Обязательные разделы: пять в политике (§12.7.7), шесть в условиях (§12.7.7а). Под заголовком — пометка о черновике. Неизвестные адреса стоят заполнителями `<site>` и `<contact>`. Раздел 2 политики перечисляет только сетевые запросы текущей сборки (design.md, D3). Корневой `README.md` ссылается на оба документа.
- **Тест `legal_documents_test.dart`** в `codelab_architecture_tests` (§12.7.10) проверяет четыре файла: они есть, дата в первой строке, у пары одна дата, заголовки разделов идут по порядку, кнопки согласия нет.
- **Копии в сборке app**: `assets/legal/PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md` объявлены в `pubspec.yaml`. Существующий `test/app/legal_assets_test.dart` сверяет их с корнем; второго теста сверки нет.
- **Страница настроек «Legal»** (`SettingsPage.legal`, последний пункт группы «App», видна всегда). Четыре вкладки: «Privacy policy», «Terms of use», «License», «Third-party notices».
  - Политика и условия показываются на языке интерфейса. Смена языка при открытой странице подменяет документ, вкладка и запрос поиска сохраняются.
  - «License» показывает краткое содержание MIT (ARB `en`/`ru`) и полный текст `LICENSE`.
  - «Third-party notices» показывает записи реестра по правилам `thirdPartyRecordsOf` (D13 `add-app-general-page`) и лицензии пакетов из `LicenseRegistry`.
  - Ссылки между документами переключают вкладку. Ссылки `https:` открываются через `ExternalLinkOpener`, остальные неактивны.
- **Поиск по пакетам** на вкладке «Third-party notices»:
  - подстрока без учёта регистра; меняется только показ, список остаётся прежним; записи реестра видны всегда;
  - счётчик `<N> packages`, `<M> of <N> packages` или `0 of <N> packages`;
  - совпадения подсвечиваются, у поля есть крестик «Clear search»;
  - если совпадений нет, показывается блок «No packages match» с кнопкой «Clear search»;
  - запрос не сохраняется и не пишется в журнал.

  Отбор и подсветку делает чистая функция. Состояние страницы (вкладка, документы, пакеты, запрос) держит `LegalPageCubit`, а не виджеты (AGENTS.md §8).
- **Страница «General»**:
  - новый блок «Privacy» со строкой «No telemetry» и ссылкой «Privacy policy»;
  - в «About» — кнопки «Privacy policy» и «Terms of use», а значение строки «License» становится ссылкой на вкладку «License»;
  - «Third-party notices» открывает вкладку страницы «Legal», а не диалог. Диалог `settings-general-third-party-dialog` удаляется (§12.7.7а: один текст — в одном месте).
- **Навигация**: `SettingsDestination` получает необязательную вкладку Legal, `NavigationCubit.selectSettingsPage` — её параметр. `codelab.settings.last_page` хранит только страницу.
- **Кит `codelab_ui`**: молекула `CodeLabSelectorBar` — вкладки-переключатель с семантикой вкладок и горизонтальной прокруткой. В Fluent 4.17 нет `SelectorBar`, а `CodeLabSegmentedControl` обрезает русские подписи (design.md, D6).
- **Локализация**: все новые тексты — ARB `en` и `ru` с ICU `plural`; новые термины — в `l10n-glossary.md`.

## Не входит

- **Публикация на сайте и в каталоге релиза**, строка `codelab --help`, итог установщика, приёмка `release/legal-documents-published`. Нужен домен `<сайт>`, а он не решён. Закрытый список spec `project-site` не меняется (§12.7.7а, «Сайт»). Это задача 9.4 или отдельный change после решения о домене.
- **`network-inventory.yaml` и `privacy_network_inventory_test`** (REL-9) — сторож сетевых вызовов. Это отдельный механизм задачи 9.4. Здесь раздел 2 политики сверяется с кодом при ревью.
- **Шаг 4 «Privacy» onboarding** (артборд 07a): onboarding в app ещё нет.
- **Кнопки артбордов без поведения в сборке** (SETUP-17): «Copy link» и «Open on the web» (нет домена), «Copy all», «Open LICENSE», оглавление «On this page» и InfoBar «In short» (design.md, D12).
- **Юридическая проверка текстов**: тексты остаются черновиками до неё, кто проверяет — открытый вопрос.
- **Раздел `CHANGELOG.md`**: его пишет ветка `release/<version>` (AGENTS.md §22). Записи «Privacy» и «Terms» появятся там при выпуске (§12.7.8).
- **Перевод `LICENSE` и `THIRD_PARTY_NOTICES.md`**: оба файла одноязычны и показываются как есть.
- **Изменения ACP**: новых методов, полей и `_meta` нет.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `app-settings`:
  - MODIFIED: «Навигация настроек» (Legal в группе «App»), «Страница «General»: состав и порядок» (блок «Privacy»), «Раздел «About» страницы «General»» (ссылки на Legal, без диалога), «События журнала страницы «General»» (`settings.legal_link`);
  - ADDED: «Страница «Legal»: видимость и вкладки», «…: документы на языке интерфейса», «…: ссылки внутри документов», «…: вкладка «License»», «…: вкладка «Third-party notices»», «…: поиск по пакетам», «События журнала страницы «Legal»».
- `licensing-and-attribution`:
  - MODIFIED: «Лицензия и сторонние уведомления в сборке app» (новые копии и страница «Legal»);
  - ADDED: «Политика конфиденциальности и условия использования».

Три MODIFIED-требования `app-settings` и MODIFIED-требование `licensing-and-attribution` вводит активный change `add-app-general-page`, а его код уже в `develop`. Этот change архивируется после него (design.md, «Порядок архивации»).

## Impact

- **Код** (`[desktop]`):
  - `apps/codelab_desktop/lib/features/settings/application/`:
    - `legal_documents.dart` — `LegalTab`, выбор ресурса по языку, разбор ссылок;
    - `package_license_search.dart` — `PackageLicense`, `searchPackageLicenses`;
    - `legal_ports.dart`, `legal_page_cubit.dart` и `legal_page_state.dart`;
    - `about_ports.dart` — из `AboutInfo` уходит текст уведомлений;
  - `presentation/`:
    - новый `legal_page.dart`;
    - `general_page.dart` — блок «Privacy»;
    - `about_section.dart` — ссылки вместо диалога;
    - `settings_shell.dart`, `settings_titles.dart`;
  - `lib/app/`:
    - `navigation/settings_page.dart` и `app_destination.dart`, `navigation_cubit.dart`;
    - новый `legal_ports_factory.dart` (единственное место `rootBundle` и `LicenseRegistry` страницы);
    - `about_ports_factory.dart` и сборка зависимостей;
  - `assets/legal/` (4 копии), `pubspec.yaml`, ARB `en`/`ru`;
  - `packages/flutter/codelab_ui` — `molecules/codelab_selector_bar.dart`, экспорт, превью, тест.
- **Тесты:**
  - `codelab_architecture_tests/test/legal_documents_test.dart`;
  - расширенный `apps/codelab_desktop/test/app/legal_assets_test.dart`;
  - модульные тесты поиска и Cubit, widget-тесты страницы, поиска и «General»;
  - интеграционный `integration_test/legal_page_test.dart` (`test:e2e:app:legal`, только `release/*`).
- **Зависимости:** новых пакетов нет. Markdown рисует существующий `CodeLabMarkdown` (`gpt_markdown`). Allowlist ядра (PKG-2), `desktopAllowlist` и граф пакетов `README.md` не меняются. Новых правил сторожа нет (design.md, D13).
- **ACP:** без изменений.
- **Данные пользователя:** новых ключей `shared_preferences` нет. Запрос поиска и выбранная вкладка не сохраняются, записи о согласии нет.
- **Безопасность:**
  - документы читаются из ресурсов сборки, без сети;
  - внешние ссылки открываются только `https:` через существующий порт;
  - запрос поиска экранируется при показе и не попадает в журнал;
  - изображения в документах не загружаются.
- **Документы** (обновлены при подготовке change):
  - `12-7-release-and-distribution.md` §12.7.7 («Языки», «Перечень по текущей сборке»), §12.7.7а (язык документов, ассеты, сайт, состав change), §12.7.10;
  - `12-4-first-run-and-settings.md` §12.4.9 (строка Legal) и SETUP-17;
  - `11-assumptions-and-open-questions.md`;
  - `agent-parity-goals.md` (D-18, D-29);
  - `09-14-stage-9-switch-default.md`.

  При реализации обновляются:
  - `apps/codelab_desktop/AGENTS.md`;
  - `packages/flutter/codelab_ui/AGENTS.md` и `README.md`;
  - `apps/codelab_desktop/doc/user-guide.md`;
  - корневой `README.md`;
  - `docs/architecture/l10n-glossary.md`.
