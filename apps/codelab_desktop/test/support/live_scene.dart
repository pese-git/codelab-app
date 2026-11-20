import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart' show ProjectFiles;
import 'package:codelab_desktop/app/appearance/app_appearance_start.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/core/platform/usage_csv_saver.dart';
import 'package:codelab_desktop/core/platform/user_shell_launcher.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_session.dart'
    show ProviderSettingsOpener;
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'start_agent.dart';
import 'test_app_scope.dart';

/// Собранное приложение с живым рабочим местом для тестов языка.
///
/// Почему: тесты локализации рабочего места (`add-desktop-localization`, D9)
/// проверяют то, что видит пользователь, на настоящем графе app: ответ агента,
/// вызов, заметки, одобрение, сайдбар, баннер и доки. Подготовка сцены
/// (подключение, сессии, ходы, кадры протокола) одна и та же, поэтому она
/// вынесена сюда, а не повторяется в каждом файле, как в `usage_pane_test.dart`.
///
/// Для чего: поднимает `CodeLabTestBinding` с языком [locale], подключает
/// агента-двойника и отдаёт короткие шаги протокола; язык меняется через
/// настоящий `AppLanguageCubit` ([selectLanguage]), как на странице «General».
///
/// Как использовать: `final scene = await LiveScene.open(tester, locale: ru)`,
/// затем шаги сцены; в конце — `await scene.close()`. Ходы, начатые
/// [prompt], сцена не ждёт: тест сам завершает их ([endTurn], [failTurn]) или
/// оставляет идущими, и тогда закрытие графа их обрывает.
final class LiveScene {
  LiveScene._(this.tester, this.binding, this.agent, this.cubit);

  final WidgetTester tester;
  final CodeLabTestBinding binding;
  final FakeAcpTransport agent;
  final CodeLabShellCubit cubit;

  /// Открывает приложение и (если [connect]) подключает агента.
  ///
  /// [listed] — сессии прошлого запуска (`id → cwd`): агент отвечает ими на
  /// `session/list`, а [capabilities] должны объявлять `list` и `loadSession`.
  static Future<LiveScene> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    String? project = '/work/app',
    AgentCapabilities capabilities = const AgentCapabilities(),
    bool connect = true,
    Map<String, String>? listed,
    ProjectFiles? projectFiles,
    UserShellLauncher? userShellLauncher,
    UsageCsvSaver? usageCsvSaver,
    CodeLabStdioTransportFactory? stdioTransportFactory,
    ProviderSettingsOpener? providerSettingsOpener,
    Size size = const Size(1440, 900),
    AppAppearanceStart? appearance,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = FakeAcpTransport()
      ..initializeAgentCapabilities = capabilities;
    final binding = CodeLabTestBinding(
      project: project,
      locale: locale,
      stdioTransportFactory: stdioTransportFactory ?? (_) => agent,
      projectFiles: projectFiles,
      userShellLauncher: userShellLauncher,
      usageCsvSaver: usageCsvSaver,
      providerSettingsOpener: providerSettingsOpener,
      appearance: appearance,
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    final scene = LiveScene._(tester, binding, agent, cubit);
    if (connect) {
      await tester.runAsync(() async {
        if (listed == null) {
          await cubit.startWith();
          return;
        }
        final sent = agent.sent.firstWhere(
          (m) => m is JsonRpcRequest && m.method == sessionListMethod,
        );
        final starting = cubit.startWith();
        final request = await sent as JsonRpcRequest;
        agent.emitInbound(
          JsonRpcMessage.response(
            id: request.id,
            result: ListSessionsResponse(
              sessions: [
                for (final entry in listed.entries)
                  SessionInfo(
                    sessionId: SessionId(entry.key),
                    cwd: entry.value,
                    title: entry.key,
                  ),
              ],
            ).toJson(),
          ),
        );
        await starting;
      });
      await scene.flush();
    }
    return scene;
  }

