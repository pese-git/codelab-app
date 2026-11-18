import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'server_harness.dart' show JournalStore, scriptedModel;

/// Порт `usage.json` в памяти с управляемыми сбоями (design.md change
/// `add-usage-ledger`, D3).
///
/// Почему: тестам адаптера нужен порт без файловой системы, который можно
/// заставить упасть на записи (статус `notSaved`) или бросить не
/// `UsageLedgerStoreException` (исключение свёртки, `-32603`).
///
/// Как использовать: передать в `ServerHarness.start(usageLedger: …)`;
/// [files] — записанное содержимое по `sessionId`, [writes] и [reads] —
/// счётчики обращений.
final class MemoryUsageLedgerStore implements UsageLedgerStore {
  /// Файлы по `sessionId`.
  final files = <String, String>{};

  var reads = 0;
  var writes = 0;

  /// Если задан, `write` бросает [UsageLedgerStoreException] с этим текстом.
  String? failWrite;

  /// Если задан, `read` бросает эту ошибку как есть: исключение вне контракта
  /// порта — «сбой свёртки», а не «сбой записи».
  Object? failRead;

  /// Если задан, `read` ждёт его завершения: тест держит операцию начатой,
  /// чтобы одновременные запросы журнала пересеклись.
  Completer<void>? readGate;

  @override
  Future<String?> read(SessionId id) async {
    reads++;
    if (readGate case final gate?) {
      await gate.future;
    }
    if (failRead case final error?) {
      throw error;
    }
    return files[id.value];
  }

  @override
  Future<void> write(SessionId id, String content) async {
    writes++;
    if (failWrite case final reason?) {
      throw UsageLedgerStoreException(reason);
    }
    files[id.value] = content;
  }
}

/// Usage с ценами модели 3 / 15 / 0.3 / 3.75 доллара за 10^6 токенов — как у
/// `pricedModel` тестов usage и фикстур `acp/prompt-usage-*`.
Usage pricedUsage(
  int input,
  int output, [
  int cacheRead = 0,
  int cacheWrite = 0,
]) => Usage(
  input: input,
  output: output,
  cacheRead: cacheRead,
  cacheWrite: cacheWrite,
  cost: UsageCost(
    input: input * 3 / 1e6,
    output: output * 15 / 1e6,
    cacheRead: cacheRead * 0.3 / 1e6,
    cacheWrite: cacheWrite * 3.75 / 1e6,
  ),
);

/// Журнал сессии, собранный записями (а не прогоном сервера): так проверяется
/// именно загрузка и свёртка, а не цикл (agent-acp-server «Полная сумма
/// сессии после session/load»; design.md change `add-usage-ledger`, D1, D8).
///
/// Как использовать: вызвать `user`/`assistant`/…, затем [seedInto] в
/// хранилище сервера до `session/load`. Id записей — `r001`, `r002`, …
final class UsageJournal {
  UsageJournal(this.sessionId, {this.cwd = '/work/demo'});

  final SessionId sessionId;
  final String cwd;
  final at = DateTime.utc(2026, 11, 17);
  final records = <SessionRecord>[];

  String _id() => 'r${(records.length + 1).toString().padLeft(3, '0')}';

  String? get _parent => records.isEmpty ? null : records.last.id;

  /// Id последней записи.
  String get lastId => records.last.id;

  void user(String text) => records.add(
    MessageRecord(
      id: _id(),
      parentId: _parent,
      timestamp: at,
      message: UserMessage([TextContent(text)], timestamp: at),
    ),
  );

  /// Служебная запись `user` с [origin] (например `subagent_notice`): ход она
  /// не открывает (D1 п. 3, Q9) и сливается с предыдущим (R2).
  void serviceUser(String text, {String origin = 'subagent_notice'}) =>
      records.add(
        MessageRecord(
          id: _id(),
          parentId: _parent,
          timestamp: at,
          origin: origin,
          message: UserMessage([TextContent(text)], timestamp: at),
        ),
      );

  /// Ответ модели `scripted/scripted-1` с [usage]; [calls] — вызовы
  /// инструментов `agent` (id вызова).
  void assistant(String text, Usage usage, {List<String> calls = const []}) =>
      records.add(
        MessageRecord(
          id: _id(),
          parentId: _parent,
          timestamp: at,
          message: AssistantMessage(
            content: [
              TextContent(text),
              for (final id in calls)
                ToolCall(
                  id: id,
                  name: 'agent',
                  arguments: const {
                    'type': 'explore',
                    'description': 'Find auth code',
                    'prompt': 'Find where authentication is implemented.',
                  },
                ),
            ],
            model: scriptedModel,
            usage: usage,
            stopReason: calls.isEmpty ? StopReason.stop : StopReason.toolUse,
            timestamp: at,
          ),
        ),
      );

