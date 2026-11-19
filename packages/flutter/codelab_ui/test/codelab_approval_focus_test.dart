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
}
