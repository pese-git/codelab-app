// Список задач в TUI: блок над композером, Ctrl+T и тихая строка операций
// (задача 1.1, «CLI» change `add-subagents-and-tasks`; spec codelab-tui
// «Субагенты и список задач в TUI»; design.md, D26, D27).
//
// Красные тесты: нет `Key.ctrlT` и `KeyAction.toggleTasks`, блока списка в
// `render`, `TaskOpsItem` в строках транскрипта (задачи 1.6a, 1.7). Заголовок
// блока — `Tasks <c>/<n> done · ctrl+t hide` (скрытый — `… · ctrl+t show`),
// строки пунктов — как в REPL.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:dart_tui/dart_tui.dart' as tea;
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 11, 12, 12);
final _sgr = RegExp('\x1b\\[[0-9;]*m');

String _plain(String line) => line.replaceAll(_sgr, '');

const _hide = 'Tasks 2/4 done · ctrl+t hide';
const _show = 'Tasks 2/4 done · ctrl+t show';

const _plan = [
  PlanEntryView(
    content: 'Map callers',
    status: PlanEntryStatus.completed,
    priority: PlanEntryPriority.medium,
    taskId: '1',
  ),
  PlanEntryView(
    content: 'Write tests',
    status: PlanEntryStatus.completed,
    priority: PlanEntryPriority.medium,
    taskId: '2',
  ),
  PlanEntryView(
    content: 'Implement',
    status: PlanEntryStatus.inProgress,
    priority: PlanEntryPriority.medium,
    taskId: '3',
    owner: 'sub_a1',
    ownerLabel: 'explore',
  ),
  PlanEntryView(
    content: 'Ship',
    status: PlanEntryStatus.pending,
    priority: PlanEntryPriority.medium,
    taskId: '4',
    blockedBy: ['3'],
    openBlockers: ['3'],
  ),
];

TuiModel _model({List<PlanEntryView> plan = const []}) {
  final (model, _) = reduce(
    TuiModel.initial(
      profile: 'default',
      size: const TerminalSize(columns: 100, rows: 30),
    ),
    SessionViewMsg(
      SessionView(revision: 1, status: SessionStatusView.idle, plan: plan),
      at: _t0,
    ),
  );
  return model;
}

TuiModel _press(TuiModel model, KeyEvent key) =>
    reduce(model, KeyMsg(key, at: _t0)).$1;

List<String> _frame(TuiModel model) => [
  for (final line in render(
    model,
    TuiChrome(hints: 'Enter send', now: _t0),
  ).lines)
    _plain(line),
];

void main() {
  group('task list block', () {
    test('is not shown before the first plan', () {
      final frame = _frame(_model());

      expect(frame.where((l) => l.startsWith('Tasks ')), isEmpty);
    });

    test('is a header and entry lines above the composer', () {
      var model = _model(plan: _plan);
      model = _press(model, const TextKey('draft'));

      final frame = _frame(model);
      final header = frame.indexOf(_hide);
      final composer = frame.indexWhere((l) => l.contains('> draft'));
      expect(header, isNonNegative);
      expect(composer, greaterThan(header));
      expect(frame.sublist(header + 1, composer).map((l) => l.trim()), [
        '#1 [completed] Map callers',
        '#2 [completed] Write tests',
        '#3 [in_progress] Implement (explore)',
        '#4 [pending] Ship (blocked by #3)',
      ]);
    });

    test('Ctrl+T hides the block to one line and shows it again; the '
        'composer keeps its text', () {
      var model = _press(_model(plan: _plan), const TextKey('draft'));

      model = _press(model, const SpecialKey(Key.ctrlT));
      var frame = _frame(model);
      expect(frame, contains(_show));
      expect(frame, isNot(contains(_hide)));
      expect(frame.where((l) => l.contains('#1 [completed]')), isEmpty);
      expect(frame.where((l) => l.contains('> draft')), hasLength(1));

      model = _press(model, const SpecialKey(Key.ctrlT));
      frame = _frame(model);
      expect(frame, contains(_hide));
      expect(frame.where((l) => l.contains('#4 [pending]')), hasLength(1));
      expect(frame.where((l) => l.contains('> draft')), hasLength(1));
    });

    test('Ctrl+T works while a turn runs and does not type into the '
        'composer', () {
      final (running, _) = reduce(
        _model(plan: _plan),
        SessionViewMsg(
          const SessionView(
            revision: 2,
            status: SessionStatusView.running,
            plan: _plan,
          ),
          at: _t0,
        ),
      );

      final model = _press(running, const SpecialKey(Key.ctrlT));

      expect(_frame(model), contains(_show));
      expect(model.composer.isEmpty, isTrue);
    });
  });

  group('key table and help line', () {
    test('Ctrl+T is the toggle_tasks action in the TUI table', () {
      final tui = KeyBindings.tui;

      expect(tui.actionFor(Key.ctrlT, running: false), KeyAction.toggleTasks);
      expect(tui.actionFor(Key.ctrlT, running: true), KeyAction.toggleTasks);
      expect(tui.helpLines().join('\n'), contains('Ctrl+T'));
    });

    test('the help line contains ctrl+t tasks', () {
      final help = tea.HelpModel.fromKeyMap(
        RegistryKeyMap(),
        title: '',
        styles: const tea.HelpStyles(),
      );

      // Подпись клавиши берётся из `Key.label` (`Ctrl+T`); сравнение без
      // учёта регистра, чтобы тест не диктовал написание метки.
      expect(hintLine(help).toLowerCase(), contains('ctrl+t tasks'));
    });
  });

  group('transcript lines', () {
    final layout = TranscriptLayout();

    List<String> lines(List<TranscriptItem> items, {bool unicode = true}) =>
        layout.lines(
          SessionView(
            revision: 1,
            status: SessionStatusView.idle,
            transcript: items,
          ),
          width: 80,
          unicode: unicode,
        );

    test('the plan block of the transcript uses the REPL format', () {
      final planLines = TranscriptLayout.planLines(_plan).map(_plain).toList();

      expect(
        planLines,
        containsAll(<String>[
          '  #1 [completed] Map callers',
          '  #3 [in_progress] Implement (explore)',
          '  #4 [pending] Ship (blocked by #3)',
        ]),
      );
    });

    test('TaskOpsItem is one dim line with the kit text, without a frame '
        'and a status', () {
      final result = lines(const [
        TaskOpsItem(id: 'ops-1', added: ['1', '2', '3', '4']),
      ]);

      expect(result, hasLength(1));
      expect(_plain(result.single), contains('Tasks #1–#4 added to the plan'));
      expect(result.single, startsWith('\x1b[2m'));
      expect(_plain(result.single), isNot(anyOf(contains('✓'), contains('✗'))));
      expect(_plain(result.single), isNot(contains('│')));
    });

    test('control characters in the kit text are removed (TUI-11)', () {
      // Текст kit строится из id пунктов, пришедших от агента.
      final result = lines(const [
        TaskOpsItem(id: 'ops-1', added: ['1\x1b[31m']),
      ]);

      expect(result.single.replaceAll(_sgr, ''), isNot(contains('\x1b')));
    });
  });
}
