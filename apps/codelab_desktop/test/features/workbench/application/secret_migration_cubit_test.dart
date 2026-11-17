// `SecretMigrationCubit` (задача 4.2 change
// `add-config-literal-secrets-and-migrate`; agent-workbench-ui «Перенос
// секретов встроенного агента»; design.md D8).
//
// Тесты идут на фейке порта `SecretMigrationRunner`: проверяются переходы
// автомата и отбрасывание позднего результата, а не файловая работа движка.

import 'dart:async';

import 'package:codelab_desktop/features/workbench/application/secret_migration_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/secret_migration_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_logger.dart';

/// Фейк порта: каждый вызов ждёт [Completer], чтобы тест управлял порядком
/// завершений.
final class _FakeRunner implements SecretMigrationRunner {
  final planCalls = <String>[];
  final applyCalls = <String>[];
  var planCompleters = <Completer<SecretMigrationOutcome>>[];
  var applyCompleters = <Completer<SecretMigrationOutcome>>[];

  @override
  Future<SecretMigrationOutcome> plan(String cwd) {
    planCalls.add(cwd);
    final completer = Completer<SecretMigrationOutcome>();
    planCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<SecretMigrationOutcome> apply(String cwd) {
    applyCalls.add(cwd);
    final completer = Completer<SecretMigrationOutcome>();
    applyCompleters.add(completer);
    return completer.future;
  }
}

const _items = ['providers.openai.api_key -> api_key_secret: codelab/openai'];

SecretMigrationOutcome _ok({
  List<String> items = _items,
  bool canApply = true,
  bool readOnlyBackend = false,
  bool nameConflict = false,
  bool onlyExtraLayerFindings = false,
  String? problem,
  bool movedAny = false,
  int exitCode = 0,
  String? backendId,
}) => SecretMigrationOutcome(
  items: items,
  canApply: canApply,
  readOnlyBackend: readOnlyBackend,
  nameConflict: nameConflict,
  onlyExtraLayerFindings: onlyExtraLayerFindings,
  problem: problem,
  movedAny: movedAny,
  exitCode: exitCode,
  backendId: backendId,
);

void main() {
  late _FakeRunner runner;
  late StreamController<bool> turns;
  late SecretMigrationCubit cubit;
  late List<SecretMigrationState> states;

  setUp(() {
    runner = _FakeRunner();
    turns = StreamController<bool>.broadcast(sync: true);
    cubit = SecretMigrationCubit(runner: runner, turnActivity: turns.stream);
    states = [];
    cubit.stream.listen(states.add);
  });

  tearDown(() async {
    await cubit.close();
    await turns.close();
  });

  test('начальное состояние hidden; setOffered(cwd) даёт offered', () {
    expect(cubit.state, isA<SecretMigrationHidden>());
    cubit.setOffered('/work/app');
    expect(cubit.state, isA<SecretMigrationOffered>());
  });

  test('setOffered(null) и dismiss скрывают предупреждение', () {
    cubit.setOffered('/work/app');
    cubit.dismiss();
    expect(cubit.state, isA<SecretMigrationHidden>());
    cubit.setOffered('/work/app');
    cubit.setOffered(null);
    expect(cubit.state, isA<SecretMigrationHidden>());
  });

  test('openPlan вне offered ничего не делает', () {
    cubit.openPlan();
    expect(runner.planCalls, isEmpty);
    expect(cubit.state, isA<SecretMigrationHidden>());
  });

  test('offered -> planning -> planReady с планом, можно применить', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    expect(cubit.state, isA<SecretMigrationPlanning>());
    expect(runner.planCalls, ['/work/app']);

    runner.planCompleters.single.complete(_ok());
    await pumpEventQueue();

    final state = cubit.state as SecretMigrationPlanReady;
    expect(state.items, _items);
    expect(state.canApply, isTrue);
    expect(state.readOnlyBackend, isFalse);
    expect(state.nameConflict, isFalse);
    expect(state.onlyExtraLayerFindings, isFalse);
  });

