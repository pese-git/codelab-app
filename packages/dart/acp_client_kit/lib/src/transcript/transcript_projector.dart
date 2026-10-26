import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';

import 'transcript_item.dart';

/// Инкрементальная проекция транскрипта одной сессии.
///
/// Почему: раньше транскрипт пересчитывался с нуля на каждое изменение
/// сессии, в том числе на каждый фрагмент потокового ответа, — длинные ходы
/// становились дороже с каждым словом (`09-10`, задача 5.3; design D5).
///
/// Для чего: держит элементы по ходам и на очередное изменение сессии
/// обрабатывает только новые `session/update` хода и перечитывает вызовы
/// инструментов и одобрения этого хода. Результат на каждом шаге совпадает
/// с [projectTranscript] — эталонным пересчётом с нуля; это проверяет тест
/// на корпусе фикстур.
///
/// Как использовать: один проектор на сессию; [apply] с каждым снимком
/// `AcpSession` из `sessionChanges` по порядку. Снимок, ходы которого не
/// изменились (тот же объект хода), — no-op: [apply] вернёт `false`, а
/// [items] останется тем же списком.
final class TranscriptProjector {
  final _turns = <_TurnProjection>[];
  List<TranscriptItem> _items = const [];

  List<TranscriptItem> get items => _items;

  /// Применяет снимок сессии; `true` — транскрипт изменился.
  bool apply(AcpSession session) {
    var changed = false;
    final turns = session.turns;
    if (turns.length < _turns.length) {
      // Ходы не исчезают внутри одной сессии; меньший список значит, что
      // сессию заменили (например, `session/load`) — проекция строится
      // заново.
      _turns.clear();
      changed = true;
    }
    for (final (index, turn) in turns.indexed) {
      if (index < _turns.length && _turns[index].turnId != turn.id) {
        _turns.removeRange(index, _turns.length);
        changed = true;
      }
      if (index == _turns.length) {
        _turns.add(_TurnProjection(turn.id));
      }
      changed = _turns[index].apply(turn) || changed;
    }
    if (!changed) {
      return false;
    }
    _items = List.unmodifiable([for (final turn in _turns) ...turn.items]);
    return true;
  }
}

/// Транскрипт сессии, пересчитанный с нуля по всем ходам.
///
/// Почему: эталон для [TranscriptProjector] — тот же алгоритм, что строил
/// транскрипт в `CodeLabShellCubit` до change (`_transcriptEntriesForSession`,
/// add-streaming-message-coalescing/design.md, embed-approval-in-thread/
/// design.md).
///
/// Для чего: тест свойства «инкрементальная проекция == пересчёт» и разовый
/// показ сессии без истории изменений.
List<TranscriptItem> projectTranscript(AcpSession session) => [
  for (final turn in session.turns) ..._rebuildTurn(turn),
];

List<TranscriptItem> _rebuildTurn(PromptTurn turn) {
  final items = <TranscriptItem>[];
  final user = _userItem(turn);
  if (user != null) {
    items.add(user);
  }

  final agent = <TranscriptItem>[];
  final seen = <ToolCallId>{};
  final focused = _earliestPendingApprovalId(turn);
  _StreamKind? runKind;
  var runStart = 0;
  var runText = StringBuffer();

  void flush() {
    final text = runText.toString().trim();
    if (runKind != null && text.isNotEmpty) {
      agent.add(_streamItem(turn.id, runKind!, runStart, text));
    }
    runKind = null;
    runText = StringBuffer();
  }

  for (final (index, update) in turn.updates.indexed) {
    switch (update) {
      case ToolCallSessionUpdate(:final toolCall):
        flush();
        if (seen.add(toolCall.toolCallId)) {
          agent.add(_toolItem(turn, toolCall.toolCallId, focused));
        }
      case ToolCallUpdateSessionUpdate():
        flush();
      default:
        final kind = _StreamKind.of(update);
        if (kind == null) {
          flush();
          continue;
        }
        if (kind != runKind) {
          flush();
          runKind = kind;
          runStart = index;
        }
        final text = _chunkText(update);
        if (text != null) {
          runText.write(text);
        }
    }
  }
  flush();
  agent.addAll(_unannouncedApprovalItems(turn, seen, focused));

  items
    ..addAll(agent)
    ..addAll(_notices(turn, hasAgentItems: agent.isNotEmpty));
  return items;
}

/// Проекция одного хода, которая обрабатывает только новые обновления.
final class _TurnProjection {
  _TurnProjection(this.turnId);

  final PromptTurnId turnId;
  PromptTurn? _turn;
  UserItem? _user;

  /// Элементы из обновлений хода: отрезки текста и вызовы инструментов.
  final _body = <TranscriptItem>[];

  /// Позиция элемента вызова в [_body]: повторный `tool_call` того же
  /// вызова обновляет элемент на месте.
  final _toolPositions = <ToolCallId, int>{};
  var _processed = 0;

