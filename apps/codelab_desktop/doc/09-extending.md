# Как расширять app

Глава собирает рецепты типовых изменений `apps/codelab_desktop`: новая фича, страница настроек, строка интерфейса, сочетание клавиш, порт платформы, вид строки ленты. У каждого рецепта одна схема: нужен ли OpenSpec change, шаги, скелет кода, тест, проверки. Как собрать, запустить и проверить приложение — в [development.md](development.md) и [главе 00](00-getting-started.md).

Перед рецептами прочитайте [01-overview.md](01-overview.md) (слои и карта `lib/`) и [02-composition-root.md](02-composition-root.md) (как собираются Cubit-ы и порты). Правила приложения — в [`AGENTS.md`](../AGENTS.md); как писать тесты из рецептов — в [08-testing.md](08-testing.md).

## Когда нужен OpenSpec change

Корневой [`AGENTS.md`](../../../AGENTS.md) (§17) требует change для изменения поведения продукта, контрактов ACP, публичного API, семантики хранения, безопасности и существенной архитектуры. Для app это означает:

| Изменение | Change |
|---|---|
| новая страница настроек, новая фича с видимым поведением, новое сочетание клавиш, новый вид строки ленты | нужен: меняется поведение, а спецификации [app-settings](../../../openspec/specs/app-settings/spec.md) и [agent-workbench-ui](../../../openspec/specs/agent-workbench-ui/spec.md) его описывают |
| новый порт платформы с видимым пользователю эффектом | нужен; чисто внутренний порт без нового поведения — нет |
| новая строка ARB и её перевод в уже описанном экране | не нужен |
| переименование внутренних классов, перенос файла, новая проверка в существующем тесте | не нужен |