  /// Доставляет кадры протокола и состояния Cubit в виджеты.
  Future<void> flush() async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    // Кнопки Fluent отпускают нажатие по таймеру 100 мс.
    await tester.pump(const Duration(milliseconds: 150));
  }

  /// Создаёт сессию [id]; агент отвечает на `session/new`.
  Future<void> newSession(String id) async {
    await tester.runAsync(() async {
      final sent = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionNewMethod,
      );
      final creating = cubit.createSession();
      final request = await sent as JsonRpcRequest;
      agent.emitInbound(
        JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
      );
      await creating;
    });
    await flush();
  }

  /// Отправляет промпт и возвращает запрос `session/prompt`; ход остаётся
  /// идущим до [endTurn] или [failTurn].
  Future<JsonRpcRequest> prompt(String text) async {
    late JsonRpcRequest request;
    await tester.runAsync(() async {
      final sent = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionPromptMethod,
      );
      // Ошибка хода (сбой, потеря соединения) нужна самому тесту; здесь она
      // не должна превращаться в необработанную.
      unawaited(cubit.submitPrompt(text).then<void>((_) {}, onError: (_) {}));
      request = await sent as JsonRpcRequest;
    });
    agent.drainSentMessages();
    await flush();
    return request;
  }

  /// Присылает `session/update` сессии [sessionId].
  Future<void> update(String sessionId, Map<String, Object?> update) async {
    agent.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: {'sessionId': sessionId, 'update': update},
      ),
    );
    await flush();
  }

  /// Ответ агента `agent_message_chunk`.
  Future<void> agentText(String sessionId, String text) => update(sessionId, {
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  });

  /// Вызов инструмента: `tool_call` в статусе [status].
  Future<void> toolCall(
    String sessionId, {
    required String toolCallId,
    required String title,
    String kind = 'execute',
    String status = 'in_progress',
    Map<String, Object?>? rawInput,
  }) => update(sessionId, {
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': title,
    'kind': kind,
    'status': status,
    'rawInput': ?rawInput,
  });

  /// Завершает ход ответом на [request] со [stopReason].
  Future<void> endTurn(
    JsonRpcRequest request, {
    String stopReason = 'end_turn',
  }) async {
    agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: {'stopReason': stopReason},
      ),
    );
    await flush();
  }

  /// Завершает ход ошибкой агента.
  Future<void> failTurn(JsonRpcRequest request) async {
    agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        error: const JsonRpcError(code: -32603, message: 'Internal error'),
      ),
    );
    await flush();
  }

  /// Агент просит разрешение на вызов [toolCallId] (запрос с номером [id]).
  Future<void> requestPermission({
    required int id,
    required String sessionId,
    required String toolCallId,
    String title = 'Run echo hi',
  }) async {
    agent.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: SessionId(sessionId),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId),
            title: title,
            kind: ToolKind.execute,
            status: ToolCallStatus.inProgress,
            rawInput: const {'command': 'echo hi'},
          ),
          options: const [
            PermissionOption(
              optionId: PermissionOptionId('allow-once'),
              name: 'Allow once',
              kind: PermissionOptionKind.allowOnce,
            ),
            PermissionOption(
              optionId: PermissionOptionId('reject-once'),
              name: 'Reject',
              kind: PermissionOptionKind.rejectOnce,
            ),
          ],
        ).toJson(),
      ),
    );
    await flush();
  }

  /// Выбор языка на странице «General»: настоящий `AppLanguageCubit`.
  Future<void> selectLanguage(AppLanguagePreference preference) async {
    await tester.runAsync(
      () => binding.scope.resolve<AppLanguageCubit>().select(preference),
    );
    // Не `pumpAndSettle`: у идущего вызова и таймера бюджета бесконечные
    // анимации. Язык применяется до следующего кадра (spec app-settings).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Строка, нарисованная всеми `RichText` под [scope] (для проверок текста).
  String textOf(Finder scope) => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(of: scope, matching: find.byType(RichText)),
    ))
      w.text.toPlainText(),
  ].join(' | ');

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }
}
