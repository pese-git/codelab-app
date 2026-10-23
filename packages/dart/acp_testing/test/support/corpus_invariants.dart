import 'dart:io';

import 'package:acp_testing/acp_testing.dart';

/// Corpus invariants of `14-golden-fixtures.md` §14.11 (design.md D5).

/// Repository root: the nearest directory above the current one whose
/// `pubspec.yaml` declares the pub workspace.
Directory repoRoot() {
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        RegExp(
          r'^workspace:',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return dir;
    }
    if (dir.parent.path == dir.path) {
      throw StateError('No workspace pubspec.yaml above ${Directory.current}');
    }
  }
}

/// `docs/acp/protocol` — the vendored ACP specification.
String protocolSpecDirectory() => '${repoRoot().path}/docs/acp/protocol';

/// FIX-1: every `spec` reference names an existing file of the protocol
/// specification and an anchor of that file (a heading or `<a id="…">`).
List<String> specReferenceViolations(
  AcpFixture fixture, {
  required String protocolDirectory,
}) {
  final violations = <String>[];
  for (final reference in fixture.spec) {
    final hash = reference.indexOf('#');
    final fileName = hash < 0 ? reference : reference.substring(0, hash);
    final anchor = hash < 0 ? null : reference.substring(hash + 1);
    final file = File('$protocolDirectory/$fileName');
    if (!file.existsSync()) {
      violations.add('${fixture.id}: spec "$reference": no file $fileName');
      continue;
    }
    if (anchor == null || anchor.isEmpty) {
      violations.add('${fixture.id}: spec "$reference": no #anchor');
      continue;
    }
    if (!markdownAnchors(file.readAsStringSync()).contains(anchor)) {
      violations.add(
        '${fixture.id}: spec "$reference": no anchor #$anchor in $fileName',
      );
    }
  }
  return violations;
}

/// Anchors of a Markdown file: slugs of its headings (lower case, tags and
/// punctuation dropped, spaces → `-`) and explicit `<a id="…">`.
Set<String> markdownAnchors(String markdown) {
  final anchors = <String>{};
  for (final match in RegExp(
    r'^#{1,6}\s+(.+?)\s*$',
    multiLine: true,
  ).allMatches(markdown)) {
    anchors.add(headingSlug(match.group(1)!));
  }
  for (final match in RegExp(r'<a id="([^"]+)"').allMatches(markdown)) {
    anchors.add(match.group(1)!);
  }
  return anchors;
}

String headingSlug(String heading) => heading
    .replaceAll(RegExp('<[^>]+>'), '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '-');

/// FIX-4: a fixture without `extensions` has no `_meta.codelab`,
/// `data.codelab` and `_codelab/*` methods in its frames.
List<String> undeclaredExtensionViolations(AcpFixture fixture) {
  if (fixture.extensions.isNotEmpty) {
    return const [];
  }
  final violations = <String>[];
  void walk(Object? node, String path) {
    switch (node) {
      case final Map<String, Object?> map:
        for (final MapEntry(:key, :value) in map.entries) {
          final keyPath = '$path.$key';
          if ((key == '_meta' || key == 'data') &&
              value is Map<String, Object?> &&
              value.containsKey('codelab')) {
            violations.add(
              '${fixture.id}: $keyPath.codelab without extensions',
            );
          }
          if (key == 'method' &&
              value is String &&
              value.startsWith('_codelab/')) {
            violations.add(
              '${fixture.id}: $keyPath "$value" without extensions',
            );
          }
          walk(value, keyPath);
        }
      case final List<Object?> list:
        for (final (i, item) in list.indexed) {
          walk(item, '$path[$i]');
        }
    }
  }

  for (final frame in fixture.frames) {
    walk(frame.frame ?? frame.unordered, '\$.frames[${frame.index}]');
  }
  return violations;
}

/// Methods and `sessionUpdate` kinds that occur in the frames of [fixtures].
({Set<String> methods, Set<String> sessionUpdates}) coveredProtocolElements(
  Iterable<AcpFixture> fixtures,
) {
  final methods = <String>{};
  final kinds = <String>{};
  void walk(Object? node) {
    switch (node) {
      case final Map<String, Object?> map:
        if (map['method'] case final String method) {
          methods.add(method);
        }
        if (map['sessionUpdate'] case final String kind) {
          kinds.add(kind);
        }
        map.values.forEach(walk);
      case final List<Object?> list:
        list.forEach(walk);
    }
  }

  for (final fixture in fixtures) {
    for (final frame in fixture.frames) {
      walk(frame.frame ?? frame.unordered);
    }
  }
  return (methods: methods, sessionUpdates: kinds);
}

/// `sessionUpdate` kinds the `acp_protocol` decoder knows.
Set<String> protocolSessionUpdateKinds() {
  final source = File(
    '${repoRoot().path}/packages/dart/acp_protocol/lib/src/acp/session_update.dart',
  ).readAsStringSync();
  return {
    for (final match in RegExp(
      r"'([a-z_]+)' => SessionUpdate\.",
    ).allMatches(source))
      match.group(1)!,
  };
}
