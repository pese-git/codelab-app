// Ответ агента как markdown в собранном приложении (задача 5.1 change
// `add-desktop-markdown`; markdown-часть §12.3.7; spec agent-workbench-ui
// «Markdown в ответе агента», «Блок кода в ответе агента», «Изображения в
// ответе агента»; design.md D1–D6).
//
// Агент отвечает заголовком, списком, таблицей, оградой `dart` и изображением.
// Тест идёт против любого агента из `E2eAgent` (внешний scripted, бинарь Dart,
// встроенный): ответ размечен, код подсвечен, «Copy» кладёт в буфер код без
// ограды, изображение — заглушка «Show image» без загрузки. В `feature/*`
// тест только компилируется и анализируется; на устройстве он идёт в
// `release/*` (`melos run test:e2e:app:transcript-rendering`, `AGENTS.md`
// §21).

import 'dart:io';

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a streamed markdown answer is rendered, the code is highlighted and '
    'copyable, and the image is a placeholder',
    (tester) async {
      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();

      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_transcript_rendering_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });
      final launch = await E2eAgent.current.launch(
        agentDirectory,
        mode: E2eAgent.current.markdownMode,
      );
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await launch.connect(tester, shellCubit);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      // Промпт отправляет Cubit: ответ приходит по настоящему каналу агента
      // (stdio или встроенный), а не из тестового двойника.
      await shellCubit.submitPrompt(E2eAgent.markdownPrompt);

      bool answered() => shellCubit.state.transcriptRows
          .whereType<CodeLabAgentTextRow>()
          .any((row) => row.text.contains('Release notes'));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!answered() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(answered(), isTrue, reason: 'the agent answer must arrive');
      await tester.pump(const Duration(milliseconds: 500));

      // Пузырь пользователя показывает промпт как есть, со всеми сырыми
      // маркерами (разметка — только у ответа агента). Поиск — только в ленте:
      // в широкой раскладке начало промпта ещё и в заголовке сессии сайдбара
      // и шапки (однострочные подписи), это не пузырь.
      expect(
        find.descendant(
          of: find.byType(CodeLabTranscriptPanel),
          matching: find.textContaining('# Release notes', findRichText: true),
        ),
        findsOneWidget,
        reason: 'the prompt bubble shows the raw prompt',
      );

      // Дальше всё проверяется только внутри ответа агента: в пузыре промпта
      // те же маркеры, и поиск по всему дереву дал бы ложные срабатывания.
      final answer = find.byType(CodeLabMarkdown);
      expect(answer, findsOneWidget);
      Finder inAnswer(Finder matching) =>
          find.descendant(of: answer, matching: matching);

      // Разметка применена: нет сырых маркеров заголовка, ограды и таблицы.
      expect(inAnswer(find.text('Release notes')), findsOneWidget);
      expect(
        inAnswer(find.textContaining('# Release', findRichText: true)),
        findsNothing,
      );
      expect(
        inAnswer(find.textContaining('```', findRichText: true)),
        findsNothing,
      );
      expect(
        inAnswer(find.textContaining('|---', findRichText: true)),
        findsNothing,
      );
      expect(
        inAnswer(find.textContaining('first item', findRichText: true)),
        findsWidgets,
      );
      expect(inAnswer(find.byType(Table)), findsAtLeastNWidgets(1));
      expect(
        inAnswer(find.textContaining('alpha', findRichText: true)),
        findsWidgets,
      );

      // Код подсвечен: в блоке больше одного цвета, подпись языка видна.
      expect(inAnswer(find.byType(CodeLabCodeBlock)), findsOneWidget);
      expect(inAnswer(find.text('dart')), findsOneWidget);
      final code = tester
          .widgetList<RichText>(
            inAnswer(
              find.byWidgetPredicate(
                (w) =>
                    w is RichText && w.text.toPlainText().contains('void main'),
              ),
            ),
          )
          .first;
      final colors = <Color>{};
      code.text.visitChildren((span) {
        final color = span is TextSpan ? span.style?.color : null;
        if (color != null) colors.add(color);
        return true;
      });
      expect(colors.length, greaterThan(1), reason: 'highlighted code');

      // «Copy» кладёт в буфер код без ограды и подписи языка.
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(inAnswer(find.widgetWithText(CodeLabButton, 'Copy')));
      await tester.pump(const Duration(seconds: 1));
      expect(clipboard, ["void main() {\n  print('hi');\n}"]);

      // Изображение — заглушка с кнопкой; сама картинка не показана (клика
      // «Show image» тест не делает, сетевых запросов нет).
      expect(inAnswer(find.byType(CodeLabImagePlaceholder)), findsOneWidget);
      expect(inAnswer(find.text('Show image')), findsOneWidget);
      expect(inAnswer(find.byType(Image)), findsNothing);
    },
  );
}
