// Страница «Agents & modes» на устройстве (задача 2.7 change
// `add-settings-agents-modes`; spec app-settings «Режим разрешений новой
// сессии…», «Таблица определений агентов…»; design.md D3, D5, D7, D14).
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` (AGENTS.md
// §21). Настоящие `~/.codelab` и хранилище ОС не затрагиваются: дом —
// временный `CODELAB_HOME` E2E-агента. Файловых диалогов и системных
// приложений тест не открывает: «Open folder» проверен тестами
// Cubit и порта.
//
// Встроенный агент открывается настоящим открывателем на временном
// `CODELAB_HOME`, поэтому в режиме `CODELAB_E2E_AGENT=embedded` (сценарий
// модели вместо конфига) тест пропускается.

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
  Duration timeout = const Duration(seconds: 30),
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

Future<void> _tapKey(WidgetTester tester, Finder finder) async {
  await _pumpUntil(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
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

/// Валидное определение и определение со строкой вместо списка в `tools`
/// (ошибка в строке 4).
const _reviewer = '''---
name: reviewer
description: Reviews diffs
tools: [read]
---
Review the diff.
''';

const _migratorBroken = '''---
name: migrator
description: Migrates code
tools: read
---
Migrate.
''';

const _migratorFixed = '''---
name: migrator
description: Migrates code
tools: [read]
---
Migrate.
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bypass needs a confirmation, a broken definition shows in the table '
    'and Reload picks up the fix',
    (tester) async {
      final home = File(E2eAgent.current.profilesPath).parent.path;
      File('$home/config.yaml').writeAsStringSync(_config);
      Directory('$home/agents').createSync(recursive: true);
      File('$home/agents/reviewer.md').writeAsStringSync(_reviewer);
      final migrator = File('$home/agents/migrator.md')
        ..writeAsStringSync(_migratorBroken);

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await ensureProject(tester, shellCubit);
      unawaited(shellCubit.startOnLaunch());
      await _pumpWhile(
        tester,
        () =>
            shellCubit.state.connectionStatus !=
            CodeLabConnectionStatus.connected,
      );
      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();
      await _tapKey(tester, _key('settings-nav-agents-and-modes'));
      await _pumpUntil(tester, _key('settings-agents-modes'));

      // Выбор bypass: диалог подтверждения, «Cancel» ничего не пишет.
      await _tapKey(tester, _key('agents-modes-mode-bypass'));
      await _pumpUntil(tester, _key('agents-modes-bypass-confirm'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        File('$home/config.yaml').readAsStringSync(),
        isNot(contains('bypass')),
      );

      // «Use bypass» записывает режим и показывает баннер о перезапуске.
      await _tapKey(tester, _key('agents-modes-mode-bypass'));
      await _pumpUntil(tester, _key('agents-modes-bypass-confirm'));
      await tester.tap(find.text('Use bypass'));
      await _pumpUntil(tester, _key('agents-modes-banner'));
      expect(
        File('$home/config.yaml').readAsStringSync(),
        contains('mode: bypass'),
      );
      expect(find.textContaining('after Restart agent'), findsWidgets);

      // Битое определение: строка и InfoBar, значение не показывается.
      await _pumpUntil(tester, _key('agents-definitions-table'));
      expect(find.text('Error · line 4'), findsOneWidget);
      expect(_key('agents-definitions-error-0'), findsOneWidget);

      // После исправления файла «Reload» убирает ошибку.
      migrator.writeAsStringSync(_migratorFixed);
      await _tapKey(tester, _key('agents-definitions-reload'));
      await _pumpWhile(
        tester,
        () => _key('agents-definitions-error-0').evaluate().isNotEmpty,
      );
      expect(find.text('Error · line 4'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
    skip: E2eAgent.current.kind == E2eAgentKind.embedded,
  );
}
