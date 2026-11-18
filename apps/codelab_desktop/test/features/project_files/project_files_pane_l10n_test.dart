// Красные тесты задачи 3.3 change `add-desktop-localization`: панель Files на
// русском (spec app-settings «Локализация интерфейса app»;
// workspace-file-browser «Панель Files в доке инструментов»; design.md D5, D7).
//
// Имена файлов и папок, пути и содержимое — данные проекта, они не
// переводятся (D7); переводятся подписи панели, пустые состояния и причины
// отказа чтения, которые `application` отдаёт типизированным
// `ProjectFilesFailureKind`, а текст собирает presentation. Русские формулировки
// вне глоссария (в нём «Файлы», «Обновить» нет) перечислены в отчёте
// задачи 3.3.

import 'package:codelab_client_core/codelab_client_core.dart'
    show ProjectFilesFailureKind;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_project_files.dart';
import '../../support/live_scene.dart';

const _ru = Locale('ru');

FakeProjectFiles _files() => FakeProjectFiles(
  listings: {
    '/work/app': {
      '': listingOf('', [fileEntry('README.md'), outsideEntry('secrets')]),
    },
  },
);

Finder _pane() => find.byKey(CodeLabToolDock.paneKey(ToolPane.files));

void main() {
  testWidgets('подписи панели и пустой предпросмотр на русском', (
    tester,
  ) async {
    final scene = await LiveScene.open(
      tester,
      locale: _ru,
      projectFiles: _files(),
    );
    scene.cubit.openPane(ToolPane.files);
    await scene.flush();

    final pane = scene.textOf(_pane());
    expect(pane, contains('.git никогда не показывается'));
    expect(pane, contains('Обновить'));
    expect(pane, contains('Выберите файл для просмотра.'));
    // Имя файла — данные проекта.
    expect(pane, contains('README.md'));

    await scene.close();
  });

  testWidgets('папка проекта не существует: сообщение на русском', (
    tester,
  ) async {
    final scene = await LiveScene.open(
      tester,
      locale: _ru,
      projectFiles: FakeProjectFiles(missingFolders: {'/work/app'}),
    );
    scene.cubit.openPane(ToolPane.files);
    await scene.flush();

    expect(scene.textOf(_pane()), contains('Папка проекта не существует.'));

    await scene.close();
  });

  testWidgets('файл не прочитан: причина по виду отказа на русском', (
    tester,
  ) async {
    final files = _files()
      ..failingFiles[('/work/app', 'README.md')] =
          ProjectFilesFailureKind.notFound;
    final scene = await LiveScene.open(
      tester,
      locale: _ru,
      projectFiles: files,
    );
    scene.cubit.openPane(ToolPane.files);
    await scene.flush();

    await tester.tap(find.byKey(const ValueKey('file-tree-row-README.md')));
    await scene.flush();

    expect(scene.textOf(_pane()), contains('Файл не найден.'));

    await scene.close();
  });

  testWidgets('папка не прочитана: строка дерева на русском', (tester) async {
    final files = FakeProjectFiles(
      listings: {
        '/work/app': {
          '': listingOf('', [dirEntry('lib')]),
        },
      },
    )..failingDirs[('/work/app', 'lib')] = ProjectFilesFailureKind.unreadable;
    final scene = await LiveScene.open(
      tester,
      locale: _ru,
      projectFiles: files,
    );
    scene.cubit.openPane(ToolPane.files);
    await scene.flush();

    await tester.tap(find.byKey(const ValueKey('file-tree-row-lib')));
    await scene.flush();

    expect(scene.textOf(_pane()), contains('Не удаётся прочитать эту папку.'));

    await scene.close();
  });
}
