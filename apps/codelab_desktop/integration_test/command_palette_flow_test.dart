// E2e палитры с командами агента (tasks 1.2 change
// `add-command-palette-agent-commands`, design D6; spec testing-quality
// «Интеграционный тест палитры с командами агента»; строка Must R-20
// матрицы паритета).
//
// Два теста (tasks 1.8 change `add-agent-builtin-slash-commands`, design D9):
// полный сценарий с тегом `scripted-only` (команда `plan` с `input.hint`
// есть только у scripted-агента) и тест без тега для встроенной команды
// `compact`, который идёт во всех режимах (`scripted`, `dart`, `embedded`).
// Теперь в файле есть тест без тега, поэтому прогон `dart` с
// `--exclude-tags scripted-only` не падает с «No tests ran», а пропуск
// `!isScripted` не нужен.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';
import '../test/support/transcript_rows.dart';

CodeLabShellCubit _cubit(WidgetTester tester) =>
    codeLabDependenciesOf(tester.element(find.byType(CodeLabApp))).shellCubit;

/// Выбирает профиль агента на странице «Connection» и ждёт подключения
/// (как в stdio_connect_flow_test.dart).
Future<void> _connect(WidgetTester tester, E2eLaunch launch) async {
  await launch.connect(tester, _cubit(tester));
  await _waitFor(
    tester,
    () =>
        _cubit(tester).state.connectionStatus ==
        CodeLabConnectionStatus.connected,
  );
}

/// Ждёт [condition] не дольше 10 секунд, прокачивая кадры.
Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 300));
  expect(condition(), isTrue);
}

List<String?> _transcript(WidgetTester tester) => [
  for (final entry in _cubit(tester).state.transcriptRows) entry.text,
];

final _composer = find.byKey(const ValueKey('composer-text-box'));

String _composerText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: _composer, matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// Открывает палитру сочетанием `Cmd+K` (тест идёт на macOS).
Future<void> _openPalette(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
  expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);
}

/// Бейдж `/name` строки палитры: строка показывает команду бейджем, нажатие
/// на него выбирает строку.
Finder _paletteRow(String slash) => find.descendant(
  of: find.byType(CodeLabCommandPaletteSurface),
  matching: find.text(slash),
);

/// Нажимает строку палитры [slash], предварительно прокрутив к ней список:
/// у Dart-агента команд больше, чем помещается в 260 px списка, и строка
/// может лежать за его видимой областью (как у пользователя — прокруткой).
Future<void> _tapPaletteRow(WidgetTester tester, String slash) async {
  await tester.ensureVisible(_paletteRow(slash));
  await tester.pumpAndSettle();
  await tester.tap(_paletteRow(slash));
  await tester.pumpAndSettle();
}

/// Закрывает app и root scope Cherrypick в конце теста: следующий тест файла
/// создаёт новый scope (`bootstrap()`), без закрытия прежний остаётся и
/// `CodeLabShellCubit` не разрешается (как в connection_profiles_flow_test).
Future<void> _shutdown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await closeCodeLabRootScope();
}

