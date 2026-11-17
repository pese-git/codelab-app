import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import 'subagent_views.dart';
import 'task_ops.dart';
import 'tool_call_tree.dart';
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

  /// Забывает проекцию: следующий [apply] строит транскрипт с нуля.
  ///
  /// Почему: после `session/load` сессия — реплей агента, и id его ходов
  /// могут совпасть с прежними (`turn-1`); по сравнению ходов замену не
  /// отличить, поэтому рабочее пространство сбрасывает проекцию по самому
  /// событию загрузки (design D4 change `add-session-list-and-reload`).
  void reset() {
    _turns.clear();
    _items = const [];
  }

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
    // План, действовавший к началу хода: разница первой операции со списком
    // задач хода считается от него (acp-client-kit «Операции со списком
    // задач в ленте»).
    List<PlanEntry>? prior;
    for (final (index, turn) in turns.indexed) {
      if (index < _turns.length && _turns[index].turnId != turn.id) {
        _turns.removeRange(index, _turns.length);
        changed = true;
      }
      if (index == _turns.length) {
        _turns.add(_TurnProjection(turn.id));
      }
      changed = _turns[index].apply(turn, prior) || changed;
      prior = _turns[index].lastPlan ?? prior;
    }
    if (!changed) {
      return false;
    }
    _items = List.unmodifiable([for (final turn in _turns) ...turn.items]);
    return true;
  }
}

/// Ожидающие одобрения сессии по порядку ходов и запросов.
///
/// Для чего: `SessionView.pendingApprovals` — тот же вид, что встроен в
/// элемент вызова транскрипта, включая фокус самого раннего одобрения.
List<PendingApprovalView> pendingApprovalViews(AcpSession session) => [
  for (final turn in session.turns)
    for (final approval in turn.approvals.values)
      if (approval.status == ApprovalStatus.pending)
        _approvalView(turn, approval, _earliestPendingApprovalId(turn))!
            as PendingApprovalView,
];

/// Транскрипт сессии, пересчитанный с нуля по всем ходам.
///
/// Почему: эталон для [TranscriptProjector] — тот же алгоритм, что строил
/// транскрипт в `CodeLabShellCubit` до change (`_transcriptEntriesForSession`,
/// add-streaming-message-coalescing/design.md, embed-approval-in-thread/
/// design.md).
///
/// Для чего: тест свойства «инкрементальная проекция == пересчёт» и разовый
/// показ сессии без истории изменений.
List<TranscriptItem> projectTranscript(AcpSession session) {
  final items = <TranscriptItem>[];
  List<PlanEntry>? prior;
  for (final turn in session.turns) {
    items.addAll(_rebuildTurn(turn, prior));
    prior = lastPlanOf(turn, prior);
  }
  return items;
}

