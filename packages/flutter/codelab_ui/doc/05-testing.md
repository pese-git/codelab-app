# Тестирование UI-кита

Глава объясняет, как устроены тесты `codelab_ui`, как писать новый тест и чем здесь заменены golden-тесты, которых в пакете нет. Общие уровни тестов репозитория описаны в [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md); эта глава — про то, что специфично для виджетов кита.

## Что проверяют тесты

Правило пакета (раздел 6 [`AGENTS.md`](../AGENTS.md)): на каждый публичный виджет — widget-тест в `packages/flutter/codelab_ui/test/`. Он проверяет поведение, а не пиксели: ключи `ValueKey`, видимые подписи, тон, реакцию на нажатие и клавиши, фокус, отсутствие переполнения. Все тесты пакета — на фиктивных данных: ни агента, ни сети, ни ключей провайдеров не нужно.

Интеграционных тестов на устройстве у кита нет: они относятся к приложению и запускаются только в ветках `release/*` (корневой `AGENTS.md`, §21).

## Устройство `test/`

В каталоге 48 файлов: 46 в корне, один в `rendering/` и один в `support/`. Группы:

| Группа | Файлы | Что проверяют |
|---|---|---|
| Виджет за файлом | `codelab_<виджет>_test.dart` — по файлу на виджет (`codelab_settings_row_test.dart`, `codelab_selector_bar_test.dart`, `codelab_usage_pane_test.dart`, `codelab_button_emphasis_test.dart` и др.) | один виджет: подписи, ключи, нажатия, переполнение |
| Сводные по слоям | `codelab_atomics_test.dart`, `codelab_molecules_test.dart`, `codelab_organisms_test.dart` | виджеты слоя без отдельного файла, раскладка по ширине окна |
| Лента | `codelab_transcript_test.dart`, `codelab_transcript_show_request_test.dart`, `codelab_transcript_approval_visibility_test.dart`, `codelab_subagent_row_test.dart`, `codelab_task_list_test.dart` | строки, прокрутка за хвостом, цели показа, видимость полосы |
| Одобрение | `codelab_approval_focus_test.dart`, `codelab_modifier_hold_test.dart` | фокус полосы, подсказки сочетаний, отсчёт зажатых модификаторов |
| Markdown | `acp_markdown_test.dart`, `codelab_markdown_tables_test.dart`, `escape_for_display_extra_test.dart`, `rendering/code_highlighter_test.dart` | разбор, ссылки, изображения, блок кода, таблицы, подсветка, экранирование |
| Сочетания | `codelab_shortcuts_test.dart`, `codelab_shortcut_bindings_test.dart`, `codelab_shortcut_table_test.dart`, `shortcut_catalog_guard_test.dart` | каталог, нажатие каждой записи, таблица, сторож |
| Локализация | `l10n_catalogs_test.dart`, `codelab_l10n_test.dart`, `codelab_l10n_en_reference_test.dart` | каталоги `en` и `ru`, словари, эталоны |
| Палитра | `codelab_palette_test.dart` | цвета из расширения темы |
| Превью | `codelab_previews_test.dart` | превью строятся без исключений |
| Оснастка | `support/approval_focus.dart` | помощники для тестов фокуса |

Файл `acp_markdown_test.dart` назван по старому имени набора; он проверяет markdown-рендеринг, а не ACP.

Большинство файлов начинается с комментария (её нет у шести тестовых файлов и у помощника в `support/`): какой change, какая спецификация и какое решение `design.md` он защищает. Например, `test/codelab_selector_bar_test.dart` ссылается на `add-app-legal-page`, D6 и сценарий «Узкое окно на русском». Такая шапка — принятая в пакете практика: по ней видно, зачем тест нужен, прежде чем его менять. Новый файл теста начинайте с шапки.

## Как пишется тест

### Скелет

Виджету нужна тема Fluent, поэтому тест оборачивает его в `FluentApp`. Типовой помощник (из `test/codelab_selector_bar_test.dart`):