  /// Открытый отрезок потокового текста: вид, индекс первого обновления,
  /// накопленный текст и позиция элемента (`null`, пока текст пуст).
  _StreamKind? _runKind;
  var _runStart = 0;
  var _runText = StringBuffer();
  int? _runPosition;

  List<TranscriptItem> items = const [];

  bool apply(PromptTurn turn) {
    if (identical(turn, _turn)) {
      return false;
    }
    if (turn.updates.length < _processed) {
      _reset();
    }
    _user ??= _userItem(turn);
    final updates = turn.updates;
    for (var index = _processed; index < updates.length; index++) {
      _process(turn.id, index, updates[index]);
    }
    _processed = updates.length;
    _turn = turn;

    // Статус вызова и одобрение читаются из живой read-модели хода, а не из
    // обновления: так их показывал и прежний пересчёт
    // (embed-approval-in-thread/design.md, Decision 1).
    final focused = _earliestPendingApprovalId(turn);
    for (final MapEntry(key: toolCallId, value: position)
        in _toolPositions.entries) {
      final next = _toolItem(turn, toolCallId, focused);
      if (next != _body[position]) {
        _body[position] = next;
      }
    }

    final unannounced = _unannouncedApprovalItems(turn, {
      ..._toolPositions.keys,
    }, focused);
    final hasAgentItems = _body.isNotEmpty || unannounced.isNotEmpty;
    items = [
      ?_user,
      ..._body,
      ...unannounced,
      ..._notices(turn, hasAgentItems: hasAgentItems),
    ];
    return true;
  }

  void _process(PromptTurnId turnId, int index, SessionUpdate update) {
    switch (update) {
      case ToolCallSessionUpdate(:final toolCall):
        _closeRun();
        _toolPositions.putIfAbsent(toolCall.toolCallId, () {
          // Содержимое элемента заполняет перечитывание вызовов в [apply].
          _body.add(
            TranscriptItem.toolCall(
              id: _toolItemId(turnId, toolCall.toolCallId),
              toolCallId: toolCall.toolCallId,
              title: toolCall.toolCallId.value,
            ),
          );
          return _body.length - 1;
        });
      case ToolCallUpdateSessionUpdate():
        _closeRun();
      default:
        final kind = _StreamKind.of(update);
        if (kind == null) {
          _closeRun();
          return;
        }
        if (kind != _runKind) {
          _closeRun();
          _runKind = kind;
          _runStart = index;
        }
        final chunk = _chunkText(update);
        if (chunk == null) {
          return;
        }
        _runText.write(chunk);
        final text = _runText.toString().trim();
        if (text.isEmpty) {
          return;
        }
        final item = _streamItem(turnId, kind, _runStart, text);
        final position = _runPosition;
        if (position == null) {
          _body.add(item);
          _runPosition = _body.length - 1;
        } else {
          _body[position] = item;
        }
    }
  }

  void _closeRun() {
    _runKind = null;
    _runText = StringBuffer();
    _runPosition = null;
  }

  void _reset() {
    _body.clear();
    _toolPositions.clear();
    _processed = 0;
    _closeRun();
  }
}

/// Два вида потоковых фрагментов, отрезки которых склеиваются.
enum _StreamKind {
  message,
  thought;

  static _StreamKind? of(SessionUpdate update) => switch (update) {
    AgentMessageChunk() => message,
    AgentThoughtChunk() => thought,
    _ => null,
  };
}

String? _chunkText(SessionUpdate update) {
  final content = switch (update) {
    AgentMessageChunk(:final content) => content,
    AgentThoughtChunk(:final content) => content,
    _ => null,
  };
  return switch (content) {
    TextContent(:final text) => text,
    _ => null,
  };
}

TranscriptItem _streamItem(
  PromptTurnId turnId,
  _StreamKind kind,
  int start,
  String text,
) => switch (kind) {
  _StreamKind.message => TranscriptItem.agentText(
    id: '${turnId.value}/text-$start',
    text: text,
  ),
  _StreamKind.thought => TranscriptItem.thought(
    id: '${turnId.value}/thought-$start',
    text: text,
  ),
};

UserItem? _userItem(PromptTurn turn) {
  final text = turn.prompt
      .whereType<TextContent>()
      .map((block) => block.text)
      .where((text) => text.trim().isNotEmpty)
      .join('\n');
  if (text.isEmpty) {
    return null;
  }
  return UserItem(id: '${turn.id.value}/prompt', text: text);
}

String _toolItemId(PromptTurnId turnId, ToolCallId toolCallId) =>
    '${turnId.value}/tool-${toolCallId.value}';

TranscriptItem _toolItem(
  PromptTurn turn,
  ToolCallId toolCallId,
  ApprovalRequestId? focused,
) {
  final record = turn.toolCalls[toolCallId];
  return TranscriptItem.toolCall(
    id: _toolItemId(turn.id, toolCallId),
    toolCallId: toolCallId,
    title: record?.title ?? toolCallId.value,
    details: record == null ? null : _callView(record),
    approval: _approvalView(_approvalFor(turn, toolCallId), focused),
  );
}

