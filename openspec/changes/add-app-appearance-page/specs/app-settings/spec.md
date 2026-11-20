## ADDED Requirements

### Requirement: Страница «Appearance»: видимость и состав
Composition root SHALL делать видимой страницу «Appearance» группы «App» (`settings-nav-appearance`, тело `settings-appearance`) после «General» в порядке требования «Навигация настроек». Страница SHALL показывать блоки в порядке артборда «10 Settings — Appearance» (design.md change `add-app-appearance-page`, D14):
1. «Mode» (`settings-appearance-mode`);
2. «Accent color» (`settings-appearance-system-accent`) — только если платформа отдаёт системный акцент (требование «Системный акцент»);
3. «Color theme» — карточки тем (`settings-appearance-themes`);
4. «Custom themes» — путь каталога тем `<home>/themes/*.json` с `~` вместо домашнего каталога и кнопка «Import JSON…» (`settings-appearance-import`);
5. панель проблем выбранной темы (`settings-appearance-issues`) — только если у выбранной темы есть предупреждения, ошибка или незаданные роли;
6. «Preview» (`settings-appearance-preview`) с проверкой контраста и кнопками «Reset» (`settings-appearance-reset`) и «Use <name>» (`settings-appearance-use`).

При ширине области страницы от 960 px «Preview» SHALL стоять правой колонкой, при меньшей — под остальными блоками.

Поиск «Find a setting» SHALL находить «Appearance» по английским ключевым словам `theme`, `dark`, `light`, `mode`, `color`, `accent`, `contrast`, `json` при любом языке интерфейса, а при русском — ещё по `тема`, `тёмная`, `светлая`, `режим`, `цвет`, `акцент`, `контраст`, `оформление` (сообщение `settingsSearchKeywordsAppearance` в ARB `en` и `ru`).

Все тексты страницы SHALL браться из каталогов ARB `en` и `ru` (требование «Локализация интерфейса app»). Имена тем, ключи JSON, значения цветов, пути, текст файла темы и отношения контраста (`4.8:1`) SHALL показываться как есть. Названия встроенных тем `Fluent Light`, `Fluent Dark` SHALL не переводиться, `High contrast` SHALL переводиться.

#### Scenario: Страница видна
- **WHEN** пользователь открывает настройки рабочей сборки
- **THEN** в группе «App» после `settings-nav-general` стоит `settings-nav-appearance`, выбор открывает `settings-appearance`

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `contrast` в «Find a setting»
- **THEN** в навигации остаётся «Appearance»

#### Scenario: Узкая область
- **WHEN** ширина области страницы 800 px
- **THEN** блок «Preview» стоит под панелью проблем, а не правой колонкой

### Requirement: Режим оформления и темы режимов
«Mode» SHALL предлагать три значения в этом порядке: `Light` (`settings-appearance-mode-light`), `Dark` (`settings-appearance-mode-dark`), `Match system` (`settings-appearance-mode-system`). У `Match system` SHALL в скобках показываться текущий режим системы (`Match system (dark)`). По умолчанию — `Match system`.

App SHALL хранить две темы: тему светлого режима (по умолчанию `light`, «Fluent Light») и тему тёмного режима (по умолчанию `dark`, «Fluent Dark»). Действующая тема SHALL быть темой режима, который даёт «Mode»: `Light` — светлого, `Dark` — тёмного, `Match system` — режима системы в данный момент. Смена режима системы при `Match system` SHALL применяться сразу.

Каждая тема SHALL относиться к одному режиму: `light` — к светлому, `dark` и `high-contrast` — к тёмному, пользовательская — к режиму своей базы `extends` (`light` — светлый, иначе тёмный).

Встроенные темы SHALL задаваться так:
- `light` и `dark` — стандартная тема Fluent своего режима; цвета статусов, ссылок и кода SHALL совпадать с теми, что app показывал до этого change;
- `high-contrast` — тёмная тема с чёрным фоном кода и палитрой из design.md, D6.

Пользовательская тема SHALL применяться поверх встроенной темы своей базы. Роли, которые тема задала, SHALL заменять роли базы (spec client-themes «Роли цветов темы»; применение ролей — design.md, D4). Тема, которая не загрузилась (ошибка разбора или чтения, файл удалён), SHALL заменяться встроенной темой своего режима (`light` или `dark`). Сохранённый выбор при этом НЕ SHALL меняться, а страница SHALL показывать InfoBar `settings-appearance-fallback`: `"<name>" couldn't be loaded. Using <built-in> until it is fixed.`.