```dart
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget bar, {
  double width = 800,
  Brightness brightness = Brightness.light,
}) => FluentApp(
  theme: FluentThemeData(brightness: brightness),
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: bar),
  ),
);

void main() {
  testWidgets('нажатие на другую вкладку вызывает onChanged', (tester) async {
    final picked = <String>[];
    // _bar — помощник теста: CodeLabSelectorBar с четырьмя вкладками.
    await tester.pumpWidget(_app(_bar(onChanged: picked.add)));

    await tester.tap(find.byKey(const ValueKey('tab-terms')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(picked, ['terms']);
  });
}
```

`Align` с `SizedBox` задаёт виджету известную ширину и прижимает к левому верхнему углу: так виджет получает ограниченные ограничения, как в приложении, а не растягивается на весь тестовый экран.

Три шага повторяются в каждом тесте: собрать хост, найти виджет по ключу или тексту, проверить результат. Что именно ищут:

- **Ключ.** Виджеты кита выставляют `ValueKey` для всего, что тесту нужно найти: `CodeLabApprovalPrompt.allowKey`, `CodeLabToolDock.tabKey(pane)`, `approvalOptionKey(kind)`, `CodeLabTranscriptPanel.rowKey(id)`. Если ключа нет, а нужен — добавляйте его в виджет, а не ищите по типу.
- **Текст.** `find.text('Retry')` работает, пока тест на английском без делегата; с русским делегатом — ищите русский текст (см. ниже).
- **Исключение.** `expect(tester.takeException(), isNull)` — самая дешёвая проверка на переполнение вёрстки и пропущенных предков.

### Язык и тема

Английский без делегата — режим по умолчанию: фолбэк кита сам отдаёт английский. Для русского хост подключает делегат (из `test/codelab_l10n_test.dart`):

```dart
Widget _ruHost(Widget child) => FluentApp(
  locale: const Locale('ru'),
  localizationsDelegates: CodeLabLocalizations.localizationsDelegates,
  supportedLocales: CodeLabLocalizations.supportedLocales,
  home: Align(alignment: Alignment.topLeft, child: child),
);
```

Тёмная тема — `FluentThemeData(brightness: Brightness.dark)`; палитру подменяют через `extensions` (см. [главу о теме](02-theme-and-tokens.md)).

### Ловушки

- **Кнопки Fluent держат таймер.** После `tester.tap` на `Button`, `FilledButton` или `CodeLabButton` в дереве остаётся таймер распознавателя жестов (около 100–167 мс). Без `await tester.pumpAndSettle()` или `await tester.pump(const Duration(milliseconds: 200))` тест падает с `A Timer is still pending even after the widget tree was disposed`. В тестах пакета это отмечено комментариями (`test/codelab_approval_focus_test.dart`, `test/codelab_file_preview_test.dart`, `test/codelab_status_table_test.dart`).
- **Подсветка и задержки живут по таймеру.** Подсветка цели показа держится около 1,5 с, поэтому там, где она мешает, тесты делают несколько кадров, а не `pumpAndSettle` (`test/codelab_agents_pane_test.dart`).
- **Платформа сочетаний.** Клавиши ответа на одобрение зависят от `defaultTargetPlatform`. Тест подменяет `debugDefaultTargetPlatformOverride` и обязательно возвращает `null` в `finally`, иначе платформа протечёт в соседние тесты (так сделано в `test/codelab_shortcut_bindings_test.dart`).
- **Часы модификаторов.** `CodeLabWorkbenchShortcuts(clock: …)` принимает часы; тест `test/codelab_modifier_hold_test.dart` двигает их явно, а не ждёт настоящее время.
- **Общее состояние между тестами.** `CodeLabCodeHighlighter.shared` и счётчики `CodeLabMarkdownStats` — статические. `test/acp_markdown_test.dart` сбрасывает их в `setUp`: `CodeLabMarkdownStats.reset()` и `CodeLabCodeHighlighter.shared.clear()`. Подсветку, в которой нужен фоновый isolate, создают с подменёнными `tokenizer` и `background`.
- **Сеть.** `test/acp_markdown_test.dart` ставит `HttpOverrides.global` с запрещающей реализацией и в `tearDown` проверяет, что ни одного запроса не было: изображение без «Show image» не должно ходить в сеть даже тогда, когда исключение проглотил пакет.

### Фокус и клавиши

Тесты фокуса одобрения доводят фокус до кнопки так же, как пользователь, — клавишей Tab. Для этого есть помощники в `test/support/approval_focus.dart`:

| Помощник | Что делает |
|---|---|
| `focusIsInside(tester, finder)` | фокус Flutter сейчас на элементе внутри `finder` или на нём |
| `tabTo(tester, finder, {maxSteps})` | нажимает Tab, пока фокус не окажется внутри `finder`, иначе падает с причиной |
| `pressPrimary(tester, key, {meta, alt})` | нажимает клавишу с Ctrl или ⌘ (и Alt) |

Причина существования помощников: после отказа от `autofocus` полоса не берёт фокус сама, и каждый сценарий обязан явно довести фокус до кнопки.

## Вёрстка без golden-тестов

Golden-тестов (`matchesGoldenFile`) в пакете нет: поиск по `lib/` и `test/` даёт ноль совпадений. Поэтому в репозитории нет эталонных изображений виджетов и нет процесса их обновления; не вводите его без отдельного решения. Корректность вёрстки проверяют другими средствами:

- `expect(tester.takeException(), isNull)` на разных ширинах и на русском: переполнение `RenderFlex` — это исключение;
- размеры: `tester.getSize(find.byKey(…))` — например, в `test/codelab_settings_row_test.dart` проверяется, что широкий `trailing` на узкой строке сжимается, а на широкой сохраняет свои 260 px, а заголовок остаётся в одну строку;
- оси прокрутки: `test/codelab_markdown_tables_test.dart` ищет `Scrollable` с `Axis.horizontal`, чтобы убедиться, что таблица по умолчанию прокручивается, а с `wrapTables: true` — нет, и что четыре столбца в 600 и 320 px не дают переполнения;
- семантика: `tester.ensureSemantics()` и `find.bySemanticsLabel(…)` проверяют подписи для чтения с экрана (`test/codelab_approval_focus_test.dart`, `test/codelab_l10n_test.dart`);
- превью: `test/codelab_previews_test.dart` строит страницы-превью и проверяет отсутствие исключений в светлой и тёмной теме;
- цвета: `test/codelab_palette_test.dart` читает цвет текста тега из `Text.style` и сверяет с палитрой.

Внешний вид виджета глазами смотрят в превью или в приложении (см. [начало работы](00-getting-started.md)).

## Тесты каталогов и сторожа

Эти тесты не строят виджеты, а читают файлы: `test/l10n_catalogs_test.dart` разбирает ARB как JSON, `test/shortcut_catalog_guard_test.dart` читает исходники `lib/src/**` и ищет запрещённые паттерны. Что они проверяют, описано в [главе о локализации и сочетаниях](04-localization-and-shortcuts.md). Если вы меняете каталог ARB или сочетание, эти тесты первыми скажут, что что-то пропущено.

Тест `test/codelab_shortcut_bindings_test.dart` построен на `switch` без `default` по `CodeLabShortcut`: добавили запись — компилятор требует сценарий нажатия.

## Реальный прогон

Команда, которой получен вывод, — в каталоге `packages/flutter/codelab_ui`:

```bash
fvm flutter test --reporter expanded
```

Вывод сокращён: показаны начало, середина и конец; путь к проекту заменён на относительный.

```text
00:00 +0: loading test/codelab_key_value_list_test.dart
00:00 +0: test/codelab_key_value_list_test.dart: shows labels and values in the given order
…
00:07 +136: test/codelab_transcript_test.dart: conversation a prompt and its reply have no You or Agent labels
…
00:11 +221: test/codelab_transcript_test.dart: follows the transcript tail (follow-transcript-tail) does not move while the user reads history
…
01:00 +927: All tests passed!
```

927 тестов прошли за около минуты. `fvm dart analyze` в том же каталоге ответил `No issues found!`.

Перед pull request кит проверяется по затронутому (корневой `AGENTS.md`, §21): формат, анализ и тесты пакета, а если изменён публичный API — ещё и тесты зависимых пакетов; для изменений ARB — `melos run l10n:check`, для импортов и `pubspec.yaml` — `melos run guard`. Полный `melos run check` запускают по просьбе.

## Смотрите также

- [Начало работы](00-getting-started.md) — один тест, превью.
- [Расширение](06-extending.md) — тест как часть рецепта «новый виджет».
- [Частые проблемы](07-troubleshooting.md) — тест упал: таймеры, тема, локализация.
- [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md) — уровни тестов репозитория.
