// Старт app с настройкой «Reopen the last project and its tabs» (задача 3.3
// change `add-app-general-page`; spec app-settings «Открытие последнего проекта
// при запуске», сценарии «По умолчанию проект прошлого запуска открывается»,
// «Выключено — старт без проекта», «Выключено — снимок нового запуска
// пишется»; design.md D9).
//
// Реализация — задача 3.4 change `add-app-general-page`.
//
// Тесты идут через граф app (`CodeLabTestBinding`) и проверяют наблюдаемое:
// выбран ли проект, какие кадры ушли агенту, сколько раз открыт транспорт,
// что записано в снимок и что видно в журнале. Вызов
// `ClientWorkspace.startWithoutRestore()` напрямую в графе не перехватить,
// поэтому «ровно раз» проверяется следствиями: проект не выбран, `session/load`
// нет, агент не стартовал, снимок нового запуска пишется (acp-client-kit
// «Старт без восстановления рабочего пространства» проверяет сам kit).

import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/core/platform/shared_preferences_workspace_snapshot_store.dart';
import 'package:codelab_desktop/core/platform/startup_preferences.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/test_app_scope.dart';

String _snapshot(String project, {String? session}) => jsonEncode({
  'version': 1,
  'windows': {
    'main': {
      'projectDirectory': project,
      'activeSessionId': ?session,
      'openSessions': [
        if (session != null) {'id': session, 'cwd': project},
      ],
    },
  },
});

const _loadSession = AgentCapabilities(loadSession: true);

/// Порт, чьё чтение возвращает заданный результат.
final class _FixedStartupPreferences implements StartupPreferences {
  _FixedStartupPreferences(this.result);

  final StartupLoad result;
  final saves = <bool>[];

  @override
  Future<StartupLoad> load() async => result;

  @override
  Future<void> save(bool reopenLastProject) async =>
      saves.add(reopenLastProject);
}

/// Порт, чьё чтение бросает (контракт «не бросает» нарушен адаптером).
final class _ThrowingStartupPreferences implements StartupPreferences {
  @override
  Future<StartupLoad> load() => Future.error(StateError('disk is gone: /x/y'));

  @override
  Future<void> save(bool reopenLastProject) async {}
}