Смена режима, темы или акцента SHALL применяться ко всему app до следующего кадра, без перезапуска. Она НЕ SHALL терять ввод пользователя (текст композера, черновики диалогов), фокус и прокрутку ленты и НЕ SHALL обращаться к агенту. Первый кадр app SHALL рисоваться уже в сохранённом оформлении.

#### Scenario: Тёмная система
- **WHEN** выбран `Match system`, обе темы по умолчанию, и система переходит в тёмный режим
- **THEN** app рисуется в «Fluent Dark», текст композера и прокрутка ленты сохранены

#### Scenario: Темы двух режимов
- **WHEN** тема светлого режима — `light`, тёмного — пользовательская `acme-night` (`extends: dark`), и пользователь переключает «Mode» с `Light` на `Dark`
- **THEN** app рисуется в `acme-night`; при возврате на `Light` — в «Fluent Light»

#### Scenario: Удалённый файл темы
- **WHEN** тема тёмного режима — `acme-night`, файл `acme-night.json` удалён, и app стартует в тёмном режиме
- **THEN** app рисуется в «Fluent Dark», `codelab.app.appearance` по-прежнему называет `acme-night`, а страница показывает `settings-appearance-fallback`

#### Scenario: Стандартная тема не меняет вид
- **WHEN** выбран `Light` с темой `light` и системный акцент выключен
- **THEN** цвета тонов `success`, `warning`, `danger` и `accent` кита и палитра кода совпадают с цветами до этого change (widget-тест сравнивает значения цветов)

### Requirement: Системный акцент
Строка «Accent color» с переключателем «Use system accent» SHALL показываться, только если порт системного акцента сообщает поддержку: платформа поддерживается пакетом `system_theme` (macOS, Windows, Linux), и чтение акцента при старте app дало цвет (design.md, D7). Иначе строка SHALL быть скрыта (SETUP-17). Видимость строки НЕ SHALL меняться после первого кадра. По умолчанию переключатель выключен.

Включённый переключатель SHALL заменять роль `accent` действующей темы системным акцентом — у встроенных и у пользовательских тем. Это касается кнопок, выделения, фокуса и производных от акцента цветов. На macOS и Windows смена акцента в системе SHALL применяться сразу. На Linux платформа не сообщает о смене, поэтому акцент SHALL перечитываться при старте app и при каждом открытии страницы «Appearance». Если платформа перестала отдавать акцент (ошибка канала), SHALL применяться `accent` темы, а в журнал SHALL писаться предупреждение без текста ошибки.

#### Scenario: Системный акцент включён
- **WHEN** порт отдаёт акцент `#ff2d55`, и пользователь включает «Use system accent»
- **THEN** `FluentTheme.accentColor` действующей темы построен из `#ff2d55`, а превью и карточки показывают акцент своих тем

#### Scenario: Пользовательская тема и системный акцент
- **WHEN** действует `acme-night` с `"accent": "#b4a0ff"`, порт отдаёт `#ff2d55`, и переключатель включён
- **THEN** `FluentTheme.accentColor` построен из `#ff2d55`

#### Scenario: Linux без уведомлений
- **WHEN** app работает на Linux, переключатель включён, пользователь сменил тему GTK и открывает «Appearance»
- **THEN** порт перечитан один раз, и действующий акцент построен из нового цвета

#### Scenario: Плагин не отдал цвет
- **WHEN** платформа поддерживается пакетом, но чтение при старте вернуло запасной цвет-маркер или ошибку
- **THEN** строки `settings-appearance-system-accent` нет, запасной цвет пакета не применяется

#### Scenario: Платформа без системного акцента
- **WHEN** порт системного акцента сообщает, что поддержки нет
- **THEN** строки `settings-appearance-system-accent` на странице нет

