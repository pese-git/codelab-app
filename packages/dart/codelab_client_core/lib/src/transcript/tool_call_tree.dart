import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import 'task_ops.dart';
import 'transcript_item.dart';

/// Сколько вызовов показывает «хвост» работающего `agent` (D25, Q15).
const _tailLength = 3;

/// Собирает дерево вызовов потомков из плоского списка элементов хода.
///
/// Почему: агент с согласием `subagentToolCalls` шлёт кадры вызовов потомков
/// обычным потоком `tool_call` с `_meta.codelab.parentToolCallId` (D21), а
/// транскрипт хоста должен показывать их внутри строки `agent`, а не вперемешку
/// с вызовами корня (design.md change `add-subagents-and-tasks`, D47 Т9).
/// Дерево строится из плоского списка, а не по ходу прихода кадров: родитель
/// может прийти позже ребёнка, а реплей повторяет кадры (§9: идемпотентность по
/// `toolCallId`).
///
/// Для чего: единая точка и для инкрементальной проекции, и для эталонного
/// пересчёта ([projectTranscript]) — их результаты обязаны совпадать.
///
/// Как использовать: [body] — элементы хода по порядку (плоские
/// [ToolCallItem] с заполненным `details.parentToolCallId`), [ops] — операции
/// со списком задач хода ([taskOperationsOf]). Вызов с неизвестным родителем
/// (кадра родителя в ходе нет) и вызовы в цикле родителей остаются на верхнем
/// уровне, ошибки нет. Слияние подряд идущих [TaskOpsItem] — только внутри
/// списка одного родителя (D48 п. 3).
List<TranscriptItem> buildToolCallTree(
  List<TranscriptItem> body,
  Map<ToolCallId, TaskDiff> ops,
) {
  final calls = <ToolCallId, ToolCallItem>{};
  for (final item in body) {
    if (item is ToolCallItem) {
      calls.putIfAbsent(item.toolCallId, () => item);
    }
  }
  final parents = _effectiveParents(calls);
  if (parents.isEmpty) {
    // Дерева нет (клиент без согласия или вызовы корня): прежняя плоская
    // раскладка, без лишних пересборок элементов.
    return withTaskOps(body, ops);
  }

  final kids = <ToolCallId, List<ToolCallItem>>{};
  for (final item in body) {
    if (item is ToolCallItem && parents[item.toolCallId] != null) {
      kids.putIfAbsent(parents[item.toolCallId]!, () => []).add(item);
    }
  }

  // Порядок прихода `tool_call` — порядок плоского списка хода; хвост и
  // счётчик берутся по нему, а не по поздним обновлениям вызова (D25).
  final order = <ToolCallId, int>{
    for (final (index, item) in body.indexed)
      if (item is ToolCallItem) item.toolCallId: index,
  };

  List<ToolCallItem> subtreeOf(ToolCallId root) {
    final ids = <ToolCallId>{};
    void collect(ToolCallId id) {
      for (final child in kids[id] ?? const <ToolCallItem>[]) {
        if (ids.add(child.toolCallId)) {
          collect(child.toolCallId);
        }
      }
    }

    collect(root);
    return [for (final id in ids) calls[id]!]
      ..sort((a, b) => order[a.toolCallId]!.compareTo(order[b.toolCallId]!));
  }

  ToolCallItem assemble(ToolCallItem item) {
    final direct = kids[item.toolCallId];
    if (direct == null) {
      return item;
    }
    final subtree = subtreeOf(item.toolCallId);
    // Операция потомка остаётся вызовом поддерева: входит в счётчик и в хвост
    // (D48 п. 3); хост отличает её по `operations` и рисует тихой строкой.
    final tail = subtree.length > _tailLength
        ? subtree.sublist(subtree.length - _tailLength)
        : subtree;
    return item.copyWith(
      children: withTaskOps([for (final child in direct) assemble(child)], ops),
      subtreeCalls: subtree.length,
      tail: SubagentTailView(
        calls: tail,
        moreCount: subtree.length - tail.length,
        operations: {
          for (final call in tail)
            if (ops[call.toolCallId] case final diff?)
              call.toolCallId: taskOpsItemOf(call.id, diff),
        },
      ),
    );
  }

  final top = <TranscriptItem>[];
  for (final item in body) {
    if (item is! ToolCallItem) {
      top.add(item);
    } else if (parents[item.toolCallId] == null &&
        identical(calls[item.toolCallId], item)) {
      top.add(assemble(item));
    }
  }
  return withTaskOps(top, ops);
}

/// Родитель каждого вызова, входящего в дерево: `toolCallId → родитель`.
///
/// В карту попадают только вызовы с известным родителем (его `tool_call` есть
/// в ходе) и вне цикла родителей; остальные — верхний уровень (D21).
Map<ToolCallId, ToolCallId> _effectiveParents(
  Map<ToolCallId, ToolCallItem> calls,
) => effectiveToolCallParents({
  for (final MapEntry(:key, :value) in calls.entries)
    key: value.details?.parentToolCallId,
});

/// Карта родителей дерева по объявленным на проводе: единственная точка
/// правила «неизвестный родитель и цикл — верхний уровень» (D21).
///
/// Почему отдельно: раскладку дерева ([buildToolCallTree]) и выбор строки,
/// под которой стоит панель одобрения, обязаны решать это одинаково, иначе при
/// цикле A↔B одно одобрение попадёт в две панели (PERM-4, §9).
///
/// Как использовать: [declared] — `toolCallId → parentToolCallId` кадров
/// `tool_call` хода (`null` — родителя нет); ключи — все объявленные вызовы.
Map<ToolCallId, ToolCallId> effectiveToolCallParents(
  Map<ToolCallId, String?> declared,
) {
  final direct = <ToolCallId, ToolCallId>{};
  for (final MapEntry(:key, :value) in declared.entries) {
    if (value == null) {
      continue;
    }
    final parent = ToolCallId(value);
    if (parent != key && declared.containsKey(parent)) {
      direct[key] = parent;
    }
  }
  // Вызов, чья цепочка родителей возвращается к нему самому, не вкладывается:
  // цикл на проводе — ошибка агента, и показ не должен зациклиться.
  final result = <ToolCallId, ToolCallId>{};
  for (final MapEntry(:key, :value) in direct.entries) {
    var cursor = value;
    var steps = 0;
    var cyclic = false;
    while (direct.containsKey(cursor)) {
      cursor = direct[cursor]!;
      if (cursor == key || ++steps > direct.length) {
        cyclic = true;
        break;
      }
    }
    if (!cyclic) {
      result[key] = value;
    }
  }
  return result;
}
