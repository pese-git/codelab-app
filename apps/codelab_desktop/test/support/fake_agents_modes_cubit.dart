import 'package:codelab_desktop/features/settings/application/agents_modes_cubit.dart';
import 'package:codelab_setup/codelab_setup.dart' show ConfigLayer;
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit-двойник: состояние задаёт тест, вызовы страницы — в [calls].
final class FakeAgentsModesCubit extends Cubit<AgentsModesState>
    implements AgentsModesCubit {
  FakeAgentsModesCubit(super.initialState);

  /// Вызовы страницы по порядку: `selectMode:<id>`, `selectEffort:<id>`,
  /// `selectTarget:<layer>`, `confirmBypass`, `cancelBypass`.
  final calls = <String>[];

  @override
  Future<void> reload() async => calls.add('reload');

  @override
  Future<void> selectMode(String id) async => calls.add('selectMode:$id');

  @override
  BypassToken? beginBypass() {
    calls.add('beginBypass');
    return token;
  }

  /// Показывает состояние (в самом Cubit `emit` защищён).
  void show(AgentsModesState state) => emit(state);

  @override
  void dismissBypass(BypassToken token) => calls.add('dismissBypass');

  @override
  bool isCurrent(BypassToken token) => true;

  /// Токен, который двойник отдаёт странице.
  final token = BypassToken(0, ConfigLayer.user, null);

  @override
  Future<void> confirmBypass(BypassToken token) async =>
      calls.add(identical(token, this.token) ? 'confirmBypass' : 'wrongToken');

  @override
  void cancelBypass() => calls.add('cancelBypass');

  @override
  Future<void> selectEffort(String id) async => calls.add('selectEffort:$id');

  @override
  Future<void> openDefinitionFolder(String filePath) async =>
      calls.add('openFolderOf:$filePath');

  @override
  Future<void> openFolder(AgentsFolder folder) async =>
      calls.add('openFolder:${folder.name}');

  @override
  void selectTarget(ConfigLayer layer) =>
      calls.add('selectTarget:${layer.name}');
}