### Requirement: Карточки тем и превью
«Color theme» SHALL показывать карточки `settings-appearance-theme-<id>`: сначала встроенные `light`, `dark`, `high-contrast`, затем пользовательские в порядке каталога тем. Карточка SHALL показывать мини-превью кода в цветах темы (фон кода, `text`, `code.keyword`, `code.string`, `code.comment`, `code.number`), имя темы и вид: `Built-in · default` у `light` и `dark`, `Built-in` у `high-contrast`, `Custom · extends <base>` у пользовательской. Карточка темы светлого режима SHALL нести тег `Light mode`, тёмного — `Dark mode`. Карточка с предупреждениями SHALL нести бейдж `settings-appearance-theme-<id>-warnings` с текстом `N warnings` (ICU `plural`). N — предупреждения разбора плюс роли с низким контрастом (требование «Контраст на фоне кода»). Тема, которая не загрузилась, SHALL нести тег `Invalid` вместо бейджа.

Нажатие карточки SHALL выбирать тему для превью и панели проблем и НЕ SHALL применять её. При открытии страницы выбрана действующая тема.

«Preview» SHALL рисовать в цветах выбранной темы:
- блок кода `dart` с подписью языка;
- строку удалённого и строку добавленного кода diff на фонах `diff_remove_bg` и `diff_add_bg`;
- статусы `Link` (`info`), `Done` (`success`), `84% context` (`warning`), `Failed` (`error`).

Тексты превью SHALL быть фиксированными данными app и НЕ SHALL браться из сессий.

«Use <name>» SHALL делать выбранную тему темой её режима. Если «Mode» стоит на другом режиме (`Light` или `Dark`), «Mode» SHALL переключаться на режим темы, чтобы выбор был виден сразу; при `Match system` «Mode» НЕ SHALL меняться. Кнопка SHALL быть недоступна для темы, которая не загрузилась, и для темы, которая уже назначена своему режиму.

«Reset» SHALL возвращать режиму выбранной темы встроенную тему по умолчанию (`light` или `dark`) и выбирать её для превью. Кнопка SHALL быть недоступна, если этому режиму уже назначена тема по умолчанию.

#### Scenario: Выбор карточки не применяет тему
- **WHEN** действующая тема — «Fluent Dark», и пользователь нажимает карточку `acme-night`
- **THEN** превью нарисовано цветами `acme-night`, app по-прежнему в «Fluent Dark», кнопка называется `Use acme-night`

#### Scenario: Use переключает фиксированный режим
- **WHEN** «Mode» — `Light`, и пользователь нажимает «Use» у выбранной `acme-night` (`extends: dark`)
- **THEN** тема тёмного режима — `acme-night`, «Mode» — `Dark`, app рисуется в `acme-night`

#### Scenario: Reset
- **WHEN** тема тёмного режима — `acme-night`, она выбрана, и пользователь нажимает «Reset»
- **THEN** тема тёмного режима — `dark`, выбрана карточка «Fluent Dark»

### Requirement: Пользовательские темы на странице «Appearance»
Страница SHALL читать каталог тем при открытии и по «Reload», только через порт каталога тем (spec client-themes «Каталог пользовательских тем»). Пока каталог читается, карточки встроенных тем SHALL работать, а на месте пользовательских SHALL стоять индикатор загрузки. Результат чтения, начатого до закрытия страницы или до более нового «Reload», НЕ SHALL менять состояние страницы.

Если у выбранной темы есть предупреждения, панель проблем SHALL показывать:
- InfoBar уровня `warning` `settings-appearance-issues-summary`: `<name> loaded with N warnings` и пояснение `Unknown keys were ignored; the theme is applied. Missing roles come from extends: "<base>" (<built-in name>).`;
- кнопки «Open folder» (`settings-appearance-open-folder`) и «Reload» (`settings-appearance-reload`);
- текст файла с номерами строк, где строки с предупреждением выделены (`CodeLabFilePreview`);
- список проблем `settings-appearance-issue-<n>` (n с 1, по порядку позиции): `<file>:<line>:<col> unknown key "<key>"` с пояснением `Ignored. Did you mean "<role>"?` или `Ignored — not a theme role.`, `duplicate key "<key>"` — `The last value is used.`, `terminal color "<value>"` — `Terminal colors are not used by the app; the role comes from extends.`, а также строка о низком контрасте для каждой такой роли;
- справку `settings-appearance-unset-roles`: `N roles not set — taken from "<base>"` и список ролей с пояснением `For reference, not a warning`. Роли, которые app не применяет (`status_bg`, `approval_border`), в справку и в N НЕ SHALL входить.

