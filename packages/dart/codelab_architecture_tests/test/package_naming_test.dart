import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';
import 'support/rules.dart';

/// Каталоги членов pub workspace из корневого `pubspec.yaml`.
///
/// Почему: схема имён ADR-0002 и правила сторожа ссылаются на пакеты
/// workspace; список берётся из того же места, что и у `pub`, а не задаётся
/// вручную, чтобы новый пакет сразу попадал под проверку.
///
/// Как использовать: передать корень репозитория (`repoRoot()`); пути
/// возвращаются относительно него в порядке файла.
List<String> workspaceMembers(String root) {
  final lines = File(p.join(root, 'pubspec.yaml')).readAsLinesSync();
  final members = <String>[];
  var inWorkspace = false;
  for (final line in lines) {
    if (line.startsWith('workspace:')) {
      inWorkspace = true;
      continue;
    }
    if (!inWorkspace) continue;
    final item = RegExp(r'^\s+-\s+(\S+)').firstMatch(line);
    if (item != null) {
      members.add(item.group(1)!);
    } else if (line.trim().isNotEmpty) {
      break;
    }
  }
  return members;
}

/// Значение `name:` из `pubspec.yaml` пакета.
String packageName(String root, String member) {
  final pubspec = File(p.join(root, member, 'pubspec.yaml')).readAsStringSync();
  return RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)!.group(1)!;
}

/// Находит запрещённые префиксы `package:codelab_`, которым не соответствует
/// ни один пакет workspace.
///
/// Почему: правила сторожа — строковые префиксы; после переименования пакета
/// устаревший префикс не даёт ошибки, а молча перестаёт что-либо запрещать
/// (ADR-0002, Risks).
///
/// Как использовать: `package:<имя>/…` требует пакет с точным именем,
/// префикс без `/` (`package:codelab_agent_`) — хотя бы один пакет, имя
/// которого с него начинается. Внешние пакеты (`package:flutter/`) не
/// проверяются.
List<String> danglingPrefixes(Iterable<String> forbidden, Set<String> names) {
  final dangling = <String>[];
  for (final uri in forbidden) {
    if (!uri.startsWith('package:codelab_')) continue;
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    final matches = slash >= 0
        ? names.contains(rest.substring(0, slash))
        : names.any((n) => n.startsWith(rest));
    if (!matches) dangling.add(uri);
  }
  return dangling;
}

void main() {
  final root = repoRoot();
  final members = workspaceMembers(root);

  test('every workspace package follows the codelab_ scheme (ADR-0002)', () {
    final offenders = [
      for (final m in members)
        if (!packageName(root, m).startsWith('codelab_') ||
            p.basename(m) != packageName(root, m))
          '$m -> ${packageName(root, m)}',
    ];

    expect(members, isNotEmpty);
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('forbidden codelab_ prefixes name existing packages (ADR-0002)', () {
    final names = {for (final m in members) packageName(root, m)};
    final dangling = {
      for (final rule in rules) ...danglingPrefixes(rule.forbidden, names),
      ...danglingPrefixes(webUnsafe, names),
    };

    expect(dangling, isEmpty, reason: dangling.join('\n'));
  });

  test('reports a prefix left over from a renamed package', () {
    const names = {'codelab_acp_transports', 'codelab_agent_core'};

    final dangling = danglingPrefixes([
      'package:flutter/',
      'package:codelab_acp_transports/io.dart',
      'package:codelab_agent_',
      'package:codelab_client_',
      'package:codelab_acp_protocol/',
    ], names);

    expect(dangling, [
      'package:codelab_client_',
      'package:codelab_acp_protocol/',
    ]);
  });
}
