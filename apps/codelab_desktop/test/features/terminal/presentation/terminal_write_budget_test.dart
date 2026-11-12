// Бюджет времени на кадр у объекта сброса буферов терминала (задача 2.7 change
// `add-integrated-terminal`; spec `integrated-terminal` «Содержимое терминала
// не покидает экран»; design.md D3 «Запись в эмулятор порциями», D15 «Рывки на
// Flood»).
//
// Тест красный до задачи 2.8: у `TerminalOutputFlusher` нет параметров `clock`
// и `frameBudget`, нет константы `terminalFrameBudget`, а сброс за кадр не
// ограничен временем. Ожидаемый API фиксируют эти тесты:
//
// * `terminalFrameBudget` = 8 мс — значение по умолчанию бюджета кадра, рядом
//   с объектом сброса; размер части — `terminalWriteChunkSize` (4 КБ) у Cubit;
// * `TerminalOutputFlusher({cubit, binding, Duration Function() clock,
//   Duration frameBudget = terminalFrameBudget})`: на кадре пишет части, пока
//   `clock() - начало кадра < frameBudget`; хотя бы одна часть за кадр
//   записывается всегда (прогресс при дорогой записи); остаток — на
//   следующий кадр.
//
// Время — fake: «стоимость» записи двигает fake-часы внутри `write` модели.
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:codelab_desktop/features/terminal/presentation/terminal_output_flusher.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/ui.dart' show TerminalView;
import 'package:xterm2_core/xterm2_core.dart' show Terminal;

import '../../../support/fake_client_workspace.dart';
import '../../../support/fake_user_shell_launcher.dart';
import '../../../support/recording_logger.dart';

const _profile = ConnectionProfile.stdio(id: 'p1', label: 'One', command: 'a');
final _session = SessionId('s1');

const _chunk = 1024;

/// Модель, у которой `write` «стоит» время: двигает fake-часы теста.
final class _CostlyTerminal extends Terminal {
  _CostlyTerminal({required this.onWrite, super.onOutput, super.onResize})
    : super(maxLines: 10000);

  final void Function(String data) onWrite;

  @override
  void write(String data) {
    onWrite(data);
    super.write(data);
  }
}

/// Двойник планировщика: считает заказы кадра и отмены (как в 2.5).
final class _CountingScheduler extends Fake implements SchedulerBinding {
  final List<FrameCallback> callbacks = [];
  final List<int> cancelled = [];
  int frameRequests = 0;

  @override
  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
    bool scheduleNewFrame = true,
  }) {
    callbacks.add(callback);
    return callbacks.length;
  }

  @override
  void scheduleFrame() => frameRequests++;

  @override
  void cancelFrameCallbackWithId(int id) => cancelled.add(id);
}

