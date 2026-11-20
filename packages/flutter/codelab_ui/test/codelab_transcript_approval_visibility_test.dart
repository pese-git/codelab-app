// Видимость полосы одобрения в ленте (задача 7.1 change `fix-approval-focus`;
// design.md D14, п. 1; spec agent-workbench-ui «Ответ на одобрение сочетанием
// с любого места рабочего места», компенсирующая мера «Видимость»).
//
// Почему: глобальное сочетание не должно отвечать на запрос, которого
// пользователь не видит. Видимость знает только лента: у неё прокрутка и
// построенные полосы. Хост (application) решает по признаку, лента только
// сообщает его через `CodeLabApprovalVisibility`.
//
// Красный до задачи 7.2: ручка — заглушка, всегда отвечающая «не видна»;
// сценарии «видна» падают, сценарии «не видна» зелёные по заглушке и
// защищают от ответа «видна» вне области.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
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

List<CodeLabTranscriptRow> _rows() => [
  CodeLabToolCallRow(
    id: 'tool-1',
    status: CodeLabToolCallStatus.running,
    label: 'Run echo',
    approval: CodeLabTranscriptApproval.pending(
      risk: CodeLabApprovalRisk.shell,
      options: _options,
      onOptionSelected: (_) {},
      targetId: 'perm-1',
      sessionId: 's1',
    ),
  ),
  for (var i = 0; i < 60; i++)
    CodeLabAgentTextRow(id: 'text-$i', text: 'Answer $i'),
];

/// Лента 700x400, поверх которой при [covered] лежит непрозрачная панель
/// (как выдвижная панель узкого окна, D14 п. 1).
Widget _host(CodeLabApprovalVisibility visibility, {bool covered = false}) =>
    FluentApp(
      home: SizedBox(
        width: 700,
        height: 400,
        child: Stack(
          children: [
            Positioned.fill(
              child: CodeLabTranscriptPanel(
                rows: _rows(),
                approvalVisibility: visibility,
              ),
            ),
            if (covered)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const ColoredBox(color: Color(0xFF202020)),
                ),
              ),
          ],
        ),
      ),
    );

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> _jumpTo(WidgetTester tester, double offset) async {
  _position(tester).jumpTo(offset);
  await tester.pump();
  await tester.pump();
}

/// Пользователь прокрутил ленту вверх до начала. Лента сначала следует за
/// хвостом, и программный `jumpTo` у начала она возвращает вниз; жест пальцем
/// помечает чтение истории, после чего позицию можно ставить `_jumpTo`.
Future<void> _scrollToTopByUser(WidgetTester tester) async {
  await _jumpTo(tester, _position(tester).maxScrollExtent);
  await tester.drag(find.byType(ListView), const Offset(0, 5000));
  await tester.pump();
  await tester.pump();
  expect(_position(tester).pixels, 0);
}

