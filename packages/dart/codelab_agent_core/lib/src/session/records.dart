/// Записи журнала сессии и их JSON-форма (`agent-core-architecture` §8.2).
///
/// Почему отдельная модель, а не события цикла: журнал — долговечный формат
/// на диске, он переживает версии ядра. Поэтому у каждой записи стабильный
/// `type`, общие поля идут первыми, а неизвестные поля и типы сохраняются
/// и пишутся обратно (forward compatibility, §8.2.2).
///
/// Как использовать: писатель журнала создаёт записи конструкторами и
/// пишет `toJson()`; разбор файла — `SessionRecord.fromJson` и
/// `SessionHeader.fromJson` (их зовёт `parseSessionLines`).
library;

import '../commands/expand_command.dart' show CommandRef;
import '../llm/messages.dart';
import '../llm/usage.dart';
import '../subagents/subagent_model.dart';
import '../llm/model_ref.dart';
import '../loop/agent_events.dart';
import '../tools/agent_tool.dart';
import '../tools/tasks/task_list.dart';

/// Текущая версия формата журнала (SES-2).
const sessionFormatVersion = 1;

/// Модель ответа из журнала, пока сессия не сопоставила её со своей.
///
/// Почему: JSON сообщения хранит только провайдера и id модели (§2.2), а
/// разбору журнала каталог моделей недоступен. Сессия после открытия
/// заменяет такие ссылки моделью сессии, если провайдер и id совпадают.
ModelRef journalModelRef(String provider, String id) => ModelRef(
  provider: provider,
  id: id,
  api: ProviderApi.openaiChat,
  baseUrl: Uri(),
  contextWindow: 0,
  maxOutputTokens: 0,
);

/// Время записи журнала: ISO-8601 UTC с миллисекундами (§8.2.1).
String formatJournalTime(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}Z';
}

/// Кто создал файл журнала; только для диагностики.
final class AgentInfo {
  const AgentInfo({required this.name, required this.version});

  factory AgentInfo.fromJson(Map<String, Object?> json) =>
      AgentInfo(name: _string(json, 'name'), version: _string(json, 'version'));

  final String name, version;

  Map<String, Object?> toJson() => {'name': name, 'version': version};
}

/// Первая строка журнала (§8.2.1); в дерево записей не входит.
final class SessionHeader {
  SessionHeader({
    required this.id,
    required this.cwd,
    required this.created,
    required this.agent,
    this.version = sessionFormatVersion,
    this.parent,
    Map<String, Object?> metadata = const {},
    Map<String, Object?> extra = const {},
  }) : metadata = Map.unmodifiable(metadata),
       extra = Map.unmodifiable(extra);

  /// [FormatException] — не заголовок или нет обязательного поля; версию
  /// проверяет разбор журнала.
  factory SessionHeader.fromJson(Map<String, Object?> json) {
    if (json['type'] != 'session') {
      throw const FormatException('not a session header');
    }
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('"version" must be an int');
    }
    return SessionHeader(
      id: SessionId(_string(json, 'id')),
      cwd: _string(json, 'cwd'),
      created: DateTime.parse(_string(json, 'created')),
      agent: AgentInfo.fromJson(_object(json, 'agent')),
      version: version,
      parent: json['parent'] is Map<String, Object?>
          ? SessionParent.fromJson(json['parent']! as Map<String, Object?>)
          : null,
      metadata: json['metadata'] is Map<String, Object?>
          ? json['metadata']! as Map<String, Object?>
          : const {},
      extra: _rest(json, const {
        'type',
        'version',
        'id',
        'cwd',
        'created',
        'agent',
        'metadata',
        'parent',
      }),
    );
  }

  final int version;
  final SessionId id;

  /// Абсолютный нормализованный путь — источник истины для фильтра списка.
  final String cwd;
  final DateTime created;
  final AgentInfo agent;

  /// Свободные данные хоста; ядро их не интерпретирует.
  final Map<String, Object?> metadata;

  /// Связь журнала потомка с деревом; `null` у журнала сессии пользователя
  /// (`agent-core/17-3-subagents.md` §17.3.6; change `add-subagents-and-tasks`,
  /// D7, D36 Т4). Обязателен для `SessionStore.createChild`.
  final SessionParent? parent;

  /// Неизвестные поля заголовка известной версии.
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    'type': 'session',
    'version': version,
    'id': id.value,
    'cwd': cwd,
    'created': formatJournalTime(created),
    'agent': agent.toJson(),
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (parent != null) 'parent': parent!.toJson(),
    ...extra,
  };
}

