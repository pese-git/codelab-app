import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'subagent_rig.dart';

/// Порог окна модели для `agent` (design.md change `add-subagents-and-tasks`,
/// D40; agent-runtime «Малое окно — нет agent», agent-subagents «Смена модели
/// на малое окно»): видимость схемы пересчитывается при смене модели и при
/// перезагрузке `compaction.context_window_cap`; вызов `agent` в истории и
/// работающие дети остаются.
void main() {
  ModelRef model(String id, int window) => ModelRef(
    provider: 'test',
    id: id,
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: window,
    maxOutputTokens: 4096,
  );

  final big = model('big', 131072);
  final small = model('small', 8192);

  group('смена модели', () {
    test('128k → 8192 → 128k: схемы agent есть, нет, есть; лог перехода; '
        'вызов agent остаётся в истории', () async {
      final rig = SubagentRig(
        config: CoreConfig(defaultModel: big),
        models: FixedModelCatalog([big, small]),
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('kid job')),
            replyStep('first'),
            replyStep('second'),
            replyStep('third'),
          ],
          'kid job': [replyStep('kid report')],
        },
      );
      await rig.open();

      await rig.run('go');
      await rig.session.setModel(const ModelId('test/small'));
      await rig.run('again');
      await rig.session.setModel(const ModelId('test/big'));
      await rig.run('once more');

      final requests = rig.requestsOf('go');
      expect(toolNamesOf(requests[0]), contains('agent'));
      expect(toolNamesOf(requests[2]), isNot(contains('agent')));
      expect(toolNamesOf(requests[3]), contains('agent'));
      // Вызов agent прошлого хода остаётся в истории малого окна.
      expect(
        requests[2].messages.whereType<AssistantMessage>().any(
          (m) => m.toolCalls.any((c) => c.name == 'agent'),
        ),
        isTrue,
      );
      final unavailable = rig.logger.eventsOf('subagent.unavailable').single;
      expect(unavailable.fields['session_id'], rig.session.id.value);
      expect(unavailable.fields['reason'], 'context_window');
      expect(unavailable.fields['window'], 8192);
      expect(unavailable.fields['min_window'], 32768);
      final available = rig.logger.eventsOf('subagent.available').single;
      expect(available.fields['session_id'], rig.session.id.value);
      expect(available.fields['window'], 131072);
      expect(available.fields['min_window'], 32768);
    });
  });

  group('compaction.context_window_cap', () {
    test('малое окно через cap скрывает agent, подъём возвращает; лог '
        'с window 8192', () async {
      final source = LayeredConfigSource();
      final rig = SubagentRig(
        source: source,
        scripts: {
          'go': [replyStep('1'), replyStep('2'), replyStep('3')],
        },
      );
      await rig.open();
      await rig.run('go');

      source.user['compaction'] = {'context_window_cap': 8192};
      await rig.core.runtime.reloadConfig();
      await rig.run('again');
      source.user['compaction'] = {'context_window_cap': 65536};
      await rig.core.runtime.reloadConfig();
      await rig.run('once more');

      final requests = rig.requestsOf('go');
      expect(toolNamesOf(requests[0]), contains('agent'));
      expect(toolNamesOf(requests[1]), isNot(contains('agent')));
      expect(toolNamesOf(requests[2]), contains('agent'));
      final unavailable = rig.logger.eventsOf('subagent.unavailable').single;
      expect(unavailable.fields['reason'], 'context_window');
      expect(unavailable.fields['window'], 8192);
      expect(unavailable.fields['min_window'], 32768);
      expect(rig.logger.eventsOf('subagent.available'), hasLength(1));
    });
  });
}
