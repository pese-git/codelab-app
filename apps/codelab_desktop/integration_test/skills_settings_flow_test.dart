// Страница «Skills & extensions» на устройстве (задача 4.7 change
// `add-app-skills-page`; spec app-settings «Страница «Skills & extensions»:
// доступ и папка», «…навыки», «…контекстные файлы и шаблоны»; design.md D1,
// D2, D6).
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` (AGENTS.md
// §21). Настоящие `~/.codelab` и хранилище ОС не затрагиваются: дом —
// временный `CODELAB_HOME` с навыком пользователя, а `AGENTS.md` лежит в
// временной папке проекта. Встроенный агент открывается настоящим
// открывателем, поэтому тест в режиме `CODELAB_E2E_AGENT=embedded` (сценарий
// модели вместо конфига) не имеет смысла. Выключатели и согласие (запись
// `skills.*`) — итерация 5.

import 'dart:async';
import 'dart:io';

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets, reason: 'did not appear in $timeout');
}

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isFalse, reason: 'still waiting after $timeout');
}

/// Конфиг дома: один локальный провайдер, чтобы встроенный агент открыл
/// сессию (ход модели не нужен).
const _config = '''
agent:
  default_model: local/m
providers:
  local:
    kind: openai-compatible
    base_url: http://127.0.0.1:9/v1
    models:
      m:
        context_window: 32000
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the page shows the user skill and the AGENTS.md of the project folder',
    (tester) async {
      final home = File(E2eAgent.current.profilesPath).parent.path;
      File('$home/config.yaml').writeAsStringSync(_config);
      Directory('$home/skills/notes').createSync(recursive: true);
      File('$home/skills/notes/SKILL.md').writeAsStringSync(
        '---\nname: notes\ndescription: Take short notes\n---\nBody of notes.\n',
      );

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await ensureProject(tester, shellCubit);
      final project = shellCubit.state.selectedProjectPath!;
      File('$project/AGENTS.md').writeAsStringSync('# Project rules\n');
      unawaited(shellCubit.startOnLaunch());
      await _pumpWhile(
        tester,
        () =>
            shellCubit.state.connectionStatus !=
            CodeLabConnectionStatus.connected,
      );

      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();
      await tester.tap(_key('settings-nav-skills-and-extensions'));
      await tester.pumpAndSettle();

      await _pumpUntil(tester, _key('skills-row-notes'));
      expect(_key('settings-skills'), findsOneWidget);
      expect(find.text('Take short notes'), findsOneWidget);
      expect(_key('skills-context-0'), findsOneWidget);
      // Тело навыка на странице не показывается.
      expect(find.textContaining('Body of notes'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
