# Расширение UI-кита

Глава — сборник рецептов: как добавить виджет, строку текста, сочетание клавиш, цвет палитры и новый вариант строки ленты. В каждом рецепте — шаги, скелет кода и список тестов, которые должны зазеленеть. Скелеты взяты из реального кода пакета и сокращены; где имя придумано для примера, это сказано.

Перед любым рецептом прочитайте [`AGENTS.md`](../AGENTS.md) пакета и [обзор](01-overview.md): граница «никакой логики» определяет, что можно положить в виджет. Если задача меняет поведение продукта или публичное API, она начинается с OpenSpec change (корневой `AGENTS.md`, §17).

## Рецепт 1. Новый виджет

### Шаг 1. Определите слой

| Что делает виджет | Слой |
|---|---|
| минимальный элемент без составных частей кита; заводится при втором употреблении, а не «на вырост» (корневой `AGENTS.md`, §13) | `atomics/` |
| составной из атомов: строка, полоса, группа | `molecules/` |
| лента, плитка, панель дока, экран | `organisms/` |
| рисует markdown-ответ | `rendering/` — только слой, где разрешены `gpt_markdown` и `val_highlight` |

Молекула не импортирует организмы и `rendering`; атом не импортирует ничего выше себя. Нужен кусок организма — опустите его в слой ниже, а не повторяйте исключение `CodeLabPromptComposer`.

### Шаг 2. Напишите виджет

Скелет молекулы «строка-подсказка» — тег тона, текст и необязательное действие (имя `CodeLabHintRow` придумано для примера; код проверен компиляцией и тестом во временном файле, после проверки файл удалён):

```dart
// lib/src/molecules/codelab_hint_row.dart
import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../l10n/strings.dart';

/// Строка-подсказка: тег тона, текст и необязательное действие.
///
/// Почему: …
///
/// Для чего: только вёрстка; что показать и что делает действие, решает хост.
///
/// Как использовать: `CodeLabHintRow(text: …, tone: …, onAction: …)`.
class CodeLabHintRow extends StatelessWidget {
  const CodeLabHintRow({
    required this.text,
    this.tone = CodeLabTone.neutral,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  static const actionKey = ValueKey('hint-row-action');

  final String text;
  final CodeLabTone tone;

  /// Подпись действия; `null` — текст кита («Retry» из каталога).
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final onAction = this.onAction;
    return Row(
      children: [
        CodeLabBadge(label: text, tone: tone),
        if (onAction != null) ...[
          const SizedBox(width: 8),
          CodeLabButton(
            key: actionKey,
            label: actionLabel ?? codeLabStringsOf(context).codeLabActionRetry,
            onPressed: onAction,
          ),
        ],
      ],
    );
  }
}
```

Что здесь по правилам пакета:

- параметры — готовые значения (`String`, `CodeLabTone`, колбэк), а не модели ACP или клиентского ядра;
- текст по умолчанию берётся из каталога и объявлен как `String?`, чтобы явная строка вызывающего показывалась как есть;
- цвета идут через `CodeLabBadge` и палитру, а не литералами;
- ключ для тестов — `static const`, а не строка в тесте;
- doc-комментарий отвечает на три вопроса «почему, для чего, как» и написан по-русски (корневой `AGENTS.md`, §15).

### Шаг 3. Экспортируйте

Добавьте файл в барель своего слоя, например в `lib/src/molecules/molecules.dart`:

```dart
export 'codelab_hint_row.dart';
```

Без экспорта виджет не виден приложению. Внутренние детали (как `CodeLabPressable`) в барель не добавляют.

### Шаг 4. Превью

Превью на фиктивных данных кладут в файл превью слоя (`codelab_molecule_previews.dart` или `codelab_organism_previews.dart`). Оболочка `_AcpPreviewSurface` в файле молекул — приватная, поэтому превью дописывается именно туда:

