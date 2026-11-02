import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Разбор значения `config set` по типу дескриптора (agent-configuration
/// «Реестр настроек»; design.md change `add-config-writer-and-reload`, D4):
/// bool — только `true`/`false`, числа — с границами, duration — `30s`,
/// перечисление — по `enumValues`, списки и отображения — JSON. Ошибка —
/// `ConfigValueException`, текст которой не цитирует значение.
void main() {
  Object parse(String key, String raw) =>
      SettingsRegistry.parseCliValue(SettingsRegistry.lookup(key)!, raw);

  // Ключ в исключении — ключ дескриптора (`providers.*.api_key_env`): разбор
  // получает дескриптор, а не путь, по которому его нашли.
  Matcher rejected(String key, {String? hint}) => throwsA(
    isA<ConfigValueException>()
        .having((e) => e.key, 'key', key)
        .having((e) => e.expected, 'expected', contains(hint ?? '')),
  );

  test('bool accepts only true and false', () {
    expect(parse('compaction.enabled', 'true'), isTrue);
    expect(parse('compaction.enabled', 'false'), isFalse);
    for (final raw in ['yes', 'TRUE', '1', '', 'on']) {
      expect(
        () => parse('compaction.enabled', raw),
        rejected('compaction.enabled', hint: 'true or false'),
        reason: raw,
      );
    }
  });

  test('int honours min and max', () {
    expect(parse('budget.max_steps', '40'), 40);
    expect(parse('tools.project_context.max_bytes', '0'), 0);
    expect(parse('tools.project_context.max_bytes', '262144'), 262144);
    expect(
      () => parse('budget.max_steps', '0'),
      rejected('budget.max_steps', hint: 'integer'),
    );
    expect(
      () => parse('tools.project_context.max_bytes', '262145'),
      rejected('tools.project_context.max_bytes', hint: '262144'),
    );
    for (final raw in ['4.5', 'ten', '', '+3', '1e3']) {
      expect(
        () => parse('budget.max_steps', raw),
        rejected('budget.max_steps'),
        reason: raw,
      );
    }
  });

  test('float parses numbers and rejects NaN and infinity', () {
    expect(parse('budget.max_cost', '2.5'), 2.5);
    expect(parse('budget.max_cost', '3'), 3.0);
    for (final raw in ['NaN', 'Infinity', 'abc', '']) {
      expect(
        () => parse('budget.max_cost', raw),
        rejected('budget.max_cost'),
        reason: raw,
      );
    }
  });

  test('duration keeps the config form and rejects other forms', () {
    expect(parse('budget.max_duration', '30s'), '30s');
    expect(parse('budget.max_duration', '2m'), '2m');
    for (final raw in ['30', '30 s', '1d', 'PT30S', '']) {
      expect(
        () => parse('budget.max_duration', raw),
        rejected('budget.max_duration', hint: '30s'),
        reason: raw,
      );
    }
  });

  test('enumeration takes only listed values and names them', () {
    expect(parse('agent.effort', 'high'), 'high');
    expect(
      () => parse('agent.effort', 'extreme'),
      rejected('agent.effort', hint: 'low, medium, high'),
    );
  });

  test('string kinds keep the text; name-like kinds are checked', () {
    expect(
      parse('providers.p.base_url', 'https://x.test/v1'),
      'https://x.test/v1',
    );
    expect(parse('agent.default_model', 'p/m'), 'p/m');
    expect(
      parse('providers.p.api_key_secret', 'codelab/openai'),
      'codelab/openai',
    );
    expect(
      parse('providers.p.api_key_env', 'OPENAI_API_KEY'),
      'OPENAI_API_KEY',
    );
    expect(
      () => parse('agent.default_model', 'no-slash'),
      rejected('agent.default_model', hint: 'provider/model'),
    );
    expect(
      () => parse('providers.p.api_key_secret', 'Not A Name'),
      rejected('providers.*.api_key_secret'),
    );
    expect(
      () => parse('providers.p.api_key_env', '1BAD'),
      rejected('providers.*.api_key_env'),
    );
  });

  test('lists and maps are JSON of the right shape', () {
    expect(parse('agent.fallback', '["a/b","c/d"]'), ['a/b', 'c/d']);
    expect(parse('trusted_projects', '["/work"]'), ['/work']);
    expect(parse('permissions.tools', '{"exec":"ask"}'), {'exec': 'ask'});
    expect(parse('mcp.servers', '[{"name":"gh","type":"http"}]'), [
      {'name': 'gh', 'type': 'http'},
    ]);

    for (final (key, raw) in [
      ('permissions.deny', 'not json'),
      ('permissions.deny', '[1,2]'),
      ('permissions.deny', '{"a":1}'),
      ('agent.fallback', '["no-slash"]'),
      ('permissions.tools', '[1]'),
      ('mcp.servers', '{"name":"gh"}'),
      ('mcp.servers', '[1]'),
    ]) {
      expect(() => parse(key, raw), rejected(key), reason: '$key $raw');
    }
  });

  test('no error text contains the rejected value, even for broken JSON', () {
    const secret = 'sk-live-0123456789';
    for (final (key, raw) in [
      ('budget.max_steps', secret),
      ('compaction.enabled', secret),
      ('budget.max_duration', secret),
      ('agent.effort', secret),
      ('permissions.deny', '["$secret"'),
      ('permissions.deny', '[1,"$secret"]'),
      ('providers.p.api_key_secret', 'UPPER $secret'),
    ]) {
      try {
        parse(key, raw);
        fail('$key accepted $raw');
      } on ConfigValueException catch (e) {
        expect(e.toString(), isNot(contains('sk-live')), reason: key);
        expect(e.expected, isNot(contains('sk-live')), reason: key);
      }
    }
  });

  test('the exception names the key and the expected format', () {
    const error = ConfigValueException('a.b', 'true or false');

    expect(error, isA<Exception>());
    expect(error.key, 'a.b');
    expect(error.expected, 'true or false');
    expect(error.toString(), contains('a.b'));
    expect(error.toString(), contains('true or false'));
  });
}
