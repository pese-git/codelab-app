import 'package:codelab_app/src/app_scope.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:cherrypick/cherrypick.dart';
import 'package:flutter/widgets.dart';

final class CodeLabTestBinding {
  CodeLabTestBinding({FakeAcpTransport? transport})
    : transport = transport ?? FakeAcpTransport() {
    scope = createCodeLabRootScope(transportFactory: () => this.transport);
  }

  final FakeAcpTransport transport;
  late final Scope scope;

  Widget bootstrap({required Widget child}) =>
      CodeLabBootstrap(scope: scope, child: child);
}