```dart
// в начало файла превью, к остальным импортам молекул:
import 'codelab_hint_row.dart';

@Preview(
  name: 'Hint row',
  group: codelabMoleculePreviewGroup,
  size: Size(420, 80),
)
Widget codelabHintRowPreview() {
  return _AcpPreviewSurface(
    child: CodeLabHintRow(
      text: 'Offline',
      tone: CodeLabTone.warning,
      onAction: codelabPreviewCancel,
    ),
  );
}
```

В данных превью нет секретов и настоящих путей пользователя. Если виджету нужны русский язык или тёмная тема — добавьте второй вариант: у `_AcpPreviewSurface` есть параметр `brightness`, у `_AcpOrganismPreviewSurface` — `brightness` и `locale`.

### Шаг 5. Тест превью и тест виджета

Вызовите превью в `test/codelab_previews_test.dart` (он не вызывает 8 из 56 существующих превью; не повторяйте это):

```dart
await tester.pumpWidget(codelabHintRowPreview());
expect(tester.takeException(), isNull);
expect(find.byType(CodeLabHintRow), findsOneWidget);
```

И напишите widget-тест виджета в `test/codelab_hint_row_test.dart` (проверялся во временном файле):

```dart
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Locale? locale}) => FluentApp(
  locale: locale,
  localizationsDelegates: CodeLabLocalizations.localizationsDelegates,
  supportedLocales: CodeLabLocalizations.supportedLocales,
  home: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  testWidgets('shows the default action label from the catalog', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host(
        CodeLabHintRow(
          text: 'Offline',
          tone: CodeLabTone.warning,
          onAction: () => pressed++,
        ),
      ),
    );
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.byKey(CodeLabHintRow.actionKey));
    await tester.pumpAndSettle(); // кнопка Fluent оставляет таймер
    expect(pressed, 1);
  });
}
```

Без `pumpAndSettle` после нажатия тест падает на «Timer is still pending» — см. [главу о тестировании](05-testing.md).

### Шаг 6. Подключите в приложении

Приложение создаёт виджет и передаёт данные через маппер. Логика остаётся в приложении. Как — в руководстве приложения, глава [«Расширение»](../../../../apps/codelab_desktop/doc/09-extending.md).

### Проверка

В каталоге пакета:

```bash
fvm dart format --set-exit-if-changed lib test
fvm dart analyze
fvm flutter test
```

Если виджет использует `freezed`-тип, перегенерируйте код: `fvm dart run build_runner build --delete-conflicting-outputs`.

## Рецепт 2. Новая строка текста

Видимый текст виджета — только через каталог: литерал в `Text('…')` поймает сторож `ui_literals_test.dart`.

1. Добавьте сообщение в `lib/src/l10n/codelab_ui_en.arb` с описанием. Ключ — `codeLab<Область><Смысл>`:

   ```json
   "codeLabHintOffline": "Offline",
   "@codeLabHintOffline": {
     "description": "Подпись тега в строке-подсказке, когда соединения нет."
   }
   ```

2. Добавьте перевод в `codelab_ui_ru.arb` — без блока `@…`:

   ```json
   "codeLabHintOffline": "Нет соединения"
   ```

   Формулировку берите из [глоссария](../../../../docs/architecture/l10n-glossary.md); если термина там нет, выберите так, как он принят в соседних сообщениях каталога.

3. Для количества — только `plural`, а в `ru` — все четыре формы. Блок `@…` содержит `placeholders` с типом:

   ```json
   "codeLabHintRetries": "{count, plural, other{{count} retries left}}",
   "@codeLabHintRetries": {
     "description": "Сколько повторов осталось. count — число повторов.",
     "placeholders": { "count": { "type": "int" } }
   }
   ```

   ```json
   "codeLabHintRetries": "{count, plural, one{остался {count} повтор} few{осталось {count} повтора} many{осталось {count} повторов} other{осталось {count} повтора}}"
   ```

4. Сгенерируйте код в каталоге пакета:

   ```bash
   mkdir -p build
   fvm flutter gen-l10n
   ```

   `mkdir -p build` нужен в свежем checkout: `l10n.yaml` пишет `build/l10n_untranslated.json`, а `gen-l10n` каталог сам не создаёт и падает (проверено на копии без `build/`).

   Генератор создаёт в `lib/src/l10n/` геттер `codeLabHintOffline` и метод `codeLabHintRetries(int count)` (проверено на копии каталога во временном каталоге). Сгенерированные файлы коммитятся.