  /// Ответ модели с вызовом `read` [callId] и результатом вызова: шаг с
  /// `toolCallIds`, как в живой сессии.
  void toolStep(String callId, Usage usage) {
    records
      ..add(
        MessageRecord(
          id: _id(),
          parentId: _parent,
          timestamp: at,
          message: AssistantMessage(
            content: [
              ToolCall(
                id: callId,
                name: 'read',
                arguments: const {'path': 'lib/a.dart'},
              ),
            ],
            model: scriptedModel,
            usage: usage,
            stopReason: StopReason.toolUse,
            timestamp: at,
          ),
        ),
      )
      ..add(
        MessageRecord(
          id: _id(),
          parentId: _parent,
          timestamp: at,
          message: ToolResultMessage(
            toolCallId: callId,
            toolName: 'read',
            content: const [TextContent('ok')],
            isError: false,
            timestamp: at,
          ),
        ),
      );
  }

  /// Две записи `subagent` (`running`, затем `completed` с итоговым [usage])
  /// и результат вызова `agent` [callId].
  void subagent(
    String callId,
    Usage usage, {
    String subagentId = 'sub_k3f9a1c2',
  }) {
    for (final status in ['running', 'completed']) {
      records.add(
        SessionRecord.fromJson({
          'type': 'subagent',
          'id': _id(),
          'parentId': _parent,
          'timestamp': at.toIso8601String(),
          'subagentId': subagentId,
          'toolCallId': callId,
          'agent': 'explore',
          'description': 'Find auth code',
          'status': status,
          if (status == 'completed') ...{
            'report': 'Auth is in lib/auth/session.dart.',
            'usage': usage.toJson(),
            'toolCalls': 2,
            'durationMs': 1000,
          },
        }),
      );
    }
    records.add(
      MessageRecord(
        id: _id(),
        parentId: _parent,
        timestamp: at,
        outcome: 'completed',
        toolMeta: ToolMeta(
          title: 'Subagent explore: Find auth code',
          kind: ToolKind.think,
        ),
        message: ToolResultMessage(
          toolCallId: callId,
          toolName: 'agent',
          content: [
            TextContent(
              '<subagent-report agent="explore" status="completed">\n'
              'Auth is in lib/auth/session.dart.\n'
              '</subagent-report>',
            ),
          ],
          isError: false,
          timestamp: at,
        ),
      ),
    );
  }

  /// Сжатие с usage суммаризатора (§8.2.4, `details.usage`); [firstKeptId] —
  /// первая сохранённая запись.
  void compaction(String firstKeptId, Usage usage) => records.add(
    CompactionRecord(
      id: _id(),
      parentId: _parent,
      timestamp: at,
      summary: 'The user asked three questions.',
      firstKeptId: firstKeptId,
      tokensBefore: 3000,
      tokensAfter: 300,
      details: {
        'splitTurn': false,
        'summaryModel': 'scripted/scripted-1',
        'usage': usage.toJson(),
      },
    ),
  );

  /// Служебная запись учёта отброшенного прохода сжатия (CMP-13; design.md
  /// change `fix-discarded-compaction-usage`, D1): суммаризатор оплачен, а
  /// записи `compaction` нет. Форма `data` — как у компактора.
  void discarded(
    Usage usage, {
    String reason = 'no reduction',
    int tokensBefore = 3000,
    int tokensAfter = 3100,
  }) => records.add(
    CustomRecord(
      id: _id(),
      parentId: _parent,
      timestamp: at,
      // Литерал, а не константа ядра: тест фиксирует формат записи на диске
      // независимо от того, экспортирует ли барель ядра эту константу.
      customType: 'codelab.compaction_discarded',
      data: {
        'reason': reason,
        'trigger': 'manual',
        'pass': 1,
        'tokensBefore': tokensBefore,
        'tokensAfter': tokensAfter,
        'summaryModel': 'scripted/scripted-1',
        'usage': usage.toJson(),
      },
    ),
  );

  /// Журнал целиком одним снимком (для `JournalStore.prebuilt`).
  SessionSnapshot snapshot() => SessionSnapshot(
    header: _header(),
    records: records,
    leafId: records.isEmpty ? null : records.last.id,
  );

  SessionHeader _header() => SessionHeader(
    id: sessionId,
    cwd: cwd,
    created: at,
    agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
  );

  /// Кладёт заголовок и записи в [store], как их оставил бы прежний сервер.
  Future<void> seedInto(JournalStore store) async {
    await store.create(_header());
    for (final record in records) {
      await store.append(sessionId, record);
    }
  }
}
