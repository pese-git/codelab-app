import 'package:codelab_agent_core/src/prompts/template.dart';
import 'package:test/test.dart';

void main() {
  // Шаблоны промптов (agent-prompts «Шаблоны», §11.4, PR-4).
  const template = PromptTemplate(
    id: 'test.t',
    vars: {'x'},
    text: r'A {{x}} \{{y}}',
  );

  test('a value is inserted as is and \\{{ is a literal {{', () {
    expect(template.render({'x': '{{z}}'}), 'A {{z}} {{y}}');
  });

  test('missing or extra values are an ArgumentError', () {
    expect(() => template.render({}), throwsArgumentError);
    expect(() => template.render({'x': '1', 'y': '2'}), throwsArgumentError);
  });

  test('a template without vars renders with an empty map', () {
    const plain = PromptTemplate(id: 'test.p', vars: {}, text: 'plain');

    expect(plain.render({}), 'plain');
    expect(plain.tools, isEmpty);
  });

  test('the error names the template and both sets', () {
    expect(
      () => template.render({'y': '1'}),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          allOf(contains('test.t'), contains('x'), contains('y')),
        ),
      ),
    );
  });
}