5. Используйте в виджете:

   ```dart
   final strings = codeLabStringsOf(context);
   CodeLabBadge(label: strings.codeLabHintOffline);
   CodeLabText(strings.codeLabHintRetries(3));
   ```

6. Если сообщение — подпись из фиксированного словаря (статус, риск, тон), добавьте проверку русского текста в `test/codelab_l10n_test.dart`. Сообщение, связанное с одобрением или риском, получает в описании пометку `Метка security (D14): перевод не смягчает смысл.`

7. Проверьте:

   ```bash
   fvm flutter test test/l10n_catalogs_test.dart test/codelab_l10n_test.dart
   ```

   Из корня репозитория: `fvm dart run tool/l10n_check.dart --package packages/flutter/codelab_ui` или `melos run l10n:check`.

Если текст приходит от приложения или агента, он в каталог не попадает: приложение передаёт его готовой строкой. Клавиши и идентификаторы тоже не переводятся.

## Рецепт 3. Новое сочетание клавиш

Литералы активаторов вне `lib/src/atomics/codelab_shortcuts.dart` запрещены сторожем, поэтому путь всегда начинается с каталога.

1. **Запись в каталоге.** Добавьте значение в `enum CodeLabShortcut` в том месте, где строка должна стоять на странице «Keyboard» (порядок записей — порядок строк). Имя `toggleUsage` придумано для примера:

   ```dart
   /// Показать или скрыть панель Usage: Cmd/Ctrl+Shift+U (пример).
   toggleUsage(CodeLabShortcutGroup.navigation, [
     CodeLabKeyCombo(LogicalKeyboardKey.keyU, primary: true, shift: true),
   ]),
   ```

   Если клавиши различаются по платформам, общие комбинации оставляют пустыми и задают `macCombos` и `otherCombos`, как у `allowOnce`:

   ```dart
   allowOnce(
     CodeLabShortcutGroup.approvals,
     [],
     macCombos: [CodeLabKeyCombo(LogicalKeyboardKey.keyY, meta: true)],
     otherCombos: [
       CodeLabKeyCombo(LogicalKeyboardKey.keyY, alt: true, shift: true),
     ],
   ),
   ```

2. **Привязка.** Для глобального действия рабочего места добавьте колбэк в `CodeLabWorkbenchShortcuts` и привяжите его через каталог:

   ```dart
   // конструктор и поле виджета
   this.onToggleUsage,
   final VoidCallback? onToggleUsage;

   // build в State: колбэк читается из widget в локальную переменную,
   // чтобы сработало продвижение типа до не-null
   final onToggleUsage = widget.onToggleUsage;
   // …
   if (onToggleUsage != null)
     ...CodeLabShortcut.toggleUsage.bind(onToggleUsage),
   ```

   Для сочетания внутри своего виджета привязывайте через `CallbackShortcuts(bindings: CodeLabShortcut.x.bind(action))`. Если у альтернатив разные действия (как у меню команд), привязывайте по `combos[i].activators`. Событие, которое читается вручную, сверяйте через `combo.accepts(event, HardwareKeyboard.instance)`.

3. **Тест на нажатие.** В `test/codelab_shortcut_bindings_test.dart` функция `_checkOf` — `switch` без `default`: пока записи нет в нём, пакет не компилируется. Добавьте строку `CodeLabShortcut.toggleUsage => const _InKit(_workbenchShortcut),` и передайте новый колбэк в `CodeLabWorkbenchShortcuts` внутри `_workbenchShortcut`:

   ```dart
   onToggleUsage: shortcut == CodeLabShortcut.toggleUsage ? hit : null,
   ```

   Если сочетание привязывает приложение, помечайте `const _InApp()` и покрывайте его тестом приложения.