void main() {
  setUp(TestWidgetsFlutterBinding.ensureInitialized);

  Iterable<Map<String, Object?>> events(
    CodeLabTestBinding binding,
    String name,
  ) => binding.scope.resolve<LogBuffer>().entries.value.where(
    (entry) => entry['event'] == name,
  );

  List<String> methodsOf(FakeAcpTransport agent) => [
    for (final message in agent.sentMessages)
      if (message case JsonRpcRequest(:final method)) method,
  ];

  Future<void> restored(CodeLabTestBinding binding) =>
      binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

  group('включено (по умолчанию)', () {
    test('проект прошлого запуска открывается, активная сессия '
        'загружается при первом подключении', () async {
      final agent = FakeAcpTransport()
        ..initializeAgentCapabilities = _loadSession;
      final binding = CodeLabTestBinding(
        stdioTransportFactory: (_) => agent,
        preferences: {
          kWorkspaceSnapshotPrefsKey: _snapshot(
            '/work/app',
            session: 'sess_42',
          ),
        },
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      await restored(binding);
      final load = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionLoadMethod,
      );

      final launching = cubit.startOnLaunch();
      final request = await load as JsonRpcRequest;
      agent.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const <String, Object?>{},
        ),
      );
      await launching;

      expect(cubit.state.selectedProjectPath, '/work/app');
      expect(
        LoadSessionRequest.fromJson(request.params).sessionId.value,
        'sess_42',
      );
      expect(events(binding, 'app.reopen_last_project_skipped'), isEmpty);
      expect(events(binding, 'app.reopen_last_project_unreadable'), isEmpty);
    });

    test('явное true ведёт себя так же', () async {
      final binding = CodeLabTestBinding(
        preferences: {
          kWorkspaceSnapshotPrefsKey: _snapshot('/work/app'),
          kReopenLastProjectKey: true,
        },
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      await restored(binding);

      expect(cubit.state.selectedProjectPath, '/work/app');
    });
  });

  group('выключено', () {
    test('старт без проекта: проект не выбран, агент не запущен, кадров '
        'нет, недавние проекты на месте', () async {
      final agent = FakeAcpTransport()
        ..initializeAgentCapabilities = _loadSession;
      var starts = 0;
      final binding = CodeLabTestBinding(
        stdioTransportFactory: (_) {
          starts++;
          return agent;
        },
        preferences: {
          kWorkspaceSnapshotPrefsKey: _snapshot(
            '/work/app',
            session: 'sess_42',
          ),
          kReopenLastProjectKey: false,
        },
        recentProjects: ['/work/app'],
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      await restored(binding);
      // До триггера запуска: проект из снимка не выбран.
      expect(cubit.state.selectedProjectPath, isNull);

      await cubit.startOnLaunch();
      await pumpEventQueue();

      expect(starts, 0);
      expect(agent.sentMessages, isEmpty);
      expect(methodsOf(agent), isNot(contains(sessionLoadMethod)));
      expect(methodsOf(agent), isNot(contains(sessionNewMethod)));
      expect(cubit.state.sessions, isEmpty);
      final recents = binding.scope
          .resolve<CodeLabShellParts>()
          .settings
          .state
          .recentProjects;
      expect([for (final r in recents) r.path], contains('/work/app'));
    });

    test('app.reopen_last_project_skipped пишется один раз, без пути и '
        'значения', () async {
      final binding = CodeLabTestBinding(
        preferences: {
          kWorkspaceSnapshotPrefsKey: _snapshot('/work/app'),
          kReopenLastProjectKey: false,
        },
      );
      binding.scope.resolve<CodeLabShellCubit>();
      await restored(binding);

      final skipped = events(binding, 'app.reopen_last_project_skipped');
      expect(skipped, hasLength(1));
      expect(skipped.single['level'], 'info');
      expect('${skipped.single}', isNot(contains('/work/app')));
    });

    test('снимок нового запуска пишется: после выбора проекта и включения '
        'настройки следующий старт открывает проект последнего '
        'запуска', () async {
      final first = CodeLabTestBinding(
        preferences: {
          kWorkspaceSnapshotPrefsKey: _snapshot(
            '/work/app',
            session: 'sess_42',
          ),
          kReopenLastProjectKey: false,
        },
      );
      final cubit = first.scope.resolve<CodeLabShellCubit>();
      await restored(first);
      expect(cubit.state.selectedProjectPath, isNull);

      await cubit.selectProject('/work/other');
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString(kWorkspaceSnapshotPrefsKey)!) as Map;
      final window = (saved['windows'] as Map)['main'] as Map;
      expect(window['projectDirectory'], '/work/other');
      expect(window['openSessions'], isEmpty);

      // Перезапуск с включённой настройкой (ключа нет).
      final snapshot = prefs.getString(kWorkspaceSnapshotPrefsKey)!;
      await closeCodeLabRootScopeInTest();
      final second = CodeLabTestBinding(
        preferences: {kWorkspaceSnapshotPrefsKey: snapshot},
      );
      final restarted = second.scope.resolve<CodeLabShellCubit>();
      await restored(second);

      expect(restarted.state.selectedProjectPath, '/work/other');
    });
  });

  group('значение не читается: как при включённом', () {
    test('сбой хранилища: проект открывается, событие unreadable с именем '
        'типа без текста', () async {
      final binding = CodeLabTestBinding(
        startupPreferences: _FixedStartupPreferences(
          const StartupLoad(true, readFailure: 'StateError'),
        ),
        preferences: {kWorkspaceSnapshotPrefsKey: _snapshot('/work/app')},
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      await restored(binding);

      expect(cubit.state.selectedProjectPath, '/work/app');
      final unreadable = events(binding, 'app.reopen_last_project_unreadable');
      expect(unreadable, hasLength(1));
      expect(unreadable.single['level'], 'warning');
      expect(unreadable.single['error_class'], 'StateError');
      expect(events(binding, 'app.reopen_last_project_skipped'), isEmpty);
    });

    test('порт бросает при чтении: восстановление не зависает, проект '
        'открывается, событие unreadable с именем типа без текста', () async {
      final binding = CodeLabTestBinding(
        startupPreferences: _ThrowingStartupPreferences(),
        preferences: {kWorkspaceSnapshotPrefsKey: _snapshot('/work/app')},
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      await restored(binding);

      expect(cubit.state.selectedProjectPath, '/work/app');
      final unreadable = events(binding, 'app.reopen_last_project_unreadable');
      expect(unreadable, hasLength(1));
      expect(unreadable.single['error_class'], 'StateError');
      expect('${unreadable.single}', isNot(contains('/x/y')));
      expect(events(binding, 'app.reopen_last_project_skipped'), isEmpty);
    });

    test('небулево значение: проект открывается, событие unreadable, ключ '
        'не перезаписан', () async {
      final binding = CodeLabTestBinding(
        preferences: {
          kWorkspaceSnapshotPrefsKey: _snapshot('/work/app'),
          kReopenLastProjectKey: 'no',
        },
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      await restored(binding);

      expect(cubit.state.selectedProjectPath, '/work/app');
      expect(
        events(binding, 'app.reopen_last_project_unreadable'),
        hasLength(1),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(kReopenLastProjectKey), 'no');
    });
  });
}
