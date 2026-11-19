import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/approval_focus.dart';

/// Клавиатурный фокус одобрения в ките (change `fix-approval-focus`, D1, D2;
/// spec agent-workbench-ui «Одобрение получает клавиатурный фокус только по
/// действию пользователя»).
///
/// Почему: `Focus(autofocus: true)` у полосы решения и у группы вариантов
/// ловил фокус, когда ни у кого его не было, и тогда Cmd/Ctrl+Enter отвечал
/// на запрос разрешения без явного действия пользователя (AGENTS.md §10).
///
/// Для чего: тесты фиксируют, что полоса не берёт фокус сама, а сочетания
/// действуют только после того, как пользователь довёл фокус до её кнопок.
///
/// Как читать: сценарии идут парами — «без фокуса не отвечает» и «после Tab
/// отвечает»; обе проверки разом исключают и случайный ответ, и «мёртвые»
/// сочетания.
void main() {
  const options = [
    CodeLabApprovalOption(
      id: 'ao',
      label: 'Разрешить один раз',
      kind: CodeLabApprovalOptionKind.allowOnce,
    ),
    CodeLabApprovalOption(
      id: 'aa',
      label: 'Всегда разрешать',
      kind: CodeLabApprovalOptionKind.allowAlways,
    ),
    CodeLabApprovalOption(
      id: 'ro',
      label: 'Отклонить',
      kind: CodeLabApprovalOptionKind.rejectOnce,
    ),
    CodeLabApprovalOption(
      id: 'ra',
      label: 'Всегда отклонять',
      kind: CodeLabApprovalOptionKind.rejectAlways,
    ),
  ];

  // Сочетание → вариант, который оно выбирает (каталог CodeLabShortcut).
  final combos = <({String name, LogicalKeyboardKey key, bool alt, String id})>[
    (name: 'Enter', key: LogicalKeyboardKey.enter, alt: false, id: 'ao'),
    (name: 'Alt+Enter', key: LogicalKeyboardKey.enter, alt: true, id: 'aa'),
    (
      name: 'Backspace',
      key: LogicalKeyboardKey.backspace,
      alt: false,
      id: 'ro',
    ),
    (
      name: 'Alt+Backspace',
      key: LogicalKeyboardKey.backspace,
      alt: true,
      id: 'ra',
    ),
  ];

  Widget prompt(
    List<String> selected, {
    bool shortcutsEnabled = true,
    List<CodeLabApprovalOption> list = options,
  }) => FluentApp(
    home: Center(
      child: SizedBox(
        width: 720,
        child: CodeLabApprovalPrompt(
          options: list,
          shortcutsEnabled: shortcutsEnabled,
          onOptionSelected: selected.add,
        ),
      ),
    ),
  );

  Widget optionGroup(
    List<String> selected, {
    bool shortcutsEnabled = true,
    List<CodeLabApprovalOption> list = options,
  }) => FluentApp(
    home: CodeLabApprovalOptionGroup(
      options: list,
      shortcutsEnabled: shortcutsEnabled,
      onSelected: selected.add,
    ),
  );

  // Обе поверхности одобрения: полоса ленты и молекула группы вариантов.
  final surfaces =
      <
        ({
          String name,
          Widget Function(
            List<String>, {
            bool shortcutsEnabled,
            List<CodeLabApprovalOption> list,
          })
          build,
          Finder root,
          Finder firstButton,
        })
      >[
        (
          name: 'CodeLabApprovalPrompt',
          build: prompt,
          root: find.byType(CodeLabApprovalPrompt),
          firstButton: find.byKey(CodeLabApprovalPrompt.allowKey),
        ),
        (
          name: 'CodeLabApprovalOptionGroup',
          build: optionGroup,
          root: find.byType(CodeLabApprovalOptionGroup),
          firstButton: find.byKey(
            approvalOptionKey(CodeLabApprovalOptionKind.allowOnce),
          ),
        ),
      ];

  for (final surface in surfaces) {
    group(surface.name, () {
      testWidgets('after pump with empty focus the bar holds no focus', (
        tester,
      ) async {
        await tester.pumpWidget(surface.build(<String>[]));
        await tester.pump();

        expect(focusIsInside(tester, surface.root), isFalse);
      });

      for (final meta in const [false, true]) {
        final modifier = meta ? 'meta' : 'control';
        for (final combo in combos) {
          testWidgets('$modifier+${combo.name} without focus selects nothing', (
            tester,
          ) async {
            final selected = <String>[];
            await tester.pumpWidget(surface.build(selected));
            await tester.pump();

            await pressPrimary(tester, combo.key, meta: meta, alt: combo.alt);

            expect(selected, isEmpty);
          });

          testWidgets(
            '$modifier+${combo.name} after Tab to the first button selects '
            '${combo.id}',
            (tester) async {
              final selected = <String>[];
              await tester.pumpWidget(surface.build(selected));
              await tester.pump();
              await tabTo(tester, surface.firstButton);

              await pressPrimary(tester, combo.key, meta: meta, alt: combo.alt);

              expect(selected, [combo.id]);
            },
          );
        }
      }

      testWidgets('rebuilding with new options does not move focus', (
        tester,
      ) async {
        final selected = <String>[];
        await tester.pumpWidget(surface.build(selected));
        await tester.pump();

        await tester.pumpWidget(
          surface.build(selected, list: options.sublist(2)),
        );
        await tester.pump();

        expect(focusIsInside(tester, surface.root), isFalse);
        await pressPrimary(tester, LogicalKeyboardKey.backspace, meta: false);
        expect(selected, isEmpty);
      });

      testWidgets(
        'shortcutsEnabled: false — after Tab the shortcuts select nothing, '
        'Enter on the button selects its option',
        (tester) async {
          final selected = <String>[];
          await tester.pumpWidget(
            surface.build(selected, shortcutsEnabled: false),
          );
          await tester.pump();
          await tabTo(tester, surface.firstButton);

          for (final meta in const [false, true]) {
            for (final combo in combos) {
              await pressPrimary(tester, combo.key, meta: meta, alt: combo.alt);
            }
          }
          expect(selected, isEmpty);

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          // Кнопка Fluent держит таймер активации (~167 мс): дожидаемся его.
          await tester.pump(const Duration(milliseconds: 300));
          expect(selected, ['ao']);
        },
      );
    });
  }

  // -------------------------------------------------------------------------
  // Переход к одобрению: фокус на самой полосе (задача 2.1 change
  // `fix-approval-focus`; design.md D4; spec agent-workbench-ui «Переход к
  // ожидающему одобрению с клавиатуры»). Узел полосы берётся через
  // `Focus.of` от `CodeLabApprovalPrompt.barKey`: так тест не зависит от
  // того, где реализация хранит `FocusNode`.
  group('фокус на самой полосе (D4)', () {
    const english = [
      CodeLabApprovalOption(
        id: 'ao',
        label: 'Allow once',
        kind: CodeLabApprovalOptionKind.allowOnce,
      ),
      CodeLabApprovalOption(
        id: 'ro',
        label: 'Reject',
        kind: CodeLabApprovalOptionKind.rejectOnce,
      ),
    ];

    // Кнопка перед полосой: от неё Tab должен вести к «Allow» без остановки
    // на самой полосе (`skipTraversal`).
    late FocusNode beforeNode;
    setUp(() {
      beforeNode = FocusNode(debugLabel: 'before');
      addTearDown(beforeNode.dispose);
    });

    Widget host(
      List<String> selected, {
      bool shortcutsEnabled = true,
      Key? promptKey,
      Locale? locale,
    }) => FluentApp(
      locale: locale,
      localizationsDelegates: locale == null
          ? null
          : CodeLabLocalizations.localizationsDelegates,
      supportedLocales: locale == null
          ? const [Locale('en')]
          : CodeLabLocalizations.supportedLocales,
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 720,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Button(
                focusNode: beforeNode,
                onPressed: () {},
                child: const Text('before'),
              ),
              CodeLabApprovalPrompt(
                key: promptKey,
                options: english,
                shortcutsEnabled: shortcutsEnabled,
                onOptionSelected: selected.add,
              ),
            ],
          ),
        ),
      ),
    );

    FocusNode barNode(WidgetTester tester) =>
        Focus.of(tester.element(find.byKey(CodeLabApprovalPrompt.barKey)));

    final allow = find.byKey(CodeLabApprovalPrompt.allowKey);
    final frame = find.byKey(CodeLabApprovalPrompt.focusFrameKey);
    final prompt = find.byType(CodeLabApprovalPrompt);

    testWidgets('requestFocus of the bar node focuses the bar, not a button', (
      tester,
    ) async {
      await tester.pumpWidget(host(<String>[]));
      final node = barNode(tester);

      node.requestFocus();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(node));
      expect(focusIsInside(tester, allow), isFalse);
    });

    testWidgets('the bar node skips traversal: Tab from the element before '
        'leads straight to Allow', (tester) async {
      await tester.pumpWidget(host(<String>[]));
      beforeNode.requestFocus();
      await tester.pump();
      expect(beforeNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(
        focusIsInside(tester, allow),
        isTrue,
        reason: 'одного Tab достаточно: на самой полосе остановки нет',
      );
    });

    testWidgets('Enter and Space on the bar do not select an option', (
      tester,
    ) async {
      final selected = <String>[];
      await tester.pumpWidget(host(selected));
      barNode(tester).requestFocus();
      // Первый кадр применяет смену фокуса, второй перерисовывает рамку и
      // подсказку по `onFocusChange`.
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 300));

      expect(selected, isEmpty);
      expect(FocusManager.instance.primaryFocus, same(barNode(tester)));
    });

    testWidgets('the focus frame shows while focus is on or inside the bar '
        'and not without focus', (tester) async {
      await tester.pumpWidget(host(<String>[]));
      await tester.pump();
      expect(frame, findsNothing);

      barNode(tester).requestFocus();
      // Первый кадр применяет смену фокуса, второй перерисовывает рамку и
      // подсказку по `onFocusChange`.
      await tester.pump();
      await tester.pump();
      expect(frame, findsOneWidget);

      // Рамка — не только заливка: толщина 2 px цветом темы Fluent.
      final box = tester.widget<DecoratedBox>(frame);
      final border = (box.decoration as BoxDecoration).border! as Border;
      final theme = FluentTheme.of(tester.element(frame));
      expect(border.top.width, 2);
      expect(border.top.color, theme.resources.focusStrokeColorOuter);

      await tabTo(tester, allow);
      expect(frame, findsOneWidget, reason: 'фокус внутри полосы');

      beforeNode.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(frame, findsNothing);
    });

    testWidgets('semantics: Awaiting approval and the spoken shortcuts on '
        'macOS', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(<String>[]));
      barNode(tester).requestFocus();
      // Первый кадр применяет смену фокуса, второй перерисовывает рамку и
      // подсказку по `onFocusChange`.
      await tester.pump();
      await tester.pump();

      final data = tester
          .getSemantics(find.bySemanticsLabel('Awaiting approval'))
          .getSemanticsData();
      expect(data.label, contains('Awaiting approval'));
      expect(data.hint, contains('Allow once: Cmd+Enter'));
      expect(data.hint, contains('Reject: Cmd+Backspace'));
      expect(data.hint, isNot(contains('⌘')));
      expect(data.hint, isNot(contains('⏎')));
      handle.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('macOS: the hint names ⇧⌘A while focus is outside the bar', (
      tester,
    ) async {
      await tester.pumpWidget(host(<String>[]));
      await tester.pump();
      expect(
        find.text('Press ⇧⌘A to answer from the keyboard'),
        findsOneWidget,
      );

      barNode(tester).requestFocus();
      // Первый кадр применяет смену фокуса, второй перерисовывает рамку и
      // подсказку по `onFocusChange`.
      await tester.pump();
      await tester.pump();
      expect(find.text('Press ⇧⌘A to answer from the keyboard'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Linux: the hint names Ctrl+Shift+A and disappears with '
        'focus', (tester) async {
      await tester.pumpWidget(host(<String>[]));
      await tester.pump();
      const text = 'Press Ctrl+Shift+A to answer from the keyboard';
      expect(find.text(text), findsOneWidget);

      await tabTo(tester, allow);
      expect(find.text(text), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a bar of an inactive approval has no hint', (tester) async {
      await tester.pumpWidget(host(<String>[], shortcutsEnabled: false));
      await tester.pump();

      expect(find.textContaining('to answer from the keyboard'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('ru: the hint is translated', (tester) async {
      await tester.pumpWidget(host(<String>[], locale: const Locale('ru')));
      await tester.pump();

      expect(
        find.text('Нажмите Ctrl+Shift+A, чтобы ответить с клавиатуры'),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a new request key gives a bar without focus', (tester) async {
      await tester.pumpWidget(
        host(<String>[], promptKey: const ValueKey('r1')),
      );
      barNode(tester).requestFocus();
      // Первый кадр применяет смену фокуса, второй перерисовывает рамку и
      // подсказку по `onFocusChange`.
      await tester.pump();
      await tester.pump();
      expect(focusIsInside(tester, prompt), isTrue);

      await tester.pumpWidget(
        host(<String>[], promptKey: const ValueKey('r2')),
      );
      await tester.pump();

      expect(focusIsInside(tester, prompt), isFalse);
      expect(frame, findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Уход полосы с фокусом (задача 3.1 change `fix-approval-focus`; design.md
  // D5; spec «Фокус после ухода одобрения»): полоса сообщает хосту, что фокус
  // был у неё, когда она исчезает или заменяется полосой другого запроса.
  group('уход полосы с фокусом (D5)', () {
    const english = [
      CodeLabApprovalOption(
        id: 'ao',
        label: 'Allow once',
        kind: CodeLabApprovalOptionKind.allowOnce,
      ),
      CodeLabApprovalOption(
        id: 'ro',
        label: 'Reject',
        kind: CodeLabApprovalOptionKind.rejectOnce,
      ),
    ];

    Widget host({
      required int Function() released,
      required void Function() onReleased,
      bool show = true,
      Key promptKey = const ValueKey('r1'),
    }) => FluentApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 720,
          child: show
              ? CodeLabApprovalPrompt(
                  key: promptKey,
                  options: english,
                  onOptionSelected: (_) {},
                  onApprovalFocusReleased: onReleased,
                )
              : const SizedBox.shrink(),
        ),
      ),
    );

    FocusNode barNode(WidgetTester tester) =>
        Focus.of(tester.element(find.byKey(CodeLabApprovalPrompt.barKey)));

    testWidgets('dispose with focus on the bar reports once', (tester) async {
      var released = 0;
      void onReleased() => released++;
      await tester.pumpWidget(
        host(released: () => released, onReleased: onReleased),
      );
      barNode(tester).requestFocus();
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(
        host(released: () => released, onReleased: onReleased, show: false),
      );
      await tester.pump();

      expect(released, 1);
    });

    testWidgets('dispose with focus on a button inside reports once', (
      tester,
    ) async {
      var released = 0;
      void onReleased() => released++;
      await tester.pumpWidget(
        host(released: () => released, onReleased: onReleased),
      );
      await tabTo(tester, find.byKey(CodeLabApprovalPrompt.allowKey));

      await tester.pumpWidget(
        host(released: () => released, onReleased: onReleased, show: false),
      );
      await tester.pump();

      expect(released, 1);
    });

    testWidgets('a new request key with focus reports once', (tester) async {
      var released = 0;
      void onReleased() => released++;
      await tester.pumpWidget(
        host(released: () => released, onReleased: onReleased),
      );
      barNode(tester).requestFocus();
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(
        host(
          released: () => released,
          onReleased: onReleased,
          promptKey: const ValueKey('r2'),
        ),
      );
      await tester.pump();

      expect(released, 1);
      // Новая полоса фокуса не получила: следующая смена ничего не сообщает.
      await tester.pumpWidget(
        host(released: () => released, onReleased: onReleased, show: false),
      );
      await tester.pump();
      expect(released, 1);
    });

    testWidgets('a bar without focus never reports', (tester) async {
      var released = 0;
      void onReleased() => released++;
      await tester.pumpWidget(
        host(released: () => released, onReleased: onReleased),
      );
      await tester.pump();

      await tester.pumpWidget(
        host(
          released: () => released,
          onReleased: onReleased,
          promptKey: const ValueKey('r2'),
        ),
      );
      await tester.pumpWidget(
        host(released: () => released, onReleased: onReleased, show: false),
      );
      await tester.pump();

      expect(released, 0);
    });
  });
}