Если тема не загрузилась, InfoBar SHALL быть уровня `error`: `<name> couldn't be loaded`. Под ним — та же проблема с позицией. Текст файла SHALL показываться, если файл прочитан и не больше 64 КиБ. Справки о ролях при этом нет.

Если у темы нет предупреждений и ошибок, но есть незаданные роли, SHALL показываться только справка.

Текст файла и значения из него SHALL проходить экранирование управляющих символов и символов направления текста (`escapeForDisplay`) перед показом.

«Open folder» SHALL открывать каталог тем через порт `LocalFolderOpener` (создавая его, если нет). Файл темы app НЕ SHALL открывать внешним приложением. «Reload» SHALL перечитывать каталог. Если выбранная тема назначена режиму, «Reload» SHALL заново применять её из файла.

#### Scenario: Тема с двумя предупреждениями
- **WHEN** выбрана `acme-night` с ключами `acent` (строка 6) и `tab_bg` (строка 9)
- **THEN** InfoBar показывает `acme-night loaded with 2 warnings`, строки 6 и 9 текста выделены, `settings-appearance-issue-1` — `acme-night.json:6:5 unknown key "acent"` с `Did you mean "accent"?`, `settings-appearance-issue-2` — `acme-night.json:9:5 unknown key "tab_bg"` с `Ignored — not a theme role.`

#### Scenario: Reload применяет исправленный файл
- **WHEN** тема тёмного режима `acme-night` действует, пользователь исправил в файле `accent` и нажал «Reload»
- **THEN** app рисуется с новым `accent` без перезапуска

#### Scenario: Поздний результат чтения
- **WHEN** чтение каталога ещё идёт, и пользователь нажимает «Reload»
- **THEN** состояние страницы строит только второе чтение, событие `appearance.catalog_discarded` записано

#### Scenario: Управляющие символы в файле
- **WHEN** файл темы содержит в строке символ U+202E
- **THEN** текст файла на странице показывает его экранированным, а не меняет направление строки

### Requirement: Импорт темы на странице «Appearance»
«Import JSON…» SHALL открывать системный диалог выбора одного файла `.json`. Отмена диалога SHALL ничего не менять. Выбранный файл SHALL импортироваться по spec client-themes «Импорт файла темы»:
- импорт удался — каталог перечитывается, импортированная тема выбирается для превью и НЕ применяется; если у неё есть предупреждения, показывается панель проблем;
- нужна замена — диалог `Replace the theme "<name>"?` с кнопками «Replace» (`settings-appearance-import-replace`) и «Cancel»; без «Replace» файл не меняется;
- тема уже есть с тем же содержимым — выбирается для превью без записи;
- ошибка разбора — InfoBar `error` `settings-appearance-import-failed`: `Couldn't import <file name>: <проблема с позицией>`, файл не копируется;
- ошибка записи — тот же InfoBar с `Couldn't save the theme to <home>/themes.` без текста исключения.

Пока идёт импорт, кнопка «Import JSON…» SHALL быть недоступна.

#### Scenario: Импорт и превью
- **WHEN** пользователь импортирует корректный файл `acme-night`
- **THEN** появляется карточка `settings-appearance-theme-acme-night`, она выбрана, действующая тема не изменилась

#### Scenario: Отказ от замены
- **WHEN** импортируется `acme-night` с другим содержимым, и пользователь нажимает «Cancel» в диалоге замены
- **THEN** файл `acme-night.json` не изменился

### Requirement: Контраст на фоне кода
Блок «Contrast on code background» (`settings-appearance-contrast`) SHALL показывать для выбранной темы строки `settings-appearance-contrast-<role>`: `Text` (`text`), `Comment` (`code.comment`), `Keyword` (`code.keyword`), `Link` (`info`), `Error` (`error`). В каждой строке — образец цвета, отношение контраста к `code.background` с одним знаком после точки (`4.8:1`) и вердикт `AA` (не меньше 4,5:1) или `Low`. Отношение SHALL считаться по WCAG 2 по относительной яркости непрозрачных цветов. Под строками — пояснение `Text roles need 4.5:1. A role below that still applies, with a warning on its card.`