/// Поле `parent` заголовка журнала потомка: прямой родитель, корень дерева,
/// вызов `agent`, id, тип и глубина потомка.
///
/// Почему в заголовке: дерево восстанавливается по заголовкам и записям
/// `subagent` (журналы лежат плоско в `subagents/` корня, D7). `agent` —
/// имя типа: в журнале поле называется так, потому что `type` — вид записи.
final class SessionParent {
  const SessionParent({
    required this.sessionId,
    required this.rootSessionId,
    required this.toolCallId,
    required this.subagentId,
    required this.agent,
    required this.depth,
  });

  factory SessionParent.fromJson(Map<String, Object?> json) => SessionParent(
    sessionId: SessionId(_string(json, 'sessionId')),
    rootSessionId: SessionId(_string(json, 'rootSessionId')),
    toolCallId: _string(json, 'toolCallId'),
    subagentId: _string(json, 'subagentId'),
    agent: _string(json, 'agent'),
    depth: _int(json, 'depth'),
  );

  final SessionId sessionId, rootSessionId;
  final String toolCallId, subagentId, agent;
  final int depth;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId.value,
    'rootSessionId': rootSessionId.value,
    'toolCallId': toolCallId,
    'subagentId': subagentId,
    'agent': agent,
    'depth': depth,
  };
}

/// Запись журнала: узел дерева по `parentId` (§8.2.2, §8.4).
sealed class SessionRecord {
  SessionRecord({
    required this.id,
    required this.parentId,
    required this.timestamp,
    Map<String, Object?> extra = const {},
  }) : extra = Map.unmodifiable(extra);

