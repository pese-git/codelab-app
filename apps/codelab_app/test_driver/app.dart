// Driver entrypoint: enables the flutter_driver VM-service extension so a
// running app instance (`flutter run -t test_driver/app.dart --print-dtd`)
// can be driven programmatically (e.g. via the dart MCP flutter_driver
// bridge) using the stable ValueKeys defined across the app widgets.
import 'package:codelab_app/main.dart' as app;
import 'package:flutter_driver/driver_extension.dart';

void main() {
  enableFlutterDriverExtension();
  app.main();
}
