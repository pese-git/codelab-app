## MODIFIED Requirements

### Requirement: Лицензия и сторонние уведомления в сборке app
Сборка `apps/codelab_desktop` SHALL содержать ресурсы `assets/legal/LICENSE`, `assets/legal/THIRD_PARTY_NOTICES.md`, `assets/legal/PRIVACY.md`, `assets/legal/PRIVACY.ru.md`, `assets/legal/TERMS.md` и `assets/legal/TERMS.ru.md`, побайтно равные одноимённым файлам корня репозитория. Равенство SHALL проверять один тест app (`test/app/legal_assets_test.dart`); правка корневого файла без копии SHALL ронять тест с именем файла (design.md change `add-app-general-page`, D13; design.md change `add-app-legal-page`, D4). Каждый ресурс SHALL быть объявлен в `pubspec.yaml` app.

Страница настроек «Legal» SHALL показывать эти документы из ресурсов, без сети; раздел «About» страницы «General» SHALL показывать строку лицензии из `assets/legal/LICENSE`. Вкладка «Third-party notices» SHALL показывать записи раздела `## Записи` реестра сторонних уведомлений, поэтому `THIRD_PARTY_NOTICES.md` SHALL содержать ровно один заголовок `## Записи`, после которого идут записи; проверяет тест app. Лицензии пакетов pub в сборке SHALL показываться из реестра лицензий Flutter (`LicenseRegistry`), без отдельной копии.

#### Scenario: Копия разошлась с корнем
- **WHEN** в `THIRD_PARTY_NOTICES.md` корня добавлена запись, а `apps/codelab_desktop/assets/legal/THIRD_PARTY_NOTICES.md` не обновлён
- **THEN** тест сверки ресурсов app падает и называет файл

#### Scenario: Русская редакция разошлась с корнем
- **WHEN** в `TERMS.ru.md` корня исправлено слово, а `apps/codelab_desktop/assets/legal/TERMS.ru.md` не обновлён
- **THEN** тест сверки ресурсов app падает и называет `TERMS.ru.md`

#### Scenario: Ресурс не объявлен
- **WHEN** `assets/legal/PRIVACY.ru.md` лежит в каталоге app, но не перечислен в `pubspec.yaml`
- **THEN** тест сверки ресурсов app падает и называет `assets/legal/PRIVACY.ru.md`

#### Scenario: Строка лицензии из ресурса
- **WHEN** раздел «About» развёрнут
- **THEN** строка «License» содержит `MIT` и строку авторского права, совпадающую с третьей строкой `assets/legal/LICENSE`

#### Scenario: Реестр без раздела записей
- **WHEN** в `THIRD_PARTY_NOTICES.md` корня и его копии в `assets/legal/` заголовок `## Записи` переименован или удалён
- **THEN** тест ресурсов app падает и называет отсутствующий заголовок

## ADDED Requirements

### Requirement: Политика конфиденциальности и условия использования
В корне репозитория SHALL лежать политика конфиденциальности и условия использования на английском и на русском: `PRIVACY.md` и `TERMS.md` — английская редакция, `PRIVACY.ru.md` и `TERMS.ru.md` — русская (`dart-agent-and-clients` §12.7.7, §12.7.7а; design.md, D2). Текст общий для CLI и app (D-18, D-29).

Для каждого из четырёх файлов SHALL выполняться:
- первая строка — дата редакции в формате `YYYY-MM-DD`: `Last revised: YYYY-MM-DD` в английской редакции, `Редакция от YYYY-MM-DD` в русской; у английской и русской редакции одного документа дата SHALL быть одной;
- заголовки второго уровня обязательных разделов идут в порядке §12.7.7 (политика, пять разделов) и §12.7.7а (условия, шесть разделов) с текстами из таблицы design.md, D3; русская редакция SHALL иметь те же разделы в том же порядке;
- до юридической проверки под заголовком первого уровня SHALL стоять пометка о черновике: `Draft pending legal review.` в английской редакции и `Черновик до юридической проверки.` в русской;
- адреса, которые ещё не решены (`<сайт>`, контакт для вопросов), SHALL оставаться явными заполнителями `<site>` и `<contact>`, а не выдуманными значениями.

Раздел 2 политики SHALL перечислять сетевые запросы текущей сборки: провайдер модели, проверка ключа провайдера при настройке, MCP-серверы из конфигурации и внешние ACP-агенты, которые подключил пользователь (stdio или WebSocket). Запросы, которых в сборке нет (web-инструменты, проверка обновлений), НЕ SHALL описываться как существующие (REL-9; design.md, D3).

Условия SHALL быть информационными: ни один документ НЕ SHALL требовать принятия, и ни CLI, ни app, ни установщик НЕ SHALL хранить запись о согласии (§12.7.7а). Тексты чужих политик и условий НЕ SHALL копироваться (AGENTS.md §5).

Обязательные разделы, даты и наличие четырёх файлов SHALL проверять тест `packages/dart/codelab_architecture_tests/test/legal_documents_test.dart` (§12.7.10). Корневой `README.md` SHALL ссылаться на `PRIVACY.md` и `TERMS.md`.

#### Scenario: Нет русской редакции
- **WHEN** в корне есть `TERMS.md`, но нет `TERMS.ru.md`
- **THEN** `legal_documents_test.dart` падает и называет `TERMS.ru.md`

#### Scenario: Даты редакций разошлись
- **WHEN** первая строка `PRIVACY.md` — `Last revised: 2026-11-20`, а `PRIVACY.ru.md` — `Редакция от 2026-11-18`
- **THEN** `legal_documents_test.dart` падает и называет оба файла

#### Scenario: Раздел пропущен или переставлен
- **WHEN** в `TERMS.ru.md` раздел «5. Содержимое, сгенерированное моделью» стоит перед разделом «4. Отказ от гарантий и ограничение ответственности»
- **THEN** `legal_documents_test.dart` падает и называет файл и ожидаемый заголовок

#### Scenario: Ссылки в README
- **WHEN** проверяется корень репозитория
- **THEN** `README.md` содержит ссылки на `PRIVACY.md` и `TERMS.md`