  /// [FormatException] — не объект записи или нет общего поля. Неизвестный
  /// `type` становится [CustomRecord.unknown], чтобы строка не терялась.
  factory SessionRecord.fromJson(Map<String, Object?> json) {
    final id = _string(json, 'id');
    final parentId = switch (json['parentId']) {
      null => null,
      final String value => value,
      final value => throw FormatException(
        '"parentId" must be a string: $value',
      ),
    };
    final timestamp = DateTime.parse(_string(json, 'timestamp'));
    Map<String, Object?> extra(Set<String> known) =>
        _rest(json, {'type', 'id', 'parentId', 'timestamp', ...known});
    // Поле, которое не разобралось, остаётся в `extra` и пишется обратно.
    final command = CommandRef.tryParse(json['command']);
    final skills = CompactionSkill.tryParseList(json['skills']);
    return switch (json['type']) {
      'message' => MessageRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        message: Message.fromJson(
          _object(json, 'message'),
          resolveModel: journalModelRef,
        ),
        outcome: json['outcome'] as String?,
        diff: json['diff'] is Map<String, Object?>
            ? _diff(json['diff']! as Map<String, Object?>)
            : null,
        toolMeta: json['toolMeta'] is Map<String, Object?>
            ? ToolMeta.fromJson(json['toolMeta']! as Map<String, Object?>)
            : null,
        origin: json['origin'] as String?,
        nudge: json['nudge'] as String?,
        attempt: json['attempt'] as int?,
        command: command,
        extra: extra(
          command == null
              ? MessageRecord._fieldNames.difference(const {'command'})
              : MessageRecord._fieldNames,
        ),
      ),
      'model_change' => ModelChangeRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        provider: _string(json, 'provider'),
        modelId: _string(json, 'modelId'),
        baseUrl: json['baseUrl'] as String?,
        extra: extra(const {'provider', 'modelId', 'baseUrl'}),
      ),
      'mode_change' => ModeChangeRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        modeId: _string(json, 'modeId'),
        extra: extra(const {'modeId'}),
      ),
      'config_change' => ConfigChangeRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        optionId: _string(json, 'optionId'),
        value: _string(json, 'value'),
        extra: extra(const {'optionId', 'value'}),
      ),
      'plan' => PlanRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        entries: [
          for (final entry in json['entries'] as List<Object?>? ?? const [])
            _planEntry(entry! as Map<String, Object?>),
        ],
        extra: extra(const {'entries'}),
      ),
      'task' => TaskRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        op: _string(json, 'op'),
        actor: TaskActor.fromWire(json['actor']),
        items: [
          for (final item in json['items'] as List<Object?>? ?? const [])
            TaskItem.fromJson(item! as Map<String, Object?>),
        ],
        deleted: [
          for (final id in json['deleted'] as List<Object?>? ?? const [])
            parseTaskId(id),
        ],
        extra: extra(const {'op', 'actor', 'items', 'deleted'}),
      ),
      'subagent' => SubagentRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        subagentId: _string(json, 'subagentId'),
        toolCallId: _string(json, 'toolCallId'),
        agent: _string(json, 'agent'),
        description: json['description'] as String? ?? '',
        childSessionId: json['childSessionId'] as String?,
        journal: json['journal'] as String?,
        status: _string(json, 'status'),
        failure: json['failure'] as String?,
        report: json['report'] as String?,
        usage: json['usage'] is Map<String, Object?>
            ? Usage.fromJson(json['usage']! as Map<String, Object?>)
            : null,
        toolCalls: json['toolCalls'] as int?,
        durationMs: json['durationMs'] as int?,
        extra: extra(const {
          'subagentId',
          'toolCallId',
          'agent',
          'description',
          'childSessionId',
          'journal',
          'status',
          'failure',
          'report',
          'usage',
          'toolCalls',
          'durationMs',
        }),
      ),
      'compaction' => CompactionRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        summary: _string(json, 'summary'),
        firstKeptId: _string(json, 'firstKeptId'),
        tokensBefore: _int(json, 'tokensBefore'),
        tokensAfter: _int(json, 'tokensAfter'),
        details: json['details'] as Map<String, Object?>?,
        skills: skills,
        extra: extra({
          'summary',
          'firstKeptId',
          'tokensBefore',
          'tokensAfter',
          'details',
          if (skills != null) 'skills',
        }),
      ),
      'label' => LabelRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        targetId: _string(json, 'targetId'),
        label: json['label'] as String?,
        extra: extra(const {'targetId', 'label'}),
      ),
      'leaf' => LeafRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        targetId: _string(json, 'targetId'),
        extra: extra(const {'targetId'}),
      ),
      'session_info' => SessionInfoRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        title: json['title'] as String?,
        source: json['source'] as String?,
        extra: extra(const {'title', 'source'}),
      ),
      'custom' => CustomRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        customType: _string(json, 'customType'),
        data: json['data'],
        extra: extra(const {'customType', 'data'}),
      ),
      final String _ => CustomRecord.unknown(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        raw: json,
      ),
      final type => throw FormatException('"type" must be a string: $type'),
    };
  }

  /// Дискриминатор записи.
  String get type;

  /// `RecordId`: 8 символов, уникален в файле (SES-3).
  final String id;

  /// `null` только у первой записи дерева.
  final String? parentId;
  final DateTime timestamp;

  /// Неизвестные поля известной записи; пишутся обратно после своих полей.
  final Map<String, Object?> extra;

  /// Поля подкласса в порядке записи.
  Map<String, Object?> get _fields;

  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'parentId': parentId,
    'timestamp': formatJournalTime(timestamp),
    ..._fields,
    ...extra,
  };
}

