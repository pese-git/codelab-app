/// Дерево записей журнала (`agent-core-architecture` §8.4).
///
/// Почему дерево, а не список: `parentId` и `leaf` стоят одно поле на
/// запись, но дают ветки, перемотку и fork после MVP без миграции формата
/// (§8.12).
///
/// Как использовать: [leafAfter] — новый лист после записи (писатель и
/// разбор журнала); [pathToLeaf] — активная ветка для проекций.
library;

import '../util/logger.dart';
import 'records.dart';
import 'session_store.dart';

/// Лист после [record] (правило 2 §8.4): после `leaf` — его цель, после
/// остальных записей — сама запись.
String leafAfter(SessionRecord record) =>
    record is LeafRecord ? record.targetId : record.id;

/// Путь от листа к корню по `parentId`, развёрнутый root-first.
///
/// Обход завершается на цикле `parentId` (`session.cycle`), на
/// отсутствующем родителе (`session.broken_link`) и не проходит больше
/// записей, чем есть в снимке: журнал мог быть испорчен или подделан.
List<SessionRecord> pathToLeaf(
  SessionSnapshot snapshot, {
  String? leafId,
  Logger? logger,
}) {
  var id = leafId ?? snapshot.leafId;
  final path = <SessionRecord>[];
  final seen = <String>{};
  while (id != null) {
    if (!seen.add(id)) {
      logger?.log(LogLevel.warning, 'session.cycle', fields: {'id': id});
      break;
    }
    final record = snapshot.byId[id];
    if (record == null) {
      logger?.log(LogLevel.warning, 'session.broken_link', fields: {'id': id});
      break;
    }
    path.add(record);
    if (path.length > snapshot.records.length) {
      break;
    }
    id = record.parentId;
  }
  return path.reversed.toList(growable: false);
}
