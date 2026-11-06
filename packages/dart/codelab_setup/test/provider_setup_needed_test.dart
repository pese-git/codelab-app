import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/real_home.dart';

/// Признак «нет провайдера» по типизированным проблемам (client-agent-setup
/// «Готовность провайдера», сценарий «Признак „нет провайдера“ по
/// типизированным проблемам»; design.md change `add-provider-setup-ui`, D26).
///
/// Снимки — из настоящего `FileAgentConfigStore`: текст проблем загрузчика не
/// разбирается, а их вид и ключ берутся из его настоящих ответов.
void main() {
  late RealHome home;

  setUp(() => home = RealHome.create('provider_setup_needed_test'));
  tearDown(() => home.dispose());

  test('пустой дом — true; проблема — agent.default_model, вид value, '
      'событие config.model.none', () async {
    final snapshot = await home.load();

    expect(providerSetupNeeded(snapshot), isTrue);
    final issue = snapshot.loaded.issues.single;
    expect(issue.key, 'agent.default_model');
    expect(issue.kind, ConfigIssueKind.value);
    expect(issue.event, 'config.model.none');
  });

  // Change `optional-default-model`, D3, D12: `agent.default_model` больше не
  // обязателен, агент стартует на первой модели первого провайдера, и мастер
  // «добавить провайдера» не нужен.
  test('провайдер без agent.default_model — false (агент стартует на первом '
      'провайдере)', () async {
    home.writeConfig(gatewayProvider);

    final snapshot = await home.load();

    expect(snapshot.loaded.issues, isEmpty);
    expect(providerSetupNeeded(snapshot), isFalse);
  });

  test('agent.default_model без провайдеров — true', () async {
    home.writeConfig('agent:\n  default_model: gw/m\n');
    expect(providerSetupNeeded(await home.load()), isTrue);
  });

  test('пустой дом плюс budget.max_steps: 0 — false', () async {
    home.writeConfig('budget:\n  max_steps: 0\n');
    expect(providerSetupNeeded(await home.load()), isFalse);
  });

  test('модель вне каталога при заданном провайдере — false', () async {
    home.writeConfig('${gatewayProvider}agent:\n  default_model: gw/typo\n');
    expect(providerSetupNeeded(await home.load()), isFalse);
  });

  test('полный конфиг — false', () async {
    home.writeConfig('${gatewayProvider}agent:\n  default_model: gw/m\n');
    expect(providerSetupNeeded(await home.load()), isFalse);
  });
}
