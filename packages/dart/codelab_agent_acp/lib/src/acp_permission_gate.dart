import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'connection/client_requests.dart';
import 'event_projection.dart' show acpContent, acpDiff, acpLocations;

/// Порт разрешений через `session/request_permission`
/// (`agent-core-architecture` §7.8, §13.9).
///
/// Почему: решение о действии принимает человек в клиенте, а политика
/// разрешений ядра спрашивает его через `PermissionGate`. ACP-хост не
/// показывает диалогов сам — он только переводит вопрос в запрос клиенту и
/// ответ обратно (`AGENTS.md` §10).
///
/// Для чего: `toolCall` запроса — `ToolCallUpdate` со статусом `pending`,
/// `rawInput`, `locations`, причиной первым текстовым блоком и `diff` на
/// каждый файл; варианты — `allow_once`, `allow_always` (если предложен),
/// `reject_once`, `reject_always`. Любой сбой — отказ, никогда не разрешение.
///
/// Как использовать: соединение создаёт gate на сессию и передаёт его в
/// порты сессии; политика зовёт [request] с токеном хода. Отмена хода
/// прекращает ожидание — решение `cancelled`, поздний ответ клиента
/// игнорируется (PERM-4). С [waitForReconnect] разрыв соединения не отказ:
/// вопрос ждёт переподключения и задаётся новому соединению с новым id и
/// тем же `toolCallId` (§13.5, шаг 8).
final class AcpPermissionGate implements PermissionGate {
  AcpPermissionGate(
    this._link, {
    required Logger logger,
    Future<bool> Function(CancelToken cancel)? waitForReconnect,
    Future<void> Function(String toolCallId)? announced,
  }) : _logger = logger,
       _waitForReconnect = waitForReconnect,
       _announced = announced;

  final ClientLink _link;
  final Logger _logger;

  /// `true` — сессию переподключили, вопрос задаётся заново; `false` —
  /// ждать нечего (ход отменён). `null` — разрыв сразу отказ.
  final Future<bool> Function(CancelToken cancel)? _waitForReconnect;

  /// Завершается, когда `tool_call` вызова уже в очереди соединения:
  /// запрос разрешения не должен опередить его (§13.7, «Статусы вызова»).
  final Future<void> Function(String toolCallId)? _announced;

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async {
    if (_announced case final announced?) {
      await announced(req.toolCallId);
    }
    Object? raw;
    while (true) {
      try {
        raw = await _link.requests.request(
          acp.acpSessionRequestPermission,
          _params(req),
          prefix: 'perm',
          cancel: cancel,
        );
        break;
      } on ClientCallCancelled {
        return PermissionDecision.cancelled;
      } on ClientDisconnected catch (failure) {
        final wait = _waitForReconnect;
        if (wait != null && await wait(cancel)) {
          continue;
        }
        if (cancel.isCancelled) {
          return PermissionDecision.cancelled;
        }
        return _failed(req, '$failure');
      } on ClientCallFailure catch (failure) {
        return _failed(req, '$failure');
      }
    }
    final acp.RequestPermissionResponse response;
    try {
      response = acp.acpSessionRequestPermission.decodeResult(raw);
    } on acp.JsonRpcProtocolException catch (error) {
      return _failed(req, 'invalid answer: ${error.message}');
    }
    return switch (response.outcome) {
      acp.RequestPermissionCancelledOutcome() => PermissionDecision.cancelled,
      acp.SelectedPermissionOutcome(:final optionId) => _decision(
        req,
        optionId.value,
      ),
    };
  }

  acp.RequestPermissionRequest _params(PermissionRequest req) {
    final pattern = req.pattern;
    final label = req.criticalLabel;
    // Пустой список не отправляется: фикстуры и клиенты ждут ключ только
    // с содержимым (§14.8).
    final content = [
      if (req.reason case final reason?)
        acp.ToolCallContent.content(content: acpContent(TextContent(reason))),
      for (final diff in req.diffs) acpDiff(diff),
    ];
    return acp.RequestPermissionRequest(
      sessionId: acp.SessionId(_link.sessionId),
      toolCall: acp.ToolCallUpdate(
        toolCallId: acp.ToolCallId(req.toolCallId),
        title: req.title,
        kind: acp.ToolKind.values.byName(req.kind.name),
        status: acp.ToolCallStatus.pending,
        rawInput: req.rawInput,
        locations: acpLocations(req.locations),
        content: content.isEmpty ? null : content,
        meta: label == null
            ? null
            : {
                'codelab': {'critical': true, 'label': label},
              },
      ),
      options: [
        _option(acp.PermissionOptionKind.allowOnce, 'Allow once'),
        if (req.allowAlwaysOffered)
          _option(
            acp.PermissionOptionKind.allowAlways,
            pattern == null ? 'Always allow' : 'Always allow $pattern',
          ),
        _option(acp.PermissionOptionKind.rejectOnce, 'Reject'),
        _option(
          acp.PermissionOptionKind.rejectAlways,
          pattern == null ? 'Always reject' : 'Always reject $pattern',
        ),
      ],
    );
  }

  /// `optionId` совпадает с `kind` варианта (§7.8, шаг 2).
  static acp.PermissionOption _option(
    acp.PermissionOptionKind kind,
    String name,
  ) => acp.PermissionOption(
    optionId: acp.PermissionOptionId(kind.wireName),
    name: name,
    kind: kind,
  );

  PermissionDecision _decision(PermissionRequest req, String optionId) {
    switch (optionId) {
      case 'allow_once':
        return PermissionDecision.allowOnce;
      case 'allow_always' when req.allowAlwaysOffered:
        return PermissionDecision.allowAlways;
      case 'reject_once':
        return PermissionDecision.rejectOnce;
      case 'reject_always':
        return PermissionDecision.rejectAlways;
    }
    // Вариант, которого не предлагали, — не разрешение (§7.8, шаг 3).
    _logger.log(
      LogLevel.warning,
      'acp.permission.unknown_option',
      fields: {
        'session_id': _link.sessionId,
        'tool_call_id': req.toolCallId,
        'option_id': optionId,
      },
    );
    return PermissionDecision.rejectOnce;
  }

  PermissionDecision _failed(PermissionRequest req, String reason) {
    _logger.log(
      LogLevel.warning,
      'acp.permission.failed',
      fields: {
        'session_id': _link.sessionId,
        'tool_call_id': req.toolCallId,
        'reason': reason,
      },
    );
    return PermissionDecision.rejectOnce;
  }
}
