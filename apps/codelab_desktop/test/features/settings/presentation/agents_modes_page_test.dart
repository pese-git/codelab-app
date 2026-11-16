// Страница «Agents & modes» (задача 1.1 change `add-settings-agents-modes`;
// spec app-settings «Страница «Agents & modes» только для чтения», «Режим
// разрешений новой сессии…», «Уровень рассуждения…», «Цель записи…»;
// design.md D3–D5, D9).
//
// Красные тесты: страница — заглушка итерации 1, тело появится в задаче 1.4.
//
// Проверяется поведение страницы, а не пиксели и не запись файлов: Cubit —
// двойник, который складывает вызовы страницы в `calls` и показывает заданное
// состояние. Запись режима и effort, итог источника, сужение проектом и
// цель записи проверяет `agents_modes_cubit_test.dart`; здесь — что страница
// показывает из состояния и какой метод Cubit вызывает при выборе
// пользователя. Ключи — D9: ключ стоит на самом виджете (`RadioButton`,
// `ComboBox`, `CodeLabButton`, InfoBar), как на страницах Providers и MCP.
//
// Ожидаемый публичный API: `AgentsModesPage` читает `AgentsModesCubit` из
// `BlocProvider`; страница не определяет сама, опасно ли действие: выбор
// `bypass` открывает диалог, а решение «Use bypass» / «Cancel» отдаёт Cubit
// (`confirmBypass` / `cancelBypass`), `selectMode('bypass')` страница не
// вызывает.

import 'package:codelab_desktop/features/settings/application/agents_modes_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/agents_modes_page.dart';
import 'package:codelab_setup/codelab_setup.dart' show ConfigLayer;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

/// Cubit-двойник: состояние задаёт тест, вызовы страницы — в [calls].
final class FakeAgentsModesCubit extends Cubit<AgentsModesState>
    implements AgentsModesCubit {
  FakeAgentsModesCubit(super.initialState);

  /// Вызовы страницы по порядку: `selectMode:<id>`, `selectEffort:<id>`,
  /// `selectTarget:<layer>`, `confirmBypass`, `cancelBypass`.
  final calls = <String>[];

  @override
  Future<void> reload() async => calls.add('reload');

  @override
  Future<void> selectMode(String id) async => calls.add('selectMode:$id');

  @override
  Future<void> confirmBypass() async => calls.add('confirmBypass');

  @override
  void cancelBypass() => calls.add('cancelBypass');

  @override
  Future<void> selectEffort(String id) async => calls.add('selectEffort:$id');

  @override
  void selectTarget(ConfigLayer layer) =>
      calls.add('selectTarget:${layer.name}');
}

AgentsModesReady _ready({
  String mode = 'standard',
  String? modeLabel,
  String modeSource = 'default',
  String? narrowedNotice,
  String effort = 'medium',
  String effortSource = 'default',
  ConfigLayer target = ConfigLayer.user,
  bool canTargetProject = true,
  bool saving = false,
  AgentsModesBanner? banner,
}) => AgentsModesReady(
  mode: mode,
  modeLabel: modeLabel ?? mode,
  modeSource: modeSource,
  narrowedNotice: narrowedNotice,
  effort: effort,
  effortSource: effortSource,
  target: target,
  canTargetProject: canTargetProject,
  saving: saving,
  banner: banner,
);

Finder _key(String key) => find.byKey(ValueKey(key));

/// Текст внутри виджета с ключом [key] (включая сам виджет, если это `Text`).
Finder _text(String key, String text) => find.descendant(
  of: _key(key),
  matching: find.textContaining(text),
  matchRoot: true,
);