void main() {
  late FakeClientWorkspace workspace;
  late FakeUserShellLauncher launcher;
  late TerminalTabsCubit cubit;
  late Duration now;
  // Записанные части по моделям в порядке создания вкладок.
  late List<List<String>> parts;
  var cost = const Duration(milliseconds: 3);

  Duration clock() => now;

  setUp(() {
    now = Duration.zero;
    cost = const Duration(milliseconds: 3);
    parts = [];
    workspace = FakeClientWorkspace();
    launcher = FakeUserShellLauncher();
    cubit = TerminalTabsCubit(
      workspace: workspace,
      launcher: launcher,
      directoryExists: (_) async => true,
      logger: RecordingLogger(),
      modelFactory: ({required onOutput, onResize}) {
        final list = <String>[];
        parts.add(list);
        return _CostlyTerminal(
          onWrite: (data) {
            list.add(data);
            now += cost;
          },
          onOutput: onOutput,
          onResize: onResize == null ? null : (w, h, _, _) => onResize(w, h),
        );
      },
      writeChunkSize: _chunk,
    );
    workspace.openSession(_profile, _session);
  });

  tearDown(() async {
    await cubit.close();
    await workspace.close();
  });

  Future<FakeUserShell> openTab(WidgetTester tester) async {
    await tester.runAsync(cubit.newTab);
    return launcher.shells.last;
  }

  int written(int tab) => parts[tab].length;

  Future<void> emit(WidgetTester tester, FakeUserShell shell, String data) {
    shell.emit(data);
    return tester.idle();
  }

  /// Ждёт ли вид перерисовки: `RenderTerminal` на запись в модель помечает
  /// себя на раскладку (число строк изменилось) или на отрисовку. Проверять надо вне кадра (после колбэка сброса, до `pump`):
  /// внутри `pump` перерисовка сразу выполняется.
  bool viewNeedsPaint(WidgetTester tester) {
    // `renderObject` элемента `TerminalView` — внешняя обёртка; нужен сам
    // `RenderTerminal` (класс не экспортируется, ищем по имени).
    final view = tester.allRenderObjects.singleWhere(
      (r) => r.runtimeType.toString() == 'RenderTerminal',
    );
    return view.debugNeedsLayout || view.debugNeedsPaint;
  }

  test('значения по умолчанию: бюджет 8 мс, часть 4 КБ (D3)', () {
    expect(terminalFrameBudget, const Duration(milliseconds: 8));
    expect(terminalWriteChunkSize, 4096);
  });

  group('бюджет времени на кадр (D3, D15)', () {
    testWidgets('за кадр пишется столько частей, сколько укладывается в '
        'бюджет; остаток уходит на следующий кадр', (tester) async {
      final flusher = TerminalOutputFlusher(
        cubit: cubit,
        clock: clock,
        frameBudget: const Duration(milliseconds: 8),
      );
      addTearDown(flusher.dispose);
      final shell = await openTab(tester);

      // 10 частей по 3 мс при бюджете 8 мс: 0, 3, 6 мс — три части, на 9 мс
      // кадр заканчивается.
      await emit(tester, shell, 'x' * (10 * _chunk));
      await tester.pump();
      expect(written(0), 3);
      await tester.pump();
      expect(written(0), 6);
      await tester.pump();
      expect(written(0), 9);
      await tester.pump();
      expect(written(0), 10);
      expect(cubit.hasPendingOutput, isFalse);
    });

    testWidgets('дорогая запись: хотя бы одна часть за кадр, остальное '
        'позже', (tester) async {
      cost = const Duration(milliseconds: 20);
      final flusher = TerminalOutputFlusher(
        cubit: cubit,
        clock: clock,
        frameBudget: const Duration(milliseconds: 8),
      );
      addTearDown(flusher.dispose);
      final shell = await openTab(tester);

      await emit(tester, shell, 'x' * (3 * _chunk));
      await tester.pump();
      expect(written(0), 1);
      await tester.pump();
      await tester.pump();
      expect(written(0), 3);
    });

    testWidgets('часть не больше заданного размера, порядок и полнота '
        'данных сохраняются', (tester) async {
      final flusher = TerminalOutputFlusher(
        cubit: cubit,
        clock: clock,
        frameBudget: const Duration(milliseconds: 8),
      );
      addTearDown(flusher.dispose);
      final shell = await openTab(tester);
      final payload = [
        for (var i = 0; i < 5000; i++) String.fromCharCode(65 + i % 26),
      ].join();

      // Несколько чанков разной длины: границы чанков и частей не совпадают.
      await emit(tester, shell, payload.substring(0, 1500));
      await emit(tester, shell, payload.substring(1500, 1600));
      await emit(tester, shell, payload.substring(1600));
      for (var i = 0; i < 10 && cubit.hasPendingOutput; i++) {
        await tester.pump();
      }

      expect(parts[0].every((p) => p.isNotEmpty && p.length <= _chunk), isTrue);
      expect(parts[0].join(), payload);
    });
  });

  group('перерисовка и фоновые вкладки (D3)', () {
    Future<void> pumpView(WidgetTester tester) async {
      final model = cubit.terminalOf(cubit.state.activeTabId!)!;
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 600,
            height: 300,
            child: TerminalView(model, key: ValueKey(cubit.state.activeTabId)),
          ),
        ),
      );
    }

    testWidgets('несколько частей за кадр дают одну перерисовку вида и один '
        'заказ кадра, а вкладка без отрисовки пишет в модель без '
        'перерисовки', (tester) async {
      // Колбэки кадра вызываем сами (двойник планировщика), чтобы смотреть на
      // вид между записью и перерисовкой.
      final scheduler = _CountingScheduler();
      final flusher = TerminalOutputFlusher(
        cubit: cubit,
        binding: scheduler,
        clock: clock,
        frameBudget: const Duration(milliseconds: 8),
      );
      addTearDown(flusher.dispose);
      final shell = await openTab(tester);
      await tester.runAsync(cubit.newTab);
      final background = launcher.shells.last;
      // Вид у первой вкладки; вторая — фоновая, без `TerminalView`.
      cubit.selectTab(cubit.state.tabs.first.id);
      await pumpView(tester);
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);
      expect(viewNeedsPaint(tester), isFalse);

      // Вывод фоновой вкладки: данные в модели есть, вид не помечен.
      await emit(tester, background, 'b' * (2 * _chunk));
      scheduler.callbacks.last(Duration.zero);
      expect(written(1), 2);
      expect(parts[1].join(), 'b' * (2 * _chunk));
      expect(viewNeedsPaint(tester), isFalse);
      await tester.pump();

      // Три части активной вкладки (3 x 3 мс < 8 мс) за один кадр: вид ждёт
      // перерисовки, а кадр заказан ровно один раз.
      final callbacksBefore = scheduler.callbacks.length;
      final requestsBefore = scheduler.frameRequests;
      await emit(tester, shell, 'a' * (3 * _chunk));
      expect(scheduler.callbacks.length, callbacksBefore + 1);
      expect(scheduler.frameRequests, requestsBefore + 1);
      scheduler.callbacks.last(Duration.zero);
      expect(written(0), 3);
      expect(viewNeedsPaint(tester), isTrue);
      expect(scheduler.callbacks.length, callbacksBefore + 1);
      expect(scheduler.frameRequests, requestsBefore + 1);

      await tester.pump();
      expect(viewNeedsPaint(tester), isFalse);
    });
  });

  group('заказ кадра и закрытие (D3)', () {
    testWidgets('непустой буфер заказывает кадр, пустой — нет; закрытие '
        'отменяет заказанный обратный вызов', (tester) async {
      final scheduler = _CountingScheduler();
      final flusher = TerminalOutputFlusher(
        cubit: cubit,
        binding: scheduler,
        clock: clock,
        frameBudget: const Duration(milliseconds: 8),
      );
      final shell = await openTab(tester);
      expect(scheduler.callbacks, isEmpty);
      expect(scheduler.frameRequests, 0);

      await emit(tester, shell, 'x' * (10 * _chunk));
      expect(scheduler.callbacks, hasLength(1));
      expect(scheduler.frameRequests, 1);

      // Кадр записал три части; остаток заказывает следующий кадр.
      scheduler.callbacks.last(Duration.zero);
      expect(written(0), 3);
      expect(scheduler.callbacks, hasLength(2));
      expect(scheduler.frameRequests, 2);

      flusher.dispose();
      expect(scheduler.cancelled, [2]);
      // После закрытия вывод кадр не заказывает.
      await emit(tester, shell, 'y');
      expect(scheduler.callbacks, hasLength(2));
    });

    testWidgets('опустошив буфер, кадр больше не заказывается', (tester) async {
      final scheduler = _CountingScheduler();
      final flusher = TerminalOutputFlusher(
        cubit: cubit,
        binding: scheduler,
        clock: clock,
        frameBudget: const Duration(milliseconds: 8),
      );
      addTearDown(flusher.dispose);
      final shell = await openTab(tester);

      await emit(tester, shell, 'x' * (2 * _chunk));
      scheduler.callbacks.last(Duration.zero);

      expect(cubit.hasPendingOutput, isFalse);
      expect(scheduler.callbacks, hasLength(1));
    });
  });
}
