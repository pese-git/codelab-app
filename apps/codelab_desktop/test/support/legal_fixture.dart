// Двойники портов страницы «Legal» и открытие страницы в настоящем дереве app
// (задачи 4.3 и 4.4 change `add-app-legal-page`; design.md D7, D10).
//
// Страница читает документы и реестр лицензий только через `LegalPorts`,
// поэтому тесты подставляют фиктивные тексты и пакеты и не зависят ни от
// `rootBundle`, ни от глобального `LicenseRegistry`.

import 'dart:async';

import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/application/legal_ports.dart';
import 'package:codelab_desktop/features/settings/application/package_license_search.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_external_link_opener.dart';
import 'recording_logger.dart';
import 'test_app_scope.dart';

/// Текст лицензии в фикстуре: первая строка как в настоящем `LICENSE`.
const legalLicenseText =
    'MIT License\n\nCopyright (c) 2026 Fixture\n\nPermission is hereby granted.';

/// Фиктивные тексты ресурсов `assets/legal/…`: ссылки в `TERMS.md` проверяют
/// политику D8 (вкладка, внешняя, неизвестный файл).
const legalFixtureAssets = <String, String>{
  'assets/legal/PRIVACY.md': '# Privacy EN\n\nprivacy-en-body\n',
  'assets/legal/PRIVACY.ru.md': '# Приватность RU\n\nprivacy-ru-body\n',
  'assets/legal/TERMS.md':
      '# Terms EN\n\nterms-en-body\n\n'
      '[license-link](LICENSE)\n\n'
      '[web-link](https://example.com/terms)\n\n'
      '[unknown-link](SECURITY.md)\n',
  'assets/legal/TERMS.ru.md': '# Условия RU\n\nterms-ru-body\n',
  'assets/legal/LICENSE': legalLicenseText,
  'assets/legal/THIRD_PARTY_NOTICES.md':
      '# Third-party notices\n\nintro-marker-text\n\n'
      '## Записи\n\n### JetBrains Mono (шрифт в пакете gpt_markdown)\n\n'
      'record-body-marker\n\n'
      '## Формат записи\n\n<Название источника>\n',
};

/// Пакет в фикстуре: имя и тексты лицензий.
PackageLicense legalPackage(String name, [int licenses = 1]) => PackageLicense(
  name: name,
  licenses: [for (var i = 1; i <= licenses; i++) 'license-text-$name-$i'],
);

/// Порты-двойники и всё, что тест хочет проверить после жестов.
final class LegalFixture {
  LegalFixture({
    this.assets = legalFixtureAssets,
    this.failing = const {},
    this.packages = const [],
    this.failedRegistry = false,
    FakeExternalLinkOpener? links,
  }) : links = links ?? FakeExternalLinkOpener();

  /// Тексты ресурсов по пути.
  final Map<String, String> assets;

  /// Ресурсы, чтение которых падает (путь есть в тексте исключения: он не
  /// должен дойти до экрана).
  final Set<String> failing;

  /// Список пакетов, который вернёт реестр.
  final List<PackageLicense> packages;

  /// Поток реестра оборвался.
  final bool failedRegistry;

  final FakeExternalLinkOpener links;

  /// Журнал портов страницы (`legal.*`).
  final logger = RecordingLogger();

  /// Пути, которые страница прочитала, по порядку.
  final reads = <String>[];

  /// Пока не завершён, реестр «собирается» (индикатор загрузки).
  Completer<CollectedLicenses>? registryGate;

  late final LegalPorts ports = LegalPorts(
    readAsset: (asset) async {
      reads.add(asset);
      if (failing.contains(asset)) {
        throw StateError('cannot read /secret/path/$asset');
      }
      return assets[asset] ?? (throw StateError('no asset $asset'));
    },
    packageLicenses: () =>
        registryGate?.future ??
        Future.value((packages: packages, failed: failedRegistry)),
    externalLinks: links,
    logger: logger,
  );
}

/// Открывает страницу «Legal» в настоящем дереве app на вкладке «Privacy
/// policy» (как пункт навигации). Окно — [size].
Future<CodeLabTestBinding> openLegalPage(
  WidgetTester tester,
  LegalFixture fixture, {
  Locale locale = const Locale('en'),
  Size size = const Size(1400, 900),
  Map<String, Object> preferences = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final binding = CodeLabTestBinding(
    project: '/workspace',
    locale: locale,
    preferences: preferences,
    legalPorts: fixture.ports,
    externalLinkOpener: fixture.links,
    settingsPages: const SettingsPages(
      available: {
        SettingsPage.connection,
        SettingsPage.general,
        SettingsPage.legal,
      },
    ),
  );
  await tester.pumpWidget(
    binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
  );
  await binding.scope.resolve<NavigationCubit>().openSettings(
    page: SettingsPage.legal,
    source: SettingsOpenSource.sidebar,
  );
  await tester.pumpAndSettle();
  return binding;
}
