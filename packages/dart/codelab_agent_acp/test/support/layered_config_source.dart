import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Подставной [ConfigSource] с изменяемым слоем пользователя.
///
/// Почему отдельный файл: тесты живой перезагрузки (`initialize` после
/// смены `subagents.enabled`, D37) нуждаются в источнике, значения которого
/// тест правит между `initialize` соединений; такой же приём у
/// `config_reload_notifications_test.dart`, но там он приватный.
///
/// Как использовать: `LayeredConfigSource(extra: {'subagents': {'enabled':
/// false}})` для начального значения, `put('subagents.enabled', false)` —
/// правка слоя, затем `core.runtime.reloadConfig()`. `load()` — настоящий
/// `CoreConfig.fromLayers`, как у файлового источника.
final class LayeredConfigSource implements ConfigSource {
  LayeredConfigSource({Map<String, Object?> extra = const {}}) {
    _user.addAll(_deep(extra)! as Map<String, Object?>);
    _initial = _build(null);
    expect(_initial.issues, isEmpty, reason: _initial.issues.join('\n'));
  }

  final Map<String, Object?> _user =
      _deep({
            'providers': {
              'a': {
                'kind': 'openai-compatible',
                'base_url': 'https://a.test/v1',
                'models': {'m1': <String, Object?>{}},
              },
            },
            'agent': {'default_model': 'a/m1'},
          })!
          as Map<String, Object?>;
  late final ConfigLoadResult _initial;

  /// Ставит значение по пути `a.b.c`, создавая промежуточные объекты.
  void put(String path, Object? value) {
    final names = path.split('.');
    var node = _user;
    for (final name in names.take(names.length - 1)) {
      node =
          node.putIfAbsent(name, () => <String, Object?>{})!
              as Map<String, Object?>;
    }
    node[names.last] = value;
  }

  ConfigLoadResult _build(List<String>? pinned) => CoreConfig.fromLayers(
    [
      ConfigTree(
        kind: ConfigLayerKind.user,
        source: '/home/u/.codelab/config.yaml',
        // Копия: снимок рантайма не должен ссылаться на правимую карту теста.
        values: _deep(_user)! as Map<String, Object?>,
      ),
    ],
    environment: const {},
    projectRoot: '/work/demo',
    pinnedTrustedProjects: pinned,
  );

  @override
  ConfigLoadResult get initial => _initial;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async =>
      _build(_initial.config!.trustedProjects);

  @override
  Stream<void> get changes => const Stream.empty();
}

/// Копия дерева с типами `Map<String, Object?>` на всех уровнях.
Object? _deep(Object? node) => switch (node) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final entry in map.entries) entry.key! as String: _deep(entry.value),
  },
  final List<Object?> list => <Object?>[for (final item in list) _deep(item)],
  _ => node,
};