4. **Каталожные тесты.** Число записей зашито в двух тестах: `CodeLabShortcut.values` из `hasLength(24)` в `test/codelab_shortcut_bindings_test.dart` и «24 записи по порядку и группам» в `test/codelab_shortcuts_test.dart`. Обновите число и порядок. Если запись с платформенными комбинациями, добавьте проверки в группу «сочетания ответа на одобрение».

5. **Приложение.** Страница «Keyboard» (`apps/codelab_desktop/lib/features/settings/presentation/keyboard_page.dart`) перебирает все записи и называет действие и место в `switch` без `default`. Приложение не соберётся, пока для записи нет текстов в `AppLocalizations`; добавьте их в оба ARB приложения. Колбэк для `CodeLabWorkbenchShortcuts` передаёт `workbench_shell.dart`.

6. **Платформы и раскладки.** Не пишите отдельных проверок раскладки: каталог сверяет логическую клавишу (см. [главу 04](04-localization-and-shortcuts.md)). Выбирая клавиши, проверьте конфликты с текстовым вводом на Windows и Linux и с раскладкой Cocoa на macOS.

7. **Проверка.** `fvm flutter test test/codelab_shortcuts_test.dart test/codelab_shortcut_bindings_test.dart test/shortcut_catalog_guard_test.dart`.

## Рецепт 4. Новый цвет палитры или новый тон

### Новый цвет в палитре

Цвет, которым должна управлять тема, добавляют в `CodeLabPalette` (`lib/src/atomics/codelab_palette.dart`). Цвет в пяти местах класса (конструктор, поле, `_derive`, `copyWith`, `lerp`) — иначе тема его не подменит или пропадёт при смене темы. Имя `hint` придумано для примера:

```dart
const CodeLabPalette({
  required this.success,
  // …
  required this.selection,
  required this.hint,
});

final Color hint;

factory CodeLabPalette._derive(FluentThemeData theme) => CodeLabPalette(
  // …
  hint: theme.resources.textFillColorSecondary,
);

// copyWith: Color? hint → hint: hint ?? this.hint
// lerp:     hint: mix(hint, other.hint)
```

Что ещё затронет изменение:

- Поле обязательное, поэтому все литералы `CodeLabPalette(...)` в тестах и превью (`test/codelab_palette_test.dart`, `codelabCustomPalettePreview`) надо дополнить. Если не хотите ломать их, сделайте значение необязательным с выводом из темы.
- Значение «без расширения» (в `_derive`) должно совпадать с прежним видом: спецификация «Цвета кита из палитры темы» требует, чтобы без расширения вид не менялся.
- Пользовательские темы задают цвета ролями `ThemeRole` (`packages/dart/codelab_client_core/lib/src/themes/theme_role.dart`). Чтобы тема могла управлять новым цветом, нужна новая роль, а `buildFluentTheme` в `apps/codelab_desktop/lib/app/appearance/fluent_theme_builder.dart` должна передать её в `derived.copyWith(...)`. Это работа вне кита (клиентский слой и приложение, и, возможно, OpenSpec change).
- Тест на цвет из расширения и без него — по образцу `test/codelab_palette_test.dart`.

### Новый тон

Новое значение `CodeLabTone` — более тяжёлое изменение. Анализатор покажет все исчерпывающие `switch` по `CodeLabTone`:

- `CodeLabPalette.toneColor` — цвет тона;
- `_toneLabel` в `lib/src/molecules/codelab_approval_option_group.dart` — подпись тона варианта одобрения из каталога (`codeLabApprovalToneInfo`, `…Safe`, `…Review`, `…Risk`, `…Option`): новый тон требует нового сообщения с пометкой `security`;
- `_backgroundColorForTone` в `codelab_badge.dart` имеет ветку по умолчанию — проверьте, нужна ли отдельная прозрачность.

Прежде чем вводить тон, убедитесь, что он нужен: смысл «успех, предупреждение, опасность, акцент, нейтрально» покрывает почти все случаи. Пары «значение — тон» (`CodeLabApprovalRisk`, `CodeLabToolCallStatus`) решайте в самих перечислениях.

## Рецепт 5. Новый вариант строки ленты

