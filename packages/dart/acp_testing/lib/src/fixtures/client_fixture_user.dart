import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';

import '../fake_acp_transport.dart';
import 'client_conformance.dart';

/// Пользователь клиента для прогона фикстур: выполняет действия, которые
/// порождают `c2a`-кадры фикстуры.
///
/// Почему: фикстура фиксирует кадры, но кадр клиента (`session/new`,
/// `session/prompt`, ответ на запрос разрешения) появляется только после
/// действия пользователя. Одинаковые действия нужны тестам ядра клиента и
/// тестам `acp_client_kit` (свойство проекции транскрипта, design D5 change
/// `extract-acp-client-kit`), поэтому драйвер общий.
///
/// Для чего: создаёт `AcpClientApplication` на портах окружения фикстуры и
/// по ожидаемому кадру вызывает нужный метод ядра клиента.
///
/// Как использовать:
///
/// ```dart
/// late ClientFixtureUser user;
/// final result = await runClientFixture(fixture, (env) {
///   user = ClientFixtureUser(env);
///   return user.app;
/// }, onBeforeExpect: (step) => user.act(step));
/// ```
///
/// Состояние сессии после прогона читается из [app]; итоги
/// `session/set_config_option` — из [configResults], ошибки хода — из
/// [promptErrors]. Закрывает [app] тест.
final class ClientFixtureUser {
  ClientFixtureUser(this.env)
    : app = AcpClientApplication(
        transport: FakeAcpTransport(),
        textFileReader: env.fileSystem,
        textFileWriter: env.fileSystem,
        terminalProcessRunner: env.terminal,
      );

  final ClientFixtureEnvironment env;
  final AcpClientApplication app;

  /// Итоги вызовов `session/set_config_option` по порядку: ошибка или
  /// `null` при успехе.
  final configResults = <Object?>[];

  /// Ошибки `session/prompt`: ход, сорвавшийся у агента, клиент получает
  /// JSON-RPC ошибкой (agent-core §13.8) — это исход сценария, а не сбой
  /// действия пользователя.
  final promptErrors = <Object>[];

  void act(ClientFixtureStep<AcpClientApplication> step) {
    final expected = step.expected;
    switch (expected['method']) {
      case 'initialize':
        step.track(app.connect(env.transport));
      case 'session/new':
        step.track(app.createSession(CreateSessionCommand(cwd: env.cwd)));
      case 'session/prompt':
        final params = expected['params']! as Map<String, Object?>;
        step.track(
          app
              .sendPrompt(
                SendPromptCommand(
                  sessionId: _session.id,
                  prompt: [
                    for (final block in params['prompt']! as List<Object?>)
                      ContentBlock.text(
                        text:
                            (block! as Map<String, Object?>)['text']! as String,
                      ),
                  ],
                ),
              )
              .then<void>((_) {}, onError: promptErrors.add),
        );
      case 'session/load':
        // id берётся из кадра: загружаемой сессии у клиента может ещё не быть
        // (acp/session-load-interrupted-turn начинается без session/new).
        final params = expected['params']! as Map<String, Object?>;
        step.track(
          app.loadSession(
            LoadSessionCommand(
              sessionId: SessionId(params['sessionId']! as String),
              cwd: env.cwd,
            ),
          ),
        );
      case 'session/cancel':
        step.track(app.cancelTurn(CancelTurnCommand(sessionId: _session.id)));
      case 'session/set_config_option':
        final params = expected['params']! as Map<String, Object?>;
        step.track(
          app
              .setSessionConfigOption(
                SetSessionConfigOptionCommand(
                  sessionId: _session.id,
                  configId: SessionConfigId(params['configId']! as String),
                  value: SessionConfigValueId(params['value']! as String),
                ),
              )
              .then<void>(
                (_) => configResults.add(null),
                onError: (Object error) => configResults.add(error),
              ),
        );
      case null when _isPermissionAnswer(expected):
        final outcome =
            ((expected['result']! as Map)['outcome']! as Map<String, Object?>);
        final approval = _session.activeTurn!.approvals.values.singleWhere(
          (a) => !a.isResolved,
        );
        step.track(
          app.respondToPermission(
            outcome['outcome'] == 'selected'
                ? RespondToPermissionCommand.selected(
                    sessionId: _session.id,
                    approvalId: approval.id,
                    optionId: PermissionOptionId(
                      outcome['optionId']! as String,
                    ),
                  )
                : RespondToPermissionCommand.cancelled(
                    sessionId: _session.id,
                    approvalId: approval.id,
                  ),
          ),
        );
    }
  }

  AcpSession get _session => app.sessions.single;

  bool _isPermissionAnswer(Map<String, Object?> frame) => switch (frame) {
    {'result': {'outcome': {'outcome': _}}} => true,
    _ => false,
  };
}