Проверяемые роли — `text`, `info`, `error` и все роли `code.*`, кроме `code.background`. Роль ниже 4,5:1 SHALL применяться как задана и SHALL давать предупреждение `Low contrast` в бейдже карточки и в списке проблем. Встроенные темы НЕ SHALL иметь проверяемой роли ниже 4,5:1 ни при каком акценте.

#### Scenario: Низкий контраст пользовательской роли
- **WHEN** тема задаёт `"code": {"background": "#14121f", "comment": "#3a3650"}`
- **THEN** строка `settings-appearance-contrast-code.comment` показывает вердикт `Low`, бейдж карточки учитывает это предупреждение, комментарии в блоках кода рисуются цветом `#3a3650`

#### Scenario: Встроенные темы проходят
- **WHEN** тест перебирает встроенные темы `light`, `dark`, `high-contrast` с выключенным и включённым системным акцентом (несколько значений акцента)
- **THEN** у каждой проверяемой роли отношение к `code.background` не меньше 4,5:1

### Requirement: Хранение оформления
Режим, темы двух режимов и переключатель системного акцента SHALL храниться одним JSON-документом в `shared_preferences` под ключом `codelab.app.appearance`: `{"version": 1, "mode": "light" | "dark" | "system", "light_theme": "<id>", "dark_theme": "<id>", "system_accent": true | false}`. Отсутствующее поле SHALL браться по умолчанию. Файлы `$CODELAB_HOME` (`config.yaml`, `cli.yaml`, `profiles.json`) выбор НЕ SHALL менять.

Документ SHALL читаться до первого кадра вместе с файлами тем двух режимов. Каждый файл читается с ограничением времени 1 с; не прочитанный вовремя — как не загрузившийся. Незнакомый или нечитаемый документ, незнакомое значение поля, тема чужого режима в поле режима SHALL читаться как значения по умолчанию для этих полей. Документ при этом НЕ SHALL перезаписываться до явного выбора пользователя, а в журнал SHALL писаться предупреждение без значения. Сбой хранилища при старте НЕ SHALL мешать запуску.

Если запись не удалась, выбор SHALL оставаться применённым до конца работы app, а страница SHALL показать ошибку `Couldn't save the appearance. CodeLab will use the previous appearance after restart.` с кнопкой `Retry` (`settings-appearance-save-retry`). При нескольких выборах подряд SHALL применяться и сохраняться последний.

#### Scenario: Повреждённый документ
- **WHEN** `codelab.app.appearance` содержит `{"mode": "sepia"}`
- **THEN** app стартует с `Match system` и темами по умолчанию, ключ не перезаписан, в журнале предупреждение `appearance.stored_value_invalid` без значения

#### Scenario: Сбой записи
- **WHEN** запись `shared_preferences` бросает исключение после выбора `Dark`
- **THEN** app остаётся тёмным, страница показывает ошибку сохранения и `Retry`

### Requirement: События журнала оформления
События оформления SHALL писаться логгером `codelab_desktop.settings`:
- `app.appearance_resolved` при старте: `mode`, `light_theme`, `dark_theme`, `system_accent`, `fallback` (`none`, `light`, `dark`, `both`);
- `settings.appearance_changed`: `field` (`mode`, `light_theme`, `dark_theme`, `system_accent`) и новое значение;
- `appearance.theme_loaded`: `theme`, `extends`, `warnings` (число), `codes` (коды проблем без ключей и значений);
- `appearance.theme_invalid`: `theme`, `code`, `line`, `column`;
- `appearance.theme_imported`: `outcome` (`imported`, `replaced`, `unchanged`, `cancelled`, `invalid`, `failed`);
- `appearance.catalog_discarded`: `reason` (`reload`, `closed`);
- `appearance.save_failed` и `appearance.stored_value_invalid` с именем типа ошибки;
- `appearance.system_accent_failed` с именем типа ошибки.

Идентификатор встроенной темы SHALL писаться как есть (`light`, `dark`, `high-contrast`), пользовательской — как `custom`. Пути, имена файлов и пользовательских тем, ключи и значения из файла и тексты исключений НЕ SHALL попадать в журнал.

#### Scenario: Журнал без имени пользовательской темы
- **WHEN** пользователь применяет `acme-night` и импортирует ещё одну тему
- **THEN** события содержат `theme: custom` и `outcome: imported`, строк `acme-night`, `themes/` и пути домашнего каталога в журнале нет
