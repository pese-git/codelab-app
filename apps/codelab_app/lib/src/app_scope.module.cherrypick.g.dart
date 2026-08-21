// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'app_scope.dart';

// **************************************************************************
// ModuleGenerator
// **************************************************************************

final class $CodeLabRootModuleContract extends CodeLabRootModuleContract {
  @override
  void builder(Scope currentScope) {
    bind<StdioAcpAgentProfile>().toInstance(stdioAgentProfile()).singleton();
    bind<AcpTransport>()
        .toProvide(
          () => transport(currentScope.resolve<AcpTransport Function()>()),
        )
        .singleton();
    bind<AcpClientApplication>()
        .toProvide(
          () => application(
            currentScope.resolve<AcpTransport>(),
            currentScope.resolve<AcpTransport Function()>(),
          ),
        )
        .singleton();
    bind<CodeLabRootLifecycle>()
        .toProvide(
          () => rootLifecycle(
            currentScope.resolve<AcpClientApplication>(),
            currentScope.resolve<AcpTransport>(),
          ),
        )
        .singleton();
  }
}
