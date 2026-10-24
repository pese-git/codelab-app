import 'dart:io';

import '../support/package_dir.dart';

/// Text of the journal fixture `test/fixtures/sessions/<name>`.
String sessionFixture(String name) =>
    File(corePath('test/fixtures/sessions/$name')).readAsStringSync();
