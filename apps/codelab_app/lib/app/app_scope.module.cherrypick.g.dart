// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'app_scope.dart';

// **************************************************************************
// ModuleGenerator
// **************************************************************************

final class $CodeLabTransportsModuleContract
    extends CodeLabTransportsModuleContract {
  @override
  void builder(Scope currentScope) {
    bind<StdioAcpAgentProfile>().toInstance(stdioAgentProfile()).singleton();
    bind<AcpTransport>()
        .toProvide(
          () => transport(currentScope.resolve<AcpTransport Function()>()),
        )
        .singleton();
  }
}

final class $CodeLabProtocolApplicationModuleContract
    extends CodeLabProtocolApplicationModuleContract {
  @override
  void builder(Scope currentScope) {
    bind<AcpClientApplication>()
        .toProvide(
          () => application(
            currentScope.resolve<AcpTransport>(),
            currentScope.resolve<AcpTransport Function()>(),
            currentScope.resolve<TextFileReader>(),
            currentScope.resolve<TextFileWriter>(),
            currentScope.resolve<TerminalProcessRunner>(),
          ),
        )
        .singleton();
  }
}

final class $CodeLabRootLifecycleModuleContract
    extends CodeLabRootLifecycleModuleContract {
  @override
  void builder(Scope currentScope) {
    bind<CodeLabRootLifecycle>()
        .toProvide(
          () => rootLifecycle(
            currentScope.resolve<AcpClientApplication>(),
            currentScope.resolve<AcpTransport>(),
            currentScope.resolve<CodeLabShellCubit>(),
          ),
        )
        .singleton();
  }
}
