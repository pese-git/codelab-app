import 'dart:async';
import 'dart:collection';

import '../cancel/cancel_token.dart';
import '../permissions/gate.dart';
import '../util/logger.dart';
import 'subagent_model.dart';

/// FIFO вопросов всего дерева субагентов к gate корневой сессии
/// (`agent-core/17-3-subagents.md` §17.3.2, §17.3.3; design.md change
/// `add-subagents-and-tasks`, D8, D42 Т3).
///
/// Почему: пользователь видит запросы корневой сессии и отвечает на них по
/// одному; три потомка с вопросами не должны открыть три диалога сразу.
///
/// Для чего: пропускает к gate корня один запрос за раз, остальные ждут в
/// порядке прихода. Запрос самого корня очередь не использует — у корня свой
/// gate напрямую. Снятие запроса при отмене (PERM-7): ждущий в очереди
/// не доходит до gate корня, отправленный получает отменённый токен и
/// освобождает очередь, не дожидаясь ответа клиента.
///
/// Как использовать: `SubagentTree.wrapGate(rootGate)` создаёт один экземпляр
/// на дерево; потомки любой глубины оборачивают именно его
/// ([SubagentPermissionGate]), а не gate родителя. Отмена — исход
/// `PermissionDecision.cancelled`, не исключение.
final class SubagentQuestionQueue implements PermissionGate {
  SubagentQuestionQueue(this.root);

  /// Gate корневой сессии: единственный, кого знает клиент (SUB-3).
  final PermissionGate root;

  /// Ждущие в очереди; `true` — право на gate передала очередь, `false` —
  /// запрос снят отменой и права не получал (иначе отмена ждущего освободила бы
  /// gate при открытом вопросе первого: ревью итерации 3).
  final _waiters = Queue<Completer<bool>>();
  var _busy = false;

  /// Запросов дерева сейчас: отправленный gate корня и ждущие в очереди.
  int get pending => _waiters.length + (_busy ? 1 : 0);

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async {
    if (cancel.isCancelled) {
      return PermissionDecision.cancelled;
    }
    if (_busy) {
      final turn = Completer<bool>();
      _waiters.add(turn);
      // Отмена в очереди: запрос снимается без кадра клиенту (PERM-7). Право
      // на gate он не получал, поэтому очередь не передаётся дальше.
      unawaited(
        cancel.onCancel.then((_) {
          if (_waiters.remove(turn)) {
            turn.complete(false);
          }
        }),
      );
      if (!await turn.future) {
        return PermissionDecision.cancelled;
      }
      if (cancel.isCancelled) {
        // Очередь передала право, но отмена пришла раньше: право возвращается
        // следующему, запрос не отправляется.
        _handOver();
        return PermissionDecision.cancelled;
      }
    } else {
      _busy = true;
    }
    try {
      return await raceCancel(root.request(req, cancel), cancel);
    } on CancelledException {
      return PermissionDecision.cancelled;
    } finally {
      _handOver();
    }
  }

  /// Передаёт право первому в очереди; `_busy` остаётся истинным при передаче.
  void _handOver() {
    if (_waiters.isEmpty) {
      _busy = false;
    } else {
      _waiters.removeFirst().complete(true);
    }
  }
}

/// Gate потомка: переписывает запрос под сессию корня и ставит его в FIFO
/// дерева (design.md change `add-subagents-and-tasks`, D8, D42 Т3, Т4, Т8;
/// §17.3.3, шаг 6).
///
/// Почему: клиент знает только корневую сессию, а `toolCallId` потомка
/// уникален лишь внутри его сессии (PERM-4); вопрос потомка должен быть
/// узнаваем по `title` и сведениям [PermissionRequest.subagent].
///
/// Для чего: `toolCallId` становится цепочкой через `/` от вызова `agent`
/// корня (`call_3/call_1`), `title` получает префикс `[<тип>: <описание>]`,
/// `subagent` заполняется; остальное (`rawInput`, `locations`, `diffs`,
/// `allowAlwaysOffered`, критическая метка) — как у потомка (PERM-6). Пока
/// вопрос ждёт очереди или ответа, хэндл потомка в `waiting` с
/// `waitingFor: approval`; лог `subagent.permission.queued` не содержит
/// текстов запроса.
///
/// Как использовать: менеджер создаёт по одному на потомка в `_runLeased`
/// поверх [SubagentQuestionQueue] дерева. Нет gate у корня — gate потомка не
/// создаётся и вопрос — отказ (PERM-5).
final class SubagentPermissionGate implements PermissionGate {
  SubagentPermissionGate({
    required this.queue,
    required this.spec,
    required this.chainPrefix,
    required this.onWaiting,
    required this.onResumed,
    required this.logger,
    required this.sessionId,
  });

  final SubagentQuestionQueue queue;
  final SubagentSpec spec;

  /// Цепочка id вызовов `agent` от корня до сессии спрашивающего: для ребёнка
  /// корня — id вызова `agent` корня.
  final String chainPrefix;

  /// Хэндл переходит в `waiting`/`approval` и обратно в `running`; менеджер
  /// учитывает терминальное состояние сам.
  final void Function() onWaiting, onResumed;
  final Logger logger;
  final String sessionId;

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async {
    final chained = '$chainPrefix/${req.toolCallId}';
    final wrapped = PermissionRequest(
      toolCallId: chained,
      tool: req.tool,
      kind: req.kind,
      tier: req.tier,
      title: '[${spec.type.name}: ${spec.description}] ${req.title}',
      rawInput: req.rawInput,
      locations: req.locations,
      diffs: req.diffs,
      pattern: req.pattern,
      reason: req.reason,
      criticalLabel: req.criticalLabel,
      allowAlwaysOffered: req.allowAlwaysOffered,
      subagent: SubagentRequestRef(
        id: spec.id,
        type: spec.type.name,
        description: spec.description,
        depth: spec.depth,
        path: spec.path,
        parentToolCallId: _firstSegment(chainPrefix),
      ),
    );
    logger.log(
      LogLevel.debug,
      'subagent.permission.queued',
      fields: {
        'session_id': sessionId,
        'subagent_id': spec.id,
        'tool_call_id': chained,
        // Запросов дерева включая этот: 1 — очереди нет.
        'queue_length': queue.pending + 1,
      },
    );
    onWaiting();
    try {
      return await queue.request(wrapped, cancel);
    } finally {
      onResumed();
    }
  }

  static String _firstSegment(String chain) {
    final slash = chain.indexOf('/');
    return slash < 0 ? chain : chain.substring(0, slash);
  }
}
