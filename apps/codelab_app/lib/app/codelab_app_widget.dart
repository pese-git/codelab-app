import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/workbench/presentation/workbench_shell.dart';
import 'app_scope.dart';

class CodeLabApp extends StatelessWidget {
  const CodeLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = codeLabDependenciesOf(context);

    return FluentApp(
      title: 'CodeLab',
      home: BlocProvider.value(
        value: dependencies.shellCubit,
        child: const CodeLabShell(),
      ),
    );
  }
}
