import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Подсказка о `codelab.toml` Python-агента, который Dart-агент не читает.
///
/// Почему: совместимость с `codelab.toml` убрана решением пользователя
/// 2026-10-29 (design.md change `add-agent-configuration`, D12): второй
/// формат и вторая таблица перевода ради временной совместимости не нужны.
/// Но пользователь, у которого настройки лежат только в старом файле, не
/// должен молча их потерять — поэтому одно предупреждение с путями.
///
/// Для чего: места поиска те же, что у Python-агента:
/// `$CODELAB_HOME/codelab.toml`, `$CODELAB_HOME/auth.toml`,
/// `<cwd>/codelab.toml` и `<cwd>/codelab.local.toml`;
/// `codelab.toml.example` — шаблон и не ищется.
///
/// Как использовать: `ConfigLoader` зовёт функцию, только если нет ни одного
/// YAML-файла слоёв 2–4 и не задан `--config`, и не со сценарием. Файл НЕ
/// открывается и НЕ разбирается: проверяется только существование
/// (`FileSystemEntity.isFileSync`), содержимое и размер в предупреждение не
/// попадают — только пути. Возвращает `null`, если искать нечего.
ConfigIssue? legacyConfigNotice({required String home, required String cwd}) {
  final files = [
    for (final path in [
      '$home/codelab.toml',
      '$home/auth.toml',
      '$cwd/codelab.toml',
      '$cwd/codelab.local.toml',
    ])
      if (FileSystemEntity.isFileSync(path)) path,
  ];
  if (files.isEmpty) {
    return null;
  }
  return ConfigIssue(
    kind: ConfigIssueKind.semantic,
    key: '',
    source: files.first,
    message:
        'codelab.toml is not used by the Dart agent: ${files.join(', ')}. '
        'Move the settings to config.yaml manually; the key mapping is in '
        'docs/architecture/proposals/agent-core/15-configuration.md, '
        'section 15.7.',
    event: 'config.legacy_found',
    fields: {'files': files},
  );
}