void main() {
  late FakeAgentsModesCubit cubit;

  Future<void> pumpPage(WidgetTester tester, AgentsModesState state) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    cubit = FakeAgentsModesCubit(state);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: BlocProvider<AgentsModesCubit>.value(
              value: cubit,
              child: const AgentsModesPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Выбрана ли кнопка режима [id]: значение группы `RadioGroup` режимов.
  bool checked(WidgetTester tester, String id) =>
      tester
          .widget<RadioGroup<String>>(
            find.ancestor(
              of: _key('agents-modes-mode-plan'),
              matching: find.byType(RadioGroup<String>),
            ),
          )
          .groupValue ==
      id;

  group('Готовая страница', () {
    testWidgets('shows the body, the five modes, the disabled autopilot row, '
        'the effort and the target switch', (tester) async {
      await pumpPage(tester, _ready());

      expect(_key('settings-agents-modes'), findsOneWidget);
      for (final id in const [
        'plan',
        'ask',
        'standard',
        'accept-edits',
        'bypass',
      ]) {
        expect(_key('agents-modes-mode-$id'), findsOneWidget, reason: id);
      }
      expect(checked(tester, 'standard'), isTrue);
      expect(checked(tester, 'bypass'), isFalse);
      expect(_key('agents-modes-effort'), findsOneWidget);
      expect(_key('agents-modes-target'), findsOneWidget);
      expect(_text('agents-modes-mode-source', 'default'), findsOneWidget);
      // Блоков, которых нет в первой версии, нет (SETUP-17, D9).
      expect(find.text('Model roles'), findsNothing);
      expect(find.text('Remote A2A agents'), findsNothing);
      expect(find.text('Remember model per project folder'), findsNothing);
    });

    testWidgets('the autopilot row is inactive and explains the launch flag; a '
        'tap writes nothing', (tester) async {
      await pumpPage(tester, _ready());

      expect(
        tester
            .widget<RadioButton<dynamic>>(_key('agents-modes-mode-autopilot'))
            .enabled,
        isFalse,
      );
      expect(
        find.textContaining(
          'Only as a launch flag of the agent '
          '(codelab-agent serve --permission-mode autopilot); '
          'never saved in config.',
        ),
        findsOneWidget,
      );
      await tester.tap(_key('agents-modes-mode-autopilot'));
      await tester.pumpAndSettle();
      expect(cubit.calls, isEmpty);
    });

    testWidgets('the selected mode and its source come from the state', (
      tester,
    ) async {
      await pumpPage(tester, _ready(mode: 'accept-edits', modeSource: 'user'));

      expect(checked(tester, 'accept-edits'), isTrue);
      expect(checked(tester, 'standard'), isFalse);
      expect(_text('agents-modes-mode-source', 'user'), findsOneWidget);
    });

    testWidgets('the block captions promise "after Restart agent" for the '
        'mode and a per-session choice in the composer', (tester) async {
      await pumpPage(tester, _ready());

      expect(
        find.textContaining(
          'New sessions start in it after Restart agent; change it for one '
          'session from the composer.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Выбор accept-edits', () {
    testWidgets('a tap on accept-edits asks the Cubit to write it', (
      tester,
    ) async {
      await pumpPage(tester, _ready());

      await tester.tap(_key('agents-modes-mode-accept-edits'));
      await tester.pumpAndSettle();

      expect(cubit.calls, ['selectMode:accept-edits']);
      expect(_key('agents-modes-bypass-confirm'), findsNothing);
    });

    testWidgets('the saved banner is shown with the text of the Cubit', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _ready(
          mode: 'accept-edits',
          modeSource: 'user',
          banner: const AgentsModesBanner(
            AgentsModesBannerKind.saved,
            'Saved. New sessions use accept-edits after Restart agent.',
          ),
        ),
      );

      expect(
        _text(
          'agents-modes-banner',
          'Saved. New sessions use accept-edits after Restart agent.',
        ),
        findsOneWidget,
      );
    });
  });

  group('bypass', () {
    testWidgets('a tap on bypass opens the confirmation and writes nothing '
        'yet (Отказ от bypass / Подтверждённый bypass)', (tester) async {
      await pumpPage(tester, _ready());

      await tester.tap(_key('agents-modes-mode-bypass'));
      await tester.pumpAndSettle();

      expect(_key('agents-modes-bypass-confirm'), findsOneWidget);
      expect(find.text('Use bypass for new sessions?'), findsOneWidget);
      expect(find.text('Use bypass'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.textContaining('Use it in a disposable checkout.'),
        findsOneWidget,
      );
      expect(cubit.calls, isEmpty);
    });

    testWidgets('Cancel closes the dialog and reports the cancellation', (
      tester,
    ) async {
      await pumpPage(tester, _ready(mode: 'ask', modeSource: 'user'));

      await tester.tap(_key('agents-modes-mode-bypass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(_key('agents-modes-bypass-confirm'), findsNothing);
      expect(cubit.calls, ['cancelBypass']);
      expect(checked(tester, 'ask'), isTrue);
      expect(checked(tester, 'bypass'), isFalse);
    });

    testWidgets('Esc is a cancellation as well', (tester) async {
      await pumpPage(tester, _ready());

      await tester.tap(_key('agents-modes-mode-bypass'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(_key('agents-modes-bypass-confirm'), findsNothing);
      expect(cubit.calls, ['cancelBypass']);
    });

    testWidgets('"Use bypass" confirms the write', (tester) async {
      await pumpPage(tester, _ready());

      await tester.tap(_key('agents-modes-mode-bypass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use bypass'));
      await tester.pumpAndSettle();

      expect(_key('agents-modes-bypass-confirm'), findsNothing);
      expect(cubit.calls, ['confirmBypass']);
    });
  });

  group('Недоверенный проект и сочетание ask и plan', () {
    testWidgets('the narrowing InfoBar names the effective mode', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _ready(
          mode: 'ask',
          modeSource: 'user',
          narrowedNotice:
              'This project is not trusted, so its config can only make the '
              'mode stricter. New sessions here use ask.',
        ),
      );

      expect(
        _text('agents-modes-mode-narrowed', 'New sessions here use ask'),
        findsOneWidget,
      );
      expect(checked(tester, 'ask'), isTrue);
    });

    testWidgets('without the narrowing the InfoBar is not shown', (
      tester,
    ) async {
      await pumpPage(tester, _ready());

      expect(_key('agents-modes-mode-plan'), findsOneWidget);
      expect(_key('agents-modes-mode-narrowed'), findsNothing);
    });

    testWidgets('ask with plan is shown as ask with blocked edits and '
        'commands', (tester) async {
      await pumpPage(
        tester,
        _ready(
          mode: 'ask',
          modeLabel: 'ask (edits and commands blocked by plan)',
          modeSource: 'user',
        ),
      );

      expect(
        find.textContaining('ask (edits and commands blocked by plan)'),
        findsOneWidget,
      );
      expect(checked(tester, 'ask'), isTrue);
    });
  });

  group('Смена effort', () {
    testWidgets('choosing high asks the Cubit to write it', (tester) async {
      await pumpPage(tester, _ready());

      await tester.tap(_key('agents-modes-effort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('high').last);
      await tester.pumpAndSettle();

      expect(cubit.calls, ['selectEffort:high']);
    });

    testWidgets('the ComboBox offers low, medium and high; the caption says '
        'that only a reasoning model gets the option', (tester) async {
      await pumpPage(tester, _ready(effort: 'high', effortSource: 'user'));

      await tester.tap(_key('agents-modes-effort'));
      await tester.pumpAndSettle();

      expect(find.text('low'), findsWidgets);
      expect(find.text('medium'), findsWidgets);
      expect(find.text('high'), findsWidgets);
      expect(
        find.textContaining('only if the model supports reasoning'),
        findsOneWidget,
      );
    });

    testWidgets('the saved banner has no Restart agent for the effort', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _ready(
          effort: 'high',
          effortSource: 'user',
          banner: const AgentsModesBanner(
            AgentsModesBannerKind.saved,
            'Saved. New sessions use high.',
          ),
        ),
      );

      expect(
        _text('agents-modes-banner', 'Saved. New sessions use high.'),
        findsOneWidget,
      );
      expect(find.textContaining('Restart agent.'), findsNothing);
    });
  });

  group('Цель записи', () {
    testWidgets('without a folder the switch has no "This project only" '
        '(Без папки нет цели проекта)', (tester) async {
      await pumpPage(tester, _ready(canTargetProject: false));

      expect(_key('agents-modes-mode-plan'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('agents-modes-target'),
          matching: find.text('This project only'),
        ),
        findsNothing,
      );
    });

    testWidgets('with a folder the switch offers both targets', (tester) async {
      await pumpPage(tester, _ready());

      for (final label in const ['All projects', 'This project only']) {
        expect(
          find.descendant(
            of: _key('agents-modes-target'),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('the target is chosen before the mode and applies to it '
        '(Только этот проект)', (tester) async {
      await pumpPage(tester, _ready());

      await tester.tap(find.text('This project only'));
      await tester.pumpAndSettle();
      await tester.tap(_key('agents-modes-mode-plan'));
      await tester.pumpAndSettle();

      expect(cubit.calls, ['selectTarget:projectLocal', 'selectMode:plan']);
    });

    testWidgets('one switch serves the mode and the effort '
        '(Одна цель для режима и effort)', (tester) async {
      await pumpPage(tester, _ready());

      await tester.tap(find.text('This project only'));
      await tester.pumpAndSettle();
      await tester.tap(_key('agents-modes-effort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('low').last);
      await tester.pumpAndSettle();

      expect(cubit.calls, ['selectTarget:projectLocal', 'selectEffort:low']);
      expect(_key('agents-modes-target'), findsOneWidget);
    });
  });

  group('Страница только для чтения', () {
    testWidgets('a WebSocket agent: the InfoBar, no radios, no effort, no '
        'table (WebSocket-агент)', (tester) async {
      await pumpPage(
        tester,
        const AgentsModesReadOnly(
          notice:
              'Read-only: this agent runs on wss://devbox:7420. Change its '
              'modes and agents on that host: codelab config set, '
              '.codelab/agents.',
        ),
      );

      expect(_key('settings-agents-modes'), findsOneWidget);
      expect(
        _text('agents-modes-read-only', 'wss://devbox:7420'),
        findsOneWidget,
      );
      expect(find.textContaining('wss://devbox:7420/acp'), findsNothing);
      expect(_key('agents-modes-mode-plan'), findsNothing);
      expect(_key('agents-modes-effort'), findsNothing);
      expect(_key('agents-modes-target'), findsNothing);
      expect(_key('agents-definitions-table'), findsNothing);
    });

    testWidgets('a third-party agent shows the managed-by notice', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const AgentsModesReadOnly(
          notice: 'Agent settings are managed by python.',
        ),
      );

      expect(
        _text('agents-modes-read-only', 'managed by python'),
        findsOneWidget,
      );
      expect(_key('agents-modes-mode-plan'), findsNothing);
    });

    testWidgets('autopilot in the file: the problems with the key path and '
        'no write controls (autopilot в файле)', (tester) async {
      await pumpPage(
        tester,
        const AgentsModesUnreadable(
          problems: [
            'config.yaml:11:3: permissions.mode: autopilot is allowed only as '
                'a launch flag (--permission-mode autopilot)',
          ],
        ),
      );

      expect(
        _text('agents-modes-unreadable', 'permissions.mode'),
        findsOneWidget,
      );
      expect(_key('agents-modes-mode-plan'), findsNothing);
      expect(_key('agents-modes-effort'), findsNothing);
      expect(_key('agents-modes-target'), findsNothing);
    });

    testWidgets('while loading the body shows a progress ring and no '
        'controls', (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      cubit = FakeAgentsModesCubit(const AgentsModesLoading());
      addTearDown(cubit.close);
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: BlocProvider<AgentsModesCubit>.value(
              value: cubit,
              child: const AgentsModesPage(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_key('settings-agents-modes'), findsOneWidget);
      expect(find.byType(ProgressRing), findsOneWidget);
      expect(_key('agents-modes-mode-plan'), findsNothing);
    });
  });

  group('Конфликт и сбой записи', () {
    testWidgets('a conflict banner is shown', (tester) async {
      await pumpPage(
        tester,
        _ready(
          banner: const AgentsModesBanner(
            AgentsModesBannerKind.conflict,
            'The config changed on disk. Choose again.',
          ),
        ),
      );

      expect(_text('agents-modes-banner', 'changed on disk'), findsOneWidget);
    });
  });
}