  test('бэкенд env: только чтение, применить нельзя', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.complete(
      _ok(readOnlyBackend: true, canApply: true),
    );
    await pumpEventQueue();

    final state = cubit.state as SecretMigrationPlanReady;
    expect(state.readOnlyBackend, isTrue);
    expect(state.canApply, isFalse);
    cubit.migrate();
    expect(runner.applyCalls, isEmpty);
    expect(cubit.state, isA<SecretMigrationPlanReady>());
  });

  test('конфликт имени: только Close, применить нельзя', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.complete(_ok(nameConflict: true));
    await pumpEventQueue();

    final state = cubit.state as SecretMigrationPlanReady;
    expect(state.nameConflict, isTrue);
    expect(state.canApply, isFalse);
    cubit.migrate();
    expect(runner.applyCalls, isEmpty);
  });

  test('находки только в CODELAB_CONFIG: только Close', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.complete(_ok(onlyExtraLayerFindings: true));
    await pumpEventQueue();

    final state = cubit.state as SecretMigrationPlanReady;
    expect(state.onlyExtraLayerFindings, isTrue);
    expect(state.canApply, isFalse);
  });

  test('canApply == false от порта сохраняется', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.complete(_ok(canApply: false));
    await pumpEventQueue();

    expect((cubit.state as SecretMigrationPlanReady).canApply, isFalse);
  });

  test('проблема в отчёте плана даёт planFailed с её текстом', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.complete(
      _ok(items: const [], canApply: false, problem: 'config is invalid'),
    );
    await pumpEventQueue();

    expect(
      (cubit.state as SecretMigrationPlanFailed).message,
      'config is invalid',
    );
  });

  test('исключение порта: текст — имя типа, без toString()', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.completeError(
      _LeakyError('sk-test-leak-0123456789'),
    );
    await pumpEventQueue();

    final message = (cubit.state as SecretMigrationPlanFailed).message;
    expect(message, contains('_LeakyError'));
    expect(message, isNot(contains('sk-test-leak-0123456789')));
  });

  test('planFailed -> close возвращает offered', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.completeError(StateError('x'));
    await pumpEventQueue();

    cubit.closeDialog();
    expect(cubit.state, isA<SecretMigrationOffered>());
  });

  test('planReady -> applying -> applied', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.complete(_ok());
    await pumpEventQueue();

    cubit.migrate();
    expect(cubit.state, isA<SecretMigrationApplying>());
    expect(runner.applyCalls, ['/work/app']);

    runner.applyCompleters.single.complete(_ok());
    await pumpEventQueue();

    final state = cubit.state as SecretMigrationApplied;
    expect(state.items, _items);
    expect(state.canRestart, isTrue);
  });

  test('applyFailed: проблема отчёта и исключение порта', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.complete(_ok());
    await pumpEventQueue();
    cubit.migrate();
    runner.applyCompleters.single.complete(
      _ok(canApply: false, problem: 'store write failed'),
    );
    await pumpEventQueue();
    expect(
      (cubit.state as SecretMigrationApplyFailed).message,
      'store write failed',
    );

    cubit.closeDialog();
    cubit.openPlan();
    runner.planCompleters.last.complete(_ok());
    await pumpEventQueue();
    cubit.migrate();
    runner.applyCompleters.last.completeError(
      _LeakyError('sk-test-leak-0123456789'),
    );
    await pumpEventQueue();
    final message = (cubit.state as SecretMigrationApplyFailed).message;
    expect(message, contains('_LeakyError'));
    expect(message, isNot(contains('sk-test-leak-0123456789')));
  });

  test('поздний план после closeDialog отбрасывается', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    cubit.closeDialog();
    expect(cubit.state, isA<SecretMigrationOffered>());

    await pumpEventQueue();
    final before = states.length;
    runner.planCompleters.single.complete(_ok());
    await pumpEventQueue();

    expect(cubit.state, isA<SecretMigrationOffered>());
    expect(states.length, before);
  });

  test('поздний план первой попытки не затирает вторую', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    cubit.closeDialog();
    cubit.openPlan();
    expect(runner.planCompleters, hasLength(2));

    runner.planCompleters.first.complete(_ok(items: const ['stale']));
    await pumpEventQueue();
    expect(cubit.state, isA<SecretMigrationPlanning>());

    runner.planCompleters.last.complete(_ok());
    await pumpEventQueue();
    expect((cubit.state as SecretMigrationPlanReady).items, _items);
  });

  test(
    'closeDialog во время переноса игнорируется; итог показывается',
    () async {
      cubit.setOffered('/work/app');
      cubit.openPlan();
      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();
      cubit.migrate();

      cubit.closeDialog();
      expect(cubit.state, isA<SecretMigrationApplying>());

      runner.applyCompleters.single.complete(_ok());
      await pumpEventQueue();
      expect(cubit.state, isA<SecretMigrationApplied>());
    },
  );

  test('во время переноса смена предложения и openPlan состояние не '
      'трогают, второй apply не стартует', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    runner.planCompleters.single.complete(_ok());
    await pumpEventQueue();
    cubit.migrate();

    cubit.setOffered(null);
    cubit.setOffered('/work/other');
    cubit.dismiss();
    cubit.openPlan();
    cubit.migrate();
    expect(cubit.state, isA<SecretMigrationApplying>());
    expect(runner.applyCalls, hasLength(1));
    expect(runner.planCalls, hasLength(1));

    runner.applyCompleters.single.complete(_ok());
    await pumpEventQueue();
    expect(cubit.state, isA<SecretMigrationApplied>());
  });

  test('план и перенос идут по папке агента из предложения, а не по '
      'текущему проекту', () async {
    cubit.setOffered('/work/agent');
    cubit.openPlan();
    runner.planCompleters.single.complete(_ok());
    await pumpEventQueue();
    cubit.migrate();

    expect(runner.planCalls, ['/work/agent']);
    expect(runner.applyCalls, ['/work/agent']);
  });

  test(
    'Cubit с потоком offered берёт текущее значение первым событием',
    () async {
      final fromStream = SecretMigrationCubit(
        runner: runner,
        turnActivity: const Stream<bool>.empty(),
        offered: Stream.fromIterable(['/work/agent']),
      );
      addTearDown(fromStream.close);
      await pumpEventQueue();

      expect(fromStream.state, isA<SecretMigrationOffered>());
      fromStream.openPlan();
      expect(runner.planCalls, ['/work/agent']);
    },
  );

  group('смена агента во время переноса', () {
    Future<void> startApply() async {
      cubit.setOffered('/work/app');
      cubit.openPlan();
      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();
      cubit.migrate();
    }

    test('агент закрыт и открыт другой: итог показывается, после Close '
        'предложение по новому cwd, Restart недоступна', () async {
      await startApply();
      cubit.setOffered(null);
      cubit.setOffered('/other');
      runner.applyCompleters.single.complete(_ok());
      await pumpEventQueue();

      final applied = cubit.state as SecretMigrationApplied;
      expect(applied.agentGone, isTrue);
      expect(applied.canRestart, isFalse);

      cubit.closeDialog();
      expect(cubit.state, isA<SecretMigrationOffered>());
      cubit.openPlan();
      expect(runner.planCalls.last, '/other');
    });

    test(
      'агент закрыт без нового: после Close предупреждение скрыто',
      () async {
        await startApply();
        cubit.setOffered(null);
        runner.applyCompleters.single.complete(_ok());
        await pumpEventQueue();

        expect((cubit.state as SecretMigrationApplied).agentGone, isTrue);
        cubit.closeDialog();
        expect(cubit.state, isA<SecretMigrationHidden>());
      },
    );

    test('тот же агент: Restart доступна, agentGone нет', () async {
      await startApply();
      runner.applyCompleters.single.complete(_ok());
      await pumpEventQueue();

      final applied = cubit.state as SecretMigrationApplied;
      expect(applied.agentGone, isFalse);
      expect(applied.canRestart, isTrue);
    });

    test(
      'сбой переноса после смены агента: Close ведёт по новому cwd',
      () async {
        await startApply();
        cubit.setOffered(null);
        runner.applyCompleters.single.complete(
          _ok(canApply: false, problem: 'store failed'),
        );
        await pumpEventQueue();

        cubit.closeDialog();
        expect(cubit.state, isA<SecretMigrationHidden>());
      },
    );

    test('смена агента во время плана-ошибки: Close не возвращает '
        'предложение без cwd', () async {
      cubit.setOffered('/work/app');
      cubit.openPlan();
      runner.planCompleters.single.completeError(StateError('x'));
      await pumpEventQueue();
      // Агент закрылся, пока диалог показывал ошибку.
      cubit.setOffered(null);
      expect(cubit.state, isA<SecretMigrationHidden>());
      cubit.closeDialog();
      expect(cubit.state, isA<SecretMigrationHidden>());
    });
  });

  group('частичный сбой переноса', () {
    Future<void> failPartially() async {
      cubit.setOffered('/work/app');
      cubit.openPlan();
      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();
      cubit.migrate();
      runner.applyCompleters.single.complete(
        _ok(
          canApply: false,
          problem: 'config.yaml: write failed',
          movedAny: true,
        ),
      );
      await pumpEventQueue();
    }

    test('applyFailed несёт перенесённое и признак movedAny', () async {
      await failPartially();
      final state = cubit.state as SecretMigrationApplyFailed;
      expect(state.message, 'config.yaml: write failed');
      expect(state.items, _items);
      expect(state.movedAny, isTrue);
      expect(state.canRestart, isTrue);
    });

    test('Restart agent следует правилу хода', () async {
      turns.add(true);
      await failPartially();
      expect((cubit.state as SecretMigrationApplyFailed).canRestart, isFalse);
      turns.add(false);
      expect((cubit.state as SecretMigrationApplyFailed).canRestart, isTrue);
    });

    test('без movedAny items не показываются и перезапуска нет', () async {
      cubit.setOffered('/work/app');
      cubit.openPlan();
      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();
      cubit.migrate();
      runner.applyCompleters.single.complete(
        _ok(canApply: false, problem: 'store failed'),
      );
      await pumpEventQueue();
      final state = cubit.state as SecretMigrationApplyFailed;
      expect(state.movedAny, isFalse);
      expect(state.items, isEmpty);
    });

    test('closeDialog после частичного сбоя скрывает предупреждение', () async {
      await failPartially();
      cubit.closeDialog();
      expect(cubit.state, isA<SecretMigrationHidden>());
    });
  });

  group('журнал (AGENTS.md §16)', () {
    late RecordingLogger logger;
    late SecretMigrationCubit logged;

    setUp(() {
      logger = RecordingLogger();
      logged = SecretMigrationCubit(
        runner: runner,
        turnActivity: const Stream<bool>.empty(),
        logger: logger,
      );
      addTearDown(logged.close);
    });

    Map<String, Object?> entry(String event) =>
        logger.entries.singleWhere((e) => e['event'] == event);

    test('planned: число пунктов и can_apply', () async {
      logged.setOffered('/work/app');
      logged.openPlan();
      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();

      expect(entry('secret_migration.planned'), containsPair('items', 1));
      expect(
        entry('secret_migration.planned'),
        containsPair('can_apply', true),
      );
    });

    test('applied: moved и backend', () async {
      logged.setOffered('/work/app');
      logged.openPlan();
      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();
      logged.migrate();
      runner.applyCompleters.single.complete(_ok(backendId: 'file'));
      await pumpEventQueue();

      final applied = entry('secret_migration.applied');
      expect(applied, containsPair('moved', 1));
      expect(applied, containsPair('backend', 'file'));
      // Ни пунктов плана, ни путей в журнале нет.
      expect(logger.entries.toString(), isNot(contains('providers.openai')));
    });

    test('problem: exit_code', () async {
      logged.setOffered('/work/app');
      logged.openPlan();
      runner.planCompleters.single.complete(
        _ok(canApply: false, problem: 'bad /secret/path', exitCode: 1),
      );
      await pumpEventQueue();

      expect(
        entry('secret_migration.plan_failed'),
        containsPair('exit_code', 1),
      );
      expect(logger.entries.toString(), isNot(contains('/secret/path')));
    });

    test('result_discarded: поздний план после закрытия', () async {
      logged.setOffered('/work/app');
      logged.openPlan();
      logged.closeDialog();
      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();

      expect(
        entry('secret_migration.result_discarded'),
        containsPair('phase', 'plan'),
      );
    });
  });

  test(
    'отключение агента (setOffered(null)) отбрасывает поздний план',
    () async {
      cubit.setOffered('/work/app');
      cubit.openPlan();
      cubit.setOffered(null);

      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();
      expect(cubit.state, isA<SecretMigrationHidden>());
    },
  );

  test('результат после close() Cubit не бросает', () async {
    cubit.setOffered('/work/app');
    cubit.openPlan();
    await cubit.close();

    runner.planCompleters.single.complete(_ok());
    await pumpEventQueue();
  });

  group('Restart agent', () {
    Future<void> reachApplied() async {
      cubit.setOffered('/work/app');
      cubit.openPlan();
      runner.planCompleters.single.complete(_ok());
      await pumpEventQueue();
      cubit.migrate();
      runner.applyCompleters.single.complete(_ok());
      await pumpEventQueue();
    }

    test('недоступна, если ход идёт в момент applied', () async {
      turns.add(true);
      await reachApplied();
      expect((cubit.state as SecretMigrationApplied).canRestart, isFalse);
    });

    test('становится доступной, когда ход закончился', () async {
      turns.add(true);
      await reachApplied();
      turns.add(false);
      expect((cubit.state as SecretMigrationApplied).canRestart, isTrue);
    });

    test('блокируется, если ход начался после applied', () async {
      await reachApplied();
      turns.add(true);
      expect((cubit.state as SecretMigrationApplied).canRestart, isFalse);
    });

    test('closeDialog после applied скрывает предупреждение', () async {
      await reachApplied();
      cubit.closeDialog();
      expect(cubit.state, isA<SecretMigrationHidden>());
    });
  });
}

/// Исключение, чей `toString()` несёт секрет: в UI он попасть не должен.
final class _LeakyError implements Exception {
  _LeakyError(this.secret);

  final String secret;

  @override
  String toString() => 'parse error near $secret';
}