/// Заголовок, вид и места вызова из `ToolCallStarted` — для реплея без
/// повторного `present()` (§8.2.3).
final class ToolMeta {
  ToolMeta({
    required this.title,
    required this.kind,
    List<Location> locations = const [],
  }) : locations = List.unmodifiable(locations);

  factory ToolMeta.fromJson(Map<String, Object?> json) => ToolMeta(
    title: _string(json, 'title'),
    kind: ToolKind.values.asNameMap()[json['kind']] ?? ToolKind.other,
    locations: [
      for (final raw in json['locations'] as List<Object?>? ?? const [])
        if (raw case final Map<String, Object?> l)
          Location(_string(l, 'path'), line: l['line'] as int?),
    ],
  );

  final String title;
  final ToolKind kind;
  final List<Location> locations;

  Map<String, Object?> toJson() => {
    'title': title,
    'kind': kind.name,
    'locations': [
      for (final l in locations) {'path': l.path, 'line': ?l.line},
    ],
  };
}

/// Сообщение транскрипта с полями записи (§8.2.3). Модель видит только
/// [message]; [outcome], [diff], [toolMeta] и [origin] — для реплея,
/// заголовка и сжатия.
final class MessageRecord extends SessionRecord {
  MessageRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.message,
    this.outcome,
    this.diff,
    this.toolMeta,
    this.origin,
    this.nudge,
    this.attempt,
    this.command,
    super.extra,
  });

  static const _fieldNames = {
    'outcome',
    'diff',
    'toolMeta',
    'origin',
    'nudge',
    'attempt',
    'command',
    'message',
  };

  final Message message;

  /// Только у `toolResult`: `ToolOutcome.name` или `interrupted`.
  final String? outcome;

  /// Только у `toolResult` с правкой одного файла.
  final FileDiff? diff;

  /// Только у `toolResult`.
  final ToolMeta? toolMeta;

  /// Кто написал служебное сообщение (§8.2.5); `null` — пользователь или
  /// ответ модели.
  final String? origin;

  /// Причина подсказки или заметки цикла (`empty_response`).
  final String? nudge;

  /// Номер повтора подсказки цикла, с 1.
  final int? attempt;

  /// Исходная команда, если сообщение пользователя получено разворачиванием
  /// шаблона (§8.2.3; design.md change `add-agent-project-files`, D8).
  /// Модель поле не видит: оно не входит в [message]. Реплей показывает по
  /// нему `/<name> <args>` вместо развёрнутого текста.
  final CommandRef? command;

  @override
  String get type => 'message';

  @override
  Map<String, Object?> get _fields => {
    'outcome': ?outcome,
    if (diff case final d?)
      'diff': {'path': d.path, 'oldText': ?d.oldText, 'newText': d.newText},
    'toolMeta': ?toolMeta?.toJson(),
    'origin': ?origin,
    'nudge': ?nudge,
    'attempt': ?attempt,
    'command': ?command?.toJson(),
    'message': message.toJson(),
  };
}

/// Модель для следующих шагов (§8.2.4); последняя на ветке выигрывает.
final class ModelChangeRecord extends SessionRecord {
  ModelChangeRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.provider,
    required this.modelId,
    this.baseUrl,
    super.extra,
  });

  final String provider, modelId;
  final String? baseUrl;

  @override
  String get type => 'model_change';

  @override
  Map<String, Object?> get _fields => {
    'provider': provider,
    'modelId': modelId,
    'baseUrl': ?baseUrl,
  };
}

/// Режим сессии (§8.2.4); последняя запись на ветке выигрывает.
final class ModeChangeRecord extends SessionRecord {
  ModeChangeRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.modeId,
    super.extra,
  });

  final String modeId;

  @override
  String get type => 'mode_change';

  @override
  Map<String, Object?> get _fields => {'modeId': modeId};
}

/// Опция конфигурации сессии, кроме режима и модели; пишет этап 4.
final class ConfigChangeRecord extends SessionRecord {
  ConfigChangeRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.optionId,
    required this.value,
    super.extra,
  });

  final String optionId, value;

  @override
  String get type => 'config_change';

  @override
  Map<String, Object?> get _fields => {'optionId': optionId, 'value': value};
}

