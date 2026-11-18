// Красные тесты задачи 3.3 change `add-desktop-localization`: диалог
// подтверждения перезапуска агента на русском (spec app-settings «Склонение
// количества», «Живое рабочее место пересобирается»; design.md D5 п. 9, D8).
//
// Количество идущих сессий — только ICU `plural` (D8): `1 выполняющуюся
// сессию`, `2 выполняющиеся сессии`, `5 выполняющихся сессий`, `21
// выполняющуюся сессию`. Склейка `n == 1 ? … : …` на русском даёт
// неправильные формы, поэтому формы проверяются явно.
//
// Русские формулировки диалога — вне глоссария (в нём только «Перезапустить
// агента», «Отмена», «промпт», «сессия»); они перечислены в отчёте задачи 3.3
// для вычитки. Диалог открывается решением пользователя «перезапустить», но
// опасность перезапуска определяет `ConnectionCubit`, а не виджет (§10).

import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/features/workbench/application/connection_cubit.dart'
    show RestartConfirmation;
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/features/workbench/presentation/widgets/restart_confirmation_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/l10n_app.dart';
import '../../../support/live_scene.dart';
import '../../../support/test_app_scope.dart';

void main() {
  Future<String> russianMessage(
    WidgetTester tester,
    CodeLabShellCubit cubit,
    List<String> sessions,
  ) async {
    await tester.pumpWidget(
      localizedFluentApp(
        locale: const Locale('ru'),
        Stack(
          children: [
            RestartConfirmationDialog(
              pending: RestartConfirmation(title: 'Remote', sessions: sessions),
              cubit: cubit,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final dialog = find.byKey(const ValueKey('restart-agent-dialog'));
    return [
      for (final widget in tester.widgetList<Text>(
        find.descendant(of: dialog, matching: find.byType(Text)),
      ))
        widget.data ?? '',
    ].join(' | ');
  }

  group('склонение количества сессий на ru', () {
    final cases = {
      1: ('1 выполняющуюся сессию', ['a']),
      2: ('2 выполняющиеся сессии', ['a', 'b']),
      5: ('5 выполняющихся сессий', ['a', 'b', 'c', 'd', 'e']),
      21: ('21 выполняющуюся сессию', [for (var i = 0; i < 21; i++) 's$i']),
    };
    for (final entry in cases.entries) {
      testWidgets('${entry.key} → ${entry.value.$1}', (tester) async {
        final binding = CodeLabTestBinding(project: '/work/app');
        final cubit = binding.scope.resolve<CodeLabShellCubit>();

        final text = await russianMessage(tester, cubit, entry.value.$2);

        expect(text, contains('Перезапустить агента?'));
        expect(
          text,
          contains(
            'Перезапустить Remote? Это прервёт ${entry.value.$1}: '
            '${entry.value.$2.join(', ')}. Промпты в очереди сохранятся.',
          ),
        );
        expect(text, contains('Отмена'));
      });
    }
  });

  testWidgets('открытый диалог пересобирается при смене языка, plural и '
      'имена сессий сохраняются', (tester) async {
    final scene = await LiveScene.open(tester);
    await scene.newSession('s1');
    await scene.prompt('work');

    await scene.cubit.restartAgent();
    await scene.flush();
    final pending = scene.cubit.state.pendingRestart!;
    final dialog = find.byKey(const ValueKey('restart-agent-dialog'));
    expect(dialog, findsOneWidget);
    expect(scene.textOf(dialog), contains('This interrupts 1 running session'));

    await scene.selectLanguage(AppLanguagePreference.ru);

    expect(dialog, findsOneWidget);
    final text = scene.textOf(dialog);
    expect(text, contains('Перезапустить агента?'));
    expect(
      text,
      contains(
        'Перезапустить ${pending.title}? Это прервёт 1 выполняющуюся сессию: '
        '${pending.sessions.join(', ')}. Промпты в очереди сохранятся.',
      ),
    );
    expect(text, isNot(contains('This interrupts')));
    // Состояние решения не тронуто: диалог тот же, ход не прерван.
    expect(scene.cubit.state.pendingRestart, pending);

    await scene.selectLanguage(AppLanguagePreference.en);
    expect(scene.textOf(dialog), contains('This interrupts 1 running session'));
    await scene.close();
  });
}
