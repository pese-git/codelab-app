import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Поле `UsageLedgerGroup.discarded` — число отброшенных вызовов
/// суммаризатора в группе `summaries` (change `fix-discarded-compaction-usage`,
/// D3, Q2 (а)).
///
/// Красная фаза (задача 1.1): файл не компилируется, пока в `lib/` нет
/// `UsageLedgerGroup.discarded` (задача 1.3). Остальная свёртка записи учёта —
/// в `usage_ledger_test.dart`, без новых имён.
void main() {
  final at = DateTime.utc(2026, 11, 17);
  final id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  final model = ModelRef(
    provider: 'openai',
    id: 'gpt-4o',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: 32000,
    maxOutputTokens: 4096,
  );

  CompactionRecord written(String recordId, String? parent) => CompactionRecord(
    id: recordId,
    parentId: parent,
    timestamp: at,
    summary: 's',
    firstKeptId: 'r0',
    tokensBefore: 1000,
    tokensAfter: 100,
    details: {
      'summaryModel': 'openai/gpt-4o-mini',
      'usage': const Usage(input: 900).toJson(),
    },
  );

  CustomRecord discarded(String recordId, String? parent, {Object? data}) =>
      CustomRecord(
        id: recordId,
        parentId: parent,
        timestamp: at,
        customType: 'codelab.compaction_discarded',
        data:
            data ??
            {
              'reason': 'no reduction',
              'usage': const Usage(input: 764, output: 171).toJson(),
              'summaryModel': 'openai/gpt-4o-mini',
            },
      );

  UsageLedger ledgerOf(
    List<SessionRecord Function(String id, String? p)> make,
  ) {
    final records = <SessionRecord>[
      MessageRecord(
        id: 'r0',
        parentId: null,
        timestamp: at,
        message: UserMessage(const [TextContent('task')], timestamp: at),
      ),
      MessageRecord(
        id: 'r1',
        parentId: 'r0',
        timestamp: at,
        message: AssistantMessage(
          content: const [TextContent('ok')],
          model: model,
          usage: const Usage(input: 100),
          stopReason: StopReason.stop,
          timestamp: at,
        ),
      ),
    ];
    for (final (i, build) in make.indexed) {
      records.add(build('r${i + 2}', records.last.id));
    }
    return buildUsageLedger(
      SessionSnapshot(
        header: SessionHeader(
          id: id,
          cwd: '/proj',
          created: at,
          agent: const AgentInfo(name: 'test', version: '0'),
        ),
        records: records,
        leafId: records.last.id,
      ),
    );
  }

  test('a written pass alone: discarded is 0', () {
    final summaries = ledgerOf([written]).summaries!;

    expect(summaries.count, 1);
    expect(summaries.discarded, 0);
  });

  test('a written and a discarded pass: count 2, discarded 1 (scenario '
      '"Записанный и отброшенный проходы")', () {
    final summaries = ledgerOf([written, discarded]).summaries!;

    expect(summaries.count, 2);
    expect(summaries.discarded, 1);
  });

  test('only discarded calls: count equals discarded', () {
    final summaries = ledgerOf([discarded, discarded]).summaries!;

    expect(summaries.count, 2);
    expect(summaries.discarded, 2);
  });

  test('a record of the wrong shape is neither counted nor discarded', () {
    final ledger = ledgerOf([
      written,
      (id, p) => discarded(id, p, data: 'broken'),
    ]);

    expect(ledger.summaries!.count, 1);
    expect(ledger.summaries!.discarded, 0);
  });

  test('the default of the group field is 0 (subagents)', () {
    const group = UsageLedgerGroup(count: 1, usage: Usage.zero);

    expect(group.discarded, 0);
  });
}