/// Одобрения вызовов, о которых агент не объявлял `tool_call`.
///
/// ACP разрешает `session/request_permission` для вызова без `tool_call`;
/// одобрение должно быть видно, поэтому такой вызов встаёт в конец хода —
/// место, которое ни одно событие не задало точнее.
List<TranscriptItem> _unannouncedApprovalItems(
  PromptTurn turn,
  Set<ToolCallId> seen,
  ApprovalRequestId? focused,
) => [
  for (final approval in turn.approvals.values)
    if (seen.add(approval.toolCall.id))
      TranscriptItem.toolCall(
        id: _toolItemId(turn.id, approval.toolCall.id),
        toolCallId: approval.toolCall.id,
        title: approval.toolCall.title,
        details: _callView(approval.toolCall),
        approval: _approvalView(approval, focused),
      ),
];

List<TranscriptItem> _notices(
  PromptTurn turn, {
  required bool hasAgentItems,
}) => [
  if (!hasAgentItems && turn.isTerminal)
    TranscriptItem.notice(
      id: '${turn.id.value}/completed',
      kind: NoticeKind.emptyTurn,
      text: 'Completed with stopReason ${turn.stopReason?.name ?? 'unknown'}.',
    ),
  if (turn.status == PromptTurnStatus.failed && turn.failureMessage != null)
    TranscriptItem.notice(
      id: '${turn.id.value}/error',
      kind: NoticeKind.error,
      text:
          'Failed to send prompt: ${_withoutTypePrefix(turn.failureMessage!)}',
    ),
];

ToolCallView _callView(ToolCallRecord record) => ToolCallView(
  kind: record.kind,
  status: switch (record.status) {
    _ when record.cancelledByClient => ToolCallStatusView.cancelled,
    ToolCallStatus.pending => ToolCallStatusView.queued,
    ToolCallStatus.inProgress => ToolCallStatusView.running,
    ToolCallStatus.completed => ToolCallStatusView.succeeded,
    ToolCallStatus.failed => ToolCallStatusView.failed,
  },
  command: _command(record),
);

String? _command(ToolCallRecord record) {
  final command = record.rawInput?['command'];
  return command is String && command.trim().isNotEmpty ? command : null;
}

ApprovalRequest? _approvalFor(PromptTurn turn, ToolCallId toolCallId) {
  for (final approval in turn.approvals.values) {
    if (approval.toolCall.id == toolCallId) {
      return approval;
    }
  }
  return null;
}

/// Самое раннее по `requestedAt` ожидающее одобрение хода — единственное,
/// которому принадлежат клавиши одобрения (embed-approval-in-thread/
/// design.md, Decision 6).
ApprovalRequestId? _earliestPendingApprovalId(PromptTurn turn) {
  final pending =
      turn.approvals.values
          .where((approval) => approval.status == ApprovalStatus.pending)
          .toList()
        ..sort((a, b) {
          final aTime = a.requestedAt;
          final bTime = b.requestedAt;
          if (aTime == null || bTime == null) {
            return 0;
          }
          return aTime.compareTo(bTime);
        });
  return pending.firstOrNull?.id;
}

ApprovalStateView? _approvalView(
  ApprovalRequest? approval,
  ApprovalRequestId? focused,
) {
  if (approval == null) {
    return null;
  }
  if (approval.status != ApprovalStatus.pending) {
    return ApprovalStateView.resolved(label: _resolvedLabel(approval));
  }
  return ApprovalStateView.pending(
    approvalId: approval.id,
    sessionId: approval.sessionId,
    risk: approval.riskLevel,
    command: _command(approval.toolCall),
    rawInput: approval.toolCall.rawInput,
    options: approval.options,
    focused: approval.id == focused,
  );
}

String _resolvedLabel(ApprovalRequest approval) {
  if (approval.status == ApprovalStatus.cancelled) {
    return 'Cancelled';
  }
  final selectedId = approval.selectedOptionId;
  if (selectedId == null) {
    return 'Resolved';
  }
  for (final option in approval.options) {
    if (option.optionId == selectedId) {
      return option.name;
    }
  }
  return selectedId.value;
}

/// `PromptTurn.failureMessage` — `error.toString()`, а исключения ядра
/// печатаются как `ClassName: <message>` или `ClassName(code): <message>`.
/// Типизированной ошибки к этому моменту уже нет, поэтому префикс с именем
/// типа срезается по шаблону, чтобы он не попал в текст для пользователя
/// (add-streaming-message-coalescing/design.md, Open Questions).
String _withoutTypePrefix(String message) {
  final prefix = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?: ',
  ).matchAsPrefix(message);
  return prefix == null ? message : message.substring(prefix.end);
}
