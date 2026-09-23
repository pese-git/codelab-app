import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/features/workbench/application/shell_cubit.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:cherrypick/cherrypick.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' show addTearDown;

final class CodeLabTestBinding {
  CodeLabTestBinding({
    FakeAcpTransport? transport,
    CodeLabStdioTransportFactory? stdioTransportFactory,
  }) : transport = transport ?? FakeAcpTransport() {
    scope = createCodeLabRootScope(
      transportFactory: () => this.transport,
      stdioTransportFactory: stdioTransportFactory,
    );
    // `CherryPick.openRootScope()` is `_rootScope ??= Scope(...)` — a
    // process-global singleton that silently REUSES whatever root scope is
    // still open if a test forgets to close it, instead of creating a
    // fresh one. In a file this large, one missed manual
    // `closeCodeLabRootScope()` call anywhere leaves every later test
    // silently resolving the previous test's already-disposed
    // dependencies (closed streams, torn-down transports) — which
    // manifests as later tests hanging/timing out, not as an obvious
    // failure at the actual missed-call site. Guaranteeing closure here,
    // regardless of whether the test body also does it, removes that
    // whole class of cross-test corruption.
    addTearDown(closeCodeLabRootScope);
  }

  final FakeAcpTransport transport;
  late final Scope scope;

  Widget bootstrap({required Widget child}) =>
      CodeLabBootstrap(scope: scope, child: child);
}
