// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../core/platform/working_directory_provider.dart';
import '../features/workbench/application/shell_cubit.dart';

part 'app_scope.module.cherrypick.g.dart';

typedef CodeLabTransportFactory = AcpTransport Function();

Scope createCodeLabRootScope({
  CodeLabTransportFactory? transportFactory,
  CodeLabStdioTransportFactory? stdioTransportFactory,
}) {
  final scope = CherryPick.openRootScope()
    ..installModules([
      CodeLabTransportRuntimeModule(
        transportFactory: transportFactory ?? _createDefaultTransport,
        stdioTransportFactory: stdioTransportFactory ?? _createStdioTransport,
      ),
      CodeLabPlatformModule(),
      CodeLabPresentationModule(),
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
    required CodeLabStdioTransportFactory stdioTransportFactory,
  }) : _transportFactory = transportFactory,
       _stdioTransportFactory = stdioTransportFactory;

  final CodeLabTransportFactory _transportFactory;
  final CodeLabStdioTransportFactory _stdioTransportFactory;

  @override
  void builder(Scope currentScope) {
    bind<CodeLabTransportFactory>().toInstance(_transportFactory);
    bind<CodeLabStdioTransportFactory>().toInstance(_stdioTransportFactory);
  }
}

final class CodeLabPlatformModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<WorkingDirectoryProvider>().toInstance(
      const IoWorkingDirectoryProvider(),
    );
  }
}

final class CodeLabPresentationModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<CreateSession>()
        .toProvide(
          () => CreateSession(currentScope.resolve<AcpClientApplication>()),
        )
        .singleton();
    bind<SendPrompt>()
        .toProvide(
          () => SendPrompt(currentScope.resolve<AcpClientApplication>()),
        )
        .singleton();
    bind<CancelTurn>()
        .toProvide(
          () => CancelTurn(currentScope.resolve<AcpClientApplication>()),
        )
        .singleton();
    bind<Reconnect>()
        .toProvide(
          () => Reconnect(currentScope.resolve<AcpClientApplication>()),
        )
        .singleton();
    bind<RespondToPermission>()
        .toProvide(
          () =>
              RespondToPermission(currentScope.resolve<AcpClientApplication>()),
        )
        .singleton();
    bind<SetSessionConfigOption>()
        .toProvide(
          () => SetSessionConfigOption(
            currentScope.resolve<AcpClientApplication>(),
          ),
        )
        .singleton();
    bind<CodeLabShellCubit>()
        .toProvide(
          () => CodeLabShellCubit(
            profile: currentScope.resolve<StdioAcpAgentProfile>(),
            application: currentScope.resolve<AcpClientApplication>(),
            createSessionUseCase: currentScope.resolve<CreateSession>(),
            sendPromptUseCase: currentScope.resolve<SendPrompt>(),
            cancelTurnUseCase: currentScope.resolve<CancelTurn>(),
            reconnectUseCase: currentScope.resolve<Reconnect>(),
            respondToPermissionUseCase: currentScope
                .resolve<RespondToPermission>(),
            setSessionConfigOptionUseCase: currentScope
                .resolve<SetSessionConfigOption>(),
            stdioTransportFactory: currentScope
                .resolve<CodeLabStdioTransportFactory>(),
            workingDirectoryProvider: currentScope
                .resolve<WorkingDirectoryProvider>(),
          ),
        )
        .singleton();
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
    CodeLabShellCubit shellCubit,
  ) => CodeLabRootLifecycle(
    application: application,
    transport: transport,
    shellCubit: shellCubit,
  );
}

final class CodeLabRootLifecycle implements Disposable {
  CodeLabRootLifecycle({
    required AcpClientApplication application,
    required AcpTransport transport,
    required CodeLabShellCubit shellCubit,
  }) : _application = application,
       _transport = transport,
       _shellCubit = shellCubit;

  final AcpClientApplication _application;
  final AcpTransport _transport;
  final CodeLabShellCubit _shellCubit;
  var _isDisposed = false;

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await _shellCubit.close();
    await _transport.close();
    await _application.dispose();
  }
}

final class CodeLabDependencies {
  const CodeLabDependencies({
    required this.application,
    required this.shellCubit,
  });

  final AcpClientApplication application;
  final CodeLabShellCubit shellCubit;
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
    application: _scope.resolve<AcpClientApplication>(),
    shellCubit: _scope.resolve<CodeLabShellCubit>(),
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

AcpTransport _createStdioTransport(StdioAcpTransportConfig config) =>
    StdioAcpTransport(config);