/// Пункт плана старого формата (запись `plan`).
///
/// Почему не [TaskItem]: запись `plan` больше не пишется, но читается всегда
/// (`agent-core/17-16-task-list.md` §17.16.6, D12), и её JSON должен
/// сохраняться побайтово; поэтому здесь только три поля старого формата.
final class PlanRecordEntry {
  const PlanRecordEntry({
    required this.content,
    required this.priority,
    required this.status,
  });

  final String content;
  final TaskPriority priority;
  final TaskStatus status;
}

/// Запись `plan` старого формата: полный снимок плана после `update_plan`.
///
/// Новые журналы её не пишут (D12); проекция `buildTaskList` превращает
/// последнюю запись в список задач «1»…«n».
final class PlanRecord extends SessionRecord {
  PlanRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required List<PlanRecordEntry> entries,
    super.extra,
  }) : entries = List.unmodifiable(entries);

  final List<PlanRecordEntry> entries;

  @override
  String get type => 'plan';

  @override
  Map<String, Object?> get _fields => {
    'entries': [
      for (final e in entries)
        {
          'content': e.content,
          'priority': e.priority.name,
          'status': e.status.wire,
        },
    ],
  };
}

/// Операция над списком задач (`agent-core/17-16-task-list.md` §17.16.6):
/// одна запись на `TaskListChanged`, кроме `op: restore` (TSK-1).
///
/// [items] — полные снимки изменённых пунктов, [deleted] — удалённые id.
/// Запись служебная: в контекст модели не входит.
final class TaskRecord extends SessionRecord {
  TaskRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.op,
    required this.actor,
    required List<TaskItem> items,
    required List<TaskId> deleted,
    super.extra,
  }) : items = List.unmodifiable(items),
       deleted = List.unmodifiable(deleted);

  final String op;
  final TaskActor actor;
  final List<TaskItem> items;
  final List<TaskId> deleted;

  @override
  String get type => 'task';

  @override
  Map<String, Object?> get _fields => {
    'op': op,
    'actor': actor.wire,
    'items': [for (final item in items) item.toJson()],
    'deleted': deleted,
  };
}

/// Связь вызова `agent` с журналом потомка (`agent-core/17-3-subagents.md`
/// §17.3.6): `running` при получении слота и итоговая запись с отчётом.
///
/// Последняя запись с данным [subagentId] выигрывает. Запись служебная, в
/// контекст модели не входит; итоговая пишется `durable` до
/// `ToolCallFinished(agent)` (SUB-10) — это точка восстановления отчёта после
/// сбоя. [agent] — имя типа (в журнале поле называется так, D28).
final class SubagentRecord extends SessionRecord {
  SubagentRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.subagentId,
    required this.toolCallId,
    required this.agent,
    required this.description,
    this.childSessionId,
    this.journal,
    required this.status,
    this.failure,
    this.report,
    this.usage,
    this.toolCalls,
    this.durationMs,
    super.extra,
  });

  final SubagentId subagentId;
  final String toolCallId, agent, description;

  /// `null` у ребёнка, отменённого в очереди.
  final String? childSessionId, journal;

  /// `running | completed | failed | cancelled`.
  final String status;

  /// `budget_exceeded:` и лимит, `invalid_output`, `error`, `refused`,
  /// `interrupted`.
  final String? failure;

  /// У итоговой записи — тело отчёта после усечения, без обёртки.
  final String? report;
  final Usage? usage;
  final int? toolCalls, durationMs;

  /// Копия записи-шаблона с настоящими `id`, родителем и временем.
  SubagentRecord placed(String id, String? parentId, DateTime timestamp) =>
      SubagentRecord(
        id: id,
        parentId: parentId,
        timestamp: timestamp,
        subagentId: subagentId,
        toolCallId: toolCallId,
        agent: agent,
        description: description,
        childSessionId: childSessionId,
        journal: journal,
        status: status,
        failure: failure,
        report: report,
        usage: usage,
        toolCalls: toolCalls,
        durationMs: durationMs,
        extra: extra,
      );

  @override
  String get type => 'subagent';

  @override
  Map<String, Object?> get _fields => {
    'subagentId': subagentId,
    'toolCallId': toolCallId,
    'agent': agent,
    'description': description,
    'childSessionId': ?childSessionId,
    'journal': ?journal,
    'status': status,
    'failure': ?failure,
    'report': ?report,
    'usage': ?usage?.toJson(),
    'toolCalls': ?toolCalls,
    'durationMs': ?durationMs,
  };
}

