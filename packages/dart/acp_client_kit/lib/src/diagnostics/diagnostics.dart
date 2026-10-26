import 'dart:convert';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:meta/meta.dart';

export 'package:acp_client_core/acp_client_core.dart' show DiagnosticSeverity;

import '../workspace/client_workspace_exception.dart';

/// Запись диагностики о событии, которым владеет kit: исход хода, отмена,
/// ответ на одобрение, опция конфигурации, потеря соединения.
///
/// Почему: эти события происходят внутри kit — в том числе для промпта,
/// который ушёл из очереди сам, — и хост не должен угадывать, что
/// случилось, по побочным признакам (spec acp-client-kit «Диагностика без
/// секретов»; design D9).
///
/// Для чего: `ClientWorkspace.diagnostics`. [severity] — `DiagnosticSeverity`
/// ядра клиента; [message] уже прошёл
/// `SecretRedactor`; [source] — область (`prompt`, `session`, `approval`,
/// `transport`), как ключ `source` в логе app.
///
/// Как использовать: подписаться на `ClientWorkspace.diagnostics` и записать
/// в свой лог; сообщения подключения, которые зависят от формы хоста,
/// пишет сам хост.
@immutable
final class WorkspaceDiagnostic {
  const WorkspaceDiagnostic({
    required this.severity,
    required this.source,
    required this.message,
  });

  final DiagnosticSeverity severity;
  final String source;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceDiagnostic &&
      other.severity == severity &&
      other.source == source &&
      other.message == message;

  @override
  int get hashCode => Object.hash(severity, source, message);

  @override
  String toString() =>
      'WorkspaceDiagnostic(${severity.name}, $source, $message)';
}

const _redactor = SecretRedactor();

/// Текст ошибки kit, ядра клиента или транспорта для UI и CLI.
///
/// Почему: исключения `acp_client_core` печатаются как `ClassName: message`,
/// а пользователю нужен только текст; текст может содержать токен из
/// заголовка или URL, поэтому он проходит `SecretRedactor` (`AGENTS.md` §10,
/// §16). Правило совпадает с прежним `_failureMessage` фасада app после
/// use case-ов `acp_client_core`.
String describeFailure(Object error) => _redactor.redactText(switch (error) {
  AcpClientApplicationException(:final message) ||
  AcpTransportException(:final message) ||
  StateTransitionException(:final message) ||
  ClientWorkspaceException(:final message) => message,
  _ => error.toString(),
});

/// JSON с отступами после редакции секретов по ключам и по тексту; `null` —
/// `null`. Так инспектор и одобрения показывают сырые аргументы вызова.
String? formatRedactedJson(Object? value) => value == null
    ? null
    : const JsonEncoder.withIndent('  ').convert(_redactor.redact(value));
