import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/workbench/presentation/workbench_shell.dart';
import 'app_scope.dart';

class CodeLabApp extends StatelessWidget {
  const CodeLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = codeLabDependenciesOf(context);

    // BlocProvider wraps FluentApp (not `home`) so the cubit stays visible
    // to every route on FluentApp's Navigator, including the modal dialog
    // ConnectionSetupDialog pushes via showDialog — a route pushed by the
    // same Navigator sits as a sibling of `home`'s content in the element
    // tree, not a descendant of it, so a provider scoped inside `home`
    // would not be reachable from the dialog.
    return BlocProvider.value(
      value: dependencies.shellCubit,
      child: const FluentApp(title: 'CodeLab', home: CodeLabShell()),
    );
  }
}
