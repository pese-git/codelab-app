// Закрытие scope при снятии `CodeLabBootstrap`: сбой `Disposable` в scope не
// уходит необработанным в зону, а пишется как `app.shutdown_step_failed`
// со `step: root_scope` (AGENTS.md §12 — ошибки fire-and-forget не теряются;
// событие — `observability.md`, change `add-client-process-shutdown-on-exit`,
// D6). Параллельные вызовы `closeCodeLabRootScope()` закрывают root scope
// один раз: `CherryPick.closeRootScope` обнуляет scope только после
// `await dispose()`.
import 'dart:async';

import 'package:cherrypick/cherrypick.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_logger.dart';
import '../support/test_app_scope.dart';

/// `Disposable`, который бросает при первом `dispose` (повторное закрытие
/// scope в teardown теста проходит чисто).
final class _FailingDisposable implements Disposable {
  var _failed = false;

  @override
  Future<void> dispose() async {
    if (_failed) return;
    _failed = true;
    throw StateError('dispose failed');
  }
}

/// `Disposable`, который считает вызовы `dispose` и ждёт ворота.
final class _GatedDisposable implements Disposable {
  final gate = Completer<void>();
  var disposeCalls = 0;

  @override
  Future<void> dispose() {
    disposeCalls++;
    return gate.future;
  }
}

final class _InstanceModule<T extends Object> extends Module {
  _InstanceModule(this.instance);

  final T instance;

  @override
  void builder(Scope currentScope) {
    bind<T>().toInstance(instance);
  }
}

void main() {
  testWidgets('сбой Disposable при закрытии scope пишется в журнал, '
      'а не уходит необработанным', (tester) async {
    final binding = CodeLabTestBinding();
    // Подскоуп закрывается раньше владельцев root scope: сбой случается
    // до ожидания реальной записи файловых журналов.
    binding.scope.openSubScope('failing')
      ..installModules([_InstanceModule(_FailingDisposable())])
      ..resolve<_FailingDisposable>();
    final logger = RecordingLogger();

    await tester.pumpWidget(
      CodeLabBootstrap(
        scope: binding.scope,
        appLogger: logger,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      logger.entries,
      contains(
        allOf(
          containsPair('event', 'app.shutdown_step_failed'),
          containsPair('level', 'error'),
          containsPair('step', 'root_scope'),
          containsPair('error_type', 'StateError'),
        ),
      ),
    );
  });

  test(
    'параллельные closeCodeLabRootScope закрывают root scope один раз',
    () async {
      final disposable = _GatedDisposable();
      CherryPick.openRootScope()
        ..installModules([_InstanceModule(disposable)])
        ..resolve<_GatedDisposable>();

      final first = closeCodeLabRootScope();
      final second = closeCodeLabRootScope();
      disposable.gate.complete();
      await Future.wait([first, second]);

      expect(disposable.disposeCalls, 1);
    },
  );
}