/// Сжатие (§9.8): резюме заменяет в контексте записи до [firstKeptId].
final class CompactionRecord extends SessionRecord {
  CompactionRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.summary,
    required this.firstKeptId,
    required this.tokensBefore,
    required this.tokensAfter,
    this.details,
    this.skills,
    super.extra,
  });

  final String summary, firstKeptId;
  final int tokensBefore, tokensAfter;

  /// Прочитанные и изменённые файлы, `splitTurn`, модель резюме.
  final Map<String, Object?>? details;

  /// Активные навыки на момент сжатия: имя и отпечаток без тела, от новой
  /// активации к старой (design.md change `add-agent-skills`, D15, D20).
  /// `null` — поля нет (сессия без активаций, старая запись).
  final List<CompactionSkill>? skills;

  @override
  String get type => 'compaction';

  @override
  Map<String, Object?> get _fields => {
    'summary': summary,
    'firstKeptId': firstKeptId,
    'tokensBefore': tokensBefore,
    'tokensAfter': tokensAfter,
    'details': ?details,
    'skills': ?skills == null
        ? null
        : [for (final skill in skills!) skill.toJson()],
  };
}

/// Элемент `compaction.skills`: имя навыка и SHA-256 hex его тела в снимке
/// каталога. Тела и аргументов команды в записи нет (CMP-2, D15).
///
/// Почему такой тип: журнал можно подложить или испортить, а запись должна
/// переживать чтение и запись без потерь (§8.2.2, как `CommandRef`). Поэтому
/// неизвестные ключи элемента лежат в [extra], а элемент, который не
/// разобрался (не объект, нет строкового `name` или `fingerprint`), хранит
/// исходное значение и пишется обратно как есть (design.md change
/// `add-agent-skills`, D20, LOW (б)).
///
/// Как использовать: `compact` создаёт полные элементы; приложение и
/// `activeSkills` берут только [isValid]. Парсер даёт [tryParseList].
final class CompactionSkill {
  const CompactionSkill({
    required String this.name,
    required String this.fingerprint,
    this.extra = const {},
  }) : _raw = null,
       _isRaw = false;

  const CompactionSkill._raw(Object? raw)
    : name = null,
      fingerprint = null,
      extra = const {},
      _raw = raw,
      _isRaw = true;

  /// Читает один элемент: объект с двумя строковыми полями даёт полный
  /// элемент, всё остальное — «сырой» (пропускается при приложении).
  factory CompactionSkill.fromJson(Object? json) {
    if (json is Map<String, Object?> &&
        json['name'] is String &&
        json['fingerprint'] is String) {
      return CompactionSkill(
        name: json['name']! as String,
        fingerprint: json['fingerprint']! as String,
        extra: Map.unmodifiable({
          for (final e in json.entries)
            if (e.key != 'name' && e.key != 'fingerprint') e.key: e.value,
        }),
      );
    }
    return CompactionSkill._raw(json);
  }

  /// `null`, если [json] — не список: поле тогда остаётся в `extra` записи и
  /// пишется обратно как есть (§8.2.2).
  static List<CompactionSkill>? tryParseList(Object? json) =>
      json is List<Object?>
      ? [for (final item in json) CompactionSkill.fromJson(item)]
      : null;

  /// Имя навыка; `null` у неразобранного элемента.
  final String? name;