void main() {
  final bar = find.byKey(CodeLabApprovalPrompt.keyFor('s1', 'perm-1'));

  testWidgets('полоса построена и целиком в области — видна', (tester) async {
    final visibility = CodeLabApprovalVisibility();
    await tester.pumpWidget(_host(visibility));
    await tester.pump();

    expect(bar, findsOneWidget);
    expect(visibility.isVisible('s1', 'perm-1'), isTrue);
  });

  testWidgets('лента прокручена вниз, полоса не построена — не видна', (
    tester,
  ) async {
    final visibility = CodeLabApprovalVisibility();
    await tester.pumpWidget(_host(visibility));
    await _jumpTo(tester, _position(tester).maxScrollExtent);

    expect(bar, findsNothing, reason: 'строка вне области не построена');
    expect(visibility.isVisible('s1', 'perm-1'), isFalse);
  });

  testWidgets('полоса частично за краем области — не видна', (tester) async {
    final visibility = CodeLabApprovalVisibility();
    await tester.pumpWidget(_host(visibility));
    await tester.pump();
    await _scrollToTopByUser(tester);
    final viewport = tester.getRect(find.byType(CodeLabTranscriptPanel));
    final rect = tester.getRect(bar);
    // Сдвигаем ленту так, чтобы верхняя половина полосы ушла за верхний край.
    final shift = rect.top - viewport.top + rect.height / 2;
    await _jumpTo(tester, shift);

    expect(bar, findsOneWidget, reason: 'полоса ещё построена');
    expect(tester.getRect(bar).top, lessThan(viewport.top));
    expect(visibility.isVisible('s1', 'perm-1'), isFalse);
  });

  testWidgets('полоса вернулась в область целиком — снова видна', (
    tester,
  ) async {
    final visibility = CodeLabApprovalVisibility();
    await tester.pumpWidget(_host(visibility));
    await _scrollToTopByUser(tester);
    expect(visibility.isVisible('s1', 'perm-1'), isTrue);
    await _jumpTo(tester, _position(tester).maxScrollExtent);
    expect(visibility.isVisible('s1', 'perm-1'), isFalse);

    await _scrollToTopByUser(tester);

    expect(visibility.isVisible('s1', 'perm-1'), isTrue);
  });

  testWidgets('чужой запрос и чужая сессия — не видны', (tester) async {
    final visibility = CodeLabApprovalVisibility();
    await tester.pumpWidget(_host(visibility));
    await tester.pump();

    expect(visibility.isVisible('s1', 'perm-2'), isFalse);
    expect(visibility.isVisible('s2', 'perm-1'), isFalse);
  });

  testWidgets('поверх ленты открыта панель — не видна', (tester) async {
    final visibility = CodeLabApprovalVisibility();
    await tester.pumpWidget(_host(visibility, covered: true));
    await tester.pump();

    expect(bar, findsOneWidget, reason: 'полоса построена, но закрыта');
    expect(visibility.isVisible('s1', 'perm-1'), isFalse);
  });

  testWidgets('панель закрыта — полоса снова видна', (tester) async {
    final visibility = CodeLabApprovalVisibility();
    await tester.pumpWidget(_host(visibility, covered: true));
    await tester.pump();
    await tester.pumpWidget(_host(visibility));
    await tester.pump();

    expect(visibility.isVisible('s1', 'perm-1'), isTrue);
  });

  // Гипотеза «полоса прокрутки ленты считается перекрытием» (D14, п. 1)
  // проверена и опровергнута: скроллбар Fluent оборачивает `Scrollable` ленты,
  // то есть он предок полосы, а предки в проверке не перекрывают. Тест
  // фиксирует это: колесо мыши на macOS, указатель у правого края (полоса
  // прокрутки разворачивается до наведённой толщины) — полоса видна.
  testWidgets('полоса прокрутки ленты полосу одобрения не перекрывает', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final visibility = CodeLabApprovalVisibility();
    await tester.pumpWidget(
      FluentApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 700,
            height: 400,
            child: CodeLabTranscriptPanel(
              rows: _rows(),
              approvalVisibility: visibility,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(695, 200)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 1)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendEventToBinding(pointer.hover(const Offset(695, 70)));
    await tester.pump(const Duration(milliseconds: 300));

    final visible = visibility.isVisible('s1', 'perm-1');
    debugDefaultTargetPlatformOverride = null;
    expect(visible, isTrue);
  });

  group('причина отказа (check)', () {
    testWidgets('видимая полоса — CodeLabApprovalVisible', (tester) async {
      final visibility = CodeLabApprovalVisibility();
      await tester.pumpWidget(_host(visibility));
      await tester.pump();

      final result = visibility.check('s1', 'perm-1');
      expect(result, isA<CodeLabApprovalVisible>());
      expect(result.diagnostic, 'visible');
    });

    testWidgets('полоса не построена и чужой запрос — NotBuilt', (
      tester,
    ) async {
      final visibility = CodeLabApprovalVisibility();
      expect(
        visibility.check('s1', 'perm-1'),
        isA<CodeLabApprovalNotBuilt>(),
        reason: 'ленты нет',
      );
      await tester.pumpWidget(_host(visibility));
      await tester.pump();

      expect(visibility.check('s1', 'perm-2').diagnostic, 'not_built');
    });

    testWidgets('полоса за краем области — OutOfViewport с прямоугольниками', (
      tester,
    ) async {
      final visibility = CodeLabApprovalVisibility();
      await tester.pumpWidget(_host(visibility));
      await tester.pump();
      await _scrollToTopByUser(tester);
      final viewport = tester.getRect(find.byType(CodeLabTranscriptPanel));
      final rect = tester.getRect(bar);
      await _jumpTo(tester, rect.top - viewport.top + rect.height / 2);

      final result = visibility.check('s1', 'perm-1');
      expect(result, isA<CodeLabApprovalOutOfViewport>());
      final out = result as CodeLabApprovalOutOfViewport;
      expect(out.bar, tester.getRect(bar));
      expect(out.viewport, viewport);
      expect(result.diagnostic, startsWith('out_of_viewport bar=('));
    });

    testWidgets('непрозрачный слой поверх — Obscured с типом и точкой', (
      tester,
    ) async {
      final visibility = CodeLabApprovalVisibility();
      await tester.pumpWidget(_host(visibility, covered: true));
      await tester.pump();

      final result = visibility.check('s1', 'perm-1');
      expect(result, isA<CodeLabApprovalObscured>());
      final obscured = result as CodeLabApprovalObscured;
      expect(obscured.blocker, isNotNull);
      expect(tester.getRect(bar).contains(obscured.point), isTrue);
      expect(result.diagnostic, startsWith('obscured by='));
      expect(result.diagnostic, contains(' at=('));
    });
  });
}