`CodeLabTranscriptRow` — запечатанный класс, поэтому компилятор сам перечисляет места, где вариант нужно обработать. Шаги:

1. **Класс строки.** В `lib/src/organisms/codelab_transcript_row.dart` добавьте `final class` с `id` и готовыми полями. Поля — строки, перечисления, колбэки; никаких моделей клиентского ядра. Имя `CodeLabCheckpointRow` придумано для примера:

   ```dart
   /// Строка контрольной точки: короткий текст и значок.
   ///
   /// Почему: … Для чего: … Как использовать: строку строит маппер приложения,
   /// [id] стабилен между обновлениями ленты.
   final class CodeLabCheckpointRow extends CodeLabTranscriptRow {
     const CodeLabCheckpointRow({required this.id, required this.text});

     @override
     final String id;

     /// Готовый текст: виджет его не разбирает.
     final String text;
   }
   ```

2. **Виджет строки.** Создайте виджет в `lib/src/organisms/` (по образцу `CodeLabTaskOpsLine`) и экспортируйте, если он публичный. Любой текст от модели прогоните через `escapeForDisplay`.

3. **Основной `switch`.** В `_TranscriptRowView` (`lib/src/organisms/codelab_transcript_panel.dart`) `switch` по строке исчерпывающий — без нового `case` анализатор выдаст ошибку:

   ```dart
   CodeLabCheckpointRow(:final text) => CodeLabCheckpointLine(text: text),
   ```

4. **Места с веткой по умолчанию.** Здесь анализатор молчит, а строка тихо не нарисуется. Решите для каждого, может ли ваша строка там появиться:

   | Место | Ветка | Что значит |
   |---|---|---|
   | `codelab_tool_call_tile.dart`, вложенные строки субагента (`children`) и «хвост» работающего `agent` | `_ => const SizedBox.shrink()` | неизвестный вариант внутри субагента не рисуется |
   | `codelab_agents_pane.dart`, обход шагов (`_collect`) | `default: break` | строка не попадёт в панель Agents |
   | `CodeLabSubagentCall._key` (`codelab_transcript_row.dart`) | `_ => ('other', row.id)` | в сравнении хвоста строка различается только по `id` |
   | `_expandedByDefault` (`codelab_transcript_panel.dart`) | `_ => false` | по умолчанию строка свёрнута |

5. **Раскрытие и ключи.** Если у строки есть раскрываемая часть, состояние держит хост через `expansionOverrides` по `id` строки; не храните его в `State` виджета. Временный просмотр («Show full command») можно держать в `State`.

6. **Приложение.** Маппер `transcriptRowsOf` в `apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart` строит новый вариант из элемента транскрипта клиентского ядра. Новый элемент транскрипта — работа клиентского слоя, а не кита.

7. **Тесты.**
   - `test/codelab_transcript_test.dart` — строка рисуется и не переполняется на узкой колонке;
   - если строка может быть вложенной или попадать в «хвост» — тесты по образцу `test/codelab_subagent_row_test.dart`;
   - превью с новой строкой рядом с `codelabTranscriptPanelPreview` и вызов в `test/codelab_previews_test.dart`;
   - русские подписи — в каталоге и в `test/codelab_l10n_test.dart`, если строка вводит словарь.

8. **Прокрутка к строке.** Если на строку можно перейти из панели Agents, ей нужна цель: `CodeLabTranscriptPanel.rowKey(id)` строки верхнего уровня и `targetKey` для вложенной цели (см. [ключевые виджеты](03-key-widgets.md)).

## Смотрите также

- [Обзор](01-overview.md) — слои и граница «никакой логики».
- [Локализация и сочетания клавиш](04-localization-and-shortcuts.md) — подробности каталога и сторожей.
- [Тестирование](05-testing.md) — как устроены тесты.
- [Частые проблемы](07-troubleshooting.md) — если рецепт закончился красным тестом.
- Руководство приложения: [«Расширение»](../../../../apps/codelab_desktop/doc/09-extending.md) — рецепты на стороне `codelab_desktop`.