/// Вводит [text] в композер, как пользователь, и выбирает подсвеченную
/// команду inline-палитры клавишей `Enter`.
Future<void> _pickInline(WidgetTester tester, String text) async {
  await tester.showKeyboard(_composer);
  await tester.enterText(_composer, text);
  await tester.pumpAndSettle();
  expect(
    find.byKey(CodeLabPromptComposer.inlineCommandPaletteKey),
    findsOneWidget,
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'built-in compact: the palette shows the agent command instead of the '
    'client stub, it is inserted without session/prompt and the agent '
    'answers on send',
    (tester) async {
      final project = await Directory.systemTemp.createTemp(
        'codelab_command_palette_compact_e2e_',
      );
      addTearDown(() async {
        if (await project.exists()) {
          await project.delete(recursive: true);
        }
      });
      final launch = await E2eAgent.current.launch(
        project,
        mode: E2eAgent.current.compactMode,
      );

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();
      await _cubit(tester).selectProject(project.path);
      await tester.pumpAndSettle();
      await _connect(tester, launch);
      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();
      await _waitFor(
        tester,
        () => _cubit(
          tester,
        ).state.agentCommands.any((c) => c.id == 'agent-compact'),
      );

      // Палитра: `/compact` агента вместо заглушки клиента.
      await _openPalette(tester);
      expect(
        find.byKey(CodeLabCommandPaletteSurface.agentSectionHeaderKey),
        findsOneWidget,
      );
      expect(_paletteRow('/compact'), findsOneWidget);
      final ids = [for (final a in _cubit(tester).state.paletteActions) a.id];
      expect(ids, contains('agent-compact'));
      expect(ids, isNot(contains('compact')));

      // Выбор вставляет команду и ничего не отправляет.
      await _tapPaletteRow(tester, '/compact');
      expect(_composerText(tester), '/compact ');
      expect(_transcript(tester), isEmpty);

      // Отправка: реплика `/compact` и ответ агента своего режима.
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();
      await _waitFor(
        tester,
        () =>
            _transcript(tester).contains(E2eAgent.current.compactReply) &&
            !_cubit(tester).state.isPromptSubmitting,
      );
      expect(_transcript(tester), ['/compact', E2eAgent.current.compactReply]);
      await _shutdown(tester);
    },
  );

  testWidgets(
    'agent-declared commands replace the client stubs in the palette, are '
    'inserted into the composer and reach the agent on send, and fuzzy '
    'search finds them inline',
    tags: scriptedOnly,
    (tester) async {
      final project = await Directory.systemTemp.createTemp(
        'codelab_command_palette_e2e_',
      );
      addTearDown(() async {
        if (await project.exists()) {
          await project.delete(recursive: true);
        }
      });
      final launch = await E2eAgent.current.launch(
        project,
        mode: CodelabCompatibleStdioAgentMode.withAvailableCommands,
      );

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();
      await _cubit(tester).selectProject(project.path);
      await tester.pumpAndSettle();
      await _connect(tester, launch);
      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();
      await _waitFor(
        tester,
        () => _cubit(tester).state.agentCommands.length == 2,
      );

      // 1. Палитра: команды агента в своей секции, заглушки клиента с теми
      // же именами нет, `/permissions` по-прежнему недоступна.
      await _openPalette(tester);
      expect(
        find.byKey(CodeLabCommandPaletteSurface.agentSectionHeaderKey),
        findsOneWidget,
      );
      expect(_paletteRow('/compact'), findsOneWidget);
      expect(_paletteRow('/plan'), findsOneWidget);
      final ids = [for (final a in _cubit(tester).state.paletteActions) a.id];
      expect(ids, containsAll(['agent-compact', 'agent-plan', 'permissions']));
      expect(ids, isNot(contains('compact')));
      expect(ids, isNot(contains('plan')));

      // 2. Выбор вставляет команду в композер и ничего не отправляет.
      await _tapPaletteRow(tester, '/compact');
      expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);
      expect(_composerText(tester), '/compact ');
      expect(_transcript(tester), isEmpty);

      // 3. Отправка: агент получил `/compact` и ответил отчётом о сжатии.
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();
      await _waitFor(
        tester,
        () =>
            _transcript(tester).contains('Compacted the conversation.') &&
            !_cubit(tester).state.isPromptSubmitting,
      );
      expect(_transcript(tester), ['/compact', 'Compacted the conversation.']);

      // 4. Inline-триггер: нечёткий поиск по буквам имени, затем команда с
      // подсказкой аргумента.
      await _pickInline(tester, '/cpt');
      expect(_composerText(tester), '/compact ');
      await _pickInline(tester, '/pl');
      expect(_composerText(tester), '/plan ');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('composer-command-hint')),
          matching: find.text('what to plan'),
        ),
        findsOneWidget,
      );

      // 5. Команда клиента выполняется в app без `session/prompt`.
      final sessionsBefore = _cubit(tester).state.sessions.length;
      await _openPalette(tester);
      await _tapPaletteRow(tester, '/new');
      await _waitFor(
        tester,
        () => _cubit(tester).state.sessions.length == sessionsBefore + 1,
      );
      expect(_transcript(tester), isEmpty);
      await _shutdown(tester);
    },
  );
}
