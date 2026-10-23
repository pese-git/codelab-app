import 'dart:convert';
import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

/// `_schema.json` documents the format; the loader checks it (design.md D2).
/// This test keeps the two from drifting apart.
void main() {
  late Map<String, Object?> schema;
  late Map<String, Object?> defs;

  setUpAll(() {
    final file = File('${defaultFixtureCorpusDirectory()}/_schema.json');
    schema = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    defs = schema[r'$defs']! as Map<String, Object?>;
  });

  Map<String, Object?> objectSchema(String name) => name == 'fixture'
      ? schema
      : defs[name] as Map<String, Object?>? ??
            fail('_schema.json has no \$defs.$name');

  Set<String> properties(Map<String, Object?> object) =>
      (object['properties']! as Map<String, Object?>).keys.toSet();

  test('is a JSON Schema draft 2020-12 document', () {
    expect(schema[r'$schema'], 'https://json-schema.org/draft/2020-12/schema');
  });

  test(r'defines exactly the loader objects in $defs', () {
    final closedDefs = defs.entries
        .where((e) => (e.value! as Map<String, Object?>)['type'] == 'object')
        .where(
          (e) =>
              (e.value! as Map<String, Object?>)['additionalProperties'] ==
              false,
        )
        .map((e) => e.key)
        .toSet();
    expect(closedDefs, fixtureFormatKeys.keys.toSet()..remove('fixture'));
  });

  for (final MapEntry(key: name, value: keys) in fixtureFormatKeys.entries) {
    test('properties of "$name" match the loader', () {
      final object = objectSchema(name);
      expect(object['additionalProperties'], isFalse);
      expect(properties(object), keys);
    });
  }

  test('required top-level fields match the loader', () {
    expect((schema['required']! as List).toSet(), {
      'id',
      'spec',
      'description',
      'setup',
      'frames',
    });
  });

  test('enums match the loader', () {
    final roles = (schema['properties']! as Map)['roles'] as Map;
    expect(
      ((roles['items']! as Map)['enum']! as List).toSet(),
      FixtureRole.values.map((r) => r.name).toSet(),
    );
    expect(roles['default'], ['agent', 'client']);

    final frame = objectSchema('frame')['properties']! as Map;
    expect(
      ((frame['dir']! as Map)['enum']! as List).toSet(),
      FrameDirection.values.map((d) => d.name).toSet(),
    );

    final step = objectSchema('llmStep')['properties']! as Map;
    expect(
      ((step['stopReason']! as Map)['enum']! as List).toSet(),
      fixtureLlmStopReasons,
    );
  });
}