  /// SHA-256 hex тела снимка; `null` у неразобранного элемента.
  final String? fingerprint;

  /// Неизвестные ключи элемента.
  final Map<String, Object?> extra;

  final Object? _raw;
  final bool _isRaw;

  /// Можно ли приложить навык: есть и имя, и отпечаток.
  bool get isValid => !_isRaw;

  Object? toJson() => _isRaw
      ? _raw
      : <String, Object?>{'name': name, 'fingerprint': fingerprint, ...extra};
}

/// Закладка на запись; пустая метка снимает её.
final class LabelRecord extends SessionRecord {
  LabelRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.targetId,
    this.label,
    super.extra,
  });

  final String targetId;
  final String? label;

  @override
  String get type => 'label';

  @override
  Map<String, Object?> get _fields => {'targetId': targetId, 'label': ?label};
}

/// Перемещение активного листа (§8.4, правило 2).
final class LeafRecord extends SessionRecord {
  LeafRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.targetId,
    super.extra,
  });

  final String targetId;

  @override
  String get type => 'leaf';

  @override
  Map<String, Object?> get _fields => {'targetId': targetId};
}

/// Заголовок сессии; последняя запись с непустым [title] выигрывает.
final class SessionInfoRecord extends SessionRecord {
  SessionInfoRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    this.title,
    this.source,
    super.extra,
  });

  final String? title;

  /// `auto` (по умолчанию) или, после MVP, `user`.
  final String? source;

  @override
  String get type => 'session_info';

  @override
  Map<String, Object?> get _fields => {'title': ?title, 'source': ?source};
}

/// Данные хоста или запись неизвестного типа.
///
/// Почему одна запись на оба случая: обе ядро хранит, но не
/// интерпретирует. Неизвестный тип (запись новой версии, например
/// `branch`) сохраняет исходный объект и пишется обратно без изменений
/// (§8.6, шаг 4b).
final class CustomRecord extends SessionRecord {
  CustomRecord({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required this.customType,
    this.data,
    super.extra,
  }) : _raw = null;

  CustomRecord.unknown({
    required super.id,
    required super.parentId,
    required super.timestamp,
    required Map<String, Object?> raw,
  }) : customType = 'unknown:${raw['type']}',
       data = null,
       _raw = Map.unmodifiable(raw);

  /// `unknown:<type>` у записи неизвестного типа.
  final String customType;
  final Object? data;
  final Map<String, Object?>? _raw;

  @override
  String get type => _raw?['type']! as String? ?? 'custom';

  @override
  Map<String, Object?> get _fields => {'customType': customType, 'data': data};

  @override
  Map<String, Object?> toJson() => _raw ?? super.toJson();
}

PlanRecordEntry _planEntry(Map<String, Object?> json) => PlanRecordEntry(
  content: _string(json, 'content'),
  priority:
      TaskPriority.values.asNameMap()[json['priority']] ?? TaskPriority.medium,
  status: TaskStatus.fromWire(json['status']) ?? TaskStatus.pending,
);

FileDiff _diff(Map<String, Object?> json) => FileDiff(
  path: _string(json, 'path'),
  oldText: json['oldText'] as String?,
  newText: _string(json, 'newText'),
);

Map<String, Object?> _rest(Map<String, Object?> json, Set<String> known) => {
  for (final MapEntry(:key, :value) in json.entries)
    if (!known.contains(key)) key: value,
};

String _string(Map<String, Object?> json, String key) => switch (json[key]) {
  final String value => value,
  final value => throw FormatException('"$key" must be a string, got $value'),
};

int _int(Map<String, Object?> json, String key) => switch (json[key]) {
  final int value => value,
  final value => throw FormatException('"$key" must be an int, got $value'),
};

Map<String, Object?> _object(Map<String, Object?> json, String key) =>
    switch (json[key]) {
      final Map<String, Object?> value => value,
      final value => throw FormatException(
        '"$key" must be an object, got $value',
      ),
    };
