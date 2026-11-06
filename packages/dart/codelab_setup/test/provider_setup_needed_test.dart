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

  test('пустой дом — true', () async {
    expect(providerSetupNeeded(await home.load()), isTrue);
  });

  test('провайдер без agent.default_model — true', () async {
    home.writeConfig(gatewayProvider);
    expect(providerSetupNeeded(await home.load()), isTrue);
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
