// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';
import 'package:fluent_ui/fluent_ui.dart';

part 'app_scope.module.cherrypick.g.dart';

typedef CodeLabTransportFactory = AcpTransport Function();

Scope createCodeLabRootScope({CodeLabTransportFactory? transportFactory}) {
  final scope = CherryPick.openRootScope()
    ..installModules([
      CodeLabTransportRuntimeModule(
        transportFactory: transportFactory ?? _createDefaultTransport,
      ),
      $CodeLabTransportsModuleContract(),
      $CodeLabProtocolApplicationModuleContract(),
      $CodeLabRootLifecycleModuleContract(),
    ]);

  scope.resolve<CodeLabRootLifecycle>();
  return scope;
}

Future<void> closeCodeLabRootScope() => CherryPick.closeRootScope();

CodeLabDependencies codeLabDependenciesOf(BuildContext context) =>
    CodeLabDependenciesScope.of(context);

final class CodeLabTransportRuntimeModule extends Module {
  CodeLabTransportRuntimeModule({
    required CodeLabTransportFactory transportFactory,
  }) : _transportFactory = transportFactory;

  final CodeLabTransportFactory _transportFactory;

  @override
  void builder(Scope currentScope) {
    bind<CodeLabTransportFactory>().toInstance(_transportFactory);
  }
}

@module()
abstract class CodeLabTransportsModuleContract extends Module {
  @instance()
  @singleton()
  StdioAcpAgentProfile stdioAgentProfile() => codelabAgentStdioProfile;

  @provide()
  @singleton()
  AcpTransport transport(CodeLabTransportFactory transportFactory) =>
      transportFactory();
}

@module()
abstract class CodeLabProtocolApplicationModuleContract extends Module {
  @provide()
  @singleton()
  AcpClientApplication application(
    AcpTransport transport,
    CodeLabTransportFactory transportFactory,
  ) => AcpClientApplication(
    transport: transport,
    reconnectTransport: transportFactory,
  );
}

@module()
abstract class CodeLabRootLifecycleModuleContract extends Module {
  @provide()
  @singleton()
  CodeLabRootLifecycle rootLifecycle(
    AcpClientApplication application,
    AcpTransport transport,
  ) => CodeLabRootLifecycle(application: application, transport: transport);
}

final class CodeLabRootLifecycle implements Disposable {
  CodeLabRootLifecycle({
    required AcpClientApplication application,
    required AcpTransport transport,
  }) : _application = application,
       _transport = transport;

  final AcpClientApplication _application;
  final AcpTransport _transport;
  var _isDisposed = false;

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await _transport.close();
    await _application.dispose();
  }
}

final class CodeLabDependencies {
  const CodeLabDependencies({required this.scope});

  final Scope scope;

  AcpClientApplication get application => scope.resolve<AcpClientApplication>();
}

final class CodeLabDependenciesScope extends InheritedWidget {
  const CodeLabDependenciesScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final CodeLabDependencies dependencies;

  static CodeLabDependencies of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<CodeLabDependenciesScope>();
    assert(inherited != null, 'CodeLabDependenciesScope was not found.');
    return inherited!.dependencies;
  }

  @override
  bool updateShouldNotify(CodeLabDependenciesScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}

class CodeLabBootstrap extends StatefulWidget {
  const CodeLabBootstrap({required this.child, this.scope, super.key});

  final Widget child;
  final Scope? scope;

  @override
  State<CodeLabBootstrap> createState() => _CodeLabBootstrapState();
}

class _CodeLabBootstrapState extends State<CodeLabBootstrap> {
  late final Scope _scope = widget.scope ?? createCodeLabRootScope();
  late final CodeLabDependencies _dependencies = CodeLabDependencies(
    scope: _scope,
  );

  @override
  void dispose() {
    final providedScope = widget.scope;
    if (providedScope == null) {
      unawaited(closeCodeLabRootScope());
    } else {
      unawaited(providedScope.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CodeLabDependenciesScope(
      dependencies: _dependencies,
      child: widget.child,
    );
  }
}

AcpTransport _createDefaultTransport() =>
    StdioAcpTransport(codelabAgentStdioProfile.toTransportConfig());
