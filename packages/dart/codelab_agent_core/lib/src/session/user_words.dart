/// Единственное правило «этот текст написал пользователь» (§8.2.5, S-16).
///
/// Почему одна функция: в журнале с ролью `user` лежат не только слова
/// человека, но и подсказки цикла, уведомления субагентов и фоновых
/// команд. Заголовок, сжатие, реплей и поиск должны отвечать на этот вопрос
/// одинаково; если каждый перечисляет значения `origin` сам, новое значение
/// легко пропустить в одном из мест (SES-14).
///
/// Как использовать: потребитель вызывает [isUserWords] для записи журнала
/// или [isUserWordsEvent] для живого события и не читает `origin` сам.
/// Новое значение `origin` добавляется в [RecordOrigin] с веткой в
/// [classifyOrigin] и, если его пишет ядро, — подклассом `MessageOrigin` со
/// строкой в [recordOriginOf].
library;

import 'package:meta/meta.dart';

import '../llm/messages.dart';
import '../loop/agent_events.dart';
import '../util/logger.dart';
import 'records.dart';

/// Все значения поля записи `origin`, известные этой версии ядра.
enum RecordOrigin {
  steer('steer'),
  subagentNotice('subagent_notice'),
  jobNotice('job_notice'),
  loopNudge('loop_nudge'),
  loopNote('loop_note'),
  deadlineNotice('deadline_notice'),
  parentMessage('parent_message'),
  subagentResume('subagent_resume');

  const RecordOrigin(this.wire);

  final String wire;

  /// `null` — значение неизвестно этой версии.
  static RecordOrigin? parse(String wire) =>
      values.where((o) => o.wire == wire).firstOrNull;
}

enum OriginClass { userWords, service }

/// `switch` без `default`: новое значение без ветки — ошибка компиляции, а
/// не молчаливое «служебное» (SES-15).
OriginClass classifyOrigin(RecordOrigin origin) => switch (origin) {
  RecordOrigin.steer || RecordOrigin.parentMessage => OriginClass.userWords,
  RecordOrigin.subagentNotice ||
  RecordOrigin.jobNotice ||
  RecordOrigin.loopNudge ||
  RecordOrigin.loopNote ||
  RecordOrigin.deadlineNotice ||
  RecordOrigin.subagentResume => OriginClass.service,
};

/// Соответствие `MessageOrigin` ядра и значения записи; один к одному.
RecordOrigin recordOriginOf(MessageOrigin origin) => switch (origin) {
  LoopNudgeOrigin() => RecordOrigin.loopNudge,
  LoopNoteOrigin() => RecordOrigin.loopNote,
};

/// Поля записи, которые писатель журнала ставит рядом с `origin` (§8.2.3).
({String origin, String? nudge, int? attempt}) originFieldsOf(
  MessageOrigin origin,
) => switch (origin) {
  LoopNudgeOrigin(:final reason, :final attempt) => (
    origin: recordOriginOf(origin).wire,
    nudge: _nudgeWire(reason),
    attempt: attempt,
  ),
  LoopNoteOrigin(:final reason) => (
    origin: recordOriginOf(origin).wire,
    nudge: _nudgeWire(reason),
    attempt: null,
  ),
};

String _nudgeWire(LoopNudgeReason reason) => switch (reason) {
  LoopNudgeReason.emptyResponse => 'empty_response',
  LoopNudgeReason.deadline => 'deadline',
};

/// Неизвестные значения, о которых уже предупредили в этом процессе.
final _warned = <String>{};

/// Сбрасывает «предупреждено один раз» между тестами.
@visibleForTesting
void resetUnknownOriginWarnings() => _warned.clear();

/// Написал ли текст записи человек (в журнале субагента — его родитель).
///
/// Неизвестное значение `origin` (журнал новой версии) считается служебным:
/// такой текст не станет заголовком и не будет считаться ходом
/// пользователя. Из контекста модели сообщение при этом не пропадает.
bool isUserWords(SessionRecord record, {Logger? logger}) {
  if (record is! MessageRecord || record.message is! UserMessage) {
    return false;
  }
  final origin = record.origin;
  if (origin == null) {
    return true;
  }
  if (RecordOrigin.parse(origin) case final known?) {
    return classifyOrigin(known) == OriginClass.userWords;
  }
  if (_warned.add(origin)) {
    logger?.log(
      LogLevel.warning,
      'session.origin.unknown',
      fields: {'origin': origin},
    );
  }
  return false;
}

/// То же для живого события `MessageStarted(message, origin)`: тот же ответ,
/// что у записи, которую из этого события пишет журнал.
bool isUserWordsEvent(Message message, MessageOrigin? origin) {
  if (message is! UserMessage) {
    return false;
  }
  return origin == null ||
      classifyOrigin(recordOriginOf(origin)) == OriginClass.userWords;
}