List<TranscriptItem> _rebuildTurn(PromptTurn turn, List<PlanEntry>? prior) {
  final items = <TranscriptItem>[];
  final user = _userItem(turn);
  if (user != null) {
    items.add(user);
  }

  final agent = <TranscriptItem>[];
  final seen = <ToolCallId>{};
  final announced = _announcedIds(turn);
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
          agent.add(_toolItem(turn, toolCall.toolCallId, focused, announced));
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
  final body = [...buildToolCallTree(agent, taskOperationsOf(turn, prior))];
  body.addAll(_unannouncedApprovalItems(turn, seen, focused, announced));

  items
    ..addAll(body)
    // `body` уже включает одобрения без `tool_call`: ход с ними не пустой
    // (так же считает инкрементальная проекция).
    ..addAll(_notices(turn, hasAgentItems: body.isNotEmpty));
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

  /// Последний `plan` этого хода (`null` — хода без плана) и признак плана
  /// со списком задач: без него разница операций не считается.
  List<PlanEntry>? lastPlan;
  var _taskPlanSeen = false;

  /// Открытый отрезок потокового текста: вид, индекс первого обновления,
  /// накопленный текст и позиция элемента (`null`, пока текст пуст).
  _StreamKind? _runKind;
  var _runStart = 0;
  var _runText = StringBuffer();
  int? _runPosition;

  List<TranscriptItem> items = const [];

  bool apply(PromptTurn turn, List<PlanEntry>? prior) {
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
    final announced = _toolPositions.keys.toSet();
    for (final MapEntry(key: toolCallId, value: position)
        in _toolPositions.entries) {
      final next = _toolItem(turn, toolCallId, focused, announced);
      if (next != _body[position]) {
        _body[position] = next;
      }
    }

    final unannounced = _unannouncedApprovalItems(
      turn,
      {...announced},
      focused,
      announced,
    );
    final hasAgentItems = _body.isNotEmpty || unannounced.isNotEmpty;
    // Дерево вызовов потомков строится из плоского `_body` на каждом
    // применении: родитель может прийти позже ребёнка (D21, D47 Т9).
    final body = buildToolCallTree(
      _body,
      _taskPlanSeen ? taskOperationsOf(turn, prior) : const {},
    );
    items = [
      ?_user,
      ...body,
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
      case PlanUpdate(:final entries, :final meta):
        _closeRun();
        lastPlan = entries;
        _taskPlanSeen = _taskPlanSeen || hasTaskChangeCall(meta);
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
    lastPlan = null;
    _taskPlanSeen = false;
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

/// Id вызовов, объявленных `tool_call` хода: у вызова потомка без дерева
/// их нет, и его запрос не заводит строки, пока есть строка корня (D43 п. 2);
/// с деревом (итерация 5) вызов потомка объявлен и стоит вложенной строкой.
Set<ToolCallId> _announcedIds(PromptTurn turn) => {
  for (final update in turn.updates)
    if (update case ToolCallSessionUpdate(:final toolCall)) toolCall.toolCallId,
};

TranscriptItem _toolItem(
  PromptTurn turn,
  ToolCallId toolCallId,
  ApprovalRequestId? focused,
  Set<ToolCallId> announced,
) {
  final record = turn.toolCalls[toolCallId];
  return TranscriptItem.toolCall(
    id: _toolItemId(turn.id, toolCallId),
    toolCallId: toolCallId,
    title: record?.title ?? toolCallId.value,
    details: record == null ? null : _callView(record),
    approval: _approvalView(turn, _approvalFor(turn, toolCallId), focused),
    childApprovals: [
      for (final approval in turn.approvals.values)
        if (_hostRowOf(turn, approval, announced) == toolCallId)
          _approvalView(turn, approval, focused)!,
    ],
  );
}

/// Строка `agent` корня, под которой стоит блок одобрения потомка, или `null`.
///
/// Почему: панель решения у запроса потомка одна — блок под строкой корня
/// (PERM-4, D43 п. 2, D47 Т9). Без дерева вызовов (клиент без согласия) у
/// запроса потомка нет своих кадров `tool_call`, и отдельная строка навсегда
/// осталась бы `pending`, поэтому одобрение переезжает под строку корня, если
/// она есть в ходе; иначе `null` — вызов остаётся прежним элементом «только
/// запрос» в конце хода. С деревом (итерация 5) вызов потомка объявлен своим
/// `tool_call` и стоит вложенной строкой: блок с панелью — у верхнего предка
/// дерева, а вложенная строка показывает только ожидание и исход (то же
/// одобрение лежит в её `approval`).
ToolCallId? _hostRowOf(
  PromptTurn turn,
  ApprovalRequest approval,
  Set<ToolCallId> announced,
) {
  final requester = approval.subagentRequester;
  if (parseSubagentRequester(requester) == null) {
    return null;
  }
  final own = approval.toolCall.id;
  if (announced.contains(own)) {
    return _treeRootOf(turn, own, announced);
  }
  final parent = requester?['parentToolCallId'];
  if (parent is! String) {
    return null;
  }
  final host = ToolCallId(parent);
  return announced.contains(host) ? host : null;
}

/// Верхний предок вызова [id] в дереве хода или `null`, если вызов сам на
/// верхнем уровне (родителя нет, он неизвестен или родители зациклены).
///
/// Совпадает с раскладкой `buildToolCallTree`: неизвестный родитель — верхний
/// уровень (D21).
ToolCallId? _treeRootOf(
  PromptTurn turn,
  ToolCallId id,
  Set<ToolCallId> announced,
) {
  // Та же карта, что у `buildToolCallTree`: вызов цикла A↔B остаётся на
  // верхнем уровне и в обеих раскладках, иначе одно одобрение получило бы две
  // панели (PERM-4).
  final parents = effectiveToolCallParents({
    for (final callId in announced)
      callId: turn.toolCalls[callId]?.parentToolCallId,
  });
  ToolCallId? root;
  var cursor = id;
  for (var parent = parents[cursor]; parent != null; parent = parents[cursor]) {
    root = parent;
    cursor = parent;
  }
  return root;
}

/// Тип вызова `agent` по записи: `subagentCall.type` → `rawInput.type`.
String? _agentTypeOf(ToolCallRecord? record) {
  final byCall = parseSubagentCall(record?.subagentMeta)?.type;
  final byInput = record?.rawInput?['type'];
  return byCall ?? (byInput is String && byInput.isNotEmpty ? byInput : null);
}

/// Спрашивающий потомок запроса с цепочкой типов для пути (D27, D43 п. 4).
///
/// Корень цепочки: `subagentCall.type` → `rawInput.type` → неизвестно. С
/// деревом вызовов (D47 Т9) промежуточные звенья берутся подъёмом по
/// `parentToolCallId` от вызова запроса; не найденное деревом звено остаётся
/// `…`, без дерева путь прежний.
SubagentRequester? _requesterOf(PromptTurn turn, ApprovalRequest approval) {
  final raw = approval.subagentRequester;
  final parsed = parseSubagentRequester(raw);
  if (parsed == null || parsed.depth <= 1) {
    return parsed;
  }
  final rootType = _agentTypeOf(
    turn.toolCalls[ToolCallId(parsed.parentToolCallId)],
  );
  final withRoot = parsed.withRootType(rootType);

  // Предки вызова запроса, ближайший первым.
  final ancestors = <ToolCallId>[];
  var cursor = approval.toolCall.id;
  while (ancestors.length < parsed.depth) {
    final parent = turn.toolCalls[cursor]?.parentToolCallId;
    if (parent == null) {
      break;
    }
    cursor = ToolCallId(parent);
    ancestors.add(cursor);
  }
  if (ancestors.isEmpty) {
    return withRoot;
  }
  // Предок k стоит на позиции `depth - 1 - k` пути; последняя позиция —
  // спрашивающий, его тип берётся из запроса.
  final chain = List<String>.filled(parsed.depth, '…');
  chain[parsed.depth - 1] = parsed.type;
  chain[0] = rootType ?? '…';
  for (var k = 1; k < ancestors.length; k++) {
    final position = parsed.depth - 1 - k;
    if (position < 0) {
      break;
    }
    chain[position] =
        _agentTypeOf(turn.toolCalls[ancestors[k]]) ?? chain[position];
  }
  return withRoot.withChainTypes(chain);
}

/// Одобрения вызовов, о которых агент не объявлял `tool_call`.
///
/// ACP разрешает `session/request_permission` для вызова без `tool_call`;
/// одобрение должно быть видно, поэтому такой вызов встаёт в конец хода —
/// место, которое ни одно событие не задало точнее.
///
/// Отмена хода: запись вызова пришла из `session/request_permission`, поэтому
/// `cancelTurn` её не помечает (`cancelledByClient` ставится только объявленным
/// `tool_call`) и вызов остался бы `queued`/`running`. Статус берётся из живой
/// записи хода (`turn.toolCalls`), а не из снимка в одобрении: поздний
/// `tool_call_update` ходу в `cancelling` ещё принимается. Вызов становится
/// `cancelled`, только если одобрение отменено, ход в `cancelling` или уже
/// завершён (`completed`, `failed`, `cancelled` и прочие; ход может закрыться
/// ошибкой или `end_turn` вместо `stopReason: cancelled`), статус записи
/// нетерминален (`pending`, `inProgress`) и она не помечена
/// `cancelledByClient` (D27, Q38: один тег «Cancelled» в app). После
/// завершения хода нетерминальный вызов с отменённым одобрением тоже
/// показывается `cancelled`: он так и не исполнился. Отмена одобрения
/// отдельной командой при идущем ходе, терминальные `completed`/`failed` и
/// одобрения, выбранные до отмены, статус не меняют.
///
/// Запрос потомка при строке корня сюда не попадает: его одобрение лежит в
/// `ToolCallItem.childApprovals` строки корня (D43 п. 2). [announced] —
/// вызовы, объявленные `tool_call` хода.
List<TranscriptItem> _unannouncedApprovalItems(
  PromptTurn turn,
  Set<ToolCallId> seen,
  ApprovalRequestId? focused,
  Set<ToolCallId> announced,
) => [
  for (final approval in turn.approvals.values)
    if (_hostRowOf(turn, approval, announced) == null &&
        seen.add(approval.toolCall.id))
      TranscriptItem.toolCall(
        id: _toolItemId(turn.id, approval.toolCall.id),
        toolCallId: approval.toolCall.id,
        title: approval.toolCall.title,
        details: _callView(
          _cancelledWithTurn(turn, approval),
          subagent: _requesterOf(turn, approval),
        ),
        approval: _approvalView(turn, approval, focused),
      ),
];

/// Запись вызова без `tool_call` для показа: при отмене хода вместе с
/// одобрением нетерминальный вызов помечается отменённым (см.
/// [_unannouncedApprovalItems]).
ToolCallRecord _cancelledWithTurn(PromptTurn turn, ApprovalRequest approval) {
  final record = turn.toolCalls[approval.toolCall.id] ?? approval.toolCall;
  // `cancelling` или завершённый ход: после отмены ход может закрыться не
  // `stopReason: cancelled`, а ошибкой `session/prompt` (`failed`) или
  // нарушившим ACP `end_turn` (`completed`).
  final turnCancelled =
      turn.status == PromptTurnStatus.cancelling || turn.isTerminal;
  final nonTerminal =
      record.status == ToolCallStatus.pending ||
      record.status == ToolCallStatus.inProgress;
  if (approval.status == ApprovalStatus.cancelled &&
      turnCancelled &&
      nonTerminal &&
      !record.cancelledByClient) {
    return record.copyWith(cancelledByClient: true);
  }
  return record;
}

/// Заметки конца хода: `emptyTurn`, `turnStopped` и `error`.
///
/// Почему: ход не должен заканчиваться молча (D27, Q33), а причину берём
/// только из `stopReason` ответа на `session/prompt`.
///
/// Ограничение: после `session/load` у ходов реплея нет `stopReason` — ACP его
/// в реплее не передаёт (`03-Session Setup.md`, «Loading a Session»), а исход
/// хода клиент не хранит. Поэтому у таких ходов нет `turnStopped`; ход реплея
/// без вывода агента по-прежнему получает `emptyTurn` («stopReason unknown»).
/// Это принятое решение, а не дефект проекции: D27,
/// Q36 (а); сценарий spec `acp-client-kit` «Реплей session/load без заметки
/// исхода». Живой ход после загрузки получает заметку как обычно.
List<TranscriptItem> _notices(
  PromptTurn turn, {
  required bool hasAgentItems,
}) => [
  // Сорвавшийся ход объясняет заметка `error` ниже; `emptyTurn` для него
  // дал бы вторую строку «Completed with stopReason unknown» — у такого хода
  // нет stopReason (spec `acp-client-kit`: `error` для сорвавшегося хода,
  // `emptyTurn` — для завершённого без вывода агента).
  // Ход, остановленный по лимиту или отказом, объясняет заметка `turnStopped`
  // ниже — она заменяет `emptyTurn` (D27, Q33).
  if (!hasAgentItems &&
      turn.isTerminal &&
      turn.status != PromptTurnStatus.failed &&
      _stoppedNoticeText(turn) == null)
    TranscriptItem.notice(
      id: '${turn.id.value}/completed',
      kind: NoticeKind.emptyTurn,
      text: 'Completed with stopReason ${turn.stopReason?.name ?? 'unknown'}.',
    ),
  if (turn.status != PromptTurnStatus.failed &&
      _stoppedNoticeText(turn) != null)
    TranscriptItem.notice(
      id: '${turn.id.value}/stopped',
      kind: NoticeKind.turnStopped,
      text: _stoppedNoticeText(turn)!,
    ),
  if (turn.status == PromptTurnStatus.failed && turn.failureMessage != null)
    TranscriptItem.notice(
      id: '${turn.id.value}/error',
      kind: NoticeKind.error,
      text:
          'Failed to send prompt: ${_withoutTypePrefix(turn.failureMessage!)}',
      failure: turn.failure,
    ),
];

/// Лимиты бюджета хода, которые заметка называет по имени (D10 change
/// `add-usage-extension`): значения `BudgetLimit.name` агента CodeLab.
/// Незнакомое значение (открытое множество) даёт прежний текст — подставлять
/// в заметку произвольную строку от агента нельзя.
const _knownBudgetLimits = {'steps', 'tokens', 'cost', 'duration', 'deadline'};

/// Текст заметки исхода хода (D27, Q33); `null` — заметка не нужна.
/// Смысл причин — `docs/protocols/acp/protocol/05-Prompt Turn.md`.
///
/// Принимает ход, а не только `stopReason`: при `max_turn_requests` агент
/// CodeLab называет исчерпанный лимит (`PromptTurn.budgetExceeded`, D10,
/// D21 Т6). Функция общая для инкрементальной проекции и эталона
/// `projectTranscript`, поэтому они остаются равными.
String? _stoppedNoticeText(PromptTurn turn) => switch (turn.stopReason) {
  StopReason.maxTokens =>
    'The model reached its token limit, so the turn ended.',
  StopReason.maxTurnRequests => switch (turn.budgetExceeded) {
    final limit? when _knownBudgetLimits.contains(limit) =>
      'The turn stopped: budget exceeded: $limit.',
    _ => 'The turn reached the limit of model requests.',
  },
  StopReason.refusal => 'The agent refused to continue.',
  StopReason.endTurn || StopReason.cancelled || null => null,
};

ToolCallView _callView(ToolCallRecord record, {SubagentRequester? subagent}) =>
    ToolCallView(
      kind: record.kind,
      status: switch (record.status) {
        _ when record.cancelledByClient => ToolCallStatusView.cancelled,
        // Агент сообщил исход: `failed` + `outcome: cancelled` — отмена для
        // любого вызова; прочие значения остаются `failed` (D41 п. 1).
        ToolCallStatus.failed when record.outcome == 'cancelled' =>
          ToolCallStatusView.cancelled,
        ToolCallStatus.pending => ToolCallStatusView.queued,
        ToolCallStatus.inProgress => ToolCallStatusView.running,
        ToolCallStatus.completed => ToolCallStatusView.succeeded,
        ToolCallStatus.failed => ToolCallStatusView.failed,
      },
      command: _command(record),
      rawInput: record.rawInput,
      paths: [for (final location in record.locations) location.path],
      textOutput: [
        for (final item in record.content)
          if (item case ToolCallContentBlock(content: TextContent(:final text)))
            text,
      ],
      subagentCall: parseSubagentCall(record.subagentMeta),
      subagentSummary: parseSubagentSummary(record.subagentMeta),
      subagentFailure: parseSubagentFailure(record.subagentMeta),
      subagent: subagent,
      parentToolCallId: record.parentToolCallId,
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
  PromptTurn turn,
  ApprovalRequest? approval,
  ApprovalRequestId? focused,
) {
  if (approval == null) {
    return null;
  }
  if (approval.status != ApprovalStatus.pending) {
    return ApprovalStateView.resolved(
      label: _resolvedLabel(approval),
      outcome: _resolvedOutcome(approval),
      subagent: _requesterOf(turn, approval),
    );
  }
  return ApprovalStateView.pending(
    approvalId: approval.id,
    sessionId: approval.sessionId,
    risk: approval.riskLevel,
    command: _command(approval.toolCall),
    rawInput: approval.toolCall.rawInput,
    options: approval.options,
    focused: approval.id == focused,
    critical: approval.critical,
    subagent: _requesterOf(turn, approval),
    toolTitle: approval.toolCall.title,
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

ApprovalOutcomeView _resolvedOutcome(ApprovalRequest approval) {
  if (approval.status == ApprovalStatus.cancelled) {
    return ApprovalOutcomeView.cancelled;
  }
  final selectedId = approval.selectedOptionId;
  for (final option in approval.options) {
    if (option.optionId == selectedId) {
      return switch (option.kind) {
        PermissionOptionKind.allowOnce ||
        PermissionOptionKind.allowAlways => ApprovalOutcomeView.allowed,
        PermissionOptionKind.rejectOnce ||
        PermissionOptionKind.rejectAlways => ApprovalOutcomeView.rejected,
      };
    }
  }
  return ApprovalOutcomeView.unknown;
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
