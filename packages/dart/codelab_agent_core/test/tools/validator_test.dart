import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/validator.dart';
import 'package:test/test.dart';

Map<String, Object?> _schema(
  Map<String, Object?> properties, {
  List<String> required = const [],
}) => {'type': 'object', 'properties': properties, 'required': required};

Object? _valueOf(Map<String, Object?> property, Object? value) =>
    switch (validateArguments(_schema({'v': property}), {'v': value})) {
      Ok(:final value) => value['v'],
      Err(:final error) => 'violation: ${error.join('; ')}',
    };

void main() {
  group('the coercion table of §6.3.2', () {
    test('integer from a string with spaces and from 5.0', () {
      expect(_valueOf({'type': 'integer'}, '42'), 42);
      expect(_valueOf({'type': 'integer'}, ' 42 '), 42);
      expect(_valueOf({'type': 'integer'}, 5.0), 5);
      expect(
        _valueOf({'type': 'integer'}, 5.5),
        'violation: v: expected integer, got number 5.5',
      );
      expect(
        _valueOf({'type': 'integer'}, 'ten'),
        'violation: v: expected integer, got string "ten"',
      );
    });

    test('number from a string', () {
      expect(_valueOf({'type': 'number'}, '1.5'), 1.5);
      expect(_valueOf({'type': 'number'}, 3), 3);
    });

    test('boolean from strings in any case and from 1 and 0', () {
      expect(_valueOf({'type': 'boolean'}, 'TRUE'), true);
      expect(_valueOf({'type': 'boolean'}, 'false'), false);
      expect(_valueOf({'type': 'boolean'}, 1), true);
      expect(_valueOf({'type': 'boolean'}, 0), false);
      expect(
        _valueOf({'type': 'boolean'}, 2),
        'violation: v: expected boolean, got integer 2',
      );
    });

    test('string from a number or a bool', () {
      expect(_valueOf({'type': 'string'}, 5), '5');
      expect(_valueOf({'type': 'string'}, true), 'true');
    });

    test('array from a single value and from a JSON string', () {
      expect(
        _valueOf({
          'type': 'array',
          'items': {'type': 'string'},
        }, 'a'),
        ['a'],
      );
      expect(
        _valueOf({
          'type': 'array',
          'items': {'type': 'string'},
        }, '["a","b"]'),
        ['a', 'b'],
      );
    });

    test('object from a JSON string', () {
      expect(
        _valueOf({
          'type': 'object',
          'properties': {
            'n': {'type': 'integer'},
          },
        }, '{"n":"7"}'),
        {'n': 7},
      );
    });
  });

  test('default fills a missing key; a missing required key is reported', () {
    final schema = _schema(
      {
        'path': {'type': 'string'},
        'limit': {'type': 'integer', 'default': 2000},
      },
      required: ['path'],
    );

    expect(
      validateArguments(schema, {'path': 'a'}),
      const Ok<Map<String, Object?>, List<String>>({
        'path': 'a',
        'limit': 2000,
      }),
    );
    expect(
      validateArguments(schema, const {}),
      const Err<Map<String, Object?>, List<String>>([
        'path: missing required property',
      ]),
    );
  });

  test('null is valid only for a union with null', () {
    final schema = _schema(
      {
        'a': {
          'type': ['string', 'null'],
        },
        'b': {'type': 'string'},
        'c': {'type': 'string'},
      },
      required: ['c'],
    );

    expect(
      validateArguments(schema, {'a': null, 'b': null, 'c': null}),
      const Err<Map<String, Object?>, List<String>>([
        'c: missing required property',
      ]),
    );
    expect(
      validateArguments(schema, {'a': null, 'b': null, 'c': 'x'}),
      const Ok<Map<String, Object?>, List<String>>({'a': null, 'c': 'x'}),
    );
  });

  test('nested objects and arrays use dotted and indexed paths', () {
    final schema = _schema({
      'entries': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'status': {
              'type': 'string',
              'enum': ['pending', 'completed'],
            },
            'n': {'type': 'integer'},
          },
          'required': ['status'],
        },
      },
    });

    final result = validateArguments(schema, {
      'entries': [
        {'status': 'pending', 'n': '1'},
        {'status': 'done', 'n': 'x'},
        {'n': 2},
      ],
    });

    expect(
      result,
      const Err<Map<String, Object?>, List<String>>([
        'entries[1].status: must be one of ["pending","completed"], got "done"',
        'entries[1].n: expected integer, got string "x"',
        'entries[2].status: missing required property',
      ]),
    );
  });

  test('enum is checked after coercion', () {
    expect(
      _valueOf({
        'type': 'integer',
        'enum': [1, 2],
      }, '2'),
      2,
    );
  });

  test('unknown keywords and extra arguments pass', () {
    final schema = _schema({
      'p': {'type': 'string', 'pattern': r'^\d+$', 'minLength': 10},
    });

    expect(
      validateArguments(schema, {'p': 'abc', 'extra': true}),
      const Ok<Map<String, Object?>, List<String>>({'p': 'abc', 'extra': true}),
    );
  });

  test('the error text for the model', () {
    expect(
      formatInvalidArguments(
        'read',
        [
          'path: missing required property',
          'limit: expected integer, got string "ten"',
        ],
        {'limit': 'ten'},
      ),
      'Invalid arguments for tool "read":\n'
      '  - path: missing required property\n'
      '  - limit: expected integer, got string "ten"\n'
      'Received arguments: {"limit":"ten"}',
    );
  });
}
