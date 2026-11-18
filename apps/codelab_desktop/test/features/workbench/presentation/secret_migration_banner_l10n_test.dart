// Красные тесты задачи 3.3 change `add-desktop-localization`: предупреждение
// и диалог переноса секретов встроенного агента на русском (spec
// agent-workbench-ui «Перенос секретов встроенного агента»; app-settings
// «Локализация интерфейса app»; design.md D5, D6, D7).
//
// Тексты виджета (предупреждение, кнопки, заголовок, ход переноса, подсказки
// кнопки перезапуска) берутся из каталога; разовые тексты ошибок плана и
// переноса `Planning failed: <тип>.` и `Migration failed: <тип>.` строит
// Cubit, и после замены строки типизированной причиной их текст собирает
// presentation (D5). Строки плана, `detail` и `problem` приходят от порта и
// показываются как есть: в них пути и значения конфигурации (D7).
//
// Строки с пометкой `security` (предупреждение о секретах в файле конфигурации)
// вычитывает пользователь (задача 3.5); все русские формулировки диалога —
// вне глоссария и перечислены в отчёте задачи 3.3.

import 'dart:async';

import 'package:codelab_desktop/features/workbench/application/secret_migration_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/secret_migration_runner.dart';
import 'package:codelab_desktop/features/workbench/presentation/widgets/secret_migration_banner.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/l10n_app.dart';

final class _FakeRunner implements SecretMigrationRunner {
  final planCompleters = <Completer<SecretMigrationOutcome>>[];
  final applyCompleters = <Completer<SecretMigrationOutcome>>[];

  @override
  Future<SecretMigrationOutcome> plan(String cwd) {
    final completer = Completer<SecretMigrationOutcome>();
    planCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<SecretMigrationOutcome> apply(String cwd) {
    final completer = Completer<SecretMigrationOutcome>();
    applyCompleters.add(completer);
    return completer.future;
  }
}

const _planLine = 'providers.lm.api_key -> api_key_secret: codelab/lm';
const _ru = Locale('ru');

/// Кнопка предупреждения: ищется по месту, а не по подписи, чтобы тест
/// падал на проверке текста, а не на нажатии несуществующей подписи.
final _bannerAction = find.descendant(
  of: find.byType(InfoBar),
  matching: find.byType(CodeLabButton),
);

/// Первая кнопка диалога (главное действие) и вторая (закрытие).
Finder _dialogButton(int index) => find
    .descendant(
      of: find.byType(ContentDialog),
      matching: find.byType(CodeLabButton),
    )
    .at(index);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  late _FakeRunner runner;
  late StreamController<bool> turns;
  late SecretMigrationCubit cubit;

  setUp(() {
    runner = _FakeRunner();
    turns = StreamController<bool>.broadcast(sync: true);
    cubit = SecretMigrationCubit(runner: runner, turnActivity: turns.stream);
  });

  tearDown(() async {
    await cubit.close();
    await turns.close();
  });

  Future<void> pumpBanner(WidgetTester tester, {Locale locale = _ru}) =>
      tester.pumpWidget(
        localizedFluentApp(
          locale: locale,
          ScaffoldPage(
            content: BlocProvider.value(
              value: cubit,
              child: SecretMigrationBanner(onRestart: () {}),
            ),
          ),
        ),
      );

  Finder button(String label) => find.widgetWithText(CodeLabButton, label);