Если сомневаетесь — начните с `codelab-architect` (команда `/change`). Нельзя молча менять спецификацию под готовый код (`AGENTS.md` §17). Для каждого рецепта ниже есть проверки по [08-testing.md](08-testing.md#какие-проверки-затрагивает-изменение); полный `melos run check` перед pull request запускают только по просьбе пользователя.

Скелеты в этой главе взяты из реального кода; фрагменты новой фичи «папка активной сессии» (`ActiveFolderCubit`) проверены компиляцией и тестами во временных файлах, которые затем удалены. Имена `ActiveFolder…` и `Notes` вымышлены; всё остальное — настоящие идентификаторы.

## Рецепт 1. Новая фича

Фича — каталог `lib/features/<фича>/` со слоями `application/` (Cubit-ы и состояние, без виджетов) и `presentation/` (виджеты). Слои `domain/` и `infrastructure/` не создаются: доменная логика живёт в `codelab_client_core`, адаптеры — в `lib/core/platform/` и `lib/app/` ([карта кода](01-overview.md#карта-кода)). Пустые слои ради формы запрещены (`AGENTS.md` §6, §13).

### Шаги

1. **Определите, чей это код.** Состояние сессий, транскрипта, одобрений, очереди промптов и рабочего пространства принадлежит `codelab_client_core`. Cubit app только подписывается на него и отображает. Если вам нужна новая логика такого рода, она идёт в клиентский слой (задача `client-engineer`), а не в app.
2. **Состояние.** Неизменяемый класс или закрытая иерархия, а не набор булевых флагов (`AGENTS.md` §8). Образцы: `StartupSettingsState` (два значения), `ProjectTreeState` с `enum ProjectTreeStatus` и `sealed class FilePreviewState`.
3. **Cubit.** Подписка на `ClientWorkspace.state` создаётся в конструкторе и отменяется в `close()`; результат более позднего события не должен перезаписываться более ранним (`concurrency.md`, [08-testing.md](08-testing.md#cubit-с-подпиской-и-таймерами)).
4. **Регистрация.** Выберите срок жизни (таблица ниже) и пропишите Cubit в `CodeLabPresentationModule` (`lib/app/app_scope.dart`).
5. **Виджет.** `BlocBuilder`, текст — `context.l10n` ([рецепт 3](#рецепт-3-новая-строка-интерфейса)), стабильные `ValueKey` для всего, что нажимают тесты.
6. **Журнал.** События без путей, содержимого файлов и текста исключений: только имя типа ошибки (`AGENTS.md` §16). Логгер строится как у остальных Cubit-ов приложения.
7. **Тесты** и **проверки** — ниже.

### Срок жизни Cubit-а

| Срок жизни | Когда | Как регистрируется | Кто закрывает | Пример |
|---|---|---|---|---|
| на открытие страницы или панели | состояние нужно, пока виджет на экране | `bind<X>().toProvide(…)` без `singleton`; поле `createXCubit` в `CodeLabDependencies`; хозяин виджета создаёт Cubit и закрывает в `dispose` | `State` хозяина | `StartupSettingsCubit` (`app_scope.dart`, `GeneralPageHost` в `general_page.dart`) |
| на окно, лениво | состояние должно пережить закрытие вкладки дока, но создаётся только по требованию | держатель `Disposable` (`ProjectFilesHolder`), который создаёт Cubit при первом обращении | scope при `dispose` | `ProjectFilesCubit` |
| на окно, всегда | события нужны, даже когда панель закрыта | `bind<X>().toProvide(…).singleton()`; поле в `CodeLabDependencies`; `BlocProvider.value` в `CodeLabApp`; закрытие в `CodeLabRootLifecycle` (шаг `cubits` в `_closeClient`) | `CodeLabRootLifecycle` | `ProtocolPaneCubit` |

Для новой фичи начинайте с первой строки: она не требует правки жизненного цикла приложения. Третья строка требует ещё правки контракта `CodeLabRootLifecycleModuleContract` и перегенерации `lib/app/app_scope.module.cherrypick.g.dart` через `build_runner` — это затрагивает порядок закрытия при выходе ([02-composition-root.md](02-composition-root.md)).

### Скелет: состояние и Cubit

`lib/features/active_folder/application/active_folder_state.dart`:

```dart
/// Папка, которую показывает бейдж: `cwd` сессии в фокусе или папка проекта.
final class ActiveFolderState {
  const ActiveFolderState({this.folder});

  /// `null` — нет ни сессии, ни выбранного проекта.
  final String? folder;
}
```

`lib/features/active_folder/application/active_folder_cubit.dart`:

```dart
import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, WorkspaceState;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'active_folder_state.dart';

/// Папка активной сессии для бейджа.
final class ActiveFolderCubit extends Cubit<ActiveFolderState> {
  ActiveFolderCubit({required ClientWorkspace workspace, Logger? logger})
    : _logger = logger,
      super(ActiveFolderState(folder: _folderOf(workspace.current))) {
    _subscription = workspace.state.listen(_onWorkspace);
  }

  final Logger? _logger;
  late final StreamSubscription<WorkspaceState> _subscription;

  void _onWorkspace(WorkspaceState next) {
    final folder = _folderOf(next);
    if (folder == state.folder) return;
    _logger?.debug('active_folder.changed'); // без пути: AGENTS.md §16
    emit(ActiveFolderState(folder: folder));
  }

  @override
  Future<void> close() async {
    await _subscription.cancel(); // подписка отменяется вместе с Cubit-ом
    return super.close();
  }
}

String? _folderOf(WorkspaceState state) {
  final active = state.activeSessionId;
  for (final session in state.sessions) {
    if (session.id == active) return session.cwd;
  }
  return state.projectDirectory;
}
```

Что здесь стоит запомнить. Cubit получает `ClientWorkspace` конструктором, а не достаёт из глобального места. Начальное состояние строится из `workspace.current`, поэтому виджет не мигает пустым значением. Cubit сравнивает папку вручную: у обычного класса `==` — тождество, и `emit` с равным значением всё равно породил бы перерисовку.

### Скелет: регистрация

В `CodeLabPresentationModule.builder` (`lib/app/app_scope.dart`), рядом с `StartupSettingsCubit`:

```dart
bind<ActiveFolderCubit>().toProvide(
  () => ActiveFolderCubit(
    workspace: currentScope.resolve<ClientWorkspace>(),
    logger: StructuredLogLogger('codelab_desktop.active_folder').bind({
      logCategoryKey: applicationLogCategory,
      logComponentKey: 'active_folder',
    }),
  ),
);
```

В `CodeLabDependencies` — обязательный параметр конструктора, поле и значение при сборке в `_CodeLabBootstrapState`:

```dart
// final class CodeLabDependencies
required this.createActiveFolderCubit,
// …
final ActiveFolderCubit Function() createActiveFolderCubit;

// _CodeLabBootstrapState: late final CodeLabDependencies _dependencies = CodeLabDependencies(…
createActiveFolderCubit: _scope.resolve<ActiveFolderCubit>,
```

Тесты не создают `CodeLabDependencies` сами (конструктор вызывается только в `app_scope.dart`), поэтому другие места править не нужно.

### Скелет: хозяин и виджет

`lib/features/active_folder/presentation/active_folder_badge.dart`:

```dart
import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart' show codeLabDependenciesOf;
import '../../../l10n/l10n.dart';
import '../application/active_folder_cubit.dart';
import '../application/active_folder_state.dart';

/// Хозяин: создаёт Cubit через composition root и закрывает вместе с виджетом.
class ActiveFolderBadgeHost extends StatefulWidget {
  const ActiveFolderBadgeHost({super.key});

  @override
  State<ActiveFolderBadgeHost> createState() => _ActiveFolderBadgeHostState();
}

class _ActiveFolderBadgeHostState extends State<ActiveFolderBadgeHost> {
  ActiveFolderCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit ??= codeLabDependenciesOf(context).createActiveFolderCubit();
  }

  @override
  void dispose() {
    unawaited(_cubit?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocProvider.value(value: _cubit!, child: const ActiveFolderBadge());
}

class ActiveFolderBadge extends StatelessWidget {
  const ActiveFolderBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActiveFolderCubit, ActiveFolderState>(
      builder: (context, state) => Text(
        state.folder ?? context.l10n.activeFolderNone, // ключ ARB — рецепт 3
        key: const ValueKey('active-folder-badge'),
      ),
    );
  }
}
```

Виджет не создаёт Cubit и порты сам: их собирает composition root, а хозяин получает только владение жизненным циклом (образец — `GeneralPageHost`, `AgentsModesPageHost`). Виджет не читает файлы и не обращается к ACP (`AGENTS.md` §6, §7).

### Тест Cubit-а

`test/features/active_folder/application/active_folder_cubit_test.dart` (запущен, 3 теста зелёные):

```dart
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/active_folder/application/active_folder_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_client_workspace.dart';

void main() {
  late FakeClientWorkspace workspace;
  late ActiveFolderCubit cubit;

  setUp(() {
    workspace = FakeClientWorkspace(
      const WorkspaceState(projectDirectory: '/work/app'),
    );
    cubit = ActiveFolderCubit(workspace: workspace);
  });

  tearDown(() async {
    await cubit.close();
    await workspace.close();
  });

  test('без сессии показывает папку проекта', () {
    expect(cubit.state.folder, '/work/app');
  });

  test('сессия в фокусе заменяет папку проекта', () async {
    final id = SessionId('s1');
    workspace.emit(
      workspace.current.copyWith(
        activeSessionId: id,
        sessions: [
          SessionSummaryView(
            id: id,
            cwd: '/work/other',
            status: SessionStatusView.idle,
          ),
        ],
      ),
    );
    await pumpEventQueue();

    expect(cubit.state.folder, '/work/other');
  });

  test('close отменяет подписку на рабочее пространство', () async {
    expect(workspace.hasStateListeners, isTrue);

    await cubit.close();

    expect(workspace.hasStateListeners, isFalse);
  });
}
```

### Тест виджета

`test/features/active_folder/presentation/active_folder_badge_test.dart` (запущен, зелёный; в проверенной версии вместо ключа `activeFolderNone` стоял существующий `commonRetry`, потому что новый ключ ARB требует `gen-l10n`):

```dart
testWidgets('бейдж показывает папку и следует за рабочим пространством', (
  tester,
) async {
  final workspace = FakeClientWorkspace(
    const WorkspaceState(projectDirectory: '/work/app'),
  );
  final cubit = ActiveFolderCubit(workspace: workspace);
  addTearDown(() async {
    await cubit.close();
    await workspace.close();
  });

  await tester.pumpWidget(
    localizedFluentApp(
      BlocProvider.value(value: cubit, child: const ActiveFolderBadge()),
    ),
  );
  expect(find.byKey(const ValueKey('active-folder-badge')), findsOneWidget);
  expect(find.text('/work/app'), findsOneWidget);

  workspace.emit(const WorkspaceState(projectDirectory: '/work/next'));
  await tester.pump();

  expect(find.text('/work/next'), findsOneWidget);
});
```

Тест проверяет хозяина отдельно: для него нужен настоящий граф app — `CodeLabTestBinding` и `CodeLabApp` ([08-testing.md](08-testing.md#страница-в-настоящем-дереве-app)).

### Проверки

- `fvm dart format --set-exit-if-changed` для новых файлов, `fvm flutter analyze` и `fvm flutter test test/features/active_folder` в `apps/codelab_desktop`.
- `fvm dart run melos run l10n:check`, если добавили строки ARB.
- `fvm dart run melos run guard`, если фича добавляет импорты между пакетами или собственную границу. Правило для новой границы (например, «`application` фичи без `dart:io`») добавляется в `packages/dart/codelab_architecture_tests/test/support/rules.dart` вместе с фичей: для `usage`, `protocol`, `terminal` и `onboarding` такие правила уже есть.
- Если фича меняет описанное в `README.md`, `doc/` или `AGENTS.md` приложения, обновите документ в том же change.

## Рецепт 2. Новая страница настроек

Страницы настроек лежат в `lib/features/settings/`. Навигация, выбор страницы и сохранение последней открытой описаны в [04-navigation-and-settings.md](04-navigation-and-settings.md). Здесь — что менять для новой страницы.

### Шаги

1. **Значение `SettingsPage`** (`lib/app/navigation/settings_page.dart`). В enum заведены двенадцать страниц двух групп `SettingsGroup.agent` и `SettingsGroup.app`; в сборке видны девять (`defaultSettingsPages`). Три страницы — `permissionsAndTools`, `redaction`, `codeAndWeb` — заведены, но скрыты, пока у них нет содержимого (SETUP-17).
   - Если вы наполняете одну из этих трёх, значение enum не трогайте; перейдите к шагу 3 и замените ветку `''` для неё в `settingsPageKeywordsOf`.
   - Если страница новая, добавьте значение `name(SettingsGroup.<группа>, 'kebab-slug')` **в нужное место**: порядок значений — порядок показа. `slug` — значение, которое сохраняется как `codelab.settings.last_page`; переименование ломает сохранённый выбор пользователя.
2. **Исчерпывающие `switch` по `SettingsPage`.** Новое значение не скомпилируется, пока не добавлены ветки в `settingsPageTitleOf` и `settingsPageKeywordsOf` (`lib/features/settings/presentation/settings_titles.dart`) и в `_iconOf` (`settings_shell.dart`).
3. **Строки ARB** в оба каталога: заголовок `settingsPage<Имя>Title` (пункт навигации и заголовок страницы), ключевые слова поиска `settingsSearchKeywords<Имя>` (слова и короткие фразы через запятую), строки самой страницы ([рецепт 3](#рецепт-3-новая-строка-интерфейса)).
4. **Cubit** — если у страницы есть данные или запись. Файлы и процессы — только через порт, реализацию которого собирает `lib/app/`; `lib/features/settings/presentation/` не импортирует `dart:io` и `package:codelab_setup/io.dart` (правило сторожа). Страница без внешних данных обходится без Cubit-а: так устроена «Keyboard» (запрос поиска — в `State` страницы).
5. **Страница и построитель**: `Widget buildNotesPage(BuildContext context)` и запись в `settingsPageBuilders` (`settings_shell.dart`).
6. **Фабрика Cubit-а** в `CodeLabPresentationModule` и поле в `CodeLabDependencies`, как в [рецепте 1](#скелет-регистрация); Cubit страницы создаётся на каждое открытие.
7. **Видимость**: значение в `defaultSettingsPages` (`lib/app/default_settings_pages.dart`). Страница из набора обязана иметь построитель.
8. **Ключи `ValueKey`**: тело страницы — `settings-<slug>`, элементы — `settings-<slug>-<элемент>`; ключ пункта навигации `settings-nav-<slug>` даёт `SettingsPage.navKey` сам.

### Скелет: страница без Cubit-а

Образец — `lib/features/settings/presentation/keyboard_page.dart`:

```dart
Widget buildNotesPage(BuildContext context) => const NotesPage();

class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey('settings-notes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodeLabText(l10n.settingsNotesTitle, role: CodeLabTextRole.title),
        // … содержимое страницы
      ],
    );
  }
}
```

### Скелет: страница с Cubit-ом

Образец — `GeneralPageHost` (`lib/features/settings/presentation/general_page.dart`). Хозяин получает фабрику у composition root, при открытии запускает загрузку и закрывает Cubit с виджетом. Скелет с существующим `StartupSettingsCubit` проверен компиляцией во временном файле (удалён):

```dart
Widget buildNotesPage(BuildContext context) => const NotesPageHost();

class NotesPageHost extends StatefulWidget {
  const NotesPageHost({super.key});

  @override
  State<NotesPageHost> createState() => _NotesPageHostState();
}

class _NotesPageHostState extends State<NotesPageHost> {
  NotesCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final cubit = codeLabDependenciesOf(context).createNotesCubit();
      _cubit = cubit;
      unawaited(cubit.load()); // чтение при открытии: снимок всегда свежий
    }
  }

  @override
  void dispose() {
    unawaited(_cubit?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocProvider.value(value: _cubit!, child: const NotesPage());
}
```

Регистрация в таблицах:

```dart
// lib/features/settings/presentation/settings_shell.dart
final Map<SettingsPage, WidgetBuilder> settingsPageBuilders =
    Map.unmodifiable(<SettingsPage, WidgetBuilder>{
      // …
      SettingsPage.notes: buildNotesPage,
    });

// lib/app/default_settings_pages.dart
const defaultSettingsPages = SettingsPages(
  available: {
    // …
    SettingsPage.notes,
  },
);

// lib/features/settings/presentation/settings_titles.dart
SettingsPage.notes => l10n.settingsPageNotesTitle,          // settingsPageTitleOf
SettingsPage.notes => l10n.settingsSearchKeywordsNotes,     // settingsPageKeywordsOf
```

### Тест

Минимум для страницы:

1. **Регистрация.** Страница стоит в видимом наборе, имеет построитель и ключ навигации — по образцу `keyboard_page_test.dart`:

   ```dart
   expect(defaultSettingsPages.visible, contains(SettingsPage.keyboard));
   expect(SettingsPage.keyboard.group, SettingsGroup.app);
   expect(SettingsPage.keyboard.navKey, 'settings-nav-keyboard');
   expect(settingsPageBuilders, contains(SettingsPage.keyboard));
   ```

2. **Содержимое.** Страница в `SettingsShell` с `localizedFluentApp` (страница без Cubit-а) или в дереве `CodeLabApp` через `CodeLabTestBinding` (с Cubit-ом): [08-testing.md](08-testing.md#виджет-тест-страницы).
3. **Cubit.** Тест Cubit-а на порте-двойнике ([08-testing.md](08-testing.md#тест-cubit-а)).
4. **Язык.** Тест с `ru` и `expectNoStaleLanguage`; сквозные `language_switch_sweep_test.dart` и `dark_theme_sweep_test.dart` обходят все страницы из `defaultSettingsPages` автоматически, поэтому новая страница в них попадёт сама и должна пройти.

### Проверки

`fvm flutter test` для затронутых файлов, `fvm dart run melos run l10n:check` (ARB), `fvm dart run melos run guard` (если страница вводит порт или импорт между пакетами). Поведение страницы описывает спецификация [app-settings](../../../openspec/specs/app-settings/spec.md); обновите документ приложения ([user-guide.md](user-guide.md)), если страница видна пользователю.

## Рецепт 3. Новая строка интерфейса

Тексты интерфейса живут в каталогах `lib/l10n/app_en.arb` (шаблон) и `lib/l10n/app_ru.arb`; код каталога генерирует `gen-l10n` (настройка — `l10n.yaml`). Подробно о трёх видах текста и порте `AppStrings` — в [05-localization.md](05-localization.md).

### Шаги

1. **Ключ** в оба каталога. Имя — camelCase `<экран><элемент><смысл>` (`settingsKeyboardActionToggleFiles`, `usageStepToolCalls`).
2. **Описание.** У каждого сообщения шаблона есть `@ключ` с `description` — контекстом для переводчика (по-русски). Если у сообщения есть плейсхолдеры, они описываются в `placeholders` с типом. Строки одобрения и безопасности несут в описании метку `security`: перевод не смягчает смысл (D14 `add-desktop-localization`).
3. **Русский текст** — по [глоссарию](../../../docs/architecture/l10n-glossary.md). В `app_ru.arb` описание `@ключ` не дублируется.
4. **Количество** — одним сообщением с ICU `plural`; склейка фраз и `n == 1 ? … : …` запрещены. В `en` формы `one` и `other`, в `ru` — `one`, `few`, `many`, `other`; `l10n_catalogs_test` проверяет формы.
5. **Генерация:** `fvm flutter gen-l10n` в `apps/codelab_desktop`; результат — `lib/l10n/app_localizations*.dart` — коммитится.
6. **Использование.** В виджете — `context.l10n.<ключ>` в `build` (`lib/l10n/l10n.dart`), смена языка пересоберёт его сама. В Cubit-е — порт `AppStrings` (ниже).
7. **Литерал, который не переводится** (название продукта, значение конфигурации, имя протокола), заносится с причиной в `packages/dart/codelab_architecture_tests/test/support/ui_literals_allowlist.txt`; иначе `ui_literals_test` найдёт его как непереведённый текст.
8. **Проверка:** `fvm dart run melos run l10n:check`.

### Скелет: сообщение с plural

Существующее сообщение `usageStepToolCalls` показывает все детали (шаблон `app_en.arb`):

```json
"usageStepToolCalls": "{count, plural, one{{count} tool call} other{{count} tool calls}}",
"@usageStepToolCalls": {
  "description": "Название шага журнала, когда вызовы не найдены в ленте.",
  "placeholders": {
    "count": { "type": "int" }
  }
},
```

и перевод `app_ru.arb`:

```json
"usageStepToolCalls": "{count, plural, one{{count} вызов инструмента} few{{count} вызова инструмента} many{{count} вызовов инструментов} other{{count} вызова инструмента}}",
```

В виджете: `Text(context.l10n.usageStepToolCalls(count))` — сгенерированный метод получает значение плейсхолдера.

### Скелет: строка простого заголовка

```json
"activeFolderNone": "No folder",
"@activeFolderNone": {
  "description": "Бейдж папки активной сессии, когда нет ни сессии, ни проекта."
}
```

### Текст в Cubit-е: три вида

Правило D5 `add-desktop-localization`:

| Вид текста | Где живёт | Как устроен |
|---|---|---|
| текст виджета | `presentation/`, `context.l10n` в `build` | пересборка при смене языка бесплатна |
| производный текст в состоянии Cubit-а | `application/` | функция «входы и язык»: Cubit держит порт `AppStrings` и пересобирает проекцию при смене языка; переведённую строку, которую нельзя пересобрать из входов, не хранит |
| разовое сообщение об исходе | состояние хранит типизированное значение (`sealed class`), текст строит код, который вызывает `presentation/`, по `context.l10n` | `McpMessage` и `mcpMessageLines` (`presentation/mcp_texts.dart`); `AddProfileFailure` и `addProfileFailureText` (функция лежит в `application/add_profile_state.dart`, вызывает её `presentation/add_profile_dialog.dart`) |

Cubit с производным текстом получает `required AppStrings strings` и держит одну подписку (образец — `AddProfileCubit`):

```dart
// В конструкторе: одна подписка на весь срок жизни Cubit-а.
_languageSubscription = strings.changes.listen(_handleLanguage);

void _handleLanguage(AppLocalizations _) {
  if (isClosed) return;            // событие после close игнорируется
  emit(_recompute(state));         // пересобрать проекцию из последних входов
}

@override
Future<void> close() {
  unawaited(_languageSubscription.cancel());
  return super.close();
}
```

Новый Cubit с текстом в состоянии добавляется в список в `test/l10n/cubit_text_list_test.dart` (`_withText`) и в раздел «Локализация» [`AGENTS.md`](../AGENTS.md) приложения, и для него пишется тест смены языка на `TestAppStrings` ([08-testing.md](08-testing.md#cubit-с-текстом-в-состоянии)). Не переводятся тексты агента, ядра, хранилища секретов, протокола и журналов (перечень — в `AGENTS.md` приложения).

### Тест

- `l10n_catalogs_test` ловит расхождение ключей, плейсхолдеров и форм plural.
- Для виджета — тест с `locale: const Locale('ru')` и проверка `expectNoStaleLanguage` (образец — `test/features/settings/presentation/keyboard_page_l10n_test.dart`).
- Для Cubit-а — смена языка через `TestAppStrings.emit` и проверка, что подписка снята после `close()`.

## Рецепт 4. Новое сочетание клавиш

Единственный источник активаторов и обозначений — каталог `CodeLabShortcut` в `packages/flutter/codelab_ui` (`lib/src/atomics/codelab_shortcuts.dart`). Страница «Keyboard» строится из него, отдельного списка в app нет. В `apps/codelab_desktop/lib` литералы `SingleActivator`, `CharacterActivator`, `LogicalKeySet` и сравнения с `LogicalKeyboardKey.` запрещены: `test/app/shortcut_catalog_guard_test.dart` падает с именем файла и строкой.

Новое сочетание — всегда один change: запись каталога затрагивает кит, ARB, привязку и спецификацию.

### Шаги

1. **Запись каталога.** В `CodeLabShortcut` добавьте значение в нужное место — порядок записей — порядок строк страницы. Конструктор: группа, список комбинаций (`CodeLabKeyCombo`), для платформенных — `macCombos` и `otherCombos`:

   ```dart
   toggleProtocol(CodeLabShortcutGroup.navigation, [
     CodeLabKeyCombo(LogicalKeyboardKey.keyI, primary: true, shift: true),
   ]),
   ```

   `primary: true` — Cmd на macOS и Ctrl в остальных ОС. Идентификатор строки (`toggle-protocol`) кит выводит из имени сам (`id`).
2. **Тексты ARB.** `settingsKeyboardAction<Имя>` — действие; `settingsKeyboardWhere<Место>` — колонка «Where», если место новое (одинаковые места делят одно сообщение).
3. **Ветки в `switch`** страницы `lib/features/settings/presentation/keyboard_page.dart`: `keyboardShortcutActionOf` и `keyboardShortcutWhereOf` (и `keyboardShortcutGroupOf`, если новая группа). `switch` исчерпывающие, запись без текста не компилируется.
4. **Привязка в месте действия.** Через запись каталога, не через литерал: `CodeLabShortcut.leaveSettings.bind(onBack)` даёт `Map<ShortcutActivator, VoidCallback>` для `CallbackShortcuts`. Для записей с разными действиями у альтернатив (стрелки вверх и вниз) используют `shortcut.combos[i]` и `accepts(event, keyboard)` (образец — `protocol_pane.dart`). Подсказку в интерфейсе строят из каталога: `shortcut.combos.single.compactFor(platform)`, а не строкой.
5. **Таблица спецификации в тестах.** `test/support/keyboard_rows.dart` хранит таблицу страницы «Keyboard» из спецификации app-settings символ в символ; добавьте строку и поправьте число строк в `keyboard_page_test.dart` и `keyboard_page_l10n_test.dart` (сейчас 24).
6. **Тест нажатия.** Запись, привязка которой живёт в виджетах кита, нажимает `packages/flutter/codelab_ui/test/codelab_shortcut_bindings_test.dart` (там `switch` без `default` по `CodeLabShortcut`: запись без сценария не компилируется); запись, привязанную в app, — `test/features/settings/presentation/keyboard_bindings_test.dart`.

### Скелет: привязка и тест нажатия

Привязка в виджете app:

```dart
CallbackShortcuts(
  bindings: CodeLabShortcut.toggleProtocol.bind(onToggleProtocol),
  child: child,
)
```

Тест нажатия (`keyboard_bindings_test.dart`, `toggle-protocol`): клавиши берутся из каталога через `pressShortcut` (`test/support/press_shortcut.dart`), а не из литералов теста, поэтому тест не расходится с каталогом при правке комбинации:

```dart
await pressShortcut(tester, CodeLabShortcut.toggleProtocol);
// … проверка: панель Protocol открылась
await pressShortcut(tester, CodeLabShortcut.toggleProtocol);
// … проверка: закрылась
```

`pressShortcut` нажимает комбинации записи для `defaultTargetPlatform`; для записей с основным модификатором есть вариант `useMeta: true` (⌘ вместо Ctrl).

### Проверки

`fvm flutter test` в `apps/codelab_desktop` и в `packages/flutter/codelab_ui`, `fvm dart run melos run l10n:check` для ARB обоих пакетов (у кита свой каталог `lib/src/l10n/`), `fvm dart run melos run guard`. Сочетания ответа на одобрение (`allowOnce`, `allowAlways`, `rejectOnce`, `rejectAlways`, `goToApproval`) относятся к безопасности: их клавиши и правила (`approval-safety`) меняет отдельный change.

## Рецепт 5. Новый порт платформы

Файлы, процессы, диалоги, ссылки, буфер обмена, нативные плагины — задачи платформы. Виджеты, Cubit-ы и `domain` обращаются к ним только через порт; реализацию с плагином собирает `lib/core/platform/` и подставляет composition root (`AGENTS.md` §11, [platform-integration.md](../../../docs/architecture/platform-integration.md)).

### Шаги

1. **Нужен ли порт.** Порт оправдан, если изолирует плагин или ОС, нужен нескольким потребителям или требует независимого теста (`AGENTS.md` §13). Простая обёртка вызова ради формы запрещена.
2. **Порт и адаптер** в `lib/core/platform/<имя>.dart`: абстрактный интерфейс (`abstract interface class`) и реализация. Исход операции — типизированный (`enum` или `sealed`), а не исключение с текстом: он может содержать пути (`LocalFolderOpener` → `FolderOpenOutcome`).
3. **Импорт плагина — только в адаптере.** Для плагинов, которые уже ограничены, правило сторожа есть: `package:file_selector/` — только `lib/core/platform/`, `package:system_theme/` — только `system_accent_source.dart`, `package:desktop_drop/` — только `os_drop_region.dart`, `package:pty2/` — только `user_shell_launcher.dart`. Для нового плагина добавьте правило в `packages/dart/codelab_architecture_tests/test/support/rules.dart` вместе с портом.
4. **Регистрация** в модуле платформы — `CodeLabPlatformModule` (`lib/app/app_scope.dart`): поле, параметр конструктора, `bind<…>().toInstance(…)` с реализацией по умолчанию; шов тестов — параметр `createCodeLabRootScope`, который передаётся в модуль.
5. **Двойник** в `test/support/fake_<имя>.dart` и параметр `CodeLabTestBinding`, чтобы тест подставлял его швом.
6. **Тест адаптера** в `test/core/platform/<имя>_test.dart` на шве самого адаптера (как `launch:` у `UrlLauncherLocalFolderOpener`), без настоящего плагина.

### Скелет: порт и адаптер

Скелет проверен компиляцией во временном файле (удалён). Образец структуры — `lib/core/platform/local_folder_opener.dart`.

```dart
// lib/core/platform/text_clipboard.dart
import 'package:flutter/services.dart';

/// Порт записи текста в буфер обмена.
///
/// Почему порт: канал буфера — платформенная деталь, Cubit-ы её не вызывают
/// (`AGENTS.md` §11); тест подставляет двойник.
abstract interface class TextClipboard {
  /// Кладёт [text] в буфер; `false` — платформа отказала.
  Future<bool> write(String text);
}

/// Реализация на системном канале Flutter.
final class SystemTextClipboard implements TextClipboard {
  const SystemTextClipboard();

  @override
  Future<bool> write(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } on PlatformException {
      return false; // без текста ошибки: он может содержать путь
    }
  }
}
```

### Скелет: регистрация и шов теста

Шов проходит четыре места; на примере реального `LocalFolderOpener` (`lib/app/app_scope.dart`):

```dart
// 1. createCodeLabRootScope: параметр шва
LocalFolderOpener? localFolderOpener,
// … и передача в модуль
CodeLabPlatformModule(…, localFolderOpener: localFolderOpener, …)

// 2. CodeLabPlatformModule: конструктор и поле
LocalFolderOpener? localFolderOpener,
…
final LocalFolderOpener? _localFolderOpener;

// 3. CodeLabPlatformModule.builder: привязка с реализацией по умолчанию
bind<LocalFolderOpener>().toInstance(
  _localFolderOpener ?? const UrlLauncherLocalFolderOpener(),
);

// 4. test/support/test_app_scope.dart: параметр CodeLabTestBinding и передача
LocalFolderOpener? localFolderOpener,
…
localFolderOpener: localFolderOpener,
```

Потребитель получает порт из scope: `currentScope.resolve<LocalFolderOpener>()` при сборке Cubit-а. Для `TextClipboard` те же четыре места с заменой имени.

### Скелет: двойник

`test/support/fake_text_clipboard.dart` (проверен компиляцией, образец — `FakeLocalFolderOpener`):

```dart
import 'package:codelab_desktop/core/platform/text_clipboard.dart';

/// Двойник порта [TextClipboard]: записывает тексты и возвращает [succeeds].
final class FakeTextClipboard implements TextClipboard {
  FakeTextClipboard({this.succeeds = true});

  bool succeeds;
  final List<String> written = [];

  @override
  Future<bool> write(String text) async {
    written.add(text);
    return succeeds;
  }
}
```

### Проверки

Тесты адаптера и потребителя, `fvm flutter analyze`, `fvm dart run melos run guard` (новый импорт плагина и правило сторожа). Если порт меняет поведение для пользователя, нужен change и обновление [06-platform-and-appearance.md](06-platform-and-appearance.md) и таблицы `lib/core/platform/` в [обзоре](01-overview.md#карта-кода).

## Рецепт 6. Новый вид строки ленты

Строки ленты — закрытая иерархия `CodeLabTranscriptRow` в `codelab_ui`; app превращает транскрипт ядра клиента в эти строки функцией `transcriptRowsOf` (`lib/features/workbench/application/ui_mappers.dart`). Маппер — единственное место, где модели `codelab_client_core` становятся моделями `codelab_ui`. Рецепт применим, только когда у ядра клиента уже есть новый вид элемента транскрипта или его добавляют в том же change: app сам новых видов элементов не придумывает.

### Что затрагивает новый вид строки

| Слой | Что менять | Кто |
|---|---|---|
| `codelab_client_core` | новый вариант `TranscriptItem` (freezed `sealed class` в `lib/src/transcript/transcript_item.dart`) и его построение из обновлений сессии | клиентский слой |
| `codelab_ui` | новый `final class … extends CodeLabTranscriptRow` в `lib/src/organisms/codelab_transcript_row.dart`, виджет, ветка в `switch` панели `CodeLabTranscriptPanel` | кит |
| `apps/codelab_desktop` | ветка в `transcriptRowsOf`; тестовое расширение `test/support/transcript_rows.dart` | app |

Приложение компилируется только после всех трёх: `switch` по `TranscriptItem` в `transcriptRowsOf` и по `CodeLabTranscriptRow` в панели исчерпывающие, а расширения `text` и `kind` в `test/support/transcript_rows.dart` — тоже.

### Шаги в app

1. **Ветка маппера.** Добавьте ветку в `switch` `transcriptRowsOf`. Идентификатор строки — позиционный (`prompt-N`, `agent-N`, `thought-N`, `tool-N`, `notice-N`, `task-ops-N`): по нему лента хранит ручное раскрытие и ключи виджетов, и он должен быть стабилен между пересборками.
2. **Текст.** Заметки строятся по типизированной причине элемента, а не по английскому `text` ядра; ответ агента, запрос пользователя и мысли не переводятся. Строка интерфейса — через `AppLocalizations`, переданный в маппер параметром `l10n` ([рецепт 3](#рецепт-3-новая-строка-интерфейса)).
3. **Тестовые расширения.** Допишите ветки `text` и `kind` в `test/support/transcript_rows.dart`.

### Скелет: ветка маппера

Реальная ветка для тихой строки операций со списком задач (`TaskOpsItem` → `CodeLabTaskOpsRow`):

```dart
// ui_mappers.dart, transcriptRowsOf: switch (item)
final TaskOpsItem ops => CodeLabTaskOpsRow(
  id: 'task-ops-${index + 1}',
  text: ops.text,
),
```

Для нового вида элемент и строка называются своими именами:

```dart
final StatusItem status => CodeLabStatusRow(     // вымышленные имена
  id: 'status-${index + 1}',
  text: status.text,
),
```

### Тест

По образцу `test/features/workbench/application/ui_mappers_test.dart`: входной элемент → `transcriptRowsOf` → тип и поля строки.

```dart
test('TaskOpsItem becomes a quiet CodeLabTaskOpsRow with the kit text', () {
  final rows = transcriptRowsOf(
    const [
      TranscriptItem.taskOps(id: 't1/task-ops-1', added: ['1', '2', '3', '4']),
    ],
    cwd: '/workspace',
    approvalsEnabled: true,
    onApprovalSelected: (_, _) {},
    l10n: AppLocalizationsEn(),
  );

  expect(rows.single, isA<CodeLabTaskOpsRow>());
  expect((rows.single as CodeLabTaskOpsRow).text, 'Tasks #1–#4 added to the plan');
});
```

Если у строки есть текст интерфейса, добавьте проверку на `ru` в `ui_mappers_l10n_test.dart`.

### Проверки

`fvm flutter test test/features/workbench/application/ui_mappers_test.dart` и тесты строки в `packages/flutter/codelab_ui`; `fvm dart run melos run l10n:check` (ARB); тесты `codelab_client_core` и, если новый элемент видит CLI, — его проверки по [AGENTS.md](../../../AGENTS.md) §21. Изменение ленты — изменение поведения продукта: спецификация [agent-workbench-ui](../../../openspec/specs/agent-workbench-ui/spec.md) и change.

## Смотрите также

- [08-testing.md](08-testing.md) — как писать тесты из рецептов и что запускать.
- [01-overview.md](01-overview.md#карта-кода) — карта `lib/`; [development.md](development.md) — вход разработчика.
- [`AGENTS.md`](../AGENTS.md) приложения — правила и ключи тестов отдельных страниц.
- [layers-and-dependencies.md](../../../docs/architecture/layers-and-dependencies.md), [state-management.md](../../../docs/architecture/state-management.md), [platform-integration.md](../../../docs/architecture/platform-integration.md) — архитектурные границы, на которых стоят рецепты.
- [codelab_ui](../../../packages/flutter/codelab_ui/README.md) — виджеты, каталог сочетаний и строки ленты.
