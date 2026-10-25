/// Регион сжатия и точка среза (`agent-core-architecture` §9.6).
///
/// Почему отдельно от компактора: срез — чистая функция записей, и её
/// гарантии (CMP-1 — вызов не отделяется от результата, CMP-7 — последний
/// запрос пользователя остаётся дословно) проверяются таблицей примеров без
/// модели и журнала.
///
/// Как использовать: компактор берёт [compactionRegion] снимка и вызывает
/// [findCutPoint]; `null` — сжимать нечего.
library;

import '../llm/messages.dart';
import '../session/records.dart';
import '../session/session_store.dart';
import '../session/tree.dart';
import '../session/user_words.dart';
import '../util/logger.dart';
import 'estimate.dart';
import 'settings.dart';

/// Первая запись хвоста и признак разрезанного хода.
final class CutPoint {
  const CutPoint({
    required this.firstKeptIndex,
    required this.splitTurn,
    required this.turnStartIndex,
  });

  /// Индекс первой записи хвоста в регионе.
  final int firstKeptIndex;

  /// Срез внутри хода: начало хода резюмируется отдельно, а слова
  /// пользователя цитируются дословно (CMP-7).
  final bool splitTurn;

  /// Начало хода, внутри которого прошёл срез.
  final int turnStartIndex;
}

/// Записи активной ветки после прошлого сжатия (§9.6) — в порядке
/// контекста модели: сохранённые записи до прошлой `compaction`, затем
/// записи после неё. Сами записи `compaction` в регион не входят: прошлое
/// резюме суммаризатор получает отдельно (`previousSummary`, CMP-9).
({List<SessionRecord> region, CompactionRecord? last}) compactionRegion(
  SessionSnapshot snapshot, {
  Logger? logger,
}) {
  final path = pathToLeaf(snapshot, logger: logger);
  final lastIndex = path.lastIndexWhere((r) => r is CompactionRecord);
  if (lastIndex < 0) {
    return (region: path, last: null);
  }
  final last = path[lastIndex] as CompactionRecord;
  final first = path.indexWhere((r) => r.id == last.firstKeptId);
  final start = first >= 0 && first < lastIndex ? first : lastIndex + 1;
  return (
    region: [
      for (final record in path.skip(start))
        if (record is! CompactionRecord) record,
    ],
    last: last,
  );
}

/// Оценка записи: сообщение — по §9.3, служебные записи стоят 0.
int recordTokens(SessionRecord record) => switch (record) {
  MessageRecord(:final message) => estimateMessageTokens(message),
  _ => 0,
};

/// Точка среза региона по шагам §9.6.
///
/// Разрезание хода (последний абзац §9.6): если правило последнего хода
/// пользователя сдвинуло срез к началу региона и сжимать стало нечего, а
/// сам ход больше `keepRecentTokens`, срез остаётся внутри хода — на
/// границе шагов 3–4 — и `splitTurn = true`. Если перед ходом есть что
/// сжать, ход сохраняется целиком (пример §9.6).
CutPoint? findCutPoint(List<SessionRecord> region, CompactionSettings s) {
  if (!region.any((r) => r is MessageRecord)) {
    return null;
  }
  final userTurns = [
    for (final (i, r) in region.indexed)
      if (_isUserWords(r)) i,
  ];
  final total = region.fold(0, (sum, r) => sum + recordTokens(r));
  if (userTurns.length <= s.keepRecentUserTurns &&
      total <= s.keepRecentTokens) {
    return null;
  }
  // Шаг 3: хвост с конца до keepRecentTokens.
  var acc = 0;
  var i = region.length - 1;
  while (i >= 0) {
    acc += recordTokens(region[i]);
    if (acc >= s.keepRecentTokens) {
      break;
    }
    i--;
  }
  if (i < 0) {
    return null;
  }
  // Шаг 4: срез только перед user- или assistant-сообщением (CMP-1).
  var c = i;
  while (c < region.length && !_isBoundary(region[c])) {
    c++;
  }
  if (c == region.length) {
    return null;
  }
  final inTurn = c;
  // Шаг 5: последние keepRecentUserTurns ходов остаются в хвосте.
  if (userTurns.isNotEmpty) {
    final lastUsers = userTurns.skip(
      userTurns.length > s.keepRecentUserTurns
          ? userTurns.length - s.keepRecentUserTurns
          : 0,
    );
    final turnStart = lastUsers.first;
    if (c > turnStart) {
      c = _withService(region, turnStart);
      final turn = region
          .skip(turnStart)
          .fold(0, (sum, r) => sum + recordTokens(r));
      if (c == 0 && turn > s.keepRecentTokens) {
        c = inTurn;
      }
    }
  }
  // Шаг 6: служебные записи прямо перед срезом остаются с хвостом.
  c = _withService(region, c);
  if (c == 0) {
    return null;
  }
  // Шаг 7: срез внутри хода, если первое значимое сообщение хвоста — не
  // слова пользователя.
  var m = c;
  while (m < region.length && !_opensTail(region[m])) {
    m++;
  }
  if (m == region.length) {
    return null;
  }
  final splitTurn = !_isUserWords(region[m]);
  final start = userTurns.lastWhere((u) => u <= m, orElse: () => 0);
  return CutPoint(
    firstKeptIndex: c,
    splitTurn: splitTurn,
    turnStartIndex: start,
  );
}

int _withService(List<SessionRecord> region, int c) {
  while (c > 0 && _isService(region[c - 1])) {
    c--;
  }
  return c;
}

bool _isUserWords(SessionRecord r) =>
    r is MessageRecord && r.message is UserMessage && isUserWords(r);

bool _isBoundary(SessionRecord r) =>
    r is MessageRecord &&
    (r.message is UserMessage || r.message is AssistantMessage);

/// Слова пользователя или ответ модели: служебные user-сообщения перед
/// словами пользователя — часть начала хода (§9.6, шаг 7).
bool _opensTail(SessionRecord r) =>
    _isUserWords(r) || (r is MessageRecord && r.message is AssistantMessage);

bool _isService(SessionRecord r) =>
    r is ModelChangeRecord ||
    r is ModeChangeRecord ||
    r is ConfigChangeRecord ||
    r is PlanRecord ||
    r is SessionInfoRecord ||
    r is LabelRecord;
