// Тесты задачи 3.3 change `add-desktop-localization`: панель Agents на русском
// и её пункт в палитре (spec app-settings «Локализация интерфейса app»;
// agent-workbench-ui «Панель Agents v1»; design.md D4, D5).
//
// Строки панели («Субагенты», «Шаги», счётчики, статусы) — словари кита и
// переведены итерацией 2, поэтому первая проверка зелёная и служит защитой
// от регрессии. Красный — пункт палитры `Agents`: его подпись и описание
// строит app по `id` (D4, задача 3.4). Описание субагента и его отчёт —
// данные агента, они не переводятся (D7).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/live_scene.dart';

Map<String, Object?> _subagentCall() => {
  'sessionUpdate': 'tool_call',
  'toolCallId': 'call_1',
  'title': 'Subagent explore: Find auth code',
  'kind': 'think',
  'status': 'in_progress',
  'rawInput': {'type': 'explore', 'description': 'Find auth code'},
  '_meta': {
    'codelab': {
      'subagent': {'id': 'sub_a1', 'type': 'explore'},
    },
  },
};

void main() {
  testWidgets('панель Agents на русском; описание субагента как есть', (
    tester,
  ) async {
    final scene = await LiveScene.open(tester, locale: const Locale('ru'));
    await scene.newSession('s1');
    await scene.prompt('explore');
    await scene.update('s1', _subagentCall());
    scene.cubit.openPane(ToolPane.agents);
    await scene.flush();

    final pane = scene.textOf(
      find.byKey(CodeLabToolDock.paneKey(ToolPane.agents)),
    );
    expect(pane, contains('Субагенты'));
    expect(pane, contains('1 выполняется'));
    expect(pane, contains('Find auth code'));

    await scene.close();
  });

  testWidgets('пункт палитры Agents: подпись и описание на русском, команда '
      '/agents не переведена', (tester) async {
    final scene = await LiveScene.open(tester, locale: const Locale('ru'));
    await scene.newSession('s1');
    await scene.prompt('explore');
    await scene.update('s1', _subagentCall());

    final agents = scene.cubit.state.paletteActions.firstWhere(
      (action) => action.id == 'agents',
    );

    expect(agents.label, 'Агенты');
    expect(agents.description, 'Перейти к панели субагентов.');
    expect(agents.slashCommand, '/agents');

    await scene.close();
  });
}
