import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'server_harness.dart' show scriptedModel;

/// Сессия для тестов `SessionBridge`: тест решает, какие события выйдут и что
/// отдаст реплей дерева.
///
/// Почему отдельный файл: те же правила, что у приватной `_FakeSession` в
/// `subagent_tool_tree_bridge_test.dart`, нужны нескольким файлам проверок
/// моста (реплей, закрытие хода), а общая правка фальшивой сессии не должна
/// трогать тот файл. Отличие — `replayTreeGates`: у каждого вызова
/// `replayTree()` свой затвор, что позволяет пересечь два реплея.
final class FakeBridgeSession implements AgentSession {
  final _events = StreamController<AgentEvent>.broadcast(sync: true);

  /// События синхронного `replay()` — корень без журналов потомков.
  List<AgentEvent> replayEvents = const [];

  /// События `replayTree()` — корень и потомки.
  List<AgentEvent> replayTreeEvents = const [];

  /// Затворы по порядку вызовов `replayTree()`: вызов номер `n` ждёт
  /// `replayTreeGates[n]`, если он есть. Пусто — читается без ожидания.
  final replayTreeGates = <Completer<void>>[];

  /// Если задан, `replayTree()` после затвора бросает эту ошибку.
  Object? replayTreeError;
  var replayTreeCalls = 0;

  void emit(AgentEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();

  @override
  SessionId get id => const SessionId('sess_fake');

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  ModelRef get model => scriptedModel;

  @override
  ModelCatalog get models => FixedModelCatalog([scriptedModel]);

  @override
  ModeId get mode => ModeId.standard;

  @override
  ReasoningEffort get effort => ReasoningEffort.medium;

  @override
  List<AgentDefinition> get agents => const [];

  @override
  List<SlashCommand> get commands => const [];

  @override
  Iterable<AgentEvent> replay() => replayEvents;

  @override
  Future<List<AgentEvent>> replayTree() async {
    final call = replayTreeCalls++;
    if (call < replayTreeGates.length) {
      await replayTreeGates[call].future;
    }
    if (replayTreeError case final error?) {
      throw error;
    }
    return replayTreeEvents;
  }

  /// Если задан, `prompt` ждёт его до `TurnEnded`: ход «идёт», и тест
  /// выпускает события потомков внутри хода.
  Completer<void>? promptGate;

  /// Ход фальшивки: `prompt` выпускает `TurnEnded` и завершается, как ядро
  /// после последнего события хода.
  @override
  Future<TurnResult> prompt(
    List<ContentBlock> content, {
    CancelToken? cancel,
  }) async {
    await promptGate?.future;
    emit(TurnEnded(id, reason: TurnEndReason.completed, usage: Usage.zero));
    return const TurnResult(reason: TurnEndReason.completed, usage: Usage.zero);
  }

  @override
  Future<void> cancel() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
