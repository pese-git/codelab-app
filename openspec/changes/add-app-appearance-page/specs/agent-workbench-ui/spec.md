## MODIFIED Requirements

### Requirement: Блок кода в ответе агента
Блок кода ответа SHALL показывать подпись языка из info-строки ограды (без языка — без подписи) вне выделения текста, код моноширинным шрифтом с сохранением переводов строк и кнопку «Copy», которая кладёт в буфер обмена исходный код блока без строк ограды. Код SHALL подсвечиваться по языку info-строки из зарегистрированного набора палитрой подсветки действующей темы app (`CodeLabCodeTheme`). У встроенных тем (`light`, `dark`, `high-contrast`; spec app-settings «Режим оформления и темы режимов») палитра SHALL выводиться из ролей `FluentTheme` с контрастом каждого класса токена не ниже 4,5:1 на фоне блока. Роль `code.*` пользовательской темы SHALL применяться как задана, даже если её контраст ниже 4,5:1; о низком контрасте предупреждает страница «Appearance» (spec app-settings «Контраст на фоне кода»). Незаданные роли пользовательской темы SHALL браться из встроенной темы её базы; неизвестный язык или его отсутствие SHALL давать код без подсветки, без автоопределения. Токенизация кода до 300 строк и 16 КиБ MAY выполняться синхронно; код больше этого НЕ SHALL токенизироваться в UI isolate, а до готовности токенов SHALL показываться без цвета; код больше 5000 строк или 256 Ki code units НЕ SHALL подсвечиваться (DSK-5). Код со строкой длиннее 150 code units НЕ SHALL токенизироваться в UI isolate, со строкой длиннее 1000 code units НЕ SHALL подсвечиваться; фоновая токенизация SHALL прерываться через 5 с, и код остаётся без подсветки; повтор того же кода после таймаута или сбоя НЕ SHALL запускать токенизацию заново. Сбой токенизации SHALL оставлять код без подсветки и SHALL сообщаться как ошибка Flutter без текста кода (design.md change `add-desktop-markdown`, D4; design.md change `add-app-appearance-page`, D4, D8).

#### Scenario: Язык и копирование
- **WHEN** выполняется `acp_markdown_test.dart: code block shows language and copy puts raw code into clipboard` для блока ```` ```dart ```` с двумя строками
- **THEN** блок показывает подпись `dart`, нажатие `code-copy-<rowId>-0` кладёт в буфер ровно две строки кода без ```` ``` ````, а выделение всего ответа не содержит подписи `dart`; второй блок с тем же кодом в том же ответе имеет ключ `code-copy-<rowId>-1`

#### Scenario: Большой блок подсвечивается вне UI isolate
- **WHEN** выполняется `acp_markdown_test.dart: large code block is highlighted off the UI isolate` для блока `dart` из 1000 строк
- **THEN** `highlightSyncRuns` равен 0, до результата код показан без цвета, после результата строка перерисована один раз

#### Scenario: Неизвестный язык
- **WHEN** блок кода имеет язык `foolang`
- **THEN** код показан моноширинно без подсветки, подпись `foolang` видна, «Copy» работает

#### Scenario: Роль пользовательской темы с низким контрастом
- **WHEN** действует пользовательская тема с `"code": {"background": "#14121f", "comment": "#3a3650"}`, и в ответе есть блок `dart` с комментарием
- **THEN** комментарий нарисован цветом `#3a3650` на фоне `#14121f`, цвет не подобран под порог

## ADDED Requirements

### Requirement: Цвета кита из палитры темы
Виджеты `codelab_ui` SHALL брать цвета тонов `success`, `warning`, `danger` и `accent` (`CodeLabTone`), цвет ссылок, фоны строк diff и цвет выделения из расширения темы `CodeLabPalette` в `FluentThemeData.extensions`. Если расширения нет, кит SHALL выводить палитру из `FluentTheme` так, чтобы цвета совпадали с цветами до change `add-app-appearance-page`: тоны `success`, `warning`, `danger`, `accent` — `Colors.green`, `Colors.warningPrimaryColor`, `Colors.red`, `Colors.blue`, ссылки — акцент темы. Цвет тона виджеты SHALL брать через `CodeLabPalette.toneColor(tone, theme)`: тон `neutral` — не цвет палитры, а роль текста, в светлой теме `Colors.grey`, в тёмной — `textFillColorSecondary` темы. Подгонку тонов по контрасту для встроенных тем выполняет app при сборке палитры (spec app-settings «Режим оформления и темы режимов»), кит цвета палитры не меняет. Кит НЕ SHALL читать файлы тем, `shared_preferences` и типы `codelab_client_core`: палитру собирает app (design.md change `add-app-appearance-page`, D4). Роли `approval_border` в палитре нет: блок одобрения не имеет акцентной рамки (design.md change `lighten-approval-block`), и тема её не возвращает.

Смысл НЕ SHALL передаваться только цветом: у тега статуса по-прежнему есть текст или значок рядом.

#### Scenario: Палитра из расширения
- **WHEN** выполняется widget-тест `codelab_ui` пользовательской темы: `FluentThemeData` с `CodeLabPalette(success: #a6e3a1, danger: #f38ba8, info: #89b4fa)`
- **THEN** тег `Done` нарисован цветом `#a6e3a1`, тег `Failed` — `#f38ba8`, ссылка в markdown — `#89b4fa`

#### Scenario: Без расширения вид прежний
- **WHEN** тот же тест строит `FluentThemeData()` без `CodeLabPalette`
- **THEN** тег `Done` нарисован `Colors.green`, тег `Failed` — `Colors.red`, ссылка — акцентом темы

#### Scenario: Нейтральный тег в тёмной теме
- **WHEN** тест строит `FluentThemeData(brightness: Brightness.dark)` без `CodeLabPalette` и рисует тег тона `neutral`
- **THEN** тег нарисован `textFillColorSecondary` темы, а не `Colors.grey`
