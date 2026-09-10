import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app_scope.dart';
import 'app/codelab_app_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDirectory = await getApplicationSupportDirectory();
  final logDirectoryPath = p.join(supportDirectory.path, 'logs');

  runApp(
    CodeLabBootstrap(
      logDirectoryPath: logDirectoryPath,
      child: const CodeLabApp(),
    ),
  );
}
