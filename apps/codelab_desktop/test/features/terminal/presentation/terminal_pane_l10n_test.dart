// Красные тесты задачи 3.3 change `add-desktop-localization`: панель Terminal
// на русском (spec app-settings «Локализация интерфейса app»;
// integrated-terminal «Терминал вне одобрений агента», «Ссылки в выводе
// терминала»; design.md D5 п. 4, D7, D14).
//
// `features/terminal/application` без Flutter: статус вкладки — типизированное
// значение (`TerminalTabStatus`), а подпись тега собирает presentation
// (`terminal_tab_view.dart`) по каталогу. Заголовок вкладки `Terminal 1`
// получает вкладку в Cubit-е как данные; в `ru` он показывается как
// `Терминал 1` (глоссарий). Содержимое терминала (вывод процесса) не
// переводится: оно приходит от shell пользователя (D7).
//
// Предупреждение панели и диалог ссылки помечены `security` в `@description`
// (D14): их вычитывает пользователь (задача 3.5). Русские формулировки вне
// глоссария перечислены в отчёте задачи 3.3.

import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:codelab_desktop/features/terminal/presentation/terminal_link_dialog.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_user_shell_launcher.dart';
import '../../../support/l10n_app.dart';
import '../../../support/live_scene.dart';

const _ru = Locale('ru');

Future<LiveScene> _openTerminal(
  WidgetTester tester,
  FakeUserShellLauncher launcher,
) async {
  final scene = await LiveScene.open(
    tester,
    locale: _ru,
    userShellLauncher: launcher,
  );
  await scene.newSession('s1');
  await tester.runAsync(
    () => scene.binding.scope.resolve<TerminalTabsCubit>().ensureTab(),
  );
  scene.cubit.openPane(ToolPane.terminal);
  await scene.flush();
  return scene;
}

void main() {
  testWidgets('вкладка: заголовок и тег «Выполняется», предупреждение '
      'панели (security)', (tester) async {
    final scene = await _openTerminal(
      tester,
      FakeUserShellLauncher()..shellsExitOnHangUp = true,
    );

    final pane = scene.textOf(find.byType(CodeLabTerminalPane));
    expect(pane, contains('Терминал 1'));
    expect(pane, contains('Выполняется'));
    // «Вне одобрений агента», «не очищается от секретов» сохранены (D14).
    expect(
      pane,
      contains(
        'Команды здесь выполняются от вашего имени, в обход одобрений '
        'агента. Вывод показывается как есть и не очищается от секретов.',
      ),
    );

    await scene.close();
  });

  testWidgets('завершённый shell: тег с кодом выхода', (tester) async {
    final launcher = FakeUserShellLauncher()..shellsExitOnHangUp = true;
    final scene = await _openTerminal(tester, launcher);

    launcher.shells.single.exit(3);
    await scene.flush();

    expect(
      scene.textOf(find.byType(CodeLabTerminalPane)),
      contains('Завершён с кодом 3'),
    );

    await scene.close();
  });

  testWidgets('диалог ссылки: заголовок, кнопки; адрес как есть (security)', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedFluentApp(
        locale: _ru,
        Builder(
          builder: (context) => Button(
            onPressed: () => showTerminalLinkDialog(
              context,
              uri: 'https://example.com/a?b=c',
              canOpen: true,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Открыть ссылку?'), findsOneWidget);
    expect(find.text('https://example.com/a?b=c'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(terminalLinkOpenKey),
        matching: find.text('Открыть'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(terminalLinkCancelKey),
        matching: find.text('Отмена'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'диалог ссылки с другой схемой: отказ на русском, без «Открыть»',
    (tester) async {
      await tester.pumpWidget(
        localizedFluentApp(
          locale: _ru,
          Builder(
            builder: (context) => Button(
              onPressed: () => showTerminalLinkDialog(
                context,
                uri: 'file:///etc/passwd',
                canOpen: false,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Можно открывать только ссылки http и https.'),
        findsOneWidget,
      );
      expect(find.byKey(terminalLinkOpenKey), findsNothing);
    },
  );
}
