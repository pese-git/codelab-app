// Страница «MCP servers» на устройстве (задача 5.11 change
// `add-provider-setup-ui`; шаги 1–5 §12.4.13; spec app-settings «Страница
// «MCP servers»», «Панель «Agent status» страницы MCP servers»; design.md
// D11, D12, решения Q21, Q22, Q28).
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` (AGENTS.md
// §21). Настоящие `~/.codelab` и хранилище ОС не затрагиваются: дом —
// временный `CODELAB_HOME`, бэкенд секретов `file` в нём. MCP-сервер —
// `FakeMcpHttpHost` из `codelab_embedded/testing.dart`: loopback HTTP с
// одним инструментом (решение Q28); его URL и есть адрес `github` шага 1.
//
// Встроенный агент открывается настоящим открывателем на временном
// `CODELAB_HOME`, поэтому тесты шагов 1–5 в режиме
// `CODELAB_E2E_AGENT=embedded` (сценарий модели вместо конфига)
// пропускаются. Вариант шага 3 для локального stdio-агента нужен бинарь
// `codelab-agent` (`CODELAB_E2E_AGENT=dart`), иначе пропускается.

import 'dart:async';
import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_embedded/testing.dart' show FakeMcpHttpHost;
import 'package:codelab_setup/io.dart' show ClientSecretAccess;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

/// Значение заголовка, которое не должно выйти из хранилища на экран и в
/// файл.
const _marker = 'sk-test-leak-0123456789';

const _authorization = 'codelab/mcp/github/authorization';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String owner, String key) =>
    find.descendant(of: _key(owner), matching: _key(key));

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

Future<void> _openMcp(WidgetTester tester) async {
  await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
  await tester.pumpAndSettle();
  await tester.tap(_key('settings-nav-mcp-servers'));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Finder finder) async {
  await _pumpUntil(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<ClientSecretAccess> _secrets(String home) => ClientSecretAccess.open(
  codelabHome: home,
  environment: {...Platform.environment, 'CODELAB_HOME': home},
  logger: CodeLabEmbeddedLogger(),
);

/// Конфиг дома: файловый бэкенд секретов и один локальный провайдер, чтобы
/// встроенный агент открыл сессию (ход модели в тестах не нужен).
String _baseConfig({String extra = ''}) => '''
secrets:
  backend: file
agent:
  default_model: local/m
providers:
  local:
    kind: openai-compatible
    base_url: http://127.0.0.1:9/v1
    models:
      m:
        context_window: 32000
$extra''';

Future<void> _shutdown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await closeCodeLabRootScope();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'steps 1-4: add an http server with a secret header, see it connected '
    'in Agent status, Reconnect it and Remove it with its secret',
    (tester) async {
      final host = await FakeMcpHttpHost.start();
      addTearDown(host.close);
      final secrets = await E2eAgent.current.openFileSecrets();
      final home = File(E2eAgent.current.profilesPath).parent.path;
      File('$home/config.yaml').writeAsStringSync(_baseConfig());

      await tester.pumpWidget(
        E2eAgent.current.bootstrap(profileSecrets: secrets),
      );
      await tester.pumpAndSettle();
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      unawaited(shellCubit.connect());
      await _pumpWhile(
        tester,
        () =>
            shellCubit.state.connectionStatus !=
            CodeLabConnectionStatus.connected,
      );
      await shellCubit.createSession();
      await _openMcp(tester);

      // Шаг 1: http-сервер с секретным заголовком.
      await _tapKey(tester, _key('mcp-empty-add'));
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'github');
      await _tapKey(tester, _in('mcp-new', 'mcp-draft-type-http'));
      await tester.enterText(
        _in('mcp-new', 'mcp-draft-url'),
        host.url.toString(),
      );
      await _tapKey(tester, _in('mcp-new', 'mcp-draft-add-row'));
      await tester.enterText(
        _in('mcp-new', 'mcp-draft-key-0'),
        'Authorization',
      );
      await tester.enterText(
        _in('mcp-new', 'mcp-draft-value-0'),
        'Bearer $_marker',
      );
      await _tapKey(tester, _in('mcp-new', 'mcp-draft-secret-0'));
      await _tapKey(tester, _key('mcp-new-save'));
      await _pumpUntil(tester, _key('mcp-row-github'));
      // Агент отложит сервер с секретом до перезапуска (R0-4): страница
      // говорит об этом сразу после записи (6.1b, Q31).
      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.text(
            'Server github saved. It starts after Restart agent '
            '(Settings › Connection).',
          ),
        ),
        findsOneWidget,
      );

      final config = File('$home/config.yaml').readAsStringSync();
      expect(config, contains('\${secret:$_authorization}'));
      expect(config, isNot(contains(_marker)));
      expect(find.textContaining(_marker), findsNothing);
      final access = await _secrets(home);
      expect(await access.isSet(_authorization), isTrue);

      // Новый сервер с секретом агент не подхватывает на лету: он откладывает
      // его до перезапуска (R0-4, `config.reload.restart_required`,
      // `config_reload_plan.dart`; подсказку на странице добавит итерация
      // 6.1b, решение Q31). Пользователь перезапускает агента кнопкой
      // «Restart agent» на странице «Connection» и возвращается на «MCP
      // servers».
      await tester.tap(_key('settings-nav-connection'));
      await tester.pumpAndSettle();
      await _tapKey(tester, _key('connection-restart-agent'));
      await tester.pump(const Duration(seconds: 1));
      await _pumpWhile(
        tester,
        () =>
            shellCubit.state.connectionStatus !=
            CodeLabConnectionStatus.connected,
      );
      await shellCubit.createSession();
      await tester.tap(_key('settings-nav-mcp-servers'));
      await tester.pumpAndSettle();

      // Шаг 2: после перезапуска таблица — из потока порта нового агента.
      await _pumpUntil(tester, _key('mcp-status-row-github'));
      await _pumpUntil(
        tester,
        find.descendant(
          of: _key('mcp-status-row-github'),
          matching: find.text('connected'),
        ),
      );
      expect(
        find.descendant(
          of: _key('mcp-status-row-github'),
          matching: find.text('1'),
        ),
        findsOneWidget,
        reason: 'the fake server has one tool',
      );
      expect(host.authorizations, contains('Bearer $_marker'));
      expect(find.textContaining(_marker), findsNothing);

      // Шаг 3: «Reconnect» строки проводит сервер через новое рукопожатие,
      // промпта в сессию нет.
      final handshakes = host.server.methods
          .where((m) => m == 'initialize')
          .length;
      await tester.tap(_key('mcp-status-reconnect-github'));
      await _pumpWhile(
        tester,
        () =>
            host.server.methods.where((m) => m == 'initialize').length <=
            handshakes,
      );
      await _pumpUntil(
        tester,
        find.descendant(
          of: _key('mcp-status-row-github'),
          matching: find.text('connected'),
        ),
      );

      // Шаг 4: «Remove» спрашивает подтверждение со списком секретов.
      await tester.tap(_key('mcp-row-github'));
      await tester.pumpAndSettle();
      await tester.tap(_key('mcp-remove-github'));
      await tester.pumpAndSettle();
      expect(find.text('Remove github?'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-remove-secrets'),
          matching: find.textContaining(_authorization, findRichText: true),
        ),
        findsOneWidget,
      );
      await tester.tap(_key('mcp-remove-confirm'));
      await _pumpWhile(
        tester,
        () => _key('mcp-row-github').evaluate().isNotEmpty,
      );

      expect(
        File('$home/config.yaml').readAsStringSync(),
        isNot(contains('github')),
      );
      final fresh = await _secrets(home);
      expect(await fresh.isSet(_authorization), isFalse);

      await _shutdown(tester);
    },
    skip: E2eAgent.current.kind == E2eAgentKind.embedded,
  );

  testWidgets(
    'step 5: a server of the project file offers only Disable here, the '
    'override goes to config.local.yaml and Enable here removes it',
    (tester) async {
      final secrets = await E2eAgent.current.openFileSecrets();
      final home = File(E2eAgent.current.profilesPath).parent.path;
      final project = await Directory.systemTemp.createTemp(
        'codelab_mcp_project_',
      );
      addTearDown(() => project.delete(recursive: true));
      Directory('${project.path}/.codelab').createSync();
      final projectFile = File('${project.path}/.codelab/config.yaml')
        ..writeAsStringSync('''
mcp:
  servers:
    - name: playwright
      type: stdio
      command: npx
      args: ["@playwright/mcp"]
''');
      final projectBefore = projectFile.readAsStringSync();
      // Проект должен быть доверенным, иначе загрузчик отбросит слой 3.
      File('$home/config.yaml').writeAsStringSync(
        _baseConfig(extra: 'trusted_projects:\n  - ${project.path}\n'),
      );

      await tester.pumpWidget(
        E2eAgent.current.bootstrap(profileSecrets: secrets),
      );
      await tester.pumpAndSettle();
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await shellCubit.selectProject(project.path);
      await tester.pumpAndSettle();
      await _openMcp(tester);

      await _pumpUntil(tester, _key('mcp-row-playwright'));
      expect(_key('mcp-disable-here-playwright'), findsOneWidget);
      expect(_key('mcp-remove-playwright'), findsNothing);

      await tester.tap(_key('mcp-disable-here-playwright'));
      await _pumpUntil(tester, _key('mcp-enable-here-playwright'));
      final local = File('${project.path}/.codelab/config.local.yaml');
      expect(local.readAsStringSync(), contains('playwright'));
      expect(local.readAsStringSync(), contains('enabled: false'));
      expect(projectFile.readAsStringSync(), projectBefore);

      await tester.tap(_key('mcp-enable-here-playwright'));
      await _pumpUntil(tester, _key('mcp-disable-here-playwright'));
      expect(
        local.existsSync() ? local.readAsStringSync() : '',
        isNot(contains('playwright')),
      );
      expect(projectFile.readAsStringSync(), projectBefore);

      await _shutdown(tester);
    },
    skip: E2eAgent.current.kind == E2eAgentKind.embedded,
  );

  testWidgets(
    'step 3 with a local stdio agent: Refresh sends /mcp list and shows the '
    'reply as is, Reconnect sends /mcp reload github',
    (tester) async {
      final host = await FakeMcpHttpHost.start();
      addTearDown(host.close);
      final home = File(E2eAgent.current.profilesPath).parent.path;
      File('$home/config.yaml').writeAsStringSync(
        _baseConfig(
          extra:
              'mcp:\n  servers:\n    - name: github\n      type: http\n'
              '      url: ${host.url}\n',
        ),
      );
      // Агент читает тот же временный дом, а не настоящий `~/.codelab`.
      const bin = String.fromEnvironment('CODELAB_E2E_AGENT_BIN');
      await E2eAgent.current.saveProfile(
        ConnectionProfile.stdio(
          id: 'mcp-e2e',
          label: 'MCP e2e agent',
          command: bin.isEmpty ? 'codelab-agent' : File(bin).absolute.path,
          args: const ['serve', '--stdio'],
          env: {'CODELAB_HOME': home},
          runInProjectDirectory: true,
        ),
      );

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await connectProfileViaSettings(tester, shellCubit, 'mcp-e2e');
      await shellCubit.createSession();
      await _openMcp(tester);

      List<String> prompts() => [
        for (final row in shellCubit.state.transcriptRows)
          if (row is CodeLabUserRow) row.text,
      ];
      String panelText() =>
          tester.widget<CodeLabMonospaceBlock>(_key('mcp-status-text')).data;
      bool buttonsActive() =>
          tester.widget<CodeLabButton>(_key('mcp-status-refresh')).onPressed !=
          null;

      await _tapKey(tester, _key('mcp-status-refresh'));
      await _pumpUntil(tester, _key('mcp-status-text'));
      await _pumpWhile(tester, () => !buttonsActive());
      expect(prompts(), ['/mcp list']);
      expect(panelText(), contains('github'));

      // «Reconnect» строки отправляет ровно один `/mcp reload github`; после
      // него `/mcp list` сам не уходит. Ядро на `/mcp reload <id>` отвечает
      // той же таблицей, что на `/mcp list` (`builtin_commands.dart`, `_mcp`),
      // поэтому текст может совпасть: конец хода видно по активным кнопкам.
      await tester.tap(_key('mcp-row-github'));
      await tester.pumpAndSettle();
      await _tapKey(tester, _key('mcp-reconnect-github'));
      await _pumpUntil(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w.key == const ValueKey('mcp-status-refresh') &&
              w is CodeLabButton &&
              prompts().length == 2 &&
              w.onPressed != null,
        ),
      );
      expect(prompts(), ['/mcp list', '/mcp reload github']);
      expect(panelText(), contains('github'));

      await _shutdown(tester);
    },
    skip: E2eAgent.current.kind != E2eAgentKind.dart,
  );
}
