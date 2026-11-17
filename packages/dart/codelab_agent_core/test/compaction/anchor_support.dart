import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// Стенд тестов якоря сжатия (design.md change
/// `anchor-context-estimate-after-compaction`, D1–D5, D8; CMP-11).
///
/// Почему отдельный файл: все сценарии рантайма (afterTurn, загрузка,
/// навыки, смена схем, отмена и ошибка суммаризатора) строятся на одном
/// риге: большой `AGENTS.md` делает эвристику постоянной части (промпт и
/// схемы) заметно выше «настоящей», а usage шагов — ниже эвристики, поэтому
/// `tokensAfter` записи сжатия отличается от эвристики проекции после
/// сжатия — именно на этой разнице красные тесты и различают якорь сжатия
/// от чистой эвристики.
///
/// Как использовать: [anchorHarness] собирает ядро с окном 8192, резервом
/// 1024 и длинным `AGENTS.md`; [turn] — шаг ответа с usage; [summaryRequests]
/// выделяет запросы суммаризатора.
const anchorWindow = 8192;

/// Сжатие: порог `anchorWindow - 1024`, хвост — один последний ход.
const anchorCompaction = CompactionOverrides(
  reserveTokens: 1024,
  keepRecentTokens: 1500,
  keepRecentUserTurns: 1,
  contextWindowCap: anchorWindow,
);

/// Ответ текстом с usage провайдера.
Map<String, Object?> turn(String text, {int input = 0, int output = 20}) => {
  'reply': [
    {'text': text},
  ],
  if (input > 0 || output > 0) 'usage': {'input': input, 'output': output},
};

/// Рантайм с большим `AGENTS.md` (эвристика постоянной части выше реальной).
CoreHarness anchorHarness(
  List<Map<String, Object?>> steps, {
  SessionStore? sessions,
  int agentsChars = 16000,
  CompactionOverrides compaction = anchorCompaction,
}) => CoreHarness.build(
  baseEnv: MemoryExecutionEnv(cwd: '/proj'),
  narrow: noExec,
  gate: FakeGate(),
  sessions: sessions,
  defaultModel: modelWithWindow(16384),
  compaction: compaction,
  projectFiles: AnchorAgents(agentsChars),
  steps: steps,
);

/// Первый `ModelRequested` хода с номером [turn] (с 0) среди событий
/// сессии: событие несёт оценку, которую видел `preflight` (CMP-11); `null`,
/// если ход не дошёл до запроса.
ModelRequested? firstRequestOfTurn(List<AgentEvent> events, int turn) {
  var started = -1;
  for (final e in events) {
    if (e is TurnStarted) started++;
    if (e is ModelRequested && started == turn) return e;
  }
  return null;
}

/// Запросы суммаризатора среди запросов модели.
List<LlmContext> summaryRequests(CoreHarness h) => [
  for (final r in h.model.requests)
    if (r.cacheKey?.endsWith(':summary') ?? false) r,
];

/// Эвристика запроса без якорей — то, что видел бы оценщик без якоря сжатия.
int heuristicOf(LlmContext c) =>
    estimateTokens(c.messages, systemPrompt: c.systemPrompt, tools: c.tools);

/// Источник файлов проекта с одним длинным `AGENTS.md` из [chars] символов.
final class AnchorAgents implements ProjectFilesSource {
  AnchorAgents(int chars)
    : file = ContextFile(path: 'AGENTS.md', content: 'p' * chars);

  final ContextFile file;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(context: [file]);
}
