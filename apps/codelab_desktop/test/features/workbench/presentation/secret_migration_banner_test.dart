// Предупреждение и диалог переноса секретов встроенного агента (задача 4.4
// change `add-config-literal-secrets-and-migrate`; agent-workbench-ui
// «Перенос секретов встроенного агента», все сценарии; design.md D8).
//
// Проверяется поведение (какие тексты и кнопки видны, что вызывается), а не
// пиксели. Виджеты работают на настоящем `SecretMigrationCubit` с фейковым
// портом: IO и хранилища здесь нет.

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/secret_migration_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/secret_migration_runner.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/features/workbench/presentation/widgets/secret_migration_banner.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app_scope.dart';
import '../../../support/start_agent.dart';

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
const _warning = 'Secrets are stored in the agent config file.';
const _moved = 'Secrets moved. Restart the embedded agent to use them.';
const _envText =
    'Secrets cannot be stored: the env backend is read-only. '
    'Add secrets.backend: file to /home/u/.codelab/config.yaml, '
    'or set CODELAB_SECRET_* variables.';

/// Нажатие с запасом на таймер подсветки кнопки Fluent (100 мс): иначе тест
/// кончается с висящим таймером.
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  late _FakeRunner runner;
  late StreamController<bool> turns;
  late SecretMigrationCubit cubit;
  var restarts = 0;

  setUp(() {
    runner = _FakeRunner();
    turns = StreamController<bool>.broadcast(sync: true);
    restarts = 0;
    cubit = SecretMigrationCubit(runner: runner, turnActivity: turns.stream);
  });

  tearDown(() async {
    await cubit.close();
    await turns.close();
  });

  Future<void> pumpBanner(WidgetTester tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: BlocProvider.value(
            value: cubit,
            child: SecretMigrationBanner(onRestart: () => restarts++),
          ),
        ),
      ),
    );
  }

  Future<void> openPlan(
    WidgetTester tester,
    SecretMigrationOutcome outcome,
  ) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();
    await tap(tester, find.text('Migrate secrets'));
    await tester.pump();
    runner.planCompleters.single.complete(outcome);
    await tester.pump();
    await tester.pump();
  }

  Finder button(String label) => find.widgetWithText(CodeLabButton, label);

  testWidgets('без предложения предупреждения нет', (tester) async {
    await pumpBanner(tester);

    expect(find.byType(InfoBar), findsNothing);
    expect(find.text(_warning), findsNothing);
  });

  testWidgets('offered: InfoBar уровня warning с текстом и кнопкой', (
    tester,
  ) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();

    final bar = tester.widget<InfoBar>(find.byType(InfoBar));
    expect(bar.severity, InfoBarSeverity.warning);
    expect(find.text(_warning), findsOneWidget);
    expect(button('Migrate secrets'), findsOneWidget);
  });

  testWidgets('крестик скрывает предупреждение до следующего подключения', (
    tester,
  ) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();

    await tap(tester, find.byIcon(FluentIcons.chrome_close));
    await tester.pump();
    expect(find.byType(InfoBar), findsNothing);
    expect(cubit.state, isA<SecretMigrationHidden>());

    // Следующее подключение: признак сбросился и выставился снова.
    cubit.setOffered(null);
    cubit.setOffered('/work/app');
    // Состояние Cubit доходит до BlocBuilder через поток — нужны два кадра.
    await tester.pump();
    await tester.pump();
    expect(find.text(_warning), findsOneWidget);
  });

  testWidgets('Migrate secrets открывает диалог, пока план строится', (
    tester,
  ) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();

    await tap(tester, find.text('Migrate secrets'));
    await tester.pump();

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
  });

  testWidgets('план: строки без значений, Migrate и Cancel', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );

    expect(find.text(_planLine), findsOneWidget);
    expect(button('Migrate'), findsOneWidget);
    expect(button('Cancel'), findsOneWidget);
    expect(button('Close'), findsNothing);
  });

  testWidgets('план: строка переноса MCP-сервера показана как есть '
      '(bind-mcp-secrets-to-origin, D7)', (tester) async {
    const moveLine =
        'Moved mcp.servers[team] (with its secrets) to '
        '/work/app/.codelab/config.local.yaml; removed the secret values '
        'from /work/app/.codelab/config.yaml';
    await openPlan(
      tester,
      const SecretMigrationOutcome(
        items: [_planLine, moveLine],
        canApply: true,
      ),
    );

    expect(find.text(_planLine), findsOneWidget);
    expect(find.text(moveLine), findsOneWidget);
    expect(button('Migrate'), findsOneWidget);
  });

  testWidgets('Cancel закрывает диалог, предупреждение остаётся', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );

    await tap(tester, button('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsNothing);
    expect(find.text(_warning), findsOneWidget);
  });

  testWidgets('бэкенд env: текст и только Close', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(
        items: [_planLine],
        canApply: false,
        readOnlyBackend: true,
        detail: _envText,
      ),
    );

    expect(find.text(_envText), findsOneWidget);
    expect(button('Close'), findsOneWidget);
    expect(button('Migrate'), findsNothing);
    expect(button('Cancel'), findsNothing);
  });

  testWidgets('конфликт имени: текст конфликта и только Close', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(
        items: [_planLine],
        canApply: false,
        nameConflict: true,
        detail: 'secret codelab/lm already exists with another value',
      ),
    );

    expect(
      find.text('secret codelab/lm already exists with another value'),
      findsOneWidget,
    );
    expect(button('Close'), findsOneWidget);
    expect(button('Migrate'), findsNothing);
  });

  testWidgets('находки только в CODELAB_CONFIG: строки плана и только Close', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(
        items: ['not migrated: /x/extra.yaml is not a writable layer'],
        canApply: false,
        onlyExtraLayerFindings: true,
      ),
    );

    expect(
      find.text('not migrated: /x/extra.yaml is not a writable layer'),
      findsOneWidget,
    );
    expect(button('Close'), findsOneWidget);
    expect(button('Migrate'), findsNothing);
  });

  testWidgets('Close закрывает диалог после блокирующего плана', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(
        items: [],
        canApply: false,
        readOnlyBackend: true,
        detail: _envText,
      ),
    );

    await tap(tester, button('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsNothing);
    expect(cubit.state, isA<SecretMigrationOffered>());
  });

  testWidgets('planFailed: сообщение и Close', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(
        items: [],
        canApply: false,
        problem: 'config is invalid',
      ),
    );

    expect(find.text('config is invalid'), findsOneWidget);
    expect(button('Close'), findsOneWidget);
    expect(button('Migrate'), findsNothing);
  });

  testWidgets('Migrate -> Secrets moved и Restart agent', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );

    await tap(tester, button('Migrate'));
    await tester.pump();
    expect(find.byType(ProgressRing), findsOneWidget);
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(_moved), findsOneWidget);
    expect(button('Restart agent'), findsOneWidget);
    expect(
      tester.widget<CodeLabButton>(button('Restart agent')).onPressed,
      isNotNull,
    );
  });

  testWidgets('applyFailed: сообщение и Close', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tap(tester, button('Migrate'));
    await tester.pump();
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(
        items: [],
        canApply: false,
        problem: 'cannot store secret codelab/lm',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('cannot store secret codelab/lm'), findsOneWidget);
    expect(button('Close'), findsOneWidget);
    expect(button('Restart agent'), findsNothing);
  });

  testWidgets('Restart agent повторяет подключение и закрывает диалог', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tap(tester, button('Migrate'));
    await tester.pump();
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pump();
    await tester.pump();

    await tap(tester, button('Restart agent'));
    await tester.pumpAndSettle();

    expect(restarts, 1);
    expect(find.byType(ContentDialog), findsNothing);
    expect(cubit.state, isA<SecretMigrationHidden>());
  });

  testWidgets('во время хода Restart agent недоступна, с подсказкой', (
    tester,
  ) async {
    turns.add(true);
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tap(tester, button('Migrate'));
    await tester.pump();
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<CodeLabButton>(button('Restart agent')).onPressed,
      isNull,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Tooltip && w.message == 'Wait for the current turn to finish.',
      ),
      findsOneWidget,
    );

    turns.add(false);
    // Cubit создан в setUp, вне fake-async зоны теста: его событие доходит до
    // виджета только через реальный проход цикла событий.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(
      tester.widget<CodeLabButton>(button('Restart agent')).onPressed,
      isNotNull,
    );
  });

  testWidgets('закрытие диалога во время плана: поздний результат не '
      'открывает диалог снова', (tester) async {
    await pumpBanner(tester);
    cubit.setOffered('/work/app');
    await tester.pump();
    await tap(tester, find.text('Migrate secrets'));
    await tester.pump();

    // Закрытие барьером/Esc: маршрут снимается, Cubit узнаёт об этом.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ContentDialog), findsNothing);

    runner.planCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsNothing);
    expect(cubit.state, isA<SecretMigrationOffered>());
  });

  testWidgets('Esc во время переноса не закрывает диалог и не теряет итог', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tap(tester, button('Migrate'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
    // Маршрут не снимается и программно (барьер, системная «назад»).
    final route = ModalRoute.of(tester.element(find.byType(ContentDialog)))!;
    expect(route.popDisposition, RoutePopDisposition.doNotPop);

    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(_moved), findsOneWidget);
    expect(button('Restart agent'), findsOneWidget);
  });

  testWidgets('пустой план: строка Nothing to migrate. и Close', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [], canApply: false),
    );

    expect(find.text('Nothing to migrate.'), findsOneWidget);
    expect(button('Close'), findsOneWidget);
    expect(button('Migrate'), findsNothing);
  });

  testWidgets('частичный сбой: проблема, перенесённое и Restart agent', (
    tester,
  ) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tap(tester, button('Migrate'));
    await tester.pump();
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(
        items: [_planLine],
        canApply: false,
        problem: 'project config: write failed',
        movedAny: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('project config: write failed'), findsOneWidget);
    expect(find.text(_planLine), findsOneWidget);
    expect(button('Restart agent'), findsOneWidget);
    expect(button('Close'), findsOneWidget);

    await tap(tester, button('Restart agent'));
    await tester.pumpAndSettle();
    expect(restarts, 1);
  });

  testWidgets('во время хода после частичного сбоя Restart agent недоступна', (
    tester,
  ) async {
    turns.add(true);
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tap(tester, button('Migrate'));
    await tester.pump();
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(
        items: [_planLine],
        canApply: false,
        problem: 'project config: write failed',
        movedAny: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<CodeLabButton>(button('Restart agent')).onPressed,
      isNull,
    );
  });

  testWidgets('после смены агента Restart agent недоступна, подсказка '
      'про отсутствие агента', (tester) async {
    await openPlan(
      tester,
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tap(tester, button('Migrate'));
    await tester.pump();
    cubit.setOffered(null);
    cubit.setOffered('/other');
    runner.applyCompleters.single.complete(
      const SecretMigrationOutcome(items: [_planLine], canApply: true),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<CodeLabButton>(button('Restart agent')).onPressed,
      isNull,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Tooltip &&
            w.message == 'The embedded agent is no longer connected.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('в рабочем месте предупреждение стоит над транскриптом при '
      'соединении', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      project: '/workspace',
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => agent,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    final shell = binding.scope.resolve<CodeLabShellCubit>();
    await tester.runAsync(() => shell.startWith());
    await tester.pump();
    final migration = binding.scope.resolve<SecretMigrationCubit>();

    migration.setOffered('/work/app');
    await tester.pump();
    await tester.pump();

    expect(find.text(_warning), findsOneWidget);
    expect(find.text('Migrate secrets'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });
}
