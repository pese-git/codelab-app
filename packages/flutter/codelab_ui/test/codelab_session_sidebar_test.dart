// Пустой сайдбар и пункт «Open folder…» внутри списка (задача 2.3 change
// `add-empty-project-screen`; design.md D9, D11; spec agent-workbench-ui
// «Sessions sidebar grouped by project», сценарии «No projects yet» и
// «Open folder… follows the project groups»).
//
// Красный до задачи 2.4: параметров `openFolderShortcut` и `noProjectsLabel`
// ещё нет, «Open folder…» стоит в нижней колонке рядом с «Settings».

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  List<CodeLabSidebarProject> projects = const [],
  double width = 300,
  String? openFolderShortcut,
  VoidCallback? onOpenFolder,
}) => FluentApp(
  home: Center(
    child: SizedBox(
      width: width,
      height: 560,
      child: CodeLabSessionSidebar(
        projects: projects,
        onSessionSelected: (_) {},
        onOpenFolder: onOpenFolder,
        onSettings: () {},
        openFolderShortcut: openFolderShortcut,
      ),
    ),
  ),
);

const _projects = [
  CodeLabSidebarProject(path: '/work/a', name: 'alpha', current: true),
  CodeLabSidebarProject(path: '/work/b', name: 'beta'),
];

void main() {
  testWidgets('пустой список проектов: «No recent projects yet.»', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    expect(find.text('No recent projects yet.'), findsOneWidget);
    expect(find.byKey(CodeLabSessionSidebar.openFolderKey), findsOneWidget);
  });

  testWidgets('есть проекты: подписи пустого списка нет', (tester) async {
    await tester.pumpWidget(_host(projects: _projects));

    expect(find.text('No recent projects yet.'), findsNothing);
  });

  testWidgets('«Open folder…» стоит после последней группы и до «Settings»', (
    tester,
  ) async {
    await tester.pumpWidget(_host(projects: _projects));

    final lastGroup = tester.getBottomLeft(
      find.byKey(CodeLabSessionSidebar.projectKey('beta')),
    );
    final open = tester.getTopLeft(
      find.byKey(CodeLabSessionSidebar.openFolderKey),
    );
    final settings = tester.getTopLeft(
      find.byKey(CodeLabSessionSidebar.settingsKey),
    );
    expect(open.dy, greaterThanOrEqualTo(lastGroup.dy));
    expect(open.dy, lessThan(settings.dy));
    // Пункт — часть прокручиваемого списка, а не нижней колонки: он ниже
    // подписи пустого/непустого списка, но выше разделителя «Settings»
    // не обязан быть; важно, что он внутри ListView.
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byKey(CodeLabSessionSidebar.openFolderKey),
      ),
      findsOneWidget,
    );
  });

  testWidgets('в пустом списке «Open folder…» идёт после подписи', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    final label = tester.getBottomLeft(find.text('No recent projects yet.'));
    final open = tester.getTopLeft(
      find.byKey(CodeLabSessionSidebar.openFolderKey),
    );
    expect(open.dy, greaterThanOrEqualTo(label.dy));
  });

  testWidgets('openFolderShortcut виден справа от подписи; нажатие работает', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(openFolderShortcut: 'Ctrl+O', onOpenFolder: () => opened++),
    );

    final shortcut = find.text('Ctrl+O');
    expect(shortcut, findsOneWidget);
    expect(
      tester.getTopLeft(shortcut).dx,
      greaterThan(tester.getTopLeft(find.text('Open folder…')).dx),
    );
    await tester.tap(find.byKey(CodeLabSessionSidebar.openFolderKey));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened, 1);
  });

  testWidgets('без openFolderShortcut подсказки нет', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.text('Ctrl+O'), findsNothing);
  });

  testWidgets('компактный вид: без подписи и без подсказки', (tester) async {
    await tester.pumpWidget(_host(width: 80, openFolderShortcut: 'Ctrl+O'));

    expect(find.byKey(CodeLabSessionSidebar.openFolderKey), findsOneWidget);
    expect(find.text('Ctrl+O'), findsNothing);
    expect(find.text('No recent projects yet.'), findsNothing);
  });
}