  Future<void> openPlan(
    WidgetTester tester,
    SecretMigrationOutcome outcome,
  ) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();
    await _tap(tester, _bannerAction);
    await tester.pump();
    runner.planCompleters.single.complete(outcome);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('предупреждение и кнопка на русском', (tester) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();

    expect(
      find.text('Секреты хранятся в файле конфигурации агента.'),
      findsOneWidget,
    );
    expect(button('Перенести секреты'), findsOneWidget);
  });

  testWidgets('диалог: заголовок и ход построения плана', (tester) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();
    await _tap(tester, _bannerAction);
    await tester.pump();

    expect(find.text('Перенести секреты'), findsWidgets);
    expect(find.text('Строится план переноса…'), findsOneWidget);
    expect(button('Закрыть'), findsOneWidget);
  });

  testWidgets('план: кнопки «Перенести» и «Отмена», строки плана как есть', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );

    expect(find.text(_planLine), findsOneWidget);
    expect(button('Перенести'), findsOneWidget);
    expect(button('Отмена'), findsOneWidget);
    expect(button('Закрыть'), findsNothing);
  });

  testWidgets('пустой план: объяснение и «Закрыть»', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [], canApply: false),
    );

    expect(find.text('Переносить нечего.'), findsOneWidget);
    expect(button('Закрыть'), findsOneWidget);
  });

  testWidgets('перенос выполнен: итог, «Перезапустить агента» и подсказка '
      'про ход', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    // Ход идёт: перезапуск недоступен, кнопка называет причину.
    turns.add(true);
    await _tap(tester, _dialogButton(0));
    await tester.pump();
    expect(find.text('Секреты переносятся…'), findsOneWidget);
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Секреты перенесены. Перезапустите встроенного агента, чтобы они '
        'вступили в силу.',
      ),
      findsOneWidget,
    );
    final restart = button('Перезапустить агента');
    expect(restart, findsOneWidget);
    expect(tester.widget<CodeLabButton>(restart).onPressed, isNull);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: restart, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, 'Дождитесь завершения текущего хода.');
  });

  testWidgets('агент закрыт: подсказка кнопки перезапуска', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await _tap(tester, _dialogButton(0));
    await tester.pump();
    // Агент сменился, пока шла запись.
    cubit.setOffered('/work/other');
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pump();
    await tester.pump();

    expect(button('Перезапустить агента'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: button('Перезапустить агента'),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tooltip.message, 'Встроенный агент больше не подключён.');
  });

  testWidgets('сбой плана: разовое сообщение собрано на русском, имя типа '
      'ошибки без текста исключения', (tester) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();
    await _tap(tester, _bannerAction);
    await tester.pump();

    runner.planCompleters.single.completeError(StateError('secret=hunter2'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Не удалось построить план: StateError.'), findsOneWidget);
    expect(find.textContaining('hunter2'), findsNothing);
  });

  testWidgets('сбой переноса: разовое сообщение на русском', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await _tap(tester, _dialogButton(0));
    await tester.pump();

    runner.applyCompleters.single.completeError(StateError('boom'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Не удалось выполнить перенос: StateError.'),
      findsOneWidget,
    );
  });

  testWidgets('текст порта (`problem`, `detail`) показывается как есть', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(
        items: [_planLine],
        canApply: false,
        readOnlyBackend: true,
        detail:
            'Secrets cannot be stored: the env backend is read-only. '
            'Add secrets.backend: file to /home/u/.codelab/config.yaml, '
            'or set CODELAB_SECRET_* variables.',
      ),
    );

    expect(
      find.textContaining('Secrets cannot be stored: the env backend'),
      findsOneWidget,
    );
    expect(button('Закрыть'), findsOneWidget);
  });

  testWidgets('смена языка пересобирает открытый диалог с планом; план и '
      'состояние Cubit те же', (tester) async {
    await pumpBanner(tester, locale: const Locale('en'));
    cubit.setOffered('/work/app');
    await tester.pump();
    await _tap(tester, _bannerAction);
    await tester.pump();
    runner.planCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pump();
    await tester.pump();
    final state = cubit.state;
    expect(find.text('Migrate'), findsOneWidget);

    await pumpBanner(tester);
    await tester.pump();

    expect(find.text('Migrate'), findsNothing);
    expect(button('Перенести'), findsOneWidget);
    expect(find.text(_planLine), findsOneWidget);
    expect(cubit.state, same(state));
  });
}
