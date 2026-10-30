import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/src/config/yaml_reader.dart';
import 'package:test/test.dart';

/// Строгий профиль YAML (agent-configuration «Строгий профиль YAML»; CFG-21;
/// `agent-core-architecture` §15.5, §15.12; design.md change
/// `add-agent-configuration`, D5).
void main() {
  YamlReadResult read(String text) =>
      readYamlTree(text, source: 'config.yaml', kind: ConfigLayerKind.user);

  void expectProfile(
    String text, {
    required int line,
    required int column,
    required String message,
    String key = '',
  }) {
    final result = read(text);
    expect(result.tree, isNull, reason: 'a violation gives no tree');
    final issue = result.issues.firstWhere(
      (i) => i.line == line && i.column == column,
      orElse: () => fail('no issue at $line:$column in ${result.issues}'),
    );
    expect(issue.kind, ConfigIssueKind.profile);
    expect(issue.source, 'config.yaml');
    expect(issue.message, contains(message));
    expect(issue.key, key);
  }

  group('profile violations', () {
    test('an anchor and a reference', () {
      final result = read('base: &b\n  k: 1\nother: *b\n');

      expect(result.tree, isNull);
      expect(
        result.issues.map((i) => i.kind),
        everyElement(ConfigIssueKind.profile),
      );
      // Якорь называется в своей позиции, ссылка — по ключу, в котором стоит.
      expect(
        result.issues.map((i) => '${i.line}:${i.column}'),
        containsAll(['1:7', '3:1']),
      );
      expect(
        result.issues.map((i) => i.message),
        everyElement('anchors, aliases, merge keys and tags are not supported'),
      );
    });

    test('a merge key', () {
      expectProfile(
        'base: &b\n  k: 1\nd:\n  <<: *b\n  z: 2\n',
        line: 4,
        column: 3,
        key: 'd."<<"',
        message: 'anchors, aliases, merge keys and tags are not supported',
      );
    });

    test('a merge key without an alias', () {
      expectProfile(
        'd:\n  <<: {a: 1}\n',
        line: 2,
        column: 3,
        key: 'd."<<"',
        message: 'merge keys',
      );
    });

    test('the tag !!str', () {
      expectProfile(
        'budget:\n  max_steps: !!str 20\n',
        line: 2,
        column: 14,
        key: 'budget.max_steps',
        message: 'anchors, aliases, merge keys and tags are not supported',
      );
    });

    test('a tag and an anchor on collections', () {
      expectProfile(
        'a: !!map\n  k: 1\n',
        line: 1,
        column: 4,
        key: 'a',
        message: 'tags',
      );
      expectProfile(
        'a: &s\n  - 1\n',
        line: 1,
        column: 4,
        key: 'a',
        message: 'anchors',
      );
    });

    test('an anchor or a tag in the flow style', () {
      expectProfile(
        'a: [&x 1, 2]\n',
        line: 1,
        column: 5,
        key: 'a[0]',
        message: 'anchors',
      );
      expectProfile(
        '{&k a: 1}',
        line: 1,
        column: 2,
        key: 'a',
        message: 'anchors',
      );
    });

    test('an unknown tag is a profile violation without the tag name', () {
      final result = read('a: !secret-tag-name 1\n');

      expect(result.tree, isNull);
      final issue = result.issues.single;
      expect(issue.kind, ConfigIssueKind.profile);
      expect(issue.line, 1);
      expect(issue.column, isNotNull);
      expect(issue.message, contains('tags'));
      expect(issue.message, isNot(contains('secret-tag-name')));
      expect(issue.toString(), isNot(contains('secret-tag-name')));
    });

    test('a tag or an anchor on the root mapping', () {
      expectProfile('!!map\na: 1\n', line: 1, column: 1, message: 'tags');
      expectProfile('&root\na: 1\n', line: 1, column: 1, message: 'anchors');
    });

    test('a second document', () {
      expectProfile(
        'a: 1\n---\nb: 2\n',
        line: 3,
        column: 1,
        message: 'multiple YAML documents are not supported',
      );
    });

    test('an integer key', () {
      expectProfile(
        'a: 1\n1: x\n',
        line: 2,
        column: 1,
        message: 'mapping keys must be strings',
      );
    });

    test('a null and a boolean key', () {
      expectProfile('~: x\n', line: 1, column: 1, message: 'keys must be');
      expectProfile('true: x\n', line: 1, column: 1, message: 'keys must be');
    });

    test('a compound key', () {
      expectProfile(
        '? [a, b]\n: 1\n',
        line: 1,
        column: 3,
        message: 'mapping keys must be strings',
      );
    });

    test('a quoted number is a legal key', () {
      final result = read('"1": x\n');

      expect(result.issues, isEmpty);
      expect(result.tree!.values, {'1': 'x'});
    });

    test('a repeated key names both positions', () {
      final result = read('a: 1\nb: 2\na: 3\n');

      expect(result.tree, isNull);
      final issue = result.issues.single;
      expect(issue.kind, ConfigIssueKind.profile);
      expect((issue.line, issue.column), (3, 1));
      expect(issue.message, contains('duplicate mapping key'));
      expect(issue.message, contains('first defined at 1:1'));
    });

    test('a repeated nested key names both positions', () {
      final result = read('x:\n  a: 1\n  c: 2\n  a: 3\n');

      final issue = result.issues.single;
      expect((issue.line, issue.column), (4, 3));
      expect(issue.message, contains('first defined at 2:3'));
    });

    test('a repeated key inside a list item', () {
      final result = read('s:\n  - name: a\n    name: b\n');

      final issue = result.issues.single;
      expect((issue.line, issue.column), (3, 5));
      expect(issue.message, contains('first defined at 2:5'));
    });

    test('a repeated key in the flow style', () {
      final result = read('{a: 1, a: 2}');

      final issue = result.issues.single;
      expect((issue.line, issue.column), (1, 8));
      expect(issue.message, contains('first defined at 1:2'));
    });

    test('all violations of a file are reported together', () {
      final result = read('a: !!str 1\n1: x\n');

      expect(result.issues, hasLength(2));
    });

    test('a top-level list is not a mapping', () {
      expectProfile(
        '- a\n- b\n',
        line: 1,
        column: 1,
        message: 'top level must be a mapping',
      );
    });
  });

  group('syntax errors', () {
    test('an unterminated flow sequence has a position', () {
      final result = read('a: [1, 2\n');

      expect(result.tree, isNull);
      final issue = result.issues.single;
      expect(issue.kind, ConfigIssueKind.syntax);
      expect(issue.line, isNotNull);
      expect(issue.column, isNotNull);
      expect(issue.source, 'config.yaml');
    });

    test('a tab in the indentation', () {
      final issue = read('a:\n\tb: 1\n').issues.single;

      expect(issue.kind, ConfigIssueKind.syntax);
      expect(issue.line, 2);
    });

    test('the message does not carry the source text', () {
      final issue = read('token: "sk-test-secret').issues.single;

      expect(issue.message, isNot(contains('sk-test-secret')));
      expect(issue.toString(), isNot(contains('sk-test-secret')));
    });
  });

  group('nesting limit', () {
    test('64 levels of flow sequences are accepted', () {
      final result = read('a: ${'[' * 64}${']' * 64}\n');

      expect(result.issues, isEmpty);
    });

    test('65 levels are a profile violation with a position', () {
      final result = read('a: ${'[' * 65}${']' * 65}\n');

      expect(result.tree, isNull);
      final issue = result.issues.single;
      expect(issue.kind, ConfigIssueKind.profile);
      expect(issue.message, contains('64'));
      expect(issue.line, 1);
    });

    test('10^4 levels give an issue and no stack overflow', () {
      final result = read('a: ${'[' * 10000}\n');

      expect(result.tree, isNull);
      expect(result.issues.single.kind, ConfigIssueKind.profile);
    });

    test('10^4 flow mappings too', () {
      final result = read('a: ${'{a: ' * 10000}\n');

      expect(result.tree, isNull);
      expect(result.issues.single.kind, ConfigIssueKind.profile);
    });

    test('brackets in quoted strings and comments are not nesting', () {
      final result = read(
        "a: '${'[' * 100}'\nb: \"${'{' * 100}\"\nc: x # ${'[' * 100}\n",
      );

      expect(result.issues, isEmpty);
    });

    test('65 levels of block mappings are a profile violation', () {
      final text = [
        for (var i = 0; i < 66; i++) '${'  ' * i}k$i:',
        '${'  ' * 66}v',
      ].join('\n');

      final result = read(text);

      expect(result.tree, isNull);
      expect(result.issues.first.kind, ConfigIssueKind.profile);
    });
  });

  group('empty files and styles', () {
    test('an empty file is an empty layer', () {
      final result = read('');

      expect(result.issues, isEmpty);
      expect(result.tree!.values, isEmpty);
      expect(result.tree!.kind, ConfigLayerKind.user);
      expect(result.tree!.source, 'config.yaml');
    });

    test('a file of comments is an empty layer', () {
      expect(read('# a\n# b\n').tree!.values, isEmpty);
    });

    test('a document marker alone is an empty layer', () {
      expect(read('---\n').tree!.values, isEmpty);
    });

    test('the block, flow, CRLF and BOM forms give the same tree', () {
      const block = 'budget:\n  max_steps: 20\ntools:\n  disabled: [a, b]\n';
      const flow = '{budget: {max_steps: 20}, tools: {disabled: [a, b]}}';
      final expected = {
        'budget': {'max_steps': 20},
        'tools': {
          'disabled': ['a', 'b'],
        },
      };

      expect(read(block).tree!.values, expected);
      expect(read(flow).tree!.values, expected);
      expect(read(block.replaceAll('\n', '\r\n')).tree!.values, expected);
      expect(read('\uFEFF$block').tree!.values, expected);
    });

    test('a BOM does not shift columns', () {
      final plain = read('budget:\n  max_steps: 20\n').tree!.positions;
      final bom = read('\uFEFFbudget:\n  max_steps: 20\n').tree!.positions;

      expect(bom, plain);
    });

    test('CRLF keeps positions', () {
      final lf = read('budget:\n  max_steps: 20\n').tree!.positions;
      final crlf = read('budget:\r\n  max_steps: 20\r\n').tree!.positions;

      expect(crlf, lf);
    });

    test('comments between keys are ignored', () {
      final result = read(
        '# head\nbudget: # tail\n  # inner\n  max_steps: 20\n',
      );

      expect(result.tree!.values, {
        'budget': {'max_steps': 20},
      });
    });
  });

  group('scalars of the YAML 1.2 core schema', () {
    test('yes and on stay strings, true and false are booleans', () {
      final values = read('a: yes\nb: on\nc: true\nd: false\n').tree!.values;

      expect(values, {'a': 'yes', 'b': 'on', 'c': true, 'd': false});
    });

    test('null forms, octal and decimal numbers', () {
      final values = read(
        'a: ~\nb: null\nc:\nd: 0o17\ne: 2.0\nf: 2\n',
      ).tree!.values;

      expect(values, {
        'a': null,
        'b': null,
        'c': null,
        'd': 15,
        'e': 2.0,
        'f': 2,
      });
      expect(values['e'], isA<double>());
    });

    test('quoted ampersands and exclamation marks are plain text', () {
      final result = read(
        'a: "&x"\nb: \'!y\'\nc: "x" # &z\nd: foo&bar\ne: |\n  &x !y\n',
      );

      expect(result.issues, isEmpty);
      expect(result.tree!.values['a'], '&x');
      expect(result.tree!.values['d'], 'foo&bar');
    });
  });

  group('positions', () {
    test('keys get line and column counted from 1', () {
      final tree = read(
        'budget:\n  max_steps: 20\nproviders:\n  openai:\n    kind: anthropic\n',
      ).tree!;

      expect(tree.positions['budget'], const ConfigPosition(1, 1));
      expect(tree.positions['budget.max_steps'], const ConfigPosition(2, 3));
      expect(
        tree.positions['providers.openai.kind'],
        const ConfigPosition(5, 5),
      );
    });

    test('names with symbols are quoted as KeyPath does', () {
      final tree = read(
        'providers:\n  ollama:\n    models:\n      "llama3.1:70b":\n'
        '        context_window: 8192\n',
      ).tree!;

      expect(
        tree.positions['providers.ollama.models."llama3.1:70b".context_window'],
        const ConfigPosition(5, 9),
      );
    });

    test('list items are addressed by name and by index', () {
      final tree = read(
        'mcp:\n  servers:\n    - name: github\n      url: http://h\n'
        '    - name: files\n      type: stdio\n',
      ).tree!;

      expect(
        tree.positions['mcp.servers[github].url'],
        const ConfigPosition(4, 7),
      );
      expect(tree.positions['mcp.servers[0]'], const ConfigPosition(3, 7));
      expect(tree.positions['mcp.servers[github]'], const ConfigPosition(3, 7));
      expect(
        tree.positions['mcp.servers[files].type'],
        const ConfigPosition(6, 7),
      );
    });

    test('elements of a list of strings are addressed by index', () {
      final tree = read('tools:\n  disabled:\n    - a\n    - b\n').tree!;

      expect(tree.positions['tools.disabled[1]'], const ConfigPosition(4, 7));
    });

    test('a flow mapping has positions too', () {
      final tree = read('{budget: {max_steps: 20}}').tree!;

      expect(tree.positions['budget.max_steps'], const ConfigPosition(1, 11));
    });
  });

  group('lineOffset', () {
    YamlReadResult readAt(String text, int offset) => readYamlTree(
      text,
      source: 'x.md',
      kind: ConfigLayerKind.user,
      lineOffset: offset,
    );

    test('positions of values are in file coordinates', () {
      final tree = readAt('a: 1\nb:\n  c: 2\n', 3).tree!;

      expect(tree.positions['a'], const ConfigPosition(4, 1));
      expect(tree.positions['b.c'], const ConfigPosition(6, 3));
    });

    test('a syntax error and a repeated key are shifted, both positions', () {
      final dup = readAt('a: 1\nb: 2\na: 3\n', 2).issues.single;
      expect((dup.line, dup.column), (5, 1));
      expect(dup.message, contains('first defined at 3:1'));

      final syntax = readAt('a: [1\n', 4).issues.single;
      expect(syntax.line, greaterThan(4));
    });

    test('a profile violation at the root is shifted', () {
      final issue = readAt('a: &x 1\nb: *x\n', 1).issues.first;

      expect(issue.line, greaterThanOrEqualTo(2));
    });

    test('an empty block with an offset is an empty layer', () {
      expect(readAt('', 1).tree!.values, isEmpty);
    });
  });
}
