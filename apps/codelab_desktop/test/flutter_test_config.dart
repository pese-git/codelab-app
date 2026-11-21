import 'dart:async';
import 'dart:io';

import 'package:codelab_client_io/codelab_client_io.dart'
    show resolveCodelabHome;
import 'package:flutter_test/flutter_test.dart';

/// Страж: ни один тест не меняет настоящий `recent_projects.json` разработчика.
///
/// Почему: `createCodeLabRootScope` без шва `environment:` и
/// `recentProjectsStore:` берёт `Platform.environment` и пишет проекты теста в
/// настоящий `~/.codelab/recent_projects.json`, общий с `codelab` (change
/// `share-recent-projects-store`, D7): так в списке пользователя оказались
/// временные папки `codelab_app_embedded_*`.
///
/// Для чего: перед файлом тестов запоминает содержимое настоящего файла, после
/// — сверяет; изменение или появление файла роняет прогон файла с названием
/// причины. Сам файл страж не читает ради значений и не пишет.
///
/// Как использовать: подхватывается `flutter test` автоматически для каждого
/// тестового файла каталога `test/`. Тест без шва чинится передачей
/// `recentProjectsStore: FakeRecentProjectsStore()` или временного
/// `environment: {'CODELAB_HOME': …}`. Если файл меняет другой процесс
/// (`codelab`) во время прогона, страж ложно сработает — перезапустите прогон.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final file = _realRecentProjectsFile();
  List<int>? before;
  setUpAll(() => before = _snapshot(file));
  tearDownAll(() {
    final after = _snapshot(file);
    if (!_same(after, before)) {
      fail(
        'Тест изменил настоящий ${file?.path}: передайте шов '
        '`recentProjectsStore:` или временный `environment: '
        "{'CODELAB_HOME': …}` в createCodeLabRootScope. Изменение мог сделать "
        'параллельный тестовый файл (-j) или запущенный codelab/app — '
        'повторите прогон.',
      );
    }
  });
  await testMain();
}

File? _realRecentProjectsFile() {
  try {
    return File(
      '${resolveCodelabHome(Platform.environment)}/recent_projects.json',
    );
  } on Object {
    return null;
  }
}

/// Байты файла (не строка: не-UTF-8 не должен ронять `setUpAll`); `null` —
/// файла нет или дом не определён.
List<int>? _snapshot(File? file) {
  if (file == null || !file.existsSync()) return null;
  return file.readAsBytesSync();
}

bool _same(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
